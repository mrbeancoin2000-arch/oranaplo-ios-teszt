import Foundation
import HealthKit
import UIKit
import Combine
import UserNotifications

@MainActor
final class SyncEngine: ObservableObject {
    @Published var busy = false
    @Published var status = "Diagnosztika: " + CrashCheckpoint.last
    @Published var basicHealthFlowCompleted = UserDefaults.standard.bool(forKey: "healthBasicCompleted")
    @Published var fullHealthFlowCompleted = UserDefaults.standard.bool(forKey: "healthFullCompleted")
    @Published var lastSync = UserDefaults.standard.string(forKey: "lastSync") ?? "–"
    @Published var pendingCount = 0
    @Published var sheetID = ""
    @Published var batteryLevel = 0
    @Published var charging = false
    @Published var selectedDays = UserDefaults.standard.integer(forKey: "days") == 0 ? 30 : UserDefaults.standard.integer(forKey: "days")
    @Published var enabledGroups: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "groups") ?? Catalog.groups.map(\.0))
    let account = GoogleAccount()
    private let reader = HealthReader.shared
    private let queue = LocalQueue.shared

    /// Called at launch, and also by the background refresh worker.
    func bootstrap() async {
        await account.restore()
        await loadCurrentAccount()
        await recoverCurrentSheetIfNeeded()
    }

    func refreshCount() async { await loadCurrentAccount() }

    private func loadCurrentAccount() async {
        guard account.loggedIn else {
            sheetID = ""
            pendingCount = 0
            return
        }
        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { sheetID = ""; return }
        do {
            try await queue.selectAccount(email)
            sheetID = SpreadsheetRegistry.sheetID(for: email)
            pendingCount = await queue.count()
        } catch {
            sheetID = ""
            status = "Fiókhoz tartozó mentési sor hiba: \(error.localizedDescription)"
        }
    }

    private func recoverCurrentSheetIfNeeded() async {
        guard account.loggedIn, sheetID.isEmpty else { return }
        let api = SheetsAPI(account: account)
        // Older versions saved one unscoped ID. Only reuse it when the current
        // authenticated account demonstrably has access to that spreadsheet.
        if let legacy = UserDefaults.standard.string(forKey: "sheetID"),
           !legacy.isEmpty, await api.canAccessSpreadsheet(legacy) {
            SpreadsheetRegistry.setSheetID(legacy, for: account.email)
            sheetID = legacy
            return
        }
        // Google Drive API is optional: failure here never blocks a fresh sheet.
        if let found = try? await api.findExistingSpreadsheet(), !found.isEmpty {
            SpreadsheetRegistry.setSheetID(found, for: account.email)
            sheetID = found
        }
    }

    func disconnectGoogle() async {
        account.signOut()
        sheetID = ""
        pendingCount = 0
        status = "Google-fiók leválasztva. A helyi adatok fiókonként elkülönítve maradnak."
    }
    func setDays(_ days: Int) { selectedDays = days; UserDefaults.standard.set(days, forKey: "days") }
    func toggleGroup(_ id: String) {
        if enabledGroups.contains(id) { enabledGroups.remove(id) } else { enabledGroups.insert(id) }
        UserDefaults.standard.set(Array(enabledGroups), forKey: "groups")
    }
    func authorizeHealth() async {
        // The first on-device check requests ONLY heart rate to isolate entitlement issues
        // from special HealthKit sample types. It is not full data authorization.
        do {
            try await reader.authorize(onlyHeartRate: true)
            basicHealthFlowCompleted = true
            UserDefaults.standard.set(true, forKey: "healthBasicCompleted")
            status = "Alap HealthKit engedélykérés lefutott (csak pulzus). Következő: teljes jogosultság."
        } catch {
            CrashCheckpoint.mark("HealthKit alapteszt hiba: \(error.localizedDescription)")
            status = "Egészség alapteszt: \(error.localizedDescription)"
        }
    }
    func authorizeAllHealth() async {
        guard basicHealthFlowCompleted else {
            status = "Előbb futtasd a pulzus HealthKit-alaptesztet"
            return
        }
        do {
            try await reader.authorize()
            fullHealthFlowCompleted = true
            UserDefaults.standard.set(true, forKey: "healthFullCompleted")
            status = "Teljes HealthKit engedélykérés lezajlott"
            await reader.enableBackgroundNotifications()
        } catch {
            CrashCheckpoint.mark("HealthKit teljes engedélykérés hiba: \(error.localizedDescription)")
            status = "Egészség teljes kérés: \(error.localizedDescription)"
        }
    }
    func login() async {
        do {
            try await account.signIn()
            await loadCurrentAccount()
            await recoverCurrentSheetIfNeeded()
            status = sheetID.isEmpty ? "Google-fiók kapcsolódott. Most létrehozhatod a táblázatodat." : "Google-fiók kapcsolódott. A saját táblázatod elérhető."
        } catch {
            CrashCheckpoint.mark("Google hiba: \(error.localizedDescription)")
            status = "Google: \(error.localizedDescription)"
        }
    }
    func addJournalEntry(kind: String, note: String) async {
        guard account.loggedIn else { status = "A napló mentéséhez először csatlakoztasd a Google-fiókodat"; return }
        await loadCurrentAccount()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Írj be egy megjegyzést"; return }
        let row = ExportRow(id: "note:\(UUID().uuidString)", sheet: "Naplo", values: [
            UUID().uuidString, kind, ISO.string(Date()), "", "", "", "Kézi napló", "iPhone",
            String(trimmed.prefix(1500)), "aktív", ISO.string(Date())
        ])
        do {
            try await queue.enqueue([row])
            pendingCount = await queue.count()
            status = "Naplóbejegyzés helyben mentve."
            // Journal rows do not require HealthKit. Try immediate upload when signed in.
            if account.loggedIn && !busy {
                await prepareGoogleSheet()
            } else if !account.loggedIn {
                status = "Napló helyben mentve. Google-bejelentkezés után tölthető fel."
            }
        } catch { status = "Naplómentés hiba: \(error.localizedDescription)" }
    }

    /// Create the user's Google spreadsheet and upload pending journal rows.
    /// This intentionally never requests Apple Health authorization.
    func prepareGoogleSheet() async {
        guard !busy else { return }
        guard account.loggedIn else {
            status = "Először csatlakoztasd a Google-fiókodat"
            return
        }
        busy = true
        defer { busy = false }
        await loadCurrentAccount()
        await recoverCurrentSheetIfNeeded()
        let sheets = SheetsAPI(account: account)
        do {
            status = sheetID.isEmpty ? "Google Sheets létrehozása…" : "Várakozó adatok feltöltése…"
            try await ensureSheet(using: sheets)
            try await flushQueue(using: sheets)
            status = "Google Sheets készen áll. A táblázat megnyitható. Várakozó sorok: \(pendingCount)."
            CrashCheckpoint.mark("Google Sheets inicializálás: sikeres")
        } catch {
            pendingCount = await queue.count()
            status = "Google Sheets hiba: \(error.localizedDescription)"
            CrashCheckpoint.mark("Google Sheets inicializálás hiba: \(error.localizedDescription)")
        }
    }

    private func ensureSheet(using sheets: SheetsAPI) async throws {
        guard sheetID.isEmpty else { return }
        let id = try await sheets.createSpreadsheet()
        sheetID = id
        SpreadsheetRegistry.setSheetID(id, for: account.email)
    }

    func sync() async {
        guard !busy else { return }
        guard account.loggedIn else {
            status = "Először csatlakoztasd a Google-fiókodat"
            return
        }
        guard fullHealthFlowCompleted else {
            status = "Egészségadatokhoz HealthKit-engedély szükséges. A Google Sheets létrehozása ettől függetlenül működik."
            return
        }
        busy = true; defer { busy = false }
        await loadCurrentAccount()
        let since = Date().addingTimeInterval(-Double(selectedDays) * 86400)
        let sheets = SheetsAPI(account: account)
        do {
            // Do not invoke a new authorization prompt during export; missing entitlements
            // on free sideload installations can cause an Objective-C exception.
            status = "Egészségadatok feldolgozása…"
            try await ensureSheet(using: sheets)
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
    var sheetURL: URL? {
        guard account.loggedIn, !sheetID.isEmpty, SpreadsheetRegistry.sheetID(for: account.email) == sheetID else { return nil }
        return URL(string: "https://docs.google.com/spreadsheets/d/\(sheetID)/edit")
    }
}

/// Each Google account has its own spreadsheet binding. Switching accounts never
/// reuses the previous account's link or the previous account's queued samples.
enum SpreadsheetRegistry {
    private static let prefix = "oranaplo.spreadsheet.v2."
    static func sheetID(for email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: prefix + normalized) ?? ""
    }
    static func setSheetID(_ id: String, for email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !id.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: prefix + normalized)
    }
}
