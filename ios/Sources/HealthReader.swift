import Foundation
import HealthKit
import UIKit
import CoreLocation

/// Reads authorized HealthKit records. The Apple Health read permission is requested per type.
final class HealthReader {
    static let shared = HealthReader()
    let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var observedTypeIDs: Set<String> = []

    func authorize(onlyHeartRate: Bool = false) async throws {
        CrashCheckpoint.mark(onlyHeartRate ? "HealthKit alapteszt: előkészítés" : "HealthKit teljes engedélykérés: előkészítés")
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SyncError.config("Az Apple Egészség ezen a készüléken nem elérhető")
        }
        var types = Set<HKObjectType>()
        if onlyHeartRate {
            guard let rate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                throw SyncError.config("Pulzus HealthKit-típus nem érhető el")
            }
            types.insert(rate)
            // Free mode may show the most recent workout *in-app*; it does not
            // export those records to Sheets and does not require Pro to read.
            types.insert(HKObjectType.workoutType())
        } else {
            for metric in Catalog.metrics { if let t = metric.sampleType { types.insert(t) } }
            types.insert(HKObjectType.workoutType())
            types.insert(HKSeriesType.workoutRoute())
            types.insert(HKObjectType.electrocardiogramType())
            types.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth))
            types.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex))
        }
        // Runtime preflight: the Xcode source plist alone is not proof that the
        // IPA or Sideloadly-re-signed app still contains these privacy strings.
        for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
            let purpose = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !purpose.isEmpty else {
                CrashCheckpoint.mark("HealthKit megállítva: hiányzik a telepített appból: \(key)")
                throw SyncError.config("HealthKit engedélykérés nem indítható: a telepített app Info.plist fájljából hiányzik: \(key)")
            }
        }
        CrashCheckpoint.mark(onlyHeartRate ? "HealthKit alapteszt: biztonságos engedélykérés indul" : "HealthKit teljes: biztonságos engedélykérés indul")
        // Catch NSException in Objective-C; it cannot be caught by Swift do/catch.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            HealthAuthorizationBridge.requestAuthorization(store: store, readTypes: types) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: SyncError.config("HealthKit engedélykérés nem sikerült")) }
            }
        }
        CrashCheckpoint.mark(onlyHeartRate ? "HealthKit alapteszt: engedélykérés visszatért" : "HealthKit teljes: engedélykérés visszatért")
    }

    /// Optional, separate consent for the local health profile and informational insights.
    /// No DOB/sex/weight/height is uploaded automatically to Google Sheets.
    func authorizeProfile() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SyncError.config("Az Apple Egészség nem érhető el ezen a készüléken")
        }
        var types: Set<HKObjectType> = [
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)
        ]
        let ids: [HKQuantityTypeIdentifier] = [
            .height, .bodyMass, .stepCount, .dietaryWater,
            .bloodPressureSystolic, .bloodPressureDiastolic
        ]
        for id in ids {
            if let type = HKObjectType.quantityType(forIdentifier: id) { types.insert(type) }
        }
        for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
            guard let reason = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SyncError.config("Hiányzik a HealthKit adatvédelmi leírás: \(key)")
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            HealthAuthorizationBridge.requestAuthorization(store: store, readTypes: types) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: SyncError.config("Egészségprofil engedélyezése sikertelen")) }
            }
        }
    }

    func samplePage(_ type: HKSampleType, since: Date, anchor: HKQueryAnchor?, limit: Int = 300) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?, Int) {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: limit) { _, added, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (added ?? [], deleted ?? [], next, (added ?? []).count + (deleted ?? []).count)) }
            }
            store.execute(query)
        }
    }
    func samples(_ type: HKSampleType, since: Date, until: Date? = nil, limit: Int = 1500, predicate: NSPredicate? = nil) async throws -> [HKSample] {
        let p = predicate ?? HKQuery.predicateForSamples(withStart: since, end: until, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: p, limit: limit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, rows, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: rows ?? []) }
            }
            store.execute(query)
        }
    }
    func getWorkouts(since: Date) async throws -> [HKWorkout] {
        try await samples(HKObjectType.workoutType(), since: since, limit: 1000).compactMap { $0 as? HKWorkout }
    }
    func heartSamples(from: Date, to: Date) async throws -> [(Date,Double)] {
        guard let t = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let samples = try await self.samples(t, since: from, until: to, limit: 10000)
        return samples.compactMap { s in
            guard let q = s as? HKQuantitySample else { return nil }
            return (q.startDate, q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        }.sorted { $0.0 < $1.0 }
    }
    func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes = try await samples(HKSeriesType.workoutRoute(), since: workout.startDate, predicate: predicate).compactMap { $0 as? HKWorkoutRoute }
        var locations: [CLLocation] = []
        for route in routes {
            let batch: [CLLocation] = try await withCheckedThrowingContinuation { cont in
                var buffer: [CLLocation] = []
                var finished = false
                let query = HKWorkoutRouteQuery(route: route) { _, newLocations, done, error in
                    if finished { return }
                    if let error { finished = true; cont.resume(throwing: error); return }
                    buffer.append(contentsOf: newLocations ?? [])
                    if done { finished = true; cont.resume(returning: buffer) }
                }
                store.execute(query)
            }
            locations += batch
        }
        // Time sorting, duplicates and inaccurate fixes are filtered in segmentation.
        return locations.sorted { $0.timestamp < $1.timestamp }
    }
    func ecgs(since: Date) async throws -> [HKElectrocardiogram] {
        try await samples(HKObjectType.electrocardiogramType(), since: since, limit: 500).compactMap { $0 as? HKElectrocardiogram }
    }
    func ecgVoltages(_ ecg: HKElectrocardiogram) async throws -> [(Date,Double)] {
        try await withCheckedThrowingContinuation { cont in
            var values: [(Date,Double)] = []
            var isDone = false
            let q = HKElectrocardiogramQuery(ecg) { _, result in
                if isDone { return }
                switch result {
                case .measurement(let m):
                    if let voltage = m.quantity(for: .appleWatchSimilarToLeadI) {
                        values.append((m.timeSinceSampleStart >= 0 ? ecg.startDate.addingTimeInterval(m.timeSinceSampleStart) : ecg.startDate,
                                       voltage.doubleValue(for: .voltUnit(with: .milli))))
                    }
                case .done:
                    isDone = true; cont.resume(returning: values)
                case .error(let error):
                    isDone = true; cont.resume(throwing: error)
                @unknown default: break
                }
            }
            store.execute(q)
        }
    }
    /// Register on launch and following authorization. HealthKit controls when callbacks occur;
    /// this is never a promise of minute-by-minute updates.
    func installObserverQueries() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let full = UserDefaults.standard.bool(forKey: "healthFullCompleted")
        let metricIDs: [HKQuantityTypeIdentifier] = full ? [.heartRate, .stepCount, .heartRateVariabilitySDNN] : [.heartRate]
        for identifier in metricIDs {
            guard observedTypeIDs.insert(identifier.rawValue).inserted else { continue }
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { _, finished, error in
                guard error == nil else { finished(); return }
                Task { @MainActor in
                    // The sync engine persists rows before acknowledging the observer event.
                    // An unsuccessful upload stays in the local durable queue for catch-up.
                    await SyncEngine.shared.sync()
                    finished()
                }
            }
            observers.append(observer)
            store.execute(observer)
        }
    }

    func enableBackgroundNotifications() async {
        installObserverQueries()
        let types: [HKQuantityTypeIdentifier] = UserDefaults.standard.bool(forKey: "healthFullCompleted") ?
            [.heartRate, .stepCount, .heartRateVariabilitySDNN] : [.heartRate]
        for id in types {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            _ = try? await store.enableBackgroundDelivery(for: type, frequency: .hourly)
        }
    }
}

func rawRow(_ sample: HKSample, metric: Metric) -> ExportRow {
    var value = ""
    var detail = ""
    if let q = sample as? HKQuantitySample {
        value = String(q.quantity.doubleValue(for: metric.quantityUnit))
    } else if let cat = sample as? HKCategorySample {
        value = String(cat.value)
        if metric.label == "Alvásszakasz" {
            switch cat.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue: detail = "Ágyban"
            case HKCategoryValueSleepAnalysis.awake.rawValue: detail = "Ébren"
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: detail = "Core / könnyű"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: detail = "Mély"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: detail = "REM"
            default: detail = "Egyéb"
            }
        }
    }
    return ExportRow(id: "hk:\(sample.uuid.uuidString)", sheet: metric.sheet, values: [
        sample.uuid.uuidString, metric.label, ISO.string(sample.startDate), ISO.string(sample.endDate),
        value, metric.unit, sample.sourceRevision.source.name, sample.device?.name ?? "", detail, "aktív", ISO.string(Date())
    ])
}

func deletedRow(_ deleted: HKDeletedObject, metric: Metric) -> ExportRow {
    ExportRow(id: "deleted:\(deleted.uuid.uuidString)", sheet: metric.sheet,
              values: [deleted.uuid.uuidString, metric.label, "", "", "", "", "HealthKit", "", "HealthKitből törölve", "törölve", ISO.string(Date())])
}
