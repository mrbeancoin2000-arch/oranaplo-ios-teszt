import Foundation
@main struct SleepCoreChecks {
    static func main() {
        let start=Date(timeIntervalSince1970:0)
        let window=DateInterval(start:start,end:start.addingTimeInterval(8*3600))
        let segments=[DateInterval(start:start.addingTimeInterval(-1800),end:start.addingTimeInterval(3600)),
                      DateInterval(start:start.addingTimeInterval(1800),end:start.addingTimeInterval(7200)),
                      DateInterval(start:start.addingTimeInterval(7200),end:start.addingTimeInterval(7800))]
        // [0,7200] + [7200,7800] -> 130 minutes, not 160 from overlapping samples.
        assert(abs(SleepDurationCore.minutes(segments,clipping:window)-130)<0.01)
        assert(SleepDurationCore.comparison(previous:[420,440,460],latest:480) != nil)
        assert(SleepDurationCore.comparison(previous:[420,440],latest:480)==nil)
        assert(SleepDurationCore.comparison(previous:[480,480,480],latest:360)! < -0.20)
        print("PASS: overlaps merged; clipping; baseline requires >=3 nights; shorter-night classification")
    }
}
