import Foundation
import WidgetKit

/// Deliberately opt-in. Works only after both targets have the SAME signed App Group.
/// Free sideload without that entitlement must not pretend widgets are showing live data.
@MainActor
enum WellnessWidgetCache {
    static let groupID="group.hu.oranaplo.shared"
    static func publishIfPermitted(restingBPM:Double?,hrvMS:Double?) {
        guard UserDefaults.standard.bool(forKey:"oranaplo.widgets.enabled"),
              let shared=UserDefaults(suiteName:groupID) else { return }
        if let restingBPM { shared.set(restingBPM,forKey:"restingBPM") }
        if let hrvMS { shared.set(hrvMS,forKey:"hrvMS") }
        let daily=DailyHealthDashboard.shared.snapshot
        if let steps=daily.steps { shared.set(steps,forKey:"steps") }
        if let minutes=daily.lastNightMinutes { shared.set(minutes,forKey:"sleepMinutes") }
        let today=Calendar.current.startOfDay(for:Date())
        let water=WellnessDiary.shared.water.filter{$0.date >= today}.reduce(0){$0+$1.milliliters}
        shared.set(water,forKey:"waterML")
        shared.set(Date(),forKey:"refreshed")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
