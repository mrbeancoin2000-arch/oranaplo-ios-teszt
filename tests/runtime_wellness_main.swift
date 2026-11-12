import Foundation
@main struct WellnessCheck {
    static func main() {
        let now=Date(timeIntervalSince1970:1_700_000_000)
        let points=[TimeValue(date:now.addingTimeInterval(-1800),value:60),TimeValue(date:now.addingTimeInterval(-3600),value:80)]
        assert(WellnessMath.baseline(points,days:7,now:now).mean == 70)
        assert(WellnessMath.baseline([],days:7,now:now).mean == nil)
        assert(WellnessMath.unionMinutes([DateInterval(start:now,end:now.addingTimeInterval(120)),DateInterval(start:now.addingTimeInterval(60),end:now.addingTimeInterval(180))]) == 3)
        assert(WellnessMath.pearson([1,2,3,4],[2,4,6,8])! > 0.99)
        assert(WellnessMath.pearson([1,1,1,1],[2,3,4,5]) == nil)
        let end=TimeValue(date:now,value:160), later=TimeValue(date:now.addingTimeInterval(60),value:125)
        assert(WellnessMath.recovery([end,later],workoutEnded:now).first?.drop == 35)
        assert(WellnessMath.recovery([],workoutEnded:now).first?.drop == nil)
        assert(WellnessMath.sleepDebt(actualMinutes:[400,500,400]) == 160)
        print("[PASS] Wellness core numerical tests")
    }
}
