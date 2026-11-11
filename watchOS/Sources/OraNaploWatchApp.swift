import SwiftUI

@main struct OraNaploWatchApp: App {
    @StateObject private var workout = WatchWorkout()
    @AppStorage("oranaplo.app.language") private var languageCode = "hu"
    var body: some Scene {
        WindowGroup {
            WatchRunView(workout:workout,language:languageCode)
        }
    }
}
struct WatchRunView:View {
    @ObservedObject var workout:WatchWorkout
    let language:String
    private func t(_ hu:String,_ en:String,_ de:String) -> String {
        language == "de" ? de : (language == "en" ? en : hu)
    }
    var body:some View {
        ScrollView {
            VStack(spacing:9) {
                Text("ÓraNapló").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Text(workout.bpm.map { String(format:"%.0f bpm",$0) } ?? "— bpm")
                    .font(.system(size:27,weight:.bold,design:.rounded))
                Text(String(format:"%.2f km",workout.meters/1000)).font(.headline)
                Text(WatchTime.format(workout.elapsed)).font(.callout.monospacedDigit())
                let pace = workout.elapsed > 0 && workout.meters > 0
                    ? (workout.elapsed / (workout.meters / 1000)) : nil
                Text(pace.map { WatchTime.pace($0) } ?? "— min/km").font(.caption)
                if workout.phase == .ready || workout.phase == .finished {
                    Button(t("Indítás","Start","Starten")) { workout.start() }.tint(.green)
                } else if workout.phase == .running {
                    Button(t("Szünet","Pause","Pause")) { workout.pause() }.tint(.orange)
                    Button(t("Befejezés","Finish","Beenden")) { workout.finish() }.tint(.red)
                } else if workout.phase == .paused {
                    Button(t("Folytatás","Resume","Fortsetzen")) { workout.resume() }.tint(.green)
                    Button(t("Befejezés","Finish","Beenden")) { workout.finish() }.tint(.red)
                } else {
                    ProgressView()
                }
                if !workout.info.isEmpty { Text(workout.info).font(.caption2) }
                Picker(t("Nyelv","Language","Sprache"),selection:Binding(
                    get:{language},set:{UserDefaults.standard.set($0,forKey:"oranaplo.app.language")})) {
                    Text("Magyar").tag("hu")
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                }.font(.caption2)
                Text(t("Óra: pulzus és edzés. iPhone: GPS-útvonal, ha elérhető.",
                       "Watch: heart rate and workout. iPhone: GPS route when reachable.",
                       "Uhr: Puls und Training. iPhone: GPS-Route, wenn erreichbar."))
                    .font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.horizontal,6)
        }
    }
}
enum WatchTime {
    static func format(_ seconds:Double) -> String {
        let s=max(0,Int(seconds));return String(format:"%02d:%02d:%02d",s/3600,s/60%60,s%60)
    }
    static func pace(_ seconds:Double) -> String {
        let s=max(0,Int(seconds));return String(format:"%d:%02d min/km",s/60,s%60)
    }
}
