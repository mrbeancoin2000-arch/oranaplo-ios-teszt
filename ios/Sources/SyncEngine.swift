import Foundation
import HealthKit
import UIKit
import Combine
import UserNotifications

@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    @Published var busy = false
    @Published var status = "Diagnosztika: " + CrashCheckpoint.last
    @Published var basicHealthFlowCompleted = UserDefaults.standard.bool(forKey: "healthBasicCompleted")
    @Published var fullHealthFlowCompleted = UserDefaults.standard.bool(forKey: "healthFullCompleted")
    @Published var lastSync = UserDefaults.standard.string(forKey: "lastSync") ?? "–"
    @Published var pendingCount = 0
    @Published var xmlImportStatusKey = "xml.ready"
    @Published var xmlImportCounts = ""
    @Published var sheetID = ""
    @Published var batteryLevel = 0
    @Published var charging = false
    @Published var profile: PersonalHealthProfile?
    @Published var personalObservations: [PersonalObservation] = []
    @Published var profileAuthorized = UserDefaults.standard.bool(forKey: "oranaplo.profile.consentRequested")
    @Published var profileMessageKey = "profile.status.notRequested"
    @Published var lastWorkout: WorkoutSnapshot?
    @Published var observations: [ObservationNotice] = []
    @Published var syncHadError = false
    @Published var lastUploadedCount = 0
    @Published var lastSuccessfulDate: Date? = UserDefaults.standard.object(forKey: "lastSuccessfulSyncDate") as? Date
    @Published var selectedDays = UserDefaults.standard.integer(forKey: "days") == 0 ? 30 : UserDefaults.standard.integer(forKey: "days")
    @Published var enabledGroups: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "groups") ?? Catalog.groups.map(\.0))
    let account = GoogleAccount()
    private let reader = HealthReader.shared
    private let queue = LocalQueue.shared

    /// Called at launch, and also by the background refresh worker.
    func bootstrap() async {
        await account.restore()
        await SubscriptionManager.shared.load()
        await loadCurrentAccount()
        if basicHealthFlowCompleted { await refreshOverview() }
        if profileAuthorized { await refreshProfileAndObservations() }
        // Opportunistic catch-up when the app starts, not a guaranteed timer.
        let previous = UserDefaults.standard.object(forKey: "lastAutoSyncAttempt") as? Date ?? .distantPast
        if account.loggedIn && basicHealthFlowCompleted && Date().timeIntervalSince(previous) > 1800 {
            UserDefaults.standard.set(Date(), forKey: "lastAutoSyncAttempt")
            await sync()
        }
        await recoverCurrentSheetIfNeeded()
    }

    func refreshCount() async { await loadCurrentAccount() }

    func refreshOverview() async {
        guard basicHealthFlowCompleted else { return }
        let overview = HealthOverview(reader: reader)
        lastWorkout = await overview.latestWorkout()
        observations = await overview.notices()
    }


    /// Separate HealthKit permission for personal profile and conservative observations.
    /// Permission is needed even for the free version; only heart rate is exported for free.
    func requestProfileAccess() async {
        do {
            try await reader.authorizeProfile()
            profileAuthorized = true
            UserDefaults.standard.set(true, forKey: "oranaplo.profile.consentRequested")
            profileMessageKey = "profile.status.ready"
            await refreshProfileAndObservations()
        } catch {
            profileMessageKey = "profile.status.error"
            status = "Egészségprofil engedélyezési hiba: \(error.localizedDescription)"
            CrashCheckpoint.mark("Egészségprofil: \(error.localizedDescription)")
        }
    }

    func refreshProfileAndObservations() async {
        guard profileAuthorized else {
            profileMessageKey = "profile.status.notRequested"
            return
        }
        let service = HealthProfileService(reader: reader)
        let snapshot = await service.readProfile()
        profile = snapshot
        var notices = await service.localObservations(profile: snapshot)
        // Optional: trusted rows written by a spreadsheet-bound, user-installed script.
        // No measurements are sent to a third-party analysis server.
        if account.loggedIn, !sheetID.isEmpty, SubscriptionManager.shared.proActive,
           let fromSheet = try? await SheetsAPI(account: account).loadScriptObservations(sheetID: sheetID) {
            // Prefer the on-device version of a rule when both sources report it.
            let present = Set(notices.map { $0.titleKey })
            notices += fromSheet.filter { !present.contains($0.titleKey) }
        }
        personalObservations = notices.sorted { $0.date > $1.date }
        profileMessageKey = "profile.status.ready"
    }

    /// Explicit opt-in; never upload profile or date of birth automatically.
    func exportProfileToOwnSheet() async {
        guard !busy else { return }
        await SubscriptionManager.shared.refreshEntitlement()
        guard SubscriptionManager.shared.proActive else {
            profileMessageKey = "profile.status.requiresPro"; return
        }
        guard account.loggedIn, let current = profile else {
            profileMessageKey = "profile.status.needGoogle"; return
        }
        busy = true
        defer { busy = false }
        await loadCurrentAccount()
        let sheets = SheetsAPI(account: account)
        do {
            try await ensureSheet(using: sheets)
            try await sheets.ensureProfileTabs(sheetID: sheetID)
            try await sheets.updateProfile(current, sheetID: sheetID)
            profileMessageKey = "profile.status.exported"
        } catch {
            profileMessageKey = "profile.status.error"
            status = "Egészségprofil Google Sheets hiba: \(error.localizedDescription)"
        }
    }

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

    func findPreviousSheet() async {
        await recoverCurrentSheetIfNeeded()
        status = sheetID.isEmpty ? "Nem található korábbi táblázat." : "A korábbi táblázat elérhető."
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
        guard !busy else { return }
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
            status = "Alap HealthKit engedélykérés lefutott (csak pulzus)."
            await reader.enableBackgroundNotifications()
            await refreshOverview()
        } catch {
            CrashCheckpoint.mark("HealthKit alapteszt hiba: \(error.localizedDescription)")
            status = "Egészség alapteszt: \(error.localizedDescription)"
        }
    }
    func authorizeAllHealth() async {
        // HealthKit READ access is available to free users for on-device dashboards.
        // Pro is checked only in export code, so free mode still uploads heart rate alone.
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
            await refreshOverview()
        } catch {
            CrashCheckpoint.mark("HealthKit teljes engedélykérés hiba: \(error.localizedDescription)")
            status = "Egészség teljes kérés: \(error.localizedDescription)"
        }
    }
    func login() async {
        guard !busy else { return }
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
    /// Opt-in export of an on-device recorded run. Raw GPS coordinates stay local;
    /// route sharing is a separate GPX action. Only verified Pro can queue these rows.
    func exportRecordedRun(_ run: RecordedRun) async {
        guard !busy else { status = "A szinkron már folyamatban van."; return }
        await SubscriptionManager.shared.refreshEntitlement()
        guard SubscriptionManager.shared.proActive else {
            status = "A saját futások részletes exportálásához Pro-előfizetés szükséges."; return
        }
        guard account.loggedIn else {
            status = "Először csatlakoztasd a Google-fiókodat."; return
        }
        guard run.completed, let end = run.ended else {
            status = "Csak befejezett futást lehet exportálni."; return
        }
        await loadCurrentAccount()
        let rootID = "phoneRun:\(run.id.uuidString)"
        let beats = run.heart.map(\.bpm)
        let row = ExportRow(id: rootID, sheet: "Edzesek", values: [
            rootID, "Futás (ÓraNapló iPhone GPS)", ISO.string(run.started), ISO.string(end),
            String(run.activeSeconds), run.estimatedKcal.map { String($0) } ?? "",
            String(run.gpsMeters), beats.isEmpty ? "" : String(beats.reduce(0,+)/Double(beats.count)),
            beats.min().map { String($0) } ?? "",
            beats.max().map { String($0) } ?? "",
            "GPS: iPhone; kalória: becslés; útvonal csak helyben / GPX-ben", ISO.string(Date())
        ])
        let segments: [ExportRow] = run.splits.map { part in
            let id = "\(rootID):100m:\(part.index)"
            let started = RunMath.wallDate(forActive:part.startActiveSeconds, windows:run.activeWindows) ?? run.started
            let finished = RunMath.wallDate(forActive:part.finishActiveSeconds, windows:run.activeWindows) ?? end
            // Split timestamps account for paused windows. Elapsed time excludes pauses.
            return ExportRow(id: id, sheet: "100m", values: [
                id, rootID, "Futás (ÓraNapló)", String(part.index*100),
                ISO.string(started), ISO.string(finished), String(part.elapsedSeconds),
                String(part.kmh), String(part.paceSecondsPerKm/60),
                part.avgHeart.map { String($0) } ?? "",
                part.minHeart.map { String($0) } ?? "",
                part.maxHeart.map { String($0) } ?? "",
                String(part.worstGPSAccuracy), ISO.string(Date()),
                part.steps.map { String($0) } ?? "",
                part.estimatedKcal.map { String($0) } ?? ""
            ])
        }
        do {
            try await queue.enqueue([row] + segments)
            pendingCount = await queue.count()
            status = "Futás és 100 m-es szakaszok helyben mentve feltöltésre."
            await prepareGoogleSheet()
            if !sheetID.isEmpty {
                do {
                    try await SheetsAPI(account:account).updateRunAchievements(
                        sheetID:sheetID,records:RunTracker.shared.personalRecords,
                        goals:RunTracker.shared.weeklySummary)
                } catch {
                    // Do not roll back a successful measurement export because of a dashboard update.
                    status += " A rekordok/friss célok szinkronja külön nem sikerült: \(error.localizedDescription)"
                }
            }
        } catch { status = "Futásexport-hiba: \(error.localizedDescription)" }
    }

    func addJournalEntry(kind: String, note: String) async {
        await SubscriptionManager.shared.refreshEntitlement()
        guard SubscriptionManager.shared.proActive else {
            status = "A napló exportálásához Pro-előfizetés szükséges."
            return
        }
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
        lastUploadedCount = 0
        defer { busy = false }
        await SubscriptionManager.shared.refreshEntitlement()
        await loadCurrentAccount()
        if !SubscriptionManager.shared.proActive { try? await queue.restrictToFreeTier() }
        await recoverCurrentSheetIfNeeded()
        let sheets = SheetsAPI(account: account)
        do {
            status = sheetID.isEmpty ? "Google Sheets létrehozása…" : "Várakozó adatok feltöltése…"
            try await ensureSheet(using: sheets)
            try await sheets.ensureProfileTabs(sheetID: sheetID)
            try await flushQueue(using: sheets)
            status = "Google Sheets készen áll. A táblázat megnyitható. Várakozó sorok: \(pendingCount)."
            CrashCheckpoint.mark("Google Sheets inicializálás: sikeres")
        } catch {
            syncHadError = true
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
        guard basicHealthFlowCompleted else {
            status = "Egészségadatokhoz HealthKit-engedély szükséges. A Google Sheets létrehozása ettől függetlenül működik."
            return
        }
        busy = true
        lastUploadedCount = 0
        defer { busy = false }
        await SubscriptionManager.shared.refreshEntitlement()
        let isPro = SubscriptionManager.shared.proActive
        await loadCurrentAccount()
        // Never upload previously queued paid-tier records after an expiration.
        if !isPro { try? await queue.restrictToFreeTier() }
        let since = Date().addingTimeInterval(-Double(selectedDays) * 86400)
        let sheets = SheetsAPI(account: account)
        do {
            // Do not invoke a new authorization prompt during export; missing entitlements
            // on free sideload installations can cause an Objective-C exception.
            status = "Egészségadatok feldolgozása…"
            try await ensureSheet(using: sheets)
            // Queue upload happens before and after the new HealthKit read: offline records recover first.
            try await flushQueue(using: sheets)
            let fullData = isPro && fullHealthFlowCompleted
            for metric in Catalog.metrics where (
                fullData ? enabledGroups.contains(metric.group) : metric.id == Catalog.freeSampleIdentifier
            ) {
                guard let type = metric.sampleType else { continue }
                // Anchors are scoped by Google identity + import period. Changing
                // 30 days to a year starts a fresh historical read without duplicates.
                let identity = account.email.lowercased()
                let key = "anchor.v3.\(identity).\(selectedDays).\(metric.id)"
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
            if fullData && enabledGroups.contains("edzes") {
                for workout in try await reader.getWorkouts(since: since) {
                    if await queue.isUploaded("workout:\(workout.uuid.uuidString)") { continue }
                    try await queue.enqueue(await WorkoutExport(reader: reader).rows(for: workout))
                }
            }
            if fullData && enabledGroups.contains("sziv") {
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
            if fullData {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            batteryLevel = Int(max(device.batteryLevel, 0) * 100)
            charging = device.batteryState == .charging || device.batteryState == .full
            let batt = ExportRow(id: "battery:\(Int(Date().timeIntervalSince1970/3600))", sheet: "Akkumulator", values: [UUID().uuidString, "iPhone akkumulátor", ISO.string(Date()), "", String(batteryLevel), "%", "iPhone", device.name, charging ? "Töltőn" : "Nem tölt", "aktív", ISO.string(Date())])
            try await queue.enqueue([batt])
            }
            try await flushQueue(using: sheets)
            lastSuccessfulDate = Date()
            UserDefaults.standard.set(lastSuccessfulDate, forKey: "lastSuccessfulSyncDate")
            lastSync = ISO.string(Date()); UserDefaults.standard.set(lastSync, forKey: "lastSync")
            syncHadError = false
            await refreshOverview()
            status = "Sikeres ellenőrzés. \(pendingCount) sor várakozik."
        } catch {
            syncHadError = true
            pendingCount = await queue.count()
            status = "Hiba: \(error.localizedDescription) – a helyi mentések megmaradnak"
            let center = UNUserNotificationCenter.current()
            let lang = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "oranaplo.app.language") ?? "hu") ?? .hu
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = L10n.t("notification.sync.title", lang)
                content.body = L10n.t("notification.sync.body", lang)
                _ = try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
    private func flushQueue(using sheets: SheetsAPI) async throws {
        // If a previous upload timed out after the server accepted it, reconcile
        // before retrying. No ACK means "unknown", not "failed".
        let inFlight = await queue.uncertainBatch()
        if !inFlight.isEmpty {
            let onServer = try await sheets.alreadyOnSheet(inFlight, sheetID: sheetID)
            let confirmed = inFlight.filter { onServer.contains($0.id) }
            if !confirmed.isEmpty { try await queue.didUpload(confirmed) }
            try await queue.clearUncertain()
        }
        // A new installation may recover the Google Sheet but not its local
        // uploaded-ID journal. One remote column-A scan per sheet prevents
        // reimporting years of already existing measurements as duplicates.
        let needsInitialReconciliation = await queue.completedCount() == 0
        var remoteIDsBySheet: [String: Set<String>] = [:]
        var attempts = 0
        while true {
            let batch = await queue.nextBatch(limit: 150)
            if batch.isEmpty { break }
            if needsInitialReconciliation, let first = batch.first {
                if remoteIDsBySheet[first.sheet] == nil {
                    remoteIDsBySheet[first.sheet] = try await sheets.remoteRowIDs(sheet: first.sheet, sheetID: sheetID)
                }
                if let ids = remoteIDsBySheet[first.sheet] {
                    let alreadyThere = batch.filter { row in
                        ids.contains(row.id) || (row.id.hasPrefix("hk:") && ids.contains(row.values.first ?? ""))
                    }
                    if !alreadyThere.isEmpty {
                        try await queue.didUpload(alreadyThere)
                        continue
                    }
                }
            }
            try await queue.beginUpload(batch)
            try await sheets.append(batch, sheetID: sheetID)
            try await queue.didUpload(batch)
            lastUploadedCount += batch.count
            attempts += 1
            if attempts > 2000 { throw SyncError.config("Feltöltési biztonsági korlát: indíts új szinkront") }
        }
        pendingCount = await queue.count()
    }

    /// Import Apple Health's user-exported export.xml file without HealthKit permission.
    /// The app never reads the file without explicit selection. Only HR for Free.
    func importAppleHealthXML(from file: URL) async {
        guard !busy else { return }
        guard account.loggedIn else { xmlImportStatusKey = "xml.googleNeeded"; return }
        busy = true
        xmlImportStatusKey = "xml.processing"
        xmlImportCounts = ""
        defer { busy = false }
        await SubscriptionManager.shared.refreshEntitlement()
        let pro = SubscriptionManager.shared.proActive
        await loadCurrentAccount()
        let currentEmail = account.email
        let selectable = Catalog.metrics.filter { pro ? enabledGroups.contains($0.group) : $0.id == Catalog.freeSampleIdentifier }
        let lookup = Dictionary(uniqueKeysWithValues: selectable.map { ($0.id, $0) })
        let allowed = Set(lookup.keys)
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        let localQueue = queue
        do {
            let (result, savedCount) = try await Task.detached(priority: .userInitiated) { () throws -> (HealthXMLStatistics, Int) in
                var stored = 0
                let statistics = try HealthXMLCore.parse(url: file, allowedTypes: allowed, batchSize: 250) { batch in
                    let rows: [ExportRow] = batch.compactMap { record in
                        guard let metric = lookup[record.type],
                              let converted = HealthXMLCore.convertedValue(record.value, from: record.unit, to: metric.unit) else { return nil }
                        return ExportRow(id: record.id, sheet: metric.sheet, values: [
                            record.id, metric.label, ISO.string(record.start), ISO.string(record.end),
                            converted, metric.unit, record.source, record.device,
                            "Apple Health XML – manual export", "aktív", ISO.string(Date())
                        ])
                    }
                    // A bounded batch is durably saved before the next XML page is parsed.
                    // The parser runs on a worker; never block the main actor with XML parsing.
                    let signal = DispatchSemaphore(value: 0)
                    let errorBox = XMLBatchErrorBox()
                    Task {
                        do { try await localQueue.enqueue(rows, forAccount: currentEmail) }
                        catch { errorBox.store(error) }
                        signal.signal()
                    }
                    signal.wait()
                    if let failure = errorBox.read() { throw failure }
                    stored += rows.count
                }
                return (statistics, stored)
            }.value
            xmlImportCounts = "\(savedCount) / \(result.recordsSeen)"
            let api = SheetsAPI(account: account)
            try await ensureSheet(using: api)
            try await flushQueue(using: api)
            xmlImportStatusKey = "xml.finished"
            status = "Apple Health XML import: \(savedCount) / \(result.recordsSeen). Várakozó: \(pendingCount)"
            CrashCheckpoint.mark("XML import finished: records=\(result.recordsAccepted), batches=\(result.batches)")
        } catch {
            pendingCount = await queue.count()
            xmlImportStatusKey = "xml.failed"
            status = "XML import hiba: \(error.localizedDescription)"
            CrashCheckpoint.mark("XML import failed; pending=\(pendingCount)")
        }
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

/// Thread-safe error bridge between FoundationXML's synchronous streaming callback
/// and LocalQueue's asynchronous actor persistence. No health values are logged.
private final class XMLBatchErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?
    func store(_ newError: Error) { lock.lock(); defer { lock.unlock() }; error = newError }
    func read() -> Error? { lock.lock(); defer { lock.unlock() }; return error }
}
