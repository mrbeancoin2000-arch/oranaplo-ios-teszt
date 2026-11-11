import Foundation

@main struct RunCoreRuntime {
    static func main() throws {
        let origin = Date(timeIntervalSince1970:1_700_000_000)
        var points:[RunRoutePoint] = []
        var meters = 0.0
        for i in 0...7 {
            if i>0 { meters += 50 }
            let p = RunRoutePoint(date:origin.addingTimeInterval(Double(i*25)),
                latitude:47.0+Double(i)*0.0004497,longitude:19, horizontalAccuracy:5,
                activeSeconds:Double(i*25),cumulativeMeters:meters,breakBefore:i==0)
            points.append(p)
        }
        let hearts = [RunPulsePoint(date:origin.addingTimeInterval(30),activeSeconds:30,bpm:124),
                      RunPulsePoint(date:origin.addingTimeInterval(90),activeSeconds:90,bpm:143),
                      RunPulsePoint(date:origin.addingTimeInterval(140),activeSeconds:140,bpm:151)]
        let steps = [RunStepPoint(activeSeconds:0,totalSteps:0),RunStepPoint(activeSeconds:175,totalSteps:280)]
        let segments = RunMath.splits(points,heart:hearts,steps:steps,kilograms:74)
        assert(segments.count == 3)
        assert(abs(segments[0].elapsedSeconds-50)<0.0001)
        assert(abs(segments[0].kmh-7.2)<0.0001)
        assert(abs(segments[0].paceSecondsPerKm-500)<0.0001)
        assert(segments[0].avgHeart == 124)
        assert(segments[0].steps == 80)
        assert(segments[1].avgHeart == 143)
        assert(abs((segments[1].estimatedKcal ?? -1)-7.4)<0.001)
        assert(RunMath.pace(seconds:0,meters:100)==nil)
        assert(RunMath.estimatedRunningKcal(meters:100,kilograms:nil)==nil)
        assert(RunMath.estimatedRunningKcal(meters:100,kilograms:500)==nil)
        assert(RunMath.stepCount(at:0,samples:steps)==0)
        assert(RunMath.stepCount(at:87.5,samples:steps)==140)
        assert(RunMath.activeTime(of:origin.addingTimeInterval(15),windows:[RunActiveWindow(started:origin,ended:origin.addingTimeInterval(25),secondsBefore:0)]) == 15)
        assert(RunMath.activeTime(of:origin.addingTimeInterval(35),windows:[RunActiveWindow(started:origin,ended:origin.addingTimeInterval(25),secondsBefore:0)])==nil)
        // Pauses: elapsed active time must exclude wall-clock gap.
        let start = origin
        let paused = start.addingTimeInterval(80)
        let resumed = start.addingTimeInterval(180)
        let windows = [RunActiveWindow(started:start,ended:paused,secondsBefore:0),
                       RunActiveWindow(started:resumed,ended:start.addingTimeInterval(230),secondsBefore:80)]
        assert(RunMath.activeTime(of:start.addingTimeInterval(120),windows:windows)==nil)
        assert(RunMath.activeTime(of:start.addingTimeInterval(200),windows:windows)==100)
        assert(RunMath.wallDate(forActive:100,windows:windows)==start.addingTimeInterval(200))
        assert(RunMath.wallDate(forActive:75,windows:windows)==start.addingTimeInterval(75))
        assert(RunMath.wallDate(forActive:150,windows:windows)==nil)
        var p2=points
        p2[2].breakBefore=true // no distance between split breaks, cumulative still describes valid distance
        let changed=RunMath.splits(p2,heart:hearts,steps:steps,kilograms:74)
        assert(changed.count == 3)
        let encoded=try JSONEncoder().encode(segments)
        let decoded=try JSONDecoder().decode([RunHundredMeters].self,from:encoded)
        assert(decoded == segments)
        let gap = RunRoutePoint(date:start.addingTimeInterval(999), latitude:47, longitude:19, horizontalAccuracy:5,
            activeSeconds:200,cumulativeMeters:meters,breakBefore:true)
        assert(RunMath.splits([points[0],gap]).isEmpty)
        print("RunMathCore: 18/18 synthetic assertions passed; 100m, pace, distance, HR, steps, kcal, pauses, serialization")
    }
}
