import Foundation

struct RunPersonalRecord: Codable, Equatable, Identifiable {
    var distanceMeters: Int
    var seconds: Double
    var runID: UUID
    var recorded: Date
    var id: Int { distanceMeters }
}
struct RunGoalSummary: Equatable {
    var weeklyMeters: Double
    var monthlyMeters: Double
    var weeklyGoalMeters: Double
    var weeklyStreak: Int
    var activeDaysThisWeek: Int
}
enum RunInsights {
    static let distances = [1_000, 5_000, 10_000, 21_097]
    /// Compare active-time route points within the SAME continuous GPS segment.
    /// A pause, bad GPS fix, or missing section can never produce a phantom record.
    static func fastest(_ run: RecordedRun, meters: Int) -> Double? {
        let points = run.route.sorted { $0.date < $1.date }
        guard meters > 0, run.completed, points.count > 1 else { return nil }
        var best: Double?
        var segment: [RunRoutePoint] = []
        func scan(_ values: [RunRoutePoint]) -> Double? {
            guard values.count >= 2 else { return nil }
            var answer: Double?
            var left = 0
            for right in 1..<values.count {
                let target = values[right].cumulativeMeters - Double(meters)
                while left + 1 < right && values[left + 1].cumulativeMeters <= target { left += 1 }
                guard values[left].cumulativeMeters <= target else { continue }
                let a = values[left], b = values[left + 1]
                let width = b.cumulativeMeters - a.cumulativeMeters
                guard width > 0 else { continue }
                let fraction = max(0, min(1, (target - a.cumulativeMeters)/width))
                let start = a.activeSeconds + fraction * (b.activeSeconds - a.activeSeconds)
                let result = values[right].activeSeconds - start
                if result > 0 && result.isFinite { answer = min(answer ?? result, result) }
            }
            return answer
        }
        for point in points {
            if point.breakBefore && !segment.isEmpty {
                if let result = scan(segment) { best = min(best ?? result, result) }
                segment = []
            }
            segment.append(point)
        }
        if let result = scan(segment) { best = min(best ?? result, result) }
        return best
    }
    static func records(_ runs: [RecordedRun]) -> [RunPersonalRecord] {
        distances.compactMap { distance in
            runs.compactMap { run -> RunPersonalRecord? in
                guard let time = fastest(run, meters: distance) else { return nil }
                return RunPersonalRecord(distanceMeters: distance,seconds: time,runID: run.id,recorded: run.started)
            }.min { $0.seconds < $1.seconds }
        }
    }
    static func newlyBroken(after run: RecordedRun, previous: [RecordedRun]) -> [RunPersonalRecord] {
        guard run.completed else { return [] }
        let previousRecords = Dictionary(uniqueKeysWithValues: records(previous.filter { $0.id != run.id }).map { ($0.distanceMeters,$0) })
        return distances.compactMap { distance in
            guard let time = fastest(run, meters: distance), time > 0,
                  time + 0.5 < (previousRecords[distance]?.seconds ?? .infinity) else { return nil }
            return RunPersonalRecord(distanceMeters:distance,seconds:time,runID:run.id,recorded:run.started)
        }
    }
    static func goals(_ runs: [RecordedRun], now: Date = Date(), weeklyGoalKM: Double = 15,
                      calendar: Calendar = Calendar(identifier:.iso8601)) -> RunGoalSummary {
        let valid = runs.filter { $0.completed && $0.gpsMeters.isFinite && $0.gpsMeters >= 0 }
        let thisWeek = calendar.dateInterval(of:.weekOfYear,for:now)?.start ?? calendar.startOfDay(for:now)
        let thisMonth = calendar.dateInterval(of:.month,for:now)?.start ?? calendar.startOfDay(for:now)
        let weekly = valid.filter { $0.started >= thisWeek && $0.started <= now }.reduce(0.0) { $0 + $1.gpsMeters }
        let monthly = valid.filter { $0.started >= thisMonth && $0.started <= now }.reduce(0.0) { $0 + $1.gpsMeters }
        let activeDays = Set(valid.filter { $0.started >= thisWeek && $0.started <= now }.map { calendar.startOfDay(for:$0.started) }).count
        let goal = max(0,weeklyGoalKM) * 1000
        var streak = 0
        // Count consecutive *complete* past weeks, then include the current one if already met.
        for offset in 0..<52 {
            guard let start = calendar.date(byAdding:.weekOfYear,value:-offset,to:thisWeek),
                  let end = calendar.date(byAdding:.weekOfYear,value:1,to:start) else { break }
            let total = valid.filter { $0.started >= start && $0.started < end }.reduce(0.0) { $0 + $1.gpsMeters }
            if total + 0.001 >= goal && goal > 0 { streak += 1 }
            else if offset > 0 || weekly >= goal { break }
        }
        return RunGoalSummary(weeklyMeters:weekly, monthlyMeters:monthly,
            weeklyGoalMeters:goal,weeklyStreak:streak,activeDaysThisWeek:activeDays)
    }
}

/// Compact, route-free local archive keeps historical goals even after detailed
/// GPS tracks are rotated out of the limited on-device cache.
struct RunHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let started: Date
    let gpsMeters: Double
}
extension RunInsights {
    static func historicalGoals(_ entries:[RunHistoryEntry], now:Date=Date(), weeklyGoalKM:Double=15,
                                calendar:Calendar=Calendar(identifier:.iso8601)) -> RunGoalSummary {
        let valid=entries.filter { $0.gpsMeters.isFinite && $0.gpsMeters >= 0 }
        let thisWeek=calendar.dateInterval(of:.weekOfYear,for:now)?.start ?? calendar.startOfDay(for:now)
        let thisMonth=calendar.dateInterval(of:.month,for:now)?.start ?? calendar.startOfDay(for:now)
        func total(_ start:Date,_ end:Date) -> Double {
            valid.filter { $0.started >= start && $0.started < end }.reduce(0) { $0 + $1.gpsMeters }
        }
        let weekly=total(thisWeek,now.addingTimeInterval(0.001))
        let monthly=total(thisMonth,now.addingTimeInterval(0.001))
        let days=Set(valid.filter { $0.started >= thisWeek && $0.started <= now }
            .map { calendar.startOfDay(for:$0.started) }).count
        let goal=max(0,weeklyGoalKM)*1000
        var streak=0
        for offset in 0..<520 { // 10 years max; not limited to 25 detailed route files
            guard let start=calendar.date(byAdding:.weekOfYear,value:-offset,to:thisWeek),
                  let end=calendar.date(byAdding:.weekOfYear,value:1,to:start) else { break }
            let value=total(start,end)
            if value >= goal && goal > 0 { streak += 1 }
            else if offset > 0 || weekly >= goal { break }
        }
        return RunGoalSummary(weeklyMeters:weekly,monthlyMeters:monthly,weeklyGoalMeters:goal,
                              weeklyStreak:streak,activeDaysThisWeek:days)
    }
}
