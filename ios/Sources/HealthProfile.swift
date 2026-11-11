import Foundation
import HealthKit

/// Local-only view model. Never transmit DOB, sex or body measurements without an explicit action.
struct PersonalHealthProfile {
    let ageYears: Int?
    let biologicalSexKey: String
    let heightCM: Double?
    let weightKG: Double?
    let weightDate: Date?
    let loadedAt: Date

    var adult: Bool { (ageYears ?? 0) >= 18 }
    var calculatedBMI: Double? {
        guard let heightCM, let weightKG, heightCM > 0, weightKG > 0 else { return nil }
        return weightKG / pow(heightCM / 100, 2)
    }
}

/// An informational observation. The app cannot diagnose disease or infer missing data.
struct PersonalObservation: Identifiable {
    enum Level: String { case informational, review, urgent }
    let id: String
    let titleKey: String
    let messageKey: String
    let measurement: String
    let date: Date
    let level: Level
    let sourceKey: String
}

struct HealthProfileService {
    let reader: HealthReader

    func readProfile() async -> PersonalHealthProfile {
        var years: Int?
        if let birth = try? reader.store.dateOfBirthComponents(),
           let year = birth.year, let month = birth.month, let day = birth.day,
           let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
           date <= Date() {
            let computed = Calendar.current.dateComponents([.year], from: date, to: Date()).year
            if let computed, (0...120).contains(computed) { years = computed }
        }

        var sex = "profile.sex.unknown"
        if let object = try? reader.store.biologicalSex() {
            switch object.biologicalSex {
            case .female: sex = "profile.sex.female"
            case .male: sex = "profile.sex.male"
            case .other: sex = "profile.sex.other"
            default: break
            }
        }
        let latestHeight = await recentQuantity(.height, unit: .meterUnit(with: .centi), sinceDays: 3650)
        let latestWeight = await recentQuantity(.bodyMass, unit: .gramUnit(with: .kilo), sinceDays: 3650)
        return PersonalHealthProfile(
            ageYears: years, biologicalSexKey: sex,
            heightCM: latestHeight?.0, weightKG: latestWeight?.0,
            weightDate: latestWeight?.1, loadedAt: Date()
        )
    }

    private func recentQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                                sinceDays: Double) async -> (Double, Date)? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier),
              let sample = try? await reader.samples(type, since: Date().addingTimeInterval(-sinceDays * 86400), limit: 1).first as? HKQuantitySample else {
            return nil
        }
        let value = sample.quantity.doubleValue(for: unit)
        return value.isFinite && value > 0 ? (value, sample.startDate) : nil
    }

    func localObservations(profile: PersonalHealthProfile) async -> [PersonalObservation] {
        let now = Date()
        var observations: [PersonalObservation] = []
        // Adult-only BP guidance: these are measurements from external devices / manual entries,
        // not from the Watch. Pair systolic and diastolic samples close in time.
        if profile.adult,
           let sys = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
           let dia = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
           let systolic = try? await reader.samples(sys, since: now.addingTimeInterval(-30 * 86400), limit: 30),
           let diastolic = try? await reader.samples(dia, since: now.addingTimeInterval(-30 * 86400), limit: 30) {
            let s = systolic.compactMap { $0 as? HKQuantitySample }
            let d = diastolic.compactMap { $0 as? HKQuantitySample }
            let unit = HKUnit.millimeterOfMercury()
            if let latest = s.first,
               let counterpart = d.min(by: { abs($0.startDate.timeIntervalSince(latest.startDate)) < abs($1.startDate.timeIntervalSince(latest.startDate)) }),
               abs(counterpart.startDate.timeIntervalSince(latest.startDate)) <= 60 {
                let high = latest.quantity.doubleValue(for: unit)
                let low = counterpart.quantity.doubleValue(for: unit)
                let value = String(format: "%.0f/%.0f mmHg", high, low)
                if high > 180 || low > 120 {
                    observations.append(PersonalObservation(id: "bp.urgent", titleKey: "profile.alert.bp.urgent.title",
                        messageKey: "profile.alert.bp.urgent.body", measurement: value, date: latest.startDate,
                        level: .urgent, sourceKey: "profile.source.health"))
                } else if high >= 140 || low >= 90 {
                    observations.append(PersonalObservation(id: "bp.review", titleKey: "profile.alert.bp.review.title",
                        messageKey: "profile.alert.bp.review.body", measurement: value, date: latest.startDate,
                        level: .review, sourceKey: "profile.source.health"))
                }
            }
        }
        // Relative comparison, not a prescribed minimum number of steps.
        if Calendar.current.component(.hour, from: now) >= 20,
           let type = HKObjectType.quantityType(forIdentifier: .stepCount),
           let samples = try? await reader.samples(type, since: now.addingTimeInterval(-9 * 86400), limit: 12000) {
            let cal = Calendar.current
            var daily: [Date: Double] = [:]
            for sample in samples {
                guard let sample = sample as? HKQuantitySample else { continue }
                daily[cal.startOfDay(for: sample.startDate), default: 0] += sample.quantity.doubleValue(for: .count())
            }
            let today = cal.startOfDay(for: now)
            let history = (1...7).compactMap { offset -> Double? in
                guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return daily[day]
            }.sorted()
            if history.count >= 5, let todayCount = daily[today], history[history.count / 2] >= 1500,
               todayCount < history[history.count / 2] / 2 {
                observations.append(PersonalObservation(id: "activity.lower", titleKey: "profile.alert.steps.title",
                    messageKey: "profile.alert.steps.body", measurement: String(format: "%.0f", todayCount),
                    date: now, level: .informational, sourceKey: "profile.source.health"))
            }
        }
        // Never infer dehydration from absence of dietary records. This optional comparison
        // only runs if the person explicitly states all drinks are recorded.
        if UserDefaults.standard.bool(forKey: "oranaplo.water.allRecorded"),
           Calendar.current.component(.hour, from: now) >= 20,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
            let start = Calendar.current.startOfDay(for: now)
            if let samples = try? await reader.samples(type, since: start, limit: 1200), !samples.isEmpty {
                let total = samples.compactMap { $0 as? HKQuantitySample }
                    .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .literUnit(with: .milli)) }
                let goal = UserDefaults.standard.double(forKey: "oranaplo.water.goalML")
                if goal >= 250, goal <= 10000, total < goal * 0.8 {
                    observations.append(PersonalObservation(id: "water.lower", titleKey: "profile.alert.water.title",
                        messageKey: "profile.alert.water.body", measurement: String(format: "%.0f / %.0f mL", total, goal),
                        date: now, level: .informational, sourceKey: "profile.source.health"))
                }
            }
        }
        return observations.sorted { $0.level == .urgent && $1.level != .urgent }
    }
}
