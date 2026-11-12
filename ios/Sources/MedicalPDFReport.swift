import Foundation
import HealthKit
import UIKit

/// PDF is generated entirely on device; no third-party PDF service sees health records.
@MainActor
enum MedicalPDFReport {
    enum ReportError: LocalizedError {
        case empty
        var errorDescription:String? { "No readable HealthKit measurements in the selected interval." }
    }
    private struct Line {
        let text:String
        let title:Bool
    }
    static func generate(days:Int,language:String) async throws -> URL {
        let now=Date()
        let beginning=days == 0 ? Date(timeIntervalSince1970:0) : now.addingTimeInterval(-Double(days)*86400)
        let hu=language == "hu", de=language == "de"
        func tr(_ huText:String,_ enText:String,_ deText:String)->String { hu ? huText : (de ? deText : enText) }
        var lines:[Line]=[]
        func heading(_ v:String) { lines.append(Line(text:v,title:true)) }
        func body(_ v:String) { lines.append(Line(text:v,title:false)) }
        heading(tr("EGÉSZSÉGÜGYI MÉRÉSI ÖSSZEFOGLALÓ","HEALTH MEASUREMENT REPORT","GESUNDHEITSMESSBERICHT"))
        body(tr("Időszak","Period","Zeitraum") + ": \(ISO.string(beginning)) – \(ISO.string(now))")
        body(tr("Készült","Generated","Erstellt") + ": \(ISO.string(now))")
        body(tr("Nagy adatmennyiség esetén az export mintakorlátos; a részleges eredményt a jelentés vége jelzi.",
                "For large datasets, export is sample-limited; a partial report is marked at its end.",
                "Bei großen Datensätzen ist der Export begrenzt; Teilberichte sind am Ende gekennzeichnet."))
        body(tr("Forrás: Apple Egészség; az adatok csak az engedélyezett méréseket tartalmazzák.",
                "Source: Apple Health; only readable authorized samples are included.",
                "Quelle: Apple Health; nur freigegebene, lesbare Messungen sind enthalten."))
        var allCount=0
        var capped=false
        let perMetricLimit=4000
        let totalLimit=40000
        for metric in Catalog.metrics {
            if allCount >= totalLimit { capped=true;break }
            guard let type=metric.sampleType else { continue }
            var rows:[HKSample]=[]
            var anchor:HKQueryAnchor?
            // Iterative bounded pages: never lose the fact that a report was truncated.
            for _ in 0..<16 {
                let (added,_,next,count)=try await HealthReader.shared.samplePage(type,since:beginning,anchor:anchor,limit:250)
                rows.append(contentsOf:added.filter{$0.startDate <= now})
                anchor=next
                if count < 250 { break }
                if rows.count >= perMetricLimit || (allCount+rows.count) >= totalLimit { capped=true;break }
            }
            guard !rows.isEmpty else { continue }
            allCount += rows.count
            heading("\(metric.label)  (\(rows.count))")
            let sorted=rows.sorted{$0.startDate < $1.startDate}
            for item in sorted {
                let row=rawRow(item,metric:metric)
                let value=row.values.count > 4 ? row.values[4] : "—"
                let source=row.values.count > 6 ? row.values[6] : "—"
                let device=row.values.count > 7 ? row.values[7] : "—"
                body("\(ISO.string(item.startDate)) – \(ISO.string(item.endDate)) | \(value) \(metric.unit) | \(source) | \(device)")
            }
        }
        heading(tr("ÉLETMÓDNAPLÓ","PERSONAL JOURNAL","PERSÖNLICHES TAGEBUCH"))
        let diary=WellnessDiary.shared
        for rating in diary.sleepRatings where rating.date >= beginning && rating.date <= now {
            body("\(ISO.string(rating.date)) | \(tr("Alvásértékelés","Sleep rating","Schlafbewertung")) | \(rating.score)/10")
        }
        for room in diary.rooms where room.date >= beginning && room.date <= now {
            body("\(ISO.string(room.date)) | \(tr("Szobamérés","Room","Zimmer")) | \(room.temperatureC.map{String(format:"%.1f °C",$0)} ?? "—") | \(room.humidityPercent.map{String(format:"%.0f %%",$0)} ?? "—") | \(room.co2PPM.map{String(format:"%.0f ppm",$0)} ?? "—")")
        }
        for dose in diary.medicines where dose.date >= beginning && dose.date <= now {
            body("\(ISO.string(dose.date)) | \(dose.name) \(dose.dose) | \(dose.taken ? tr("Bevéve","Taken","Eingenommen") : tr("Kihagyva","Missed","Ausgelassen"))")
        }
        if capped { heading(tr("RÉSZLEGES JELENTÉS: legfeljebb 4 000 minta/típus és 40 000 minta összesen. A teljes áttekintéshez rövidebb időszakokat exportálj.",
                               "PARTIAL REPORT: at most 4,000 samples/type and 40,000 overall. Export smaller intervals for full coverage.",
                               "TEILBERICHT: maximal 4.000 Messungen/Typ und 40.000 insgesamt. Für vollständige Daten kürzere Zeiträume exportieren.")) }
        body(tr("Összes felsorolt HealthKit-mérés","Listed HealthKit samples","Aufgeführte HealthKit-Messungen") + ": \(allCount)")
        guard allCount > 0 || !diary.sleepRatings.isEmpty || !diary.medicines.isEmpty else { throw ReportError.empty }
        let bounds=CGRect(x:0,y:0,width:595,height:842)
        let renderer=UIGraphicsPDFRenderer(bounds:bounds)
        let result=renderer.pdfData { context in
            var y:CGFloat=0
            var page=0
            func newPage() {
                context.beginPage(); page += 1; y=36
                let footer="ÓraNapló | \(ISO.string(now)) | \(page)"
                (footer as NSString).draw(at:CGPoint(x:40,y:816),withAttributes:[.font:UIFont.systemFont(ofSize:8),.foregroundColor:UIColor.darkGray])
            }
            newPage()
            for line in lines {
                let font:UIFont=line.title ? .boldSystemFont(ofSize:11.5) : .systemFont(ofSize:8.5)
                let para=NSMutableParagraphStyle();para.lineBreakMode = .byCharWrapping
                let attrib:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:UIColor.black,.paragraphStyle:para]
                let rect=(line.text as NSString).boundingRect(with:CGSize(width:515,height:CGFloat.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrib,context:nil)
                let needed=max(15,ceil(rect.height)+4)
                if y+needed > 803 { newPage() }
                (line.text as NSString).draw(in:CGRect(x:40,y:y,width:515,height:needed),withAttributes:attrib)
                y += needed + (line.title ? 4 : 0)
            }
        }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("OraNaploReports",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent("OraNaplo-\(language)-\(Int(now.timeIntervalSince1970)).pdf")
        try result.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
