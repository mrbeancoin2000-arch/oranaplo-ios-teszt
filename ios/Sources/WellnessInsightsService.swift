import Foundation
import HealthKit
import Combine
import UserNotifications

struct HealthReading: Identifiable {
    let id: UUID
    let at: Date
    let end: Date
    let value: Double
    let unit: String
    let source: String
    let device: String
}
struct SleepNight: Identifiable {
    let id: Date
    let stages: [SleepPeriod]
    let asleepMinutes: Double
    let bedtime: Date?
    let wake: Date?
    let respiratoryMean: Double?
    let wristTemperatureMean: Double?
    var awakenings: Int { stages.filter { $0.stage == "awake" }.count }
}
struct WellnessInsightsSnapshot {
    var resting: [PeriodMean] = []
    var hrv: [PeriodMean] = []
    var pulseHRVCorrelation: Double?
    var matchedDays = 0
    var sleepAndNextDayRestingCorrelation:Double?
    var sleepAndNextDayHRVCorrelation:Double?
    var nextDayPairs:Int = 0
    var currentWeight: HealthReading?
    var currentBodyFat: HealthReading?
    var currentLeanMass: HealthReading?
    var wristTempDeviation:Double?
    var nights: [SleepNight] = []
    var sleepRegularity: Double?
    var sleepDebtMinutes: Double?
    var recovery: [RecoveryPoint] = []
    var latestResting: HealthReading?
    var latestHRV: HealthReading?
    var sourceSamples: [HealthReading] = []
    var error: String?
    var refreshedAt: Date?
}

@MainActor
final class WellnessInsightsService: ObservableObject {
    static let shared = WellnessInsightsService()
    @Published private(set) var snapshot = WellnessInsightsSnapshot()
    @Published private(set) var loading = false
    private let reader = HealthReader.shared

    private func quantity(_ identifier: HKQuantityTypeIdentifier, since: Date, until: Date = Date(), unit: HKUnit) async -> [HealthReading] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        // Do not turn missing or unauthorized samples into "normal" zero values.
        guard let records = try? await reader.samples(type, since: since, until: until, limit: 35000) else { return [] }
        return records.compactMap { item in
            guard let q = item as? HKQuantitySample else { return nil }
            let value = q.quantity.doubleValue(for: unit)
            guard value.isFinite else { return nil }
            return HealthReading(id: item.uuid, at: item.startDate, end: item.endDate,
                                 value: value, unit: unit.unitString,
                                 source: item.sourceRevision.source.name, device: item.device?.name ?? "—")
        }.sorted { $0.at < $1.at }
    }
    func refresh() async {
        guard !loading, HKHealthStore.isHealthDataAvailable() else { return }
        loading=true
        defer { loading=false }
        let now=Date(), since=now.addingTimeInterval(-91*86400)
        async let restingQuery=quantity(.restingHeartRate,since:since,unit:HKUnit.count().unitDivided(by:.minute()))
        async let hrvQuery=quantity(.heartRateVariabilitySDNN,since:since,unit:.secondUnit(with:.milli))
        async let respQuery=quantity(.respiratoryRate,since:now.addingTimeInterval(-15*86400),unit:HKUnit.count().unitDivided(by:.minute()))
        async let tempQuery=quantity(.appleSleepingWristTemperature,since:now.addingTimeInterval(-15*86400),unit:.degreeCelsius())
        async let massQuery=quantity(.bodyMass,since:now.addingTimeInterval(-365*86400),unit:.gramUnit(with:.kilo))
        async let fatQuery=quantity(.bodyFatPercentage,since:now.addingTimeInterval(-365*86400),unit:.percent())
        async let leanQuery=quantity(.leanBodyMass,since:now.addingTimeInterval(-365*86400),unit:.gramUnit(with:.kilo))
        let resting=await restingQuery, hrv=await hrvQuery
        let resp=await respQuery, temp=await tempQuery
        let masses=await massQuery, fats=await fatQuery, lean=await leanQuery
        var next=WellnessInsightsSnapshot()
        let rests=resting.map { TimeValue(date:$0.at,value:$0.value) }
        let hrvs=hrv.map { TimeValue(date:$0.at,value:$0.value) }
        next.resting=[7,30,90].map { WellnessMath.baseline(rests,days:$0,now:now) }
        next.hrv=[7,30,90].map { WellnessMath.baseline(hrvs,days:$0,now:now) }
        next.latestResting=resting.last
        next.latestHRV=hrv.last
        next.currentWeight=masses.last
        next.currentBodyFat=fats.last
        next.currentLeanMass=lean.last
        next.sourceSamples=Array((Array(resting.suffix(10)) + Array(hrv.suffix(10))).sorted { $0.at > $1.at })
        let common=WellnessMath.dailyPairs(heart:rests,hrv:hrvs)
        next.matchedDays=common.heart.count
        next.pulseHRVCorrelation=WellnessMath.pearson(common.heart,common.hrv)
        let calendar=Calendar.current
        let sleepStart=now.addingTimeInterval(-16*86400)
        if let sleepType=HKObjectType.categoryType(forIdentifier:.sleepAnalysis),
           let samples=try? await reader.samples(sleepType,since:sleepStart,until:now,limit:15000) {
            let categories=samples.compactMap{$0 as? HKCategorySample}
            for daysAgo in (0..<14).reversed() {
                guard let midnight=calendar.date(byAdding:.day,value:-daysAgo,to:calendar.startOfDay(for:now)),
                      let before=calendar.date(byAdding:.hour,value:-6,to:midnight),
                      let end=calendar.date(byAdding:.hour,value:12,to:midnight) else { continue }
                let window=DateInterval(start:before,end:min(end,now))
                guard window.duration > 0 else { continue }
                let stageSamples: [SleepPeriod] = categories.compactMap { sample in
                    guard sample.endDate > window.start && sample.startDate < window.end else { return nil }
                    let stage:String
                    switch HKCategoryValueSleepAnalysis(rawValue:sample.value) {
                    case .asleepCore: stage="core"
                    case .asleepDeep: stage="deep"
                    case .asleepREM: stage="rem"
                    case .asleepUnspecified: stage="asleep"
                    case .awake: stage="awake"
                    case .inBed: stage="inbed"
                    default: return nil
                    }
                    return SleepPeriod(start:max(sample.startDate,window.start),end:min(sample.endDate,window.end),stage:stage)
                }.sorted {$0.start < $1.start}
                let actual=stageSamples.filter { ["core","deep","rem","asleep"].contains($0.stage) }
                let total=WellnessMath.unionMinutes(actual.map{DateInterval(start:$0.start,end:$0.end)})
                guard total > 0 else { continue }
                func average(_ points:[HealthReading]) -> Double? {
                    let values=points.filter{$0.at>=window.start && $0.at<window.end}.map(\.value)
                    return values.isEmpty ? nil : values.reduce(0,+)/Double(values.count)
                }
                next.nights.append(SleepNight(id:midnight,stages:stageSamples,asleepMinutes:total,
                                  bedtime:actual.map(\.start).min(), wake:actual.map(\.end).max(),
                                  respiratoryMean:average(resp),wristTemperatureMean:average(temp)))
            }
        }
        let recent=Array(next.nights.suffix(7))
        next.sleepRegularity=WellnessMath.regularity(bedtimes:recent.compactMap(\.bedtime),waketimes:recent.compactMap(\.wake))
        next.sleepDebtMinutes=WellnessMath.sleepDebt(actualMinutes:recent.map(\.asleepMinutes))
        if let last=recent.last?.wristTemperatureMean {
            let previous=recent.dropLast().compactMap(\.wristTemperatureMean)
            if previous.count >= 3 { next.wristTempDeviation=last-previous.reduce(0,+)/Double(previous.count) }
        }
        var durations:[Double]=[], restVals:[Double]=[],hrvVals:[Double]=[]
        for night in recent {
            let since=night.id, until=since.addingTimeInterval(86400)
            let localRest=resting.filter{$0.at>=since && $0.at<until}
            let localHRV=hrv.filter{$0.at>=since && $0.at<until}
            if !localRest.isEmpty && !localHRV.isEmpty {
                durations.append(night.asleepMinutes)
                restVals.append(localRest.reduce(0){$0+$1.value}/Double(localRest.count))
                hrvVals.append(localHRV.reduce(0){$0+$1.value}/Double(localHRV.count))
            }
        }
        next.nextDayPairs=durations.count
        next.sleepAndNextDayRestingCorrelation=WellnessMath.pearson(durations,restVals)
        next.sleepAndNextDayHRVCorrelation=WellnessMath.pearson(durations,hrvVals)
        if let workout=(try? await reader.getWorkouts(since:now.addingTimeInterval(-14*86400)))?.first {
            if let pulse=try? await reader.heartSamples(from:workout.endDate.addingTimeInterval(-30),to:workout.endDate.addingTimeInterval(630)) {
                next.recovery=WellnessMath.recovery(pulse.map{TimeValue(date:$0.0,value:$0.1)},workoutEnded:workout.endDate)
            }
        }
        next.refreshedAt=now
        snapshot=next
        WellnessWidgetCache.publishIfPermitted(restingBPM:next.latestResting?.value,hrvMS:next.latestHRV?.value)
        await notifyIfUnusualRestingPulse(next,now:now)
    }
    private func notifyIfUnusualRestingPulse(_ snapshot:WellnessInsightsSnapshot,now:Date) async {
        guard UserDefaults.standard.bool(forKey:"oranaplo.wellness.unusualPulseEnabled"),
              let last=snapshot.latestResting,now.timeIntervalSince(last.at) < 7200,
              let baseline=snapshot.resting.first(where:{$0.days == 30}),
              baseline.samples >= 5,let average=baseline.mean,
              abs(last.value-average) >= 20 else { return }
        let key="oranaplo.wellness.lastRestingAlert"
        if let previous=UserDefaults.standard.object(forKey:key) as? Date,
           Calendar.current.isDate(previous,inSameDayAs:now) { return }
        let center=UNUserNotificationCenter.current()
        guard (await center.notificationSettings()).authorizationStatus == .authorized else { return }
        let lang=UserDefaults.standard.string(forKey:"oranaplo.app.language") ?? "hu"
        let text=lang == "de" ? "Ungewöhnlicher Ruhepuls" : lang == "en" ? "Unusual resting heart rate" : "Szokatlan nyugalmi pulzus"
        let content=UNMutableNotificationContent()
        content.title=text
        content.body=String(format:"%.0f bpm (30d: %.0f bpm).",last.value,average)
        do {
            try await center.add(UNNotificationRequest(identifier:"oranaplo.resting.\(Int(now.timeIntervalSince1970))",content:content,trigger:nil))
            UserDefaults.standard.set(now,forKey:key)
        } catch { /* Best effort; never claim that an alert was delivered. */ }
    }
}
