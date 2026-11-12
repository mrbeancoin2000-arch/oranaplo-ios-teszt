import Foundation
@main struct Check {
    static func main() {
        let date=Date(timeIntervalSince1970:1700000000)
        let route=[RunRoutePoint(date:date,latitude:47.0,longitude:19.0,horizontalAccuracy:5,activeSeconds:0,cumulativeMeters:0,breakBefore:false),
                   RunRoutePoint(date:date.addingTimeInterval(120),latitude:47.0003,longitude:19.0,horizontalAccuracy:5,activeSeconds:120,cumulativeMeters:300,breakBefore:false)]
        let base=RecordedRun(id:UUID(),started:date,ended:date.addingTimeInterval(120),activeSeconds:120,
                             gpsMeters:300,steps:nil,estimatedKcal:nil,kilograms:nil,centimeters:nil,route:route,
                             heart:[],stepHistory:[],activeWindows:[],completed:true,interrupted:false)
        var other=base
        other.id=UUID();other.activeSeconds=115
        assert(AdvancedRunMath.compare(base,other)?.timeDifferenceSeconds == 5)
        other.route[0].latitude=48.0
        assert(AdvancedRunMath.compare(base,other) == nil)
        print("[PASS] Advanced running route comparison tests")
    }
}
