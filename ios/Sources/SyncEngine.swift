import Foundation
import HealthKit
import UIKit
import Combine
import UserNotifications

@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    @Published var busy = false
    @Published var status = SyncStatusText.t("Diagnosztika: ", "Diagnostics: ", "Diagnose: ") + CrashCheckpoint.last
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
    @Published private(set) var lastFailureKind = ""
    @Published private(set) var lastAttemptDate: Date?
    @Published private(set) var syncProgress = "idle"
    @Published private(set) var autoSyncPaused = false
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
        if account.loggedIn && !autoSyncPaused && basicHealthFlowCompleted && Date().timeIntervalSince(previous) > 1800 {
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
            status = SyncStatusText.t("Egészségprofil engedélyezési hiba: \(error.localizedDescription)", "Health profile authorization error: \(error.localizedDescription)", "Fehler bei der Freigabe des Gesundheitsprofils: \(error.localizedDescription)")
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
            status = SyncStatusText.t("Egészségprofil Google Sheets hiba: \(error.localizedDescription)", "Health profile Google Sheets error: \(error.localizedDescription)", "Google-Sheets-Fehler beim Gesundheitsprofil: \(error.localizedDescription)")
        }
    }

    private func loadCurrentAccount() async {
        guard account.loggedIn else {
            WellnessDiary.shared.selectAccount("")
            sheetID = ""
            pendingCount = 0
            lastSync = "–"; lastSuccessfulDate = nil; lastAttemptDate = nil; lastFailureKind = ""; autoSyncPaused = false
            return
        }
        let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { sheetID = ""; return }
        do {
            try await queue.selectAccount(email)
            WellnessDiary.shared.selectAccount(email)
            sheetID = SpreadsheetRegistry.sheetID(for: email)
            pendingCount = await queue.count()
            // Sync state must be scoped by Google identity, not by a global date.
            lastSync = UserDefaults.standard.string(forKey:"syncLast.\(email)") ?? "–"
            lastSuccessfulDate = UserDefaults.standard.object(forKey:"syncDate.\(email)") as? Date
            lastFailureKind = UserDefaults.standard.string(forKey:"syncError.\(email)") ?? ""
            lastAttemptDate = UserDefaults.standard.object(forKey:"syncAttempt.\(email)") as? Date
            syncHadError = !lastFailureKind.isEmpty
            autoSyncPaused = UserDefaults.standard.bool(forKey:"syncPause.\(email)")
        } catch {
            sheetID = ""
            status = SyncStatusText.t("Fiókhoz tartozó mentési sor hiba: \(error.localizedDescription)", "Account-specific upload queue error: \(error.localizedDescription)", "Fehler in der Kontowarteschlange: \(error.localizedDescription)")
        }
    }

    func findPreviousSheet() async {
        await recoverCurrentSheetIfNeeded()
        status = sheetID.isEmpty
            ? SyncStatusText.t("Nem található korábbi táblázat.", "No previous spreadsheet found.", "Keine frühere Tabelle gefunden.")
            : SyncStatusText.t("A korábbi táblázat elérhető.", "Previous spreadsheet is available.", "Frühere Tabelle ist verfügbar.")
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
        WellnessDiary.shared.selectAccount("")
        sheetID = ""
        pendingCount = 0
        lastSync = "–"; lastSuccessfulDate = nil; lastAttemptDate = nil; lastFailureKind = ""
        syncProgress = "idle"; autoSyncPaused = false
        status = SyncStatusText.t("Google-fiók leválasztva. A helyi adatok fiókonként elkülönítve maradnak.", "Google account disconnected. Local data remains separated by account.", "Google-Konto getrennt. Lokale Daten bleiben nach Konto getrennt.")
    }
    private var syncAccountKey: String {
        account.email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
    }
    private func markAttempt(_ key:String) {
        lastAttemptDate = Date()
        let identity=syncAccountKey
        if !identity.isEmpty { UserDefaults.standard.set(lastAttemptDate,forKey:"syncAttempt.\(identity)") }
        syncProgress = key
        SafeDiagnosticTrail.mark(.syncStarted)
    }
    private func markSuccess() {
        let now=Date()
        lastSuccessfulDate=now; lastSync=ISO.string(now)
        let identity=syncAccountKey
        if !identity.isEmpty {
            UserDefaults.standard.set(now,forKey:"syncDate.\(identity)")
            UserDefaults.standard.set(lastSync,forKey:"syncLast.\(identity)")
            UserDefaults.standard.removeObject(forKey:"syncError.\(identity)")
        }
        lastFailureKind=""; syncHadError=false; syncProgress="done"
        SafeDiagnosticTrail.mark(.syncFinished)
    }
    private func markFailure(_ error:Error) {
        // Save only an intentionally coarse error category; no token, user ID,
        // spreadsheet title, GPS position or raw health measurement in diagnostics.
        let ns=error as NSError
        let kind:String
        if ns.domain==NSURLErrorDomain { kind="network" }
        else if ns.code==401 || ns.code==403 { kind="authorization" }
        else if ns.code==429 { kind="quota" }
        else { kind="unknown" }
        lastFailureKind=kind; syncHadError=true; syncProgress="failed"
        let identity=syncAccountKey
        if !identity.isEmpty { UserDefaults.standard.set(kind,forKey:"syncError.\(identity)") }
        CrashCheckpoint.mark("sync.failed.\(kind)")
        SafeDiagnosticTrail.mark(.syncFailed)
    }

    /// Explicit, confirmed local deletion. The remote Google spreadsheet and
    /// Apple's Health data are deliberately not modified here.
    func eraseLocalHistory() async throws {
        guard !busy else { throw SyncError.config("A szinkron befejezése után törölhetsz.") }
        guard RunTracker.shared.phase != .recording else { throw RunStorageError.activeWorkout }
        try WellnessDiary.shared.erase() // Medication, sleep rating, water and room data too.
        let identity=syncAccountKey
        if !identity.isEmpty {
            try await queue.selectAccount(identity)
            try await queue.eraseSelectedAccount()
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("anchor.v3.\(identity).") {
                UserDefaults.standard.removeObject(forKey:key)
            }
            for name in ["syncDate.\(identity)","syncLast.\(identity)","syncError.\(identity)","syncAttempt.\(identity)"] {
                UserDefaults.standard.removeObject(forKey:name)
            }
        }
        try RunTracker.shared.eraseAllLocalRuns()
        UserDefaults.standard.removeObject(forKey:"lastSync")
        UserDefaults.standard.removeObject(forKey:"lastSuccessfulSyncDate")
        lastSync="–"; lastSuccessfulDate=nil; lastAttemptDate=nil; lastFailureKind=""; lastUploadedCount=0
        pendingCount=0; xmlImportCounts=""; syncProgress="idle"
        profile=nil; lastWorkout=nil; observations=[]; personalObservations=[]
        CrashCheckpoint.eraseHistory()
        SafeDiagnosticTrail.erase()
        if !identity.isEmpty {
            UserDefaults.standard.set(true,forKey:"syncPause.\(identity)")
            autoSyncPaused=true
            try await queue.selectAccount(identity)
        }
        status=SyncStatusText.t("A helyi előzmények törölve. A Google Sheets és az Apple Egészség adatai megmaradtak.", "Local history deleted. Google Sheets and Apple Health data were preserved.", "Lokaler Verlauf gelöscht. Google Sheets und Apple Health bleiben erhalten.")
    }

    /// User-initiated reactivation. Warn in the UI: data in Apple Health can
    /// be imported again; deleting local history never deletes the source.
    func resumeAutoSyncAfterErase() {
        let identity=syncAccountKey
        guard !identity.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey:"syncPause.\(identity)")
        autoSyncPaused=false
        syncProgress="idle"
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
            status = SyncStatusText.t("Alap HealthKit engedélykérés lefutott (csak pulzus).", "Basic HealthKit authorization requested (heart rate only).", "Grundlegende HealthKit-Freigabe angefordert (nur Herzfrequenz).")
            await reader.enableBackgroundNotifications()
            await refreshOverview()
        } catch {
            CrashCheckpoint.mark("HealthKit alapteszt hiba: \(error.localizedDescription)")
            status = SyncStatusText.t("Egészség alapteszt: \(error.localizedDescription)", "Basic Health test: \(error.localizedDescription)", "Health-Grundtest: \(error.localizedDescription)")
        }
    }
    func authorizeAllHealth() async {
        // HealthKit READ access is available to free users for on-device dashboards.
        // Pro is checked only in export code, so free mode still uploads heart rate alone.
        guard basicHealthFlowCompleted else {
            status = SyncStatusText.t("Előbb futtasd a pulzus HealthKit-alaptesztet", "Run the basic HealthKit heart-rate test first", "Führe zuerst den HealthKit-Grundtest für die Herzfrequenz durch")
            return
        }
        do {
            try await reader.authorize()
            fullHealthFlowCompleted = true
            UserDefaults.standard.set(true, forKey: "healthFullCompleted")
            status = SyncStatusText.t("Teljes HealthKit engedélykérés lezajlott", "Full HealthKit authorization requested", "Vollständige HealthKit-Freigabe angefordert")
            await reader.enableBackgroundNotifications()
            await refreshOverview()
        } catch {
            CrashCheckpoint.mark("HealthKit teljes engedélykérés hiba: \(error.localizedDescription)")
            status = SyncStatusText.t("Egészség teljes kérés: \(error.localizedDescription)", "Full Health authorization: \(error.localizedDescription)", "Vollständige Health-Freigabe: \(error.localizedDescription)")
        }
    }
    func login() async {
        guard !busy else { return }
        do {
            try await account.signIn()
            await loadCurrentAccount()
            await recoverCurrentSheetIfNeeded()
            status = sheetID.isEmpty
                ? SyncStatusText.t("Google-fiók kapcsolódott. Most létrehozhatod a táblázatodat.", "Google account connected. You can now create a spreadsheet.", "Google-Konto verbunden. Du kannst jetzt eine Tabelle erstellen.")
                : SyncStatusText.t("Google-fiók kapcsolódott. A saját táblázatod elérhető.", "Google account connected. Your spreadsheet is available.", "Google-Konto verbunden. Deine Tabelle ist verfügbar.")
        } catch {
            CrashCheckpoint.mark("Google hiba: \(error.localizedDescription)")
            status = SyncStatusText.t("Google: \(error.localizedDescription)", "Google: \(error.localizedDescription)", "Google: \(error.localizedDescription)")
        }
    }
    /// Opt-in export of an on-device recorded run. Raw GPS coordinates stay local;
    /// route sharing is a separate GPX action. Only verified Pro can queue these rows.
    func exportRecordedRun(_ run: RecordedRun) async {
        guard !busy else { status = SyncStatusText.t("A szinkron már folyamatban van.", "Synchronization is already in progress.", "Synchronisierung läuft bereits."); return }
        await SubscriptionManager.shared.refreshEntitlement()
        guard SubscriptionManager.shared.proActive else {
            status = SyncStatusText.t("A saját futások részletes exportálásához Pro-előfizetés szükséges.", "Pro subscription required to export detailed runs.", "Für den detaillierten Laufexport ist Pro erforderlich."); return
        }
        guard account.loggedIn else {
            status = SyncStatusText.t("Először csatlakoztasd a Google-fiókodat.", "Connect your Google account first.", "Verbinde zuerst dein Google-Konto."); return
        }
        guard run.completed, let end = run.ended else {
            status = SyncStatusText.t("Csak befejezett futást lehet exportálni.", "Only completed runs can be exported.", "Nur abgeschlossene Läufe können exportiert werden."); return
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
            status = SyncStatusText.t("Futás és 100 m-es szakaszok helyben mentve feltöltésre.", "Run and 100 m splits saved locally for upload.", "Lauf und 100-m-Abschnitte lokal zum Hochladen gespeichert.")
            await prepareGoogleSheet()
            if !sheetID.isEmpty {
                do {
                    try await SheetsAPI(account:account).updateRunAchievements(
                        sheetID:sheetID,records:RunTracker.shared.personalRecords,
                        goals:RunTracker.shared.weeklySummary)
                } catch {
                    // Do not roll back a successful measurement export because of a dashboard update.
                    status += SyncStatusText.t(" A rekordok/friss célok szinkronja külön nem sikerült: \(error.localizedDescription)", " Records or goal synchronization failed separately: \(error.localizedDescription)", " Die Synchronisierung der Rekorde oder Ziele ist separat fehlgeschlagen: \(error.localizedDescription)")
                }
            }
        } catch { status = SyncStatusText.t("Futásexport-hiba: \(error.localizedDescription)", "Run export error: \(error.localizedDescription)", "Fehler beim Laufexport: \(error.localizedDescription)") }
    }

    func addJournalEntry(kind: String, note: String) async {
        await SubscriptionManager.shared.refreshEntitlement()
        guard SubscriptionManager.shared.proActive else {
            status = SyncStatusText.t("A napló exportálásához Pro-előfizetés szükséges.", "Pro subscription required to export journal entries.", "Für den Tagebuchexport ist Pro erforderlich.")
            return
        }
        guard account.loggedIn else { status = SyncStatusText.t("A napló mentéséhez először csatlakoztasd a Google-fiókodat", "Connect your Google account before saving journal entries", "Verbinde dein Google-Konto, bevor du Einträge speicherst"); return }
        await loadCurrentAccount()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = SyncStatusText.t("Írj be egy megjegyzést", "Enter a note", "Gib eine Notiz ein"); return }
        let row = ExportRow(id: "note:\(UUID().uuidString)", sheet: "Naplo", values: [
            UUID().uuidString, kind, ISO.string(Date()), "", "", "", "Kézi napló", "iPhone",
            String(trimmed.prefix(1500)), "aktív", ISO.string(Date())
        ])
        do {
            try await queue.enqueue([row])
            pendingCount = await queue.count()
            status = SyncStatusText.t("Naplóbejegyzés helyben mentve.", "Journal entry saved locally.", "Tagebucheintrag lokal gespeichert.")
            // Journal rows do not require HealthKit. Try immediate upload when signed in.
            if account.loggedIn && !busy {
                await prepareGoogleSheet()
            } else if !account.loggedIn {
                status = SyncStatusText.t("Napló helyben mentve. Google-bejelentkezés után tölthető fel.", "Journal saved locally. Upload after signing into Google.", "Tagebuch lokal gespeichert. Upload nach Google-Anmeldung möglich.")
            }
        } catch { status = SyncStatusText.t("Naplómentés hiba: \(error.localizedDescription)", "Journal save error: \(error.localizedDescription)", "Fehler beim Speichern des Tagebuchs: \(error.localizedDescription)") }
    }

    /// Create the user's Google spreadsheet and upload pending journal rows.
    /// This intentionally never requests Apple Health authorization.
    func prepareGoogleSheet() async {
        guard !busy else { return }
        guard account.loggedIn else {
            status = SyncStatusText.t("Először csatlakoztasd a Google-fiókodat", "Connect your Google account first", "Verbinde zuerst dein Google-Konto")
            return
        }
        busy = true
        lastUploadedCount = 0
        markAttempt("starting")
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
            markSuccess()
            status = SyncStatusText.t("Google Sheets készen áll. A táblázat megnyitható. Várakozó sorok: \(pendingCount).", "Google Sheets is ready. You can open the spreadsheet. Pending rows: \(pendingCount).", "Google Sheets ist bereit. Tabelle kann geöffnet werden. Ausstehende Zeilen: \(pendingCount).")
            CrashCheckpoint.mark("Google Sheets inicializálás: sikeres")
        } catch {
            markFailure(error)
            pendingCount = await queue.count()
            status = SyncStatusText.t("Google Sheets hiba: \(error.localizedDescription)", "Google Sheets error: \(error.localizedDescription)", "Google-Sheets-Fehler: \(error.localizedDescription)")
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
        guard !autoSyncPaused else {
            status = SyncStatusText.t("A szinkronizálás szünetel a helyi törlés után. A folytatást külön engedélyezd.", "Sync is paused after local deletion. Explicitly enable it to continue.", "Synchronisierung nach lokaler Löschung pausiert. Zum Fortfahren ausdrücklich aktivieren.")
            return
        }
        guard account.loggedIn else {
            status = SyncStatusText.t("Először csatlakoztasd a Google-fiókodat", "Connect your Google account first", "Verbinde zuerst dein Google-Konto")
            return
        }
        guard basicHealthFlowCompleted else {
            status = SyncStatusText.t("Egészségadatokhoz HealthKit-engedély szükséges. A Google Sheets létrehozása ettől függetlenül működik.", "HealthKit permission required for health data. You can still create a Google Sheet.", "Für Gesundheitsdaten ist HealthKit-Zugriff erforderlich. Google Sheets kann trotzdem erstellt werden.")
            return
        }
        busy = true
        lastUploadedCount = 0
        markAttempt("starting")
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
            status = SyncStatusText.t("Egészségadatok feldolgozása…", "Processing health data…", "Gesundheitsdaten werden verarbeitet…")
            syncProgress = "reading"
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
                // 30k records per metric per pass used to be a silent truncation.
                // When a page cap is reached, surface a recoverable error so another
                // sync resumes from the already persisted anchor instead of claiming success.
                var caughtUp = false
                for _ in 0..<100 {
                    let (added, deleted, newAnchor, count) = try await reader.samplePage(type, since: since, anchor: anchor)
                    let rows = added.map { rawRow($0, metric: metric) } + deleted.map { deletedRow($0, metric: metric) }
                    try await queue.enqueue(rows)
                    if let newAnchor {
                        let bytes = try NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true)
                        UserDefaults.standard.set(bytes, forKey: key)
                        anchor = newAnchor
                    }
                    if count < 300 { caughtUp = true; break }
                }
                if !caughtUp {
                    throw SyncError.config("Nagy HealthKit előzmény: 30 000 minta után folytatás szükséges. A mentett importpozíció megmaradt; indíts új szinkront.")
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
            markSuccess()
            await refreshOverview()
            status = SyncStatusText.t("Sikeres ellenőrzés. \(pendingCount) sor várakozik.", "Check completed. \(pendingCount) rows pending.", "Prüfung abgeschlossen. \(pendingCount) Zeilen ausstehend.")
        } catch {
            markFailure(error)
            pendingCount = await queue.count()
            status = SyncStatusText.t("Hiba: \(error.localizedDescription) – a helyi mentések megmaradnak", "Error: \(error.localizedDescription) – local saves are preserved", "Fehler: \(error.localizedDescription) – lokale Daten bleiben erhalten")
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
        let sheetChanged = await queue.needsRemoteReconciliation(for: sheetID)
        let previousCompleted = await queue.completedCount()
        let needsInitialReconciliation = previousCompleted == 0 || sheetChanged
        var remoteIDsBySheet: [String: Set<String>] = [:]
        var attempts = 0
        while true {
            let batch = await queue.nextBatch(limit: 150, allowPremium: SubscriptionManager.shared.proActive)
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
            syncProgress = "uploading"
            try await sheets.append(batch, sheetID: sheetID)
            try await queue.didUpload(batch)
            lastUploadedCount += batch.count
            attempts += 1
            if attempts > 2000 { throw SyncError.config("Feltöltési biztonsági korlát: indíts új szinkront") }
        }
        // Mark only after every queried remote sheet succeeded; a failed scan must
        // be repeated on the next attempt rather than allowing duplicate appends.
        if needsInitialReconciliation && !remoteIDsBySheet.isEmpty {
            try await queue.markRemoteReconciled(for: sheetID)
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
            status = SyncStatusText.t("Apple Health XML import: \(savedCount) / \(result.recordsSeen). Várakozó: \(pendingCount)", "Apple Health XML import: \(savedCount) / \(result.recordsSeen). Pending: \(pendingCount)", "Apple Health XML-Import: \(savedCount) / \(result.recordsSeen). Ausstehend: \(pendingCount)")
            CrashCheckpoint.mark("XML import finished: records=\(result.recordsAccepted), batches=\(result.batches)")
        } catch {
            pendingCount = await queue.count()
            xmlImportStatusKey = "xml.failed"
            status = SyncStatusText.t("XML import hiba: \(error.localizedDescription)", "XML import error: \(error.localizedDescription)", "XML-Importfehler: \(error.localizedDescription)")
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

/// Language-dependent operational messages. Values are computed at the point of the event.
/// They are presentation strings only and must not control authorization or queue logic.
private enum SyncStatusText {
    static func t(_ hu: String, _ en: String, _ de: String) -> String {
        switch AppLanguage(rawValue: UserDefaults.standard.string(forKey: "oranaplo.app.language") ?? "hu") ?? .hu {
        case .hu: return hu
        case .en: return en
        case .de: return de
        }
    }
}
