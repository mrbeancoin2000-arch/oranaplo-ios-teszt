import Foundation
import HealthKit

struct WorkoutSnapshot {
    let kindKey: String
    let started: Date
    let seconds: TimeInterval
    let distanceMeters: Double?
    let energyKcal: Double?
    let averageBPM: Double?
    let minBPM: Double?
    let maxBPM: Double?
    let hundredMeterSegments: Int?
}

struct ObservationNotice: Identifiable {
    let id: String
    let titleKey: String
    let date: Date
}

struct HealthOverview {
    let reader: HealthReader

    func latestWorkout() async -> WorkoutSnapshot? {
        guard let workouts = try? await reader.getWorkouts(since: Date().addingTimeInterval(-90 * 86400)),
              let workout = workouts.max(by: { $0.startDate < $1.startDate }) else { return nil }
        let kind: String
        switch workout.workoutActivityType {
        case .running: kind = "workout.running"
        case .walking: kind = "workout.walking"
        case .cycling: kind = "workout.cycling"
        case .swimming: kind = "workout.swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: kind = "workout.strength"
        default: kind = "workout.other"
        }
        let samples = (try? await reader.heartSamples(from: workout.startDate, to: workout.endDate)) ?? []
        let bpm = samples.map(\.1)
        var splitCount: Int?
        if workout.workoutActivityType == .running || workout.workoutActivityType == .walking {
            if let locations = try? await reader.routeLocations(for: workout) {
                splitCount = split100m(locations, heart: samples, workout: workout,
                                        label: kind).count
            }
        }
        return WorkoutSnapshot(
            kindKey: kind,
            started: workout.startDate,
            seconds: workout.duration,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            energyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
            averageBPM: bpm.isEmpty ? nil : bpm.reduce(0, +) / Double(bpm.count),
            minBPM: bpm.min(), maxBPM: bpm.max(), hundredMeterSegments: splitCount
        )
    }

    /// Apple's actual category notifications, not invented medical thresholds.
    /// Low-step note requires seven complete days and is shown only after 20:00.
    func notices() async -> [ObservationNotice] {
        let now = Date()
        let from = now.addingTimeInterval(-7 * 86400)
        var result: [ObservationNotice] = []
        let categories: [(String, String)] = [
            ("HighHeartRateEvent", "attention.high"),
            ("LowHeartRateEvent", "attention.low"),
            ("IrregularHeartRhythmEvent", "attention.irregular")
        ]
        for (identifier, key) in categories {
            let id = HKCategoryTypeIdentifier(rawValue: "HKCategoryTypeIdentifier" + identifier)
            guard let type = HKObjectType.categoryType(forIdentifier: id),
                  let samples = try? await reader.samples(type, since: from, limit: 5),
                  let recent = samples.max(by: { $0.startDate < $1.startDate }) else { continue }
            result.append(ObservationNotice(id: key, titleKey: key, date: recent.startDate))
        }
        // No absolute step 'warning': the value below is a non-medical comparison
        // with the user's own history, and never triggers before 20:00 local time.
        if Calendar.current.component(.hour, from: now) >= 20,
           let type = HKObjectType.quantityType(forIdentifier: .stepCount),
           let all = try? await reader.samples(type, since: from, limit: 6000) {
            let cal = Calendar.current
            var perDay: [Date: Double] = [:]
            for item in all {
                guard let quantity = item as? HKQuantitySample else { continue }
                perDay[cal.startOfDay(for: item.startDate), default: 0] += quantity.quantity.doubleValue(for: .count())
            }
            let today = cal.startOfDay(for: now)
            let previous = (1...7).compactMap { gap -> Double? in
                guard let day = cal.date(byAdding: .day, value: -gap, to: today) else { return nil }
                return perDay[day]
            }.sorted()
            if previous.count >= 5 {
                let mid = previous[previous.count / 2]
                if mid >= 1500, let todaySteps = perDay[today], todaySteps < mid * 0.5 {
                    result.append(ObservationNotice(id: "attention.steps", titleKey: "attention.steps", date: now))
                }
            }
        }
        return result.sorted { $0.date > $1.date }
    }
}
