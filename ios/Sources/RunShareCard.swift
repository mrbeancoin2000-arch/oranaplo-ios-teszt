import Foundation
import UIKit
import MapKit

/// Export is explicitly initiated by the person. A running route can expose home/work:
/// never upload or share automatically. The map snapshot is generated on-device.
@MainActor
enum RunShareCard {
    enum CardError: LocalizedError {
        case noRoute
        var errorDescription:String? { "Ehhez a kártyához GPS-útvonal szükséges." }
    }
    static func create(_ run:RecordedRun, language:AppLanguage) async throws -> URL {
        let coords=run.route.map { CLLocationCoordinate2D(latitude:$0.latitude,longitude:$0.longitude) }
        guard coords.count > 1, run.completed else { throw CardError.noRoute }
        let lowLat=coords.map(\.latitude).min()!, highLat=coords.map(\.latitude).max()!
        let lowLon=coords.map(\.longitude).min()!,highLon=coords.map(\.longitude).max()!
        let region=MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:(lowLat+highLat)/2,
            longitude:(lowLon+highLon)/2),span:MKCoordinateSpan(
            latitudeDelta:max(0.006,(highLat-lowLat)*1.45),
            longitudeDelta:max(0.006,(highLon-lowLon)*1.45)))
        let options=MKMapSnapshotter.Options()
        options.region=region
        options.size=CGSize(width:980,height:720)
        options.scale=1
        options.mapType = .standard
        let snapshot=try await MKMapSnapshotter(options:options).start()
        let blue=UIColor(red:0.33,green:0.69,blue:0.98,alpha:1)
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:1080,height:1350))
        let image=renderer.image { ctx in
            let graphics=ctx.cgContext
            UIColor(red:0.045,green:0.068,blue:0.105,alpha:1).setFill()
            graphics.fill(CGRect(x:0,y:0,width:1080,height:1350))
            func text(_ value:String,rect:CGRect,font:UIFont,color:UIColor = .white) {
                (value as NSString).draw(in:rect,withAttributes:[.font:font,.foregroundColor:color])
            }
            text("ÓraNapló",rect:CGRect(x:60,y:64,width:900,height:70),
                 font:.systemFont(ofSize:61,weight:.bold),color:blue)
            text(language == .de ? "MEIN LAUF" : (language == .en ? "MY RUN" : "A FUTÁSOM"),
                 rect:CGRect(x:64,y:160,width:900,height:68),font:.systemFont(ofSize:39,weight:.bold))
            let labels = language == .de ? ["DISTANZ","ZEIT","TEMPO"] :
                (language == .en ? ["DISTANCE","TIME","PACE"] : ["TÁVOLSÁG","IDŐ","TEMPÓ"])
            let values=[String(format:"%.2f km",run.gpsMeters/1000),RunFormatting.duration(run.activeSeconds),
                        run.paceSecondsPerKm.map(RunFormatting.pace) ?? "—"]
            for i in 0..<3 {
                let x=64+CGFloat(i)*330
                text(labels[i],rect:CGRect(x:x,y:268,width:310,height:35),
                     font:.systemFont(ofSize:22,weight:.medium),color:.lightGray)
                text(values[i],rect:CGRect(x:x,y:309,width:310,height:52),
                     font:.systemFont(ofSize:35,weight:.bold))
            }
            let mapRect=CGRect(x:50,y:408,width:980,height:720)
            let path=UIBezierPath(roundedRect:mapRect,cornerRadius:32)
            graphics.saveGState();path.addClip()
            snapshot.image.draw(in:mapRect)
            var segment=UIBezierPath()
            segment.lineWidth=11;segment.lineJoinStyle = .round
            for (index,point) in run.route.enumerated() {
                let position=snapshot.point(for:CLLocationCoordinate2D(latitude:point.latitude,longitude:point.longitude))
                let destination=CGPoint(x:mapRect.minX+position.x,y:mapRect.minY+position.y)
                if index == 0 || point.breakBefore { segment.move(to:destination) }
                else { segment.addLine(to:destination) }
            }
            UIColor.white.withAlphaComponent(0.8).setStroke();segment.lineWidth=16;segment.stroke()
            blue.setStroke();segment.lineWidth=10;segment.stroke()
            graphics.restoreGState()
            text(run.started.formatted(date:.abbreviated,time:.shortened),
                 rect:CGRect(x:63,y:1170,width:900,height:44),
                 font:.systemFont(ofSize:25,weight:.medium),color:.lightGray)
            text(language == .de ? "Erstellt mit ÓraNapló" : (language == .en ? "Made with ÓraNapló" : "Készítve az ÓraNaplóval"),
                 rect:CGRect(x:63,y:1260,width:900,height:36),
                 font:.systemFont(ofSize:23,weight:.semibold),color:blue)
        }
        let out=FileManager.default.temporaryDirectory.appendingPathComponent("OraNaplo-Run-\(run.id.uuidString).png")
        guard let png=image.pngData() else { throw CardError.noRoute }
        try png.write(to:out,options:.atomic)
        return out
    }
}
