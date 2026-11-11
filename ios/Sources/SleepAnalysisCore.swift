import Foundation

/// Deduplicates overlapping asleep intervals (inBed and awake must be filtered before use).
enum SleepDurationCore {
    static func minutes(_ ranges: [DateInterval], clipping to: DateInterval) -> Double {
        let clipped = ranges.compactMap { interval -> DateInterval? in
            let start = max(interval.start, to.start)
            let end = min(interval.end, to.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var seconds = 0.0
        var lastEnd = to.start
        for interval in clipped {
            let start = max(lastEnd, interval.start)
            if interval.end > start { seconds += interval.end.timeIntervalSince(start) }
            lastEnd = max(lastEnd, interval.end)
        }
        return seconds / 60
    }
    static func comparison(previous: [Double], latest: Double) -> Double? {
        let reliable = previous.filter { $0.isFinite && $0 > 60 && $0 < 1200 }
        guard reliable.count >= 3, latest.isFinite, latest >= 0 else { return nil }
        let ordered = reliable.sorted()
        let baseline = ordered[ordered.count / 2]
        return baseline > 0 ? (latest - baseline) / baseline : nil
    }
}

