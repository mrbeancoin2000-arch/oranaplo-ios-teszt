import Foundation

@main struct InsightsRuntime {
    static func main() {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        func run(uuid:String, meters:Int, stepMeters:Double=50, secondsPerStep:Double=25,
                 breaks:Set<Int> = []) -> RecordedRun {
            let id=UUID(uuidString:uuid)!
            var points: [RunRoutePoint] = []
            let total = Int(Double(meters) / stepMeters)
            for i in 0...total {
                let offset = Double(i) * secondsPerStep
                let metres = Double(i) * stepMeters
                let point = RunRoutePoint(date:origin.addingTimeInterval(offset),latitude:47,longitude:19,
                    horizontalAccuracy:4,activeSeconds:offset,cumulativeMeters:metres,
                    breakBefore:(i==0 || breaks.contains(i)))
                points.append(point)
            }
            return RecordedRun(id:id,started:origin,ended:origin.addingTimeInterval(Double(points.count)*secondsPerStep),
                activeSeconds:Double(points.count)*secondsPerStep,gpsMeters:Double(meters),steps:nil,
                estimatedKcal:nil,kilograms:nil,centimeters:nil,route:points,heart:[],stepHistory:[],
                activeWindows:[],completed:true,interrupted:false)
        }
        let id1="00000000-0000-0000-0000-000000000001"
        let id2="00000000-0000-0000-0000-000000000002"
        let first=run(uuid:id1,meters:6000)
        assert(abs((RunInsights.fastest(first,meters:1000) ?? -1)-500)<0.001)
        assert(abs((RunInsights.fastest(first,meters:5000) ?? -1)-2500)<0.001)
        assert(RunInsights.fastest(first,meters:10000)==nil)
        let quick=run(uuid:id2,meters:6000,secondsPerStep:20)
        let newRecords=RunInsights.newlyBroken(after:quick,previous:[first])
        assert(Set(newRecords.map(\.distanceMeters))==Set([1000,5000]))
        assert(RunInsights.newlyBroken(after:first,previous:[quick]).isEmpty)
        assert(RunInsights.records([first,quick]).first?.runID==quick.id)
        let interrupted=run(uuid:id1,meters:6000,breaks:[40])
        assert(RunInsights.fastest(interrupted,meters:5000)==nil) // gap disqualifies invented continuous 5k
        var unfinished=first;unfinished.completed=false
        assert(RunInsights.fastest(unfinished,meters:1000)==nil)
        let summary=RunInsights.goals([first],now:origin.addingTimeInterval(12*3600),weeklyGoalKM:5)
        assert(summary.weeklyMeters == 6000)
        assert(summary.monthlyMeters == 6000)
        assert(summary.weeklyStreak == 1)
        assert(summary.activeDaysThisWeek == 1)
        let empty=RunInsights.goals([],now:origin,weeklyGoalKM:5)
        assert(empty.weeklyStreak == 0 && empty.weeklyMeters == 0)
        let sampleEntries = [RunHistoryEntry(id:first.id,started:first.started,gpsMeters:6000),
            RunHistoryEntry(id:quick.id,started:quick.started,gpsMeters:6000)]
        let lifetime = RunInsights.historicalGoals(sampleEntries,now:origin.addingTimeInterval(12*3600),weeklyGoalKM:10)
        assert(lifetime.weeklyMeters == 12000)
        assert(lifetime.monthlyMeters == 12000)
        assert(lifetime.weeklyStreak == 1)
        assert(lifetime.activeDaysThisWeek == 1)
        print("RunningInsights: 16/16 checks passed (GPS, splits, PR, streak, long-term archive)")
    }
}
