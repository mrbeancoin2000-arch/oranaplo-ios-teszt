import SwiftUI
import WidgetKit
private struct WatchData:TimelineEntry { let date:Date;let battery:Int?;let pulse:Double? }
private struct WatchProvider:TimelineProvider {
    func read()->WatchData {
        let store=UserDefaults(suiteName:"group.hu.oranaplo.watch")
        let battery=store?.object(forKey:"battery") == nil ? nil : store?.integer(forKey:"battery")
        let pulse=store?.object(forKey:"pulse") == nil ? nil : store?.double(forKey:"pulse")
        return WatchData(date:Date(),battery:battery,pulse:pulse)
    }
    func placeholder(in context:Context)->WatchData { WatchData(date:Date(),battery:nil,pulse:nil) }
    func getSnapshot(in context:Context,completion:@escaping (WatchData)->Void){completion(read())}
    func getTimeline(in context:Context,completion:@escaping (Timeline<WatchData>)->Void){
        completion(Timeline(entries:[read()],policy:.after(Date().addingTimeInterval(1800))))
    }
}
private struct WatchView:View {
    let entry:WatchData
    var body:some View {
        HStack {
            Image(systemName:"heart.fill")
            Text(entry.pulse.map{String(format:"%.0f",$0)} ?? "—")
            Text(entry.battery.map{"\($0)%"} ?? "—")
        }.font(.caption).containerBackground(.fill.tertiary,for:.widget)
    }
}
@main struct OraNaploWatchWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:"hu.oranaplo.watch.summary",provider:WatchProvider()) { WatchView(entry:$0) }
            .configurationDisplayName("ÓraNapló Watch")
            .description("Last cached pulse and battery; not continuous monitoring.")
            .supportedFamilies([.accessoryRectangular,.accessoryCircular,.accessoryInline])
    }
}
