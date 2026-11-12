import Foundation

/// Platform-independent workout maths: contains no HealthKit, CoreLocation, or UI code.
/// All distance/step/heart values are sourced from sensors, not inferred from demographics.
struct RunRoutePoint: Codable, Equatable {
    var date: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var activeSeconds: Double
    var cumulativeMeters: Double
    var breakBefore: Bool
    var altitudeMeters: Double? = nil // GPS altitude, only when vertical accuracy is valid
}

struct RunPulsePoint: Codable, Equatable {
    var date: Date
    var activeSeconds: Double
    var bpm: Double
}

struct RunStepPoint: Codable, Equatable {
    var activeSeconds: Double
    var totalSteps: Int
}

struct RunActiveWindow: Codable, Equatable {
    var started: Date
    var ended: Date?
    var secondsBefore: Double
}

struct RunHundredMeters: Codable, Identifiable, Equatable {
    var index: Int
    var id: Int { index }
    var startActiveSeconds: Double
    var finishActiveSeconds: Double
    var elapsedSeconds: Double
    var kmh: Double
    var paceSecondsPerKm: Double
    var steps: Int?
    var avgHeart: Double?
    var minHeart: Double?
    var maxHeart: Double?
    var estimatedKcal: Double?
    var worstGPSAccuracy: Double
}

struct RecordedRun: Codable, Identifiable {
    var id: UUID
    var started: Date
    var ended: Date?
    var activeSeconds: Double
    var gpsMeters: Double
    var steps: Int?
    var estimatedKcal: Double?
    var kilograms: Double?
    var centimeters: Double?
    var route: [RunRoutePoint]
    var heart: [RunPulsePoint]
    var stepHistory: [RunStepPoint]
    var activeWindows: [RunActiveWindow]
    var completed: Bool
    var interrupted: Bool

    var splits: [RunHundredMeters] { RunMath.splits(route, heart: heart, steps: stepHistory, kilograms: kilograms) }
    var paceSecondsPerKm: Double? { RunMath.pace(seconds: activeSeconds, meters: gpsMeters) }
    var avgKmh: Double? { RunMath.speed(seconds: activeSeconds, meters: gpsMeters) }
}

enum RunMath {
    static func distance(_ a: RunRoutePoint, _ b: RunRoutePoint) -> Double {
        let radius = 6_371_000.0
        let p1 = a.latitude * .pi / 180
        let p2 = b.latitude * .pi / 180
        let dphi = (b.latitude - a.latitude) * .pi / 180
        let dlambda = (b.longitude - a.longitude) * .pi / 180
        let h = pow(sin(dphi / 2), 2) + cos(p1) * cos(p2) * pow(sin(dlambda / 2), 2)
        return 2 * radius * atan2(sqrt(max(0,h)),sqrt(max(0,1-h)))
    }

    static func speed(seconds: Double, meters: Double) -> Double? {
        guard seconds > 0, meters > 0, seconds.isFinite, meters.isFinite else { return nil }
        return 3.6 * meters / seconds
    }
    static func pace(seconds: Double, meters: Double) -> Double? {
        guard seconds > 0, meters > 0, seconds.isFinite, meters.isFinite else { return nil }
        return seconds / (meters / 1000)
    }
    /// Clearly labelled approximate running economy: 1 kcal/kg/km, never a sensor reading.
    static func estimatedRunningKcal(meters: Double, kilograms: Double?) -> Double? {
        guard let kg = kilograms, (20...400).contains(kg), meters >= 0, meters.isFinite else { return nil }
        return kg * meters / 1000
    }
    static func activeTime(of date: Date, windows: [RunActiveWindow]) -> Double? {
        for w in windows {
            if date >= w.started && date <= (w.ended ?? date) {
                return w.secondsBefore + max(0,date.timeIntervalSince(w.started))
            }
        }
        return nil
    }
    /// Convert active workout seconds to an actual wall-clock timestamp.
    /// Needed for exporting splits across paused intervals without fictitious timestamps.
    static func wallDate(forActive seconds: Double, windows: [RunActiveWindow]) -> Date? {
        guard seconds >= 0, seconds.isFinite else { return nil }
        for w in windows {
            let duration = w.ended.map { max(0,$0.timeIntervalSince(w.started)) } ?? Double.infinity
            let localSeconds = seconds - w.secondsBefore
            if localSeconds >= -0.000001 && localSeconds <= duration + 0.000001 {
                return w.started.addingTimeInterval(max(0,localSeconds))
            }
        }
        return nil
    }
    static func stepCount(at seconds: Double, samples: [RunStepPoint]) -> Int? {
        let points = samples.sorted { $0.activeSeconds < $1.activeSeconds }
        guard !points.isEmpty, seconds >= points[0].activeSeconds else { return nil }
        if seconds >= points[points.count-1].activeSeconds { return points.last?.totalSteps }
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]
            if seconds <= b.activeSeconds {
                let fraction = max(0,min(1,(seconds - a.activeSeconds) / max(0.0001,b.activeSeconds-a.activeSeconds)))
                return Int((Double(a.totalSteps) + fraction*Double(b.totalSteps-a.totalSteps)).rounded())
            }
        }
        return nil
    }
    /// 100 m boundaries are interpolated in time from accepted cumulative GPS distance.
    /// Discontinuous gaps (paused, stale, inaccurate) do not contribute distance.
    static func splits(_ route: [RunRoutePoint], heart: [RunPulsePoint] = [],
                       steps: [RunStepPoint] = [], kilograms: Double? = nil) -> [RunHundredMeters] {
        let points = route.sorted { $0.date < $1.date }
        guard points.count > 1 else { return [] }
        var output: [RunHundredMeters] = []
        var targetMeters = 100.0
        var lastMarkSeconds = 0.0
        for i in 1..<points.count {
            let before = points[i-1], after = points[i]
            guard !after.breakBefore, after.date > before.date,
                  after.activeSeconds > before.activeSeconds,
                  after.cumulativeMeters > before.cumulativeMeters else { continue }
            let increment = after.cumulativeMeters - before.cumulativeMeters
            guard increment < 250 else { continue }
            while targetMeters <= after.cumulativeMeters + 0.000001 {
                if targetMeters < before.cumulativeMeters - 0.000001 { targetMeters += 100; continue }
                let fraction = max(0,min(1,(targetMeters-before.cumulativeMeters)/increment))
                let finish = before.activeSeconds + fraction*(after.activeSeconds-before.activeSeconds)
                let elapsed = finish-lastMarkSeconds
                guard elapsed > 0.01 else { targetMeters += 100; continue }
                let hearts = heart.filter { $0.activeSeconds >= lastMarkSeconds && $0.activeSeconds <= finish && $0.bpm >= 25 && $0.bpm <= 250 }.map(\.bpm)
                let stepsStart = stepCount(at: lastMarkSeconds, samples: steps)
                let stepsEnd = stepCount(at: finish, samples: steps)
                let stepDelta: Int? = (stepsStart != nil && stepsEnd != nil) ? max(0,stepsEnd! - stepsStart!) : nil
                output.append(RunHundredMeters(index: output.count + 1,
                    startActiveSeconds: lastMarkSeconds, finishActiveSeconds: finish, elapsedSeconds: elapsed,
                    kmh: 360 / elapsed, paceSecondsPerKm: elapsed * 10,
                    steps: stepDelta,
                    avgHeart: hearts.isEmpty ? nil : hearts.reduce(0,+)/Double(hearts.count),
                    minHeart: hearts.min(), maxHeart: hearts.max(),
                    estimatedKcal: estimatedRunningKcal(meters: 100, kilograms: kilograms),
                    worstGPSAccuracy: max(before.horizontalAccuracy, after.horizontalAccuracy)))
                lastMarkSeconds = finish
                targetMeters += 100
            }
        }
        return output
    }
}
