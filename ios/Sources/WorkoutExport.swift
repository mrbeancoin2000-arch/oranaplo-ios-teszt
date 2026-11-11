import Foundation
import HealthKit
import CoreLocation

struct WorkoutExport {
    let reader: HealthReader
    func rows(for workout: HKWorkout) async -> [ExportRow] {
        let type = workout.workoutActivityType
        let label: String
        switch type {
        case .running: label = "Futás"
        case .walking: label = "Gyaloglás"
        case .cycling: label = "Kerékpár"
        case .swimming: label = "Úszás"
        case .traditionalStrengthTraining, .functionalStrengthTraining: label = "Erősítés"
        default: label = "Egyéb (\(type.rawValue))"
        }
        let heart = (try? await reader.heartSamples(from: workout.startDate, to: workout.endDate)) ?? []
        let heartValues = heart.map(\.1)
        let avg = heartValues.isEmpty ? "" : String(heartValues.reduce(0,+)/Double(heartValues.count))
        let minHR = heartValues.min().map { String(describing: $0) } ?? ""
        let maxHR = heartValues.max().map { String(describing: $0) } ?? ""
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        var notes = ""
        var segments: [ExportRow] = []
        if type == .running || type == .walking {
            do {
                let fixes = try await reader.routeLocations(for: workout)
                segments = split100m(fixes, heart: heart, workout: workout, label: label)
                if fixes.count < 2 { notes = "Nincs GPS-útvonal; 100 méteres szakasz nem számítható" }
                else if segments.isEmpty { notes = "Nincs legalább 100 m megbízható útvonalszakasz" }
            } catch { notes = "GPS-útvonal nem olvasható: \(error.localizedDescription.prefix(100))" }
        }
        let summary = ExportRow(id: "workout:\(workout.uuid.uuidString)", sheet: "Edzesek", values: [
            workout.uuid.uuidString, label, ISO.string(workout.startDate), ISO.string(workout.endDate),
            String(workout.duration), String(kcal), String(distance), avg, minHR, maxHR, notes, ISO.string(Date())
        ])
        return [summary] + segments
    }
}

/// 100 m splits derived from stored GPS route points, not fictional 100 m HealthKit samples.
/// Distances and times are interpolated; HR is arithmetic mean/min/max of the available samples.
func split100m(_ locations: [CLLocation], heart: [(Date,Double)], workout: HKWorkout, label: String) -> [ExportRow] {
    let fixes = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        .sorted { $0.timestamp < $1.timestamp }
    guard fixes.count > 1 else { return [] }
    var output: [ExportRow] = []
    var distanceInSegment = 0.0
    var segmentStart = fixes[0].timestamp
    var index = 0
    for i in 1..<fixes.count {
        let a = fixes[i - 1], b = fixes[i]
        let time = b.timestamp.timeIntervalSince(a.timestamp)
        let segmentDistance = b.distance(from: a)
        guard time > 0, time <= 120, segmentDistance > 0, segmentDistance <= 250 else {
            distanceInSegment = 0
            segmentStart = b.timestamp
            continue
        }
        var traveled = 0.0
        while distanceInSegment + (segmentDistance - traveled) >= 100 {
            let remaining = 100 - distanceInSegment
            let part = (traveled + remaining) / segmentDistance
            let finish = a.timestamp.addingTimeInterval(time * part)
            let elapsed = finish.timeIntervalSince(segmentStart)
            if elapsed > 0.1 {
                index += 1
                let hrs = heart.filter { $0.0 >= segmentStart && $0.0 <= finish }.map(\.1)
                let hrAvg = hrs.isEmpty ? "" : String(hrs.reduce(0,+) / Double(hrs.count))
                let hrMin = hrs.min().map { String(describing: $0) } ?? ""
                let hrMax = hrs.max().map { String(describing: $0) } ?? ""
                let speed = 360.0 / elapsed // 0.1 km / (s / 3600)
                let pace = elapsed / 6.0     // seconds per 100m -> min/km
                let segmentID = "segment:\(workout.uuid.uuidString):\(index)"
                let accuracy = max(a.horizontalAccuracy, b.horizontalAccuracy)
                output.append(ExportRow(id: segmentID, sheet: "100m", values: [
                    segmentID, workout.uuid.uuidString, label, String(index * 100), ISO.string(segmentStart),
                    ISO.string(finish), String(elapsed), String(speed), String(pace), hrAvg, hrMin, hrMax,
                    String(accuracy), ISO.string(Date())
                ]))
            }
            traveled += remaining
            distanceInSegment = 0
            segmentStart = finish
            // Prevent infinite loop from floating point roundoff
            if segmentDistance - traveled < 0.0001 { break }
        }
        distanceInSegment += max(0, segmentDistance - traveled)
    }
    return output
}
