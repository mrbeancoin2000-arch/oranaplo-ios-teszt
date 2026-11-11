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
    let fixes = locations.map {
        TrackFix(time: $0.timestamp, latitude: $0.coordinate.latitude,
                 longitude: $0.coordinate.longitude, accuracyMeters: $0.horizontalAccuracy)
    }
    let pulse = heart.map { HeartFix(time: $0.0, beatsPerMinute: $0.1) }
    let maximumSpeed = workout.workoutActivityType == .walking ? 5.0 : 15.0
    let sections = SplitMath.calculate(fixes, hearts: pulse,
        workoutStart: workout.startDate, workoutEnd: workout.endDate,
        maxSpeedMetersPerSecond: maximumSpeed)
    return sections.map { segment in
        let sectionID = "segment:\(workout.uuid.uuidString):\(segment.index)"
        return ExportRow(id: sectionID, sheet: "100m", values: [
            sectionID, workout.uuid.uuidString, label, String(segment.index * 100),
            ISO.string(segment.start), ISO.string(segment.finish),
            String(segment.elapsedSeconds), String(segment.speedKmh), String(segment.paceMinutesPerKm),
            segment.heartMean.map { String($0) } ?? "",
            segment.heartMinimum.map { String($0) } ?? "",
            segment.heartMaximum.map { String($0) } ?? "",
            String(segment.maxGPSAccuracy), ISO.string(Date())
        ])
    }
}
