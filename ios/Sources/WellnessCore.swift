import Foundation

// Pure algorithms: no HealthKit permission, no fabricated medical results.
struct TimeValue: Codable, Hashable {
    let date: Date
    let value: Double
}
struct PeriodMean: Hashable {
    let days: Int
    let mean: Double?
    let samples: Int
}
struct SleepPeriod: Hashable, Identifiable {
    var id: String { "\(start.timeIntervalSince1970):\(end.timeIntervalSince1970):\(stage)" }
    let start: Date
    let end: Date
    let stage: String
}
struct RecoveryPoint: Hashable, Identifiable {
    var id: Int { minute }
    let minute: Int
    let heartRate: Double?
    let drop: Double?
}
enum WellnessMath {
    static func baseline(_ points: [TimeValue], days: Int, now: Date) -> PeriodMean {
        let lower = now.addingTimeInterval(-Double(days) * 86400)
        let selected = points.filter { $0.date >= lower && $0.date <= now && $0.value.isFinite && $0.value > 0 }
        return PeriodMean(days: days, mean: selected.isEmpty ? nil : selected.reduce(0) { $0 + $1.value } / Double(selected.count), samples: selected.count)
    }
    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 4 else { return nil }
        let pairs = zip(x,y).filter { $0.0.isFinite && $0.1.isFinite }
        guard pairs.count >= 4 else { return nil }
        let n = Double(pairs.count)
        let mx = pairs.reduce(0.0) { $0 + $1.0 } / n
        let my = pairs.reduce(0.0) { $0 + $1.1 } / n
        var xx=0.0, yy=0.0, xy=0.0
        for (a,b) in pairs { xx += (a-mx)*(a-mx); yy += (b-my)*(b-my); xy += (a-mx)*(b-my) }
        guard xx > 0, yy > 0 else { return nil }
        return xy / sqrt(xx * yy)
    }
    // Never sum overlapping sleep samples: multiple devices can write concurrent periods.
    static func unionMinutes(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var seconds = 0.0
        for next in sorted.dropFirst() {
            if next.start <= current.end { current = DateInterval(start:current.start,end:max(current.end,next.end)) }
            else { seconds += current.duration; current = next }
        }
        return (seconds + current.duration) / 60
    }
    // A 0–100 consistency score reflects bedtime / wake-time spread, not a diagnosis.
    static func regularity(bedtimes: [Date], waketimes: [Date], calendar: Calendar = .current) -> Double? {
        guard bedtimes.count >= 3, waketimes.count >= 3 else { return nil }
        func spread(_ dates:[Date]) -> Double {
            let minutes = dates.map { Double(calendar.component(.hour,from:$0)*60 + calendar.component(.minute,from:$0)) }
            let angle = minutes.map { $0 * 2 * Double.pi / 1440 }
            let mid = atan2(angle.reduce(0){$0+sin($1)}/Double(angle.count),angle.reduce(0){$0+cos($1)}/Double(angle.count))
            let mean = mid < 0 ? mid + 2 * Double.pi : mid
            return angle.map { min(abs($0-mean), 2*Double.pi-abs($0-mean)) * 1440/(2*Double.pi) }.reduce(0,+)/Double(angle.count)
        }
        return max(0,min(100,100-(spread(bedtimes)+spread(waketimes))*0.45))
    }
    static func sleepDebt(actualMinutes: [Double], goalMinutes: Double = 480) -> Double? {
        let valid = actualMinutes.filter { $0 > 0 && $0.isFinite }
        guard valid.count >= 3, goalMinutes > 0 else { return nil }
        return valid.reduce(0) { $0 + max(0,goalMinutes-$1) }
    }
    // A valid recovery value needs measurements near the end and near each target minute.
    static func recovery(_ points:[TimeValue], workoutEnded:Date) -> [RecoveryPoint] {
        func near(_ seconds:Double, tolerance:Double) -> Double? {
            let target=workoutEnded.addingTimeInterval(seconds)
            return points.filter { abs($0.date.timeIntervalSince(target)) <= tolerance && $0.value > 0 && $0.value.isFinite }
                .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }?.value
        }
        let endValue=near(0,tolerance:30)
        return [1,2,3,4,5,10].map { min in
            let at=near(Double(min)*60,tolerance:30)
            return RecoveryPoint(minute:min,heartRate:at,drop:(endValue != nil && at != nil) ? endValue!-at! : nil)
        }
    }
    static func dailyPairs(heart:[TimeValue],hrv:[TimeValue],calendar:Calendar = .current) -> (heart:[Double],hrv:[Double]) {
        func means(_ samples:[TimeValue]) -> [Date:Double] {
            let grouped=Dictionary(grouping:samples.filter{$0.value>0 && $0.value.isFinite},by:{calendar.startOfDay(for:$0.date)})
            return grouped.mapValues { $0.reduce(0){$0+$1.value} / Double($0.count) }
        }
        let a=means(heart), b=means(hrv)
        let common=Set(a.keys).intersection(b.keys).sorted()
        return (common.compactMap{a[$0]},common.compactMap{b[$0]})
    }
}
