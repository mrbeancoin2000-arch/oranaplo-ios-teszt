import Foundation

struct TrackFix {
    let time: Date
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
}

struct HeartFix {
    let time: Date
    let beatsPerMinute: Double
}

struct HundredMeterSplit {
    let index: Int
    let start: Date
    let finish: Date
    let elapsedSeconds: Double
    let speedKmh: Double
    let paceMinutesPerKm: Double
    let heartMean: Double?
    let heartMinimum: Double?
    let heartMaximum: Double?
    let maxGPSAccuracy: Double
}

/// Deterministic distance/time segmentation independent of HealthKit or CoreLocation.
/// Valid coordinates and route continuity are required; no invented missing pulse values.
enum SplitMath {
    static func distanceMeters(_ a: TrackFix, _ b: TrackFix) -> Double {
        let r = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let v = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return r * 2 * atan2(sqrt(max(0, v)), sqrt(max(0, 1 - v)))
    }
    static func calculate(_ fixes: [TrackFix], hearts: [HeartFix],
                          workoutStart: Date, workoutEnd: Date,
                          maxSpeedMetersPerSecond: Double = 15) -> [HundredMeterSplit] {
        let filtered = fixes.filter {
            $0.accuracyMeters >= 0 && $0.accuracyMeters <= 50 &&
            (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) &&
            $0.time >= workoutStart && $0.time <= workoutEnd
        }.sorted { $0.time < $1.time }
        guard filtered.count >= 2 else { return [] }
        var result: [HundredMeterSplit] = []
        var segmentDistance = 0.0
        var started = filtered[0].time
        var segmentAccuracy = filtered[0].accuracyMeters
        for position in 1..<filtered.count {
            let prev = filtered[position - 1]
            let next = filtered[position]
            let seconds = next.time.timeIntervalSince(prev.time)
            let meters = distanceMeters(prev, next)
            if seconds <= 0 || seconds > 120 || meters <= 0 || meters > 250 || meters / seconds > maxSpeedMetersPerSecond {
                segmentDistance = 0
                started = next.time
                segmentAccuracy = next.accuracyMeters
                continue
            }
            var advanced = 0.0
            segmentAccuracy = max(segmentAccuracy, prev.accuracyMeters, next.accuracyMeters)
            while segmentDistance + meters - advanced >= 100 - 0.000001 {
                let remainder = max(0, 100 - segmentDistance)
                let fraction = min(1, (advanced + remainder) / meters)
                let finished = prev.time.addingTimeInterval(seconds * fraction)
                let elapsed = finished.timeIntervalSince(started)
                if elapsed > 0.1 {
                    let pulse = hearts.filter { $0.time >= started && $0.time <= finished && $0.beatsPerMinute.isFinite && $0.beatsPerMinute > 0 }
                        .map(\.beatsPerMinute)
                    result.append(HundredMeterSplit(index: result.count + 1, start: started, finish: finished,
                        elapsedSeconds: elapsed, speedKmh: 360 / elapsed, paceMinutesPerKm: elapsed / 6,
                        heartMean: pulse.isEmpty ? nil : pulse.reduce(0, +) / Double(pulse.count),
                        heartMinimum: pulse.min(), heartMaximum: pulse.max(), maxGPSAccuracy: segmentAccuracy))
                }
                advanced += remainder
                segmentDistance = 0
                segmentAccuracy = max(prev.accuracyMeters, next.accuracyMeters)
                started = finished
                if meters - advanced < 0.000001 { break }
            }
            segmentDistance += max(0, meters - advanced)
        }
        return result
    }
}
