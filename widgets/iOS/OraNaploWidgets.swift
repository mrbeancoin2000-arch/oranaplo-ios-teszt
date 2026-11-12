import SwiftUI
import WidgetKit

private struct DataEntry:TimelineEntry {
    let date:Date
    let steps:Int?
    let water:Int?
    let sleepMinutes:Double?
    let resting:Double?
}
private struct Provider:TimelineProvider {
    func entry() -> DataEntry {
        let store=UserDefaults(suiteName:"group.hu.oranaplo.shared")
        func readInt(_ k:String)->Int? { guard store?.object(forKey:k) != nil else{return nil};return store?.integer(forKey:k) }
        func readDouble(_ k:String)->Double? { guard store?.object(forKey:k) != nil else{return nil};return store?.double(forKey:k) }
        return DataEntry(date:Date(),steps:readInt("steps"),water:readInt("waterML"),
                         sleepMinutes:readDouble("sleepMinutes"),resting:readDouble("restingBPM"))
    }
    func placeholder(in context:Context)->DataEntry { DataEntry(date:Date(),steps:nil,water:nil,sleepMinutes:nil,resting:nil) }
    func getSnapshot(in context:Context,completion:@escaping (DataEntry)->Void) { completion(entry()) }
    func getTimeline(in context:Context,completion:@escaping (Timeline<DataEntry>)->Void) {
        completion(Timeline(entries:[entry()],policy:.after(Date().addingTimeInterval(1800))))
    }
}
private struct SummaryView:View {
    let entry:DataEntry
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            Text("ÓraNapló").font(.headline)
            Text("👟 \(entry.steps.map(String.init) ?? "—")")
            Text("💧 \(entry.water.map(String.init) ?? "—") ml")
            Text("♥ \(entry.resting.map{String(format:"%.0f",$0)} ?? "—") bpm")
            Text("☾ \(entry.sleepMinutes.map{String(format:"%.0f",$0)} ?? "—") min")
        }.font(.caption).containerBackground(.fill.tertiary,for:.widget)
    }
}
private struct PulseView:View {
    let entry:DataEntry
    var body:some View {
        HStack {
            Image(systemName:"heart.fill")
            Text(entry.resting.map { String(format:"%.0f",$0) } ?? "—")
            Text("bpm")
        }.containerBackground(.fill.tertiary,for:.widget)
    }
}
private struct SummaryWidget:Widget {
    let kind="hu.oranaplo.summary"
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:Provider()) { SummaryView(entry:$0) }
            .configurationDisplayName("ÓraNapló")
            .description("Steps, sleep, water and resting heart rate from your cached data.")
            .supportedFamilies([.systemSmall,.systemMedium])
    }
}
private struct LockWidget:Widget {
    let kind="hu.oranaplo.lock"
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:Provider()) { PulseView(entry:$0) }
            .configurationDisplayName("ÓraNapló Pulse")
            .description("Cached resting heart rate, not a live reading.")
            .supportedFamilies([.accessoryRectangular,.accessoryCircular,.accessoryInline])
    }
}
@main struct OraNaploWidgetBundle:WidgetBundle {
    var body:some Widget { SummaryWidget(); LockWidget() }
}
