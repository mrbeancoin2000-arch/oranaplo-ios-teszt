import Foundation
import HealthKit
import UIKit
import Combine
import UserNotifications

@MainActor
final class SyncEngine: ObservableObject {
    @Published var busy = false
    @Published var status = "Még nem történt szinkronizálás"
    @Published var lastSync = UserDefaults.standard.string(forKey: "lastSync") ?? "–"
    @Published var pendingCount = 0
    @Published var sheetID = UserDefaults.standard.string(forKey: "sheetID") ?? ""
    @Published var batteryLevel = 0
    @Published var charging = false
    @Published var selectedDays = UserDefaults.standard.integer(forKey: "days") == 0 ? 30 : UserDefaults.standard.integer(forKey: "days")
    @Published var enabledGroups: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "groups") ?? Catalog.groups.map(\.0))
    let account = GoogleAccount()
    private let reader = HealthReader.shared
    private let queue = LocalQueue.shared

    func refreshCount() async { pendingCount = await queue.count() }
    func setDays(_ days: Int) { selectedDays = days; UserDefaults.standard.set(days, forKey: "days") }
    func toggleGroup(_ id: String) {
        if enabledGroups.contains(id) { enabledGroups.remove(id) } else { enabledGroups.insert(id) }
        UserDefaults.standard.set(Array(enabledGroups), forKey: "groups")
    }
    func authorizeHealth() async {
        do { try await reader.authorize(); status = "Apple Egészség jogosultságkérés lezajlott"; await reader.enableBackgroundNotifications() }
        catch { status = "Egészség: \(error.localizedDescription)" }
    }
    func login() async {
        do { try await account.signIn(); status = "Google kapcsolat létrejött" }
        catch { status = "Google: \(error.localizedDescription)" }
    }
    func addJournalEntry(kind: String, note: String) async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Írj be egy megjegyzést"; return }
        let row = ExportRow(id: "note:\(UUID().uuidString)", sheet: "Naplo", values: [
            UUID().uuidString, kind, ISO.string(Date()), "", "", "", "Kézi napló", "iPhone",
            String(trimmed.prefix(1500)), "aktív", ISO.string(Date())
        ])
        do { try await queue.enqueue([row]); pendingCount = await queue.count(); status = "Naplóbejegyzés helyben mentve. A következő szinkron továbbítja." }
        catch { status = "Naplómentés hiba: \(error.localizedDescription)" }
    }
    func sync() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let since = Date().addingTimeInterval(-Double(selectedDays) * 86400)
        let sheets = SheetsAPI(account: account)
        do {
            try await reader.authorize()
            status = "Egészségadatok feldolgozása…"
            if sheetID.isEmpty {
                sheetID = try await sheets.createSpreadsheet()
                UserDefaults.standard.set(sheetID, forKey: "sheetID")
            }
            // Queue upload happens before and after the new HealthKit read: offline records recover first.
            try await flushQueue(using: sheets)
            for metric in Catalog.metrics where enabledGroups.contains(metric.group) {
                guard let type = metric.sampleType else { continue }
                let key = "anchor.\(metric.id)"
                var anchor: HKQueryAnchor? = nil
                if let data = UserDefaults.standard.data(forKey: key) {
                    anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
                }
                for _ in 0..<100 {
                    let (added, deleted, newAnchor, count) = try await reader.samplePage(type, since: since, anchor: anchor)
                    let rows = added.map { rawRow($0, metric: metric) } + deleted.map { deletedRow($0, metric: metric) }
                    try await queue.enqueue(rows)
                    if let newAnchor {
                        let bytes = try NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true)
                        UserDefaults.standard.set(bytes, forKey: key)
                        anchor = newAnchor
                    }
                    if count < 300 { break }
                }
            }
            if enabledGroups.contains("edzes") {
                for workout in try await reader.getWorkouts(since: since) {
                    if await queue.isUploaded("workout:\(workout.uuid.uuidString)") { continue }
                    try await queue.enqueue(await WorkoutExport(reader: reader).rows(for: workout))
                }
            }
            if enabledGroups.contains("sziv") {
                // ECG raw voltage values can be numerous; uploaded only when the ECG category is enabled.
                for ecg in try await reader.ecgs(since: since) {
                    let root = "ecg:\(ecg.uuid.uuidString)"
                    if await queue.isUploaded(root) { continue }
                    let summary = ExportRow(id: root, sheet: "EKG", values: [ecg.uuid.uuidString, "EKG összefoglaló", ISO.string(ecg.startDate), ISO.string(ecg.endDate), "", "", "Apple Watch", "", "EKG hullámforma külön sorokban", "aktív", ISO.string(Date())])
                    try await queue.enqueue([summary])
                    if let voltages = try? await reader.ecgVoltages(ecg) {
                        let rows = voltages.enumerated().map { i, v in ExportRow(id: "\(root):\(i)", sheet: "EKG", values: ["\(ecg.uuid.uuidString):\(i)", "EKG feszültség", ISO.string(v.0), "", String(v.1), "mV", "Apple Watch", "", "I. elvezetés", "aktív", ISO.string(Date())]) }
                        try await queue.enqueue(rows)
                    }
                }
            }
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            batteryLevel = Int(max(device.batteryLevel, 0) * 100)
            charging = device.batteryState == .charging || device.batteryState == .full
            let batt = ExportRow(id: "battery:\(Int(Date().timeIntervalSince1970/3600))", sheet: "Akkumulator", values: [UUID().uuidString, "iPhone akkumulátor", ISO.string(Date()), "", String(batteryLevel), "%", "iPhone", device.name, charging ? "Töltőn" : "Nem tölt", "aktív", ISO.string(Date())])
            try await queue.enqueue([batt])
            try await flushQueue(using: sheets)
            lastSync = ISO.string(Date()); UserDefaults.standard.set(lastSync, forKey: "lastSync")
            status = "Sikeres ellenőrzés. \(pendingCount) sor várakozik."
        } catch {
            pendingCount = await queue.count()
            status = "Hiba: \(error.localizedDescription) – a helyi mentések megmaradnak"
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = "ÓraNapló – mentési hiba"
                content.body = "A Google Sheets-szinkron nem sikerült. Nyisd meg az alkalmazást az ellenőrzéshez."
                _ = try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
    private func flushQueue(using sheets: SheetsAPI) async throws {
        var attempts = 0
        while true {
            let batch = await queue.nextBatch(limit: 150)
            if batch.isEmpty { break }
            try await sheets.append(batch, sheetID: sheetID)
            try await queue.didUpload(batch)
            attempts += 1
            if attempts > 2000 { throw SyncError.config("Feltöltési biztonsági korlát: indíts új szinkront") }
        }
        pendingCount = await queue.count()
    }
    var sheetURL: URL? { sheetID.isEmpty ? nil : URL(string: "https://docs.google.com/spreadsheets/d/\(sheetID)/edit") }
}
