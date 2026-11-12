import Foundation

struct AdvancedRunSegment: Identifiable {
    let index:Int
    var id:Int { index }
    let cadence:Double?
    let estimatedStrideM:Double?
    let ascentM:Double?
    let descentM:Double?
}
struct GradeSpeedComparison:Hashable {
    let uphillKmh:Double?
    let downhillKmh:Double?
    let flatKmh:Double?
}
struct RouteComparison:Hashable {
    let priorID:UUID
    let timeDifferenceSeconds:Double
    let distanceDifferenceMeters:Double
}
enum AdvancedRunMath {
    static func compare(_ current:RecordedRun,_ candidate:RecordedRun) -> RouteComparison? {
        guard current.id != candidate.id, current.completed,candidate.completed,
              let first=current.route.first, let otherFirst=candidate.route.first,
              let last=current.route.last, let otherLast=candidate.route.last,
              current.gpsMeters > 100, candidate.gpsMeters > 100 else { return nil }
        let startDist=RunMath.distance(first,otherFirst)
        let endDist=RunMath.distance(last,otherLast)
        let length=abs(current.gpsMeters-candidate.gpsMeters)
        // No comparison on unrelated routes merely because the distance matches.
        guard startDist < 80,endDist < 80,length < max(70,current.gpsMeters*0.06) else { return nil }
        return RouteComparison(priorID:candidate.id,timeDifferenceSeconds:current.activeSeconds-candidate.activeSeconds,
                               distanceDifferenceMeters:current.gpsMeters-candidate.gpsMeters)
    }
    static func gradeSpeed(_ route:[RunRoutePoint]) -> GradeSpeedComparison {
        var totals:[(distance:Double,seconds:Double)] = Array(repeating:(0,0),count:3)
        if route.count > 1 { for i in 1..<route.count {
            let a=route[i-1],b=route[i]
            guard !b.breakBefore,let startElevation=a.altitudeMeters,
                  let endElevation=b.altitudeMeters else { continue }
            let distance=b.cumulativeMeters-a.cumulativeMeters
            let duration=b.activeSeconds-a.activeSeconds
            guard distance >= 5, duration > 0, distance/duration <= 12 else { continue }
            let slope=(endElevation-startElevation)/distance
            let bucket=slope > 0.02 ? 0 : slope < -0.02 ? 1 : 2
            totals[bucket].distance += distance
            totals[bucket].seconds += duration
        } }
        func speed(_ index:Int)->Double? {
            let segment=totals[index]
            return segment.seconds >= 15 && segment.distance >= 30 ? segment.distance/segment.seconds*3.6 : nil
        }
        return GradeSpeedComparison(uphillKmh:speed(0),downhillKmh:speed(1),flatKmh:speed(2))
    }
    static func analyze(_ run:RecordedRun) -> [AdvancedRunSegment] {
        run.splits.map { split in
            let cadence:Double? = (split.steps != nil && split.steps! > 0 && split.elapsedSeconds > 0) ?
                Double(split.steps!)/split.elapsedSeconds*60 : nil
            let stride:Double? = (split.steps != nil && split.steps! > 0) ? 100/Double(split.steps!) : nil
            let relevant=run.route.filter { $0.cumulativeMeters >= Double(split.index-1)*100 && $0.cumulativeMeters <= Double(split.index)*100 }
            var ascent=0.0,descent=0.0,valid=0
            if relevant.count > 1 { for i in 1..<relevant.count {
                let a=relevant[i-1],b=relevant[i]
                guard !b.breakBefore,let m1=a.altitudeMeters,let m2=b.altitudeMeters else { continue }
                let d=m2-m1
                // Suppress tiny altitude jumps at GPS noise level.
                if d >= 2 { ascent += d;valid += 1 }
                if d <= -2 { descent += -d;valid += 1 }
            }
            } // End guarded pair iteration
            return AdvancedRunSegment(index:split.index,cadence:cadence,estimatedStrideM:stride,
                                      ascentM:valid>0 ? ascent : nil,descentM:valid>0 ? descent : nil)
        }
    }
}
