import Foundation
import Combine
import HealthKit

/// Real on-device HealthKit data. Nil means unavailable / not shared, never zero.
struct DailyDashboardSnapshot {
    var steps: Int?
    var activeKcal: Double?
    var walkingRunningKM: Double?
    var exerciseMinutes: Double?
    var pulseMean: Double?
    var pulseLow: Double?
    var pulseHigh: Double?
    var lastNightMinutes: Double?
    var comparisonFraction: Double?
    var nightsCompared: Int = 0
    var loadedAt: Date?
}

@MainActor
final class DailyHealthDashboard: ObservableObject {
    @Published private(set) var snapshot = DailyDashboardSnapshot()
    @Published private(set) var busy = false
    @Published private(set) var hadQueryError = false
    static let shared = DailyHealthDashboard()
    private let store = HealthReader.shared.store

    func refresh() async {
        guard !busy, HKHealthStore.isHealthDataAvailable() else { return }
        busy = true
        defer { busy = false }
        let now = Date(), day = Calendar.current.startOfDay(for: now)
        let start = max(day, now.addingTimeInterval(-86400))
        var next = DailyDashboardSnapshot()
        let step = await sum(.stepCount, from: start, to: now, unit: .count())
        next.steps = step.map { Int(max(0, $0.rounded())) }
        next.activeKcal = await sum(.activeEnergyBurned, from: start, to: now, unit: .kilocalorie())
        next.walkingRunningKM = await sum(.distanceWalkingRunning, from: start, to: now, unit: .meter()).map { $0 / 1000 }
        next.exerciseMinutes = await sum(.appleExerciseTime, from: start, to: now, unit: .minute())
        if let pulses = try? await HealthReader.shared.heartSamples(from: start, to: now), !pulses.isEmpty {
            let values = pulses.map(\.1).filter { $0.isFinite && $0 > 0 }
            if !values.isEmpty {
                next.pulseMean = values.reduce(0,+) / Double(values.count)
                next.pulseLow = values.min()
                next.pulseHigh = values.max()
            }
        }
        let sleepStart = Calendar.current.date(byAdding:.day, value:-16, to:day) ?? day.addingTimeInterval(-16*86400)
        if let sleepType = HKObjectType.categoryType(forIdentifier:.sleepAnalysis),
           let raw = try? await HealthReader.shared.samples(sleepType, since:sleepStart, until:now, limit:6000) {
            let asleep = raw.compactMap { $0 as? HKCategorySample }.filter {
                switch HKCategoryValueSleepAnalysis(rawValue:$0.value) {
                case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified: return true
                default: return false
                }
            }.map { DateInterval(start:$0.startDate,end:$0.endDate) }
            var nights:[Double] = []
            // "Last night" is yesterday 18:00 – today 12:00, not today's midnight window.
            for offset in (0...14).reversed() {
                guard let morning = Calendar.current.date(byAdding:.day,value:-offset,to:day),
                      let yesterday = Calendar.current.date(byAdding:.day,value:-1,to:morning),
                      let evening = Calendar.current.date(byAdding:.hour,value:18,to:yesterday),
                      let noon = Calendar.current.date(byAdding:.hour,value:12,to:morning) else { continue }
                let length = SleepDurationCore.minutes(asleep,clipping:DateInterval(start:evening,end:min(noon,now)))
                nights.append(length)
            }
            if let latest = nights.last, latest > 0 {
                next.lastNightMinutes = latest
                let history = Array(nights.dropLast())
                next.nightsCompared = history.filter {$0 > 60}.count
                next.comparisonFraction = SleepDurationCore.comparison(previous:history,latest:latest)
            }
        }
        next.loadedAt = now
        snapshot = next
    }

    /// Apple Health's cumulative statistics handle overlapping sensor sources better than raw summation.
    func sum(_ identifier: HKQuantityTypeIdentifier, from: Date, to: Date, unit: HKUnit) async -> Double? {
        guard from < to, let type = HKObjectType.quantityType(forIdentifier:identifier) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let predicate = HKQuery.predicateForSamples(withStart:from,end:to,options:.strictStartDate)
            let query = HKStatisticsQuery(quantityType:type,quantitySamplePredicate:predicate,options:[.cumulativeSum]) { _, result, error in
                if error != nil { continuation.resume(returning:nil); return }
                guard let value = result?.sumQuantity()?.doubleValue(for:unit), value.isFinite else {
                    continuation.resume(returning:nil); return
                }
                continuation.resume(returning:max(0,value))
            }
            store.execute(query)
        }
    }
}

/// First use of this installation only; never invent a historical installation date.
enum OraUsageClock {
    static let key = "oranaplo.firstUse.local"
    static func register() {
        if UserDefaults.standard.object(forKey:key) == nil { UserDefaults.standard.set(Date(),forKey:key) }
    }
    static var firstUse: Date { UserDefaults.standard.object(forKey:key) as? Date ?? Date() }
    static var days: Int { max(1, (Calendar.current.dateComponents([.day],from:Calendar.current.startOfDay(for:firstUse),to:Date()).day ?? 0)+1) }
}
