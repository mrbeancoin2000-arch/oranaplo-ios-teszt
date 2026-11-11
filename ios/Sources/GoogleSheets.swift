import Foundation
import UIKit
import Combine
import GoogleSignIn

@MainActor
final class GoogleAccount: ObservableObject {
    @Published private(set) var loggedIn = false
    @Published private(set) var email = ""
    static let scope = "https://www.googleapis.com/auth/drive.file"

    init() {
        let client = AppConfig.googleClientID
        if !client.hasPrefix("ADD_") { GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: client) }
        Task { await restore() }
    }
    func restore() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            loggedIn = user.grantedScopes?.contains(Self.scope) == true
            email = user.profile?.email ?? ""
            if email.isEmpty { loggedIn = false }
        } catch { loggedIn = false; email = "" }
    }
    func signIn() async throws {
        CrashCheckpoint.mark("Google: bejelentkezés előzetes ellenőrzése")
        let client = AppConfig.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !client.hasPrefix("ADD_"), client.hasSuffix(".apps.googleusercontent.com") else {
            throw SyncError.config("Hiányzó vagy hibás Google iOS OAuth Client ID. Lásd: GOOGLE_BEALLITAS.md")
        }
        // The Google SDK can throw an Objective-C exception (not catchable with Swift do/catch)
        // when its expected reversed-client-ID URL scheme is absent from the signed application.
        let expectedScheme = client.split(separator: ".").reversed().joined(separator: ".")
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let installedSchemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard installedSchemes.contains(where: { $0.caseInsensitiveCompare(expectedScheme) == .orderedSame }) else {
            CrashCheckpoint.mark("Google: hibás visszairányítási URL-séma")
            throw SyncError.config("A telepített app Google URL-sémája eltér. Elvárt: \(expectedScheme). Új Google-konfiguráció és IPA-fordítás szükséges.")
        }
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID == AppConfig.googleBundleID else {
            CrashCheckpoint.mark("Google: Sideloadly által módosított bundle ID")
            throw SyncError.config("Az iPhone-ra telepített app azonosítója (\(Bundle.main.bundleIdentifier ?? "ismeretlen")) eltér a Google iOS OAuth-ban beállított azonosítótól (\(AppConfig.googleBundleID)). Készíts iOS OAuth klienst a telepített azonosítóhoz, majd frissítsd a google_oauth.json fájlt és építs új IPA-t.")
        }
        guard let controller = UIViewController.topMost else {
            throw SyncError.config("Nem található bejelentkezési ablak")
        }
        CrashCheckpoint.mark("Google: natív GoogleSignIn indítása")
        var user = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller).user
        CrashCheckpoint.mark("Google: alapbejelentkezés visszatért")
        if user.grantedScopes?.contains(Self.scope) != true {
            CrashCheckpoint.mark("Google: drive.file jogosultság bekérése")
            user = try await user.addScopes([Self.scope], presenting: controller).user
        }
        loggedIn = true
        email = user.profile?.email ?? ""
        guard !email.isEmpty else {
            loggedIn = false
            throw SyncError.config("Google-fiók e-mail címe nem elérhető")
        }
        CrashCheckpoint.mark("Google: sikeres bejelentkezés")
    }
    func token() async throws -> String {
        guard let current = GIDSignIn.sharedInstance.currentUser else { throw SyncError.config("Jelentkezz be a Google-fiókodba") }
        let refreshed = try await current.refreshTokensIfNeeded()
        guard refreshed.grantedScopes?.contains(Self.scope) == true else { throw SyncError.config("Google Sheets jogosultság hiányzik") }
        return refreshed.accessToken.tokenString
    }
    func signOut() {
        GIDSignIn.sharedInstance.signOut(); loggedIn = false; email = ""
    }
}

extension UIViewController {
    static var topMost: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        var current = root
        while let presented = current.presentedViewController { current = presented }
        return current
    }
}

enum SyncError: LocalizedError {
    case config(String)
    case api(Int, String)
    var errorDescription: String? {
        switch self { case .config(let detail): return detail; case .api(let status, let detail): return "Google API \(status): \(detail.prefix(400))" }
    }
}

struct SheetsAPI {
    let account: GoogleAccount
    private func request(_ method: String, _ path: String, body: Any? = nil, allowRetry: Bool = true) async throws -> Data {
        let token = try await account.token()
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets" + path) else { throw SyncError.config("Hibás API URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 55
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        for attempt in 0..<4 {
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) { return data }
                if allowRetry && [429,500,502,503,504].contains(status) && attempt < 3 {
                    try await Task.sleep(for: .seconds(Double(1 << attempt))); continue
                }
                throw SyncError.api(status, String(data: data, encoding: .utf8) ?? "ismeretlen hiba")
            } catch {
                if allowRetry && attempt < 3 && !(error is SyncError) {
                    try await Task.sleep(for: .seconds(Double(1 << attempt))); continue
                }
                throw error
            }
        }
        throw SyncError.config("Sikertelen adatküldés")
    }
    /// Best-effort recovery after reinstall or a second device. The drive.file OAuth
    /// scope restricts discovery to files created/opened through this application.
    func findExistingSpreadsheet() async throws -> String? {
        let token = try await account.token()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = 'ÓraNapló – Egészségadatok' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name,createdTime)"),
            URLQueryItem(name: "orderBy", value: "createdTime desc"),
            URLQueryItem(name: "pageSize", value: "30")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SyncError.config("A korábbi Google Sheets-fájlok keresése nem elérhető. Ellenőrizd, hogy a Google Drive API engedélyezve van-e.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        return files.first?["id"] as? String
    }

    func canAccessSpreadsheet(_ id: String) async -> Bool {
        guard !id.isEmpty else { return false }
        return (try? await request("GET", "/\(id)?fields=spreadsheetId")) != nil
    }

    func createSpreadsheet() async throws -> String {
        let sheets: [[String: Any]] = Catalog.sheets.map { ["properties": ["title": $0, "gridProperties": ["frozenRowCount": 1]]] }
        let data = try await request("POST", "", body: ["properties": ["title": "ÓraNapló – Egészségadatok"], "sheets": sheets])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String:Any], let id = obj["spreadsheetId"] as? String else { throw SyncError.config("Nem érkezett táblázatazonosító") }
        var ranges: [[String:Any]] = Catalog.sheets.map { sheet in
            let header = sheet == "ElemzesBeallitasok" ? Catalog.analysisSettingsHeader : (sheet == "Profil" ? Catalog.profileHeader : (sheet == "Megfigyelesek" ? Catalog.observationHeader : (sheet == "100m" ? Catalog.segmentHeader : (sheet == "Edzesek" ? Catalog.workoutHeader : (sheet == "Rekordok" ? Catalog.recordHeader : (sheet == "Celok" ? Catalog.goalHeader : (sheet == "Dashboard" ? ["ÓraNapló · FUTÁS DASHBOARD"] : Catalog.rawHeader)))))))
            return ["range": "'\(sheet)'!A1", "values": [header]]
        }
        ranges.append(["range": "'ElemzesBeallitasok'!A2", "values": [
            ["teljes_folyadeknaplo", "NEM", "Csak IGEN esetén figyelmeztethet a saját folyadékcél alatti napló"],
            ["napi_cel_ml", "", "Saját naplózási cél; orvosi ajánlásként nem használható"]
        ]])
        _ = try await request("POST", "/\(id)/values:batchUpdate", body: ["valueInputOption":"RAW", "data":ranges])
        // The spreadsheet is already created. Never lose its ID if chart formatting
        // is rejected due to an API permission/quota/transient failure.
        do { try await styleDashboard(sheetID:id, initial:true) }
        catch { print("ÓraNapló dashboard formatting deferred: \(error.localizedDescription)") }
        return id
    }
    /// Upgrade spreadsheets created before the profile/observation feature.
    /// Existing measurements and worksheets are never deleted or rewritten.
    func ensureProfileTabs(sheetID: String) async throws {
        let bytes = try await request("GET", "/\(sheetID)?fields=sheets.properties.title")
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
        let existing = Set((object["sheets"] as? [[String: Any]] ?? []).compactMap { sheet -> String? in
            (sheet["properties"] as? [String: Any])?["title"] as? String
        })
        let required = ["Profil", "Megfigyelesek", "ElemzesBeallitasok", "Dashboard", "Rekordok", "Celok"]
        let missing = required.filter { !existing.contains($0) }
        if missing.isEmpty {
            try await ensureRunSplitColumns(sheetID:sheetID)
            return
        }
        let operations = missing.map { ["addSheet": ["properties": ["title": $0]]] }
        _ = try await request("POST", "/\(sheetID):batchUpdate", body: ["requests": operations])
        var updates: [[String: Any]] = missing.map { tab in
            let header = tab == "Profil" ? Catalog.profileHeader :
                (tab == "Megfigyelesek" ? Catalog.observationHeader :
                (tab == "Rekordok" ? Catalog.recordHeader : (tab == "Celok" ? Catalog.goalHeader :
                (tab == "Dashboard" ? ["ÓraNapló · FUTÁS DASHBOARD"] : Catalog.analysisSettingsHeader))))
            return ["range": "'\(tab)'!A1", "values": [header]]
        }
        if missing.contains("ElemzesBeallitasok") {
            updates.append(["range": "'ElemzesBeallitasok'!A2", "values": [
                ["teljes_folyadeknaplo", "NEM", "Külön felhasználói jóváhagyás szükséges"],
                ["napi_cel_ml", "", "Saját naplózási cél, nem orvosi ajánlás"]
            ]])
        }
        _ = try await request("POST", "/\(sheetID)/values:batchUpdate",
                              body: ["valueInputOption": "RAW", "data": updates])
        try await ensureRunSplitColumns(sheetID:sheetID)
        if missing.contains("Dashboard") {
            do { try await styleDashboard(sheetID:sheetID, initial:false) }
            catch { print("ÓraNapló dashboard formatting deferred: \(error.localizedDescription)") }
        }
    }

    /// Migration for 0.5.1: preserve existing columns A:N and add step/calorie
    /// details for *new* 100 m rows in O:P. This does not rewrite historic runs.
    private func ensureRunSplitColumns(sheetID: String) async throws {
        _ = try await request("PUT", "/\(sheetID)/values/'100m'!O1:P1?valueInputOption=RAW",
                              body: ["values": [["lepes_100m_becsult", "kaloria_kcal_becsult"]]])
    }

    /// Create a ready-to-use dashboard only once; never overwrite a customized one.
    private func styleDashboard(sheetID: String, initial: Bool) async throws {
        func weeklyFormula(_ row: Int) -> String {
            #"=IFERROR(SUM(ARRAYFORMULA(VALUE(FILTER(Edzesek!G$2:G,LEFT(Edzesek!C$2:C,10)>=A\#(row),LEFT(Edzesek!C$2:C,10)<TEXT(DATEVALUE(A\#(row))+7,"yyyy-mm-dd"),REGEXMATCH(LOWER(Edzesek!B$2:B),"fut")))))/1000,0)"#
        }
        func speedFormula(_ row: Int) -> String {
            #"=IFERROR(AVERAGE(ARRAYFORMULA(VALUE(FILTER('100m'!H$2:H,LEFT('100m'!E$2:E,10)>=A\#(row),LEFT('100m'!E$2:E,10)<TEXT(DATEVALUE(A\#(row))+7,"yyyy-mm-dd"))))),0)"#
        }
        var weekly: [[String]] = [["HETI FUTÓTÁV", "km", "100 m átlag km/h"]]
        for row in 12...19 {
            let dateFormula = row == 12
                ? #"=TEXT(TODAY()-WEEKDAY(TODAY(),2)+1-49,"yyyy-mm-dd")"#
                : #"=TEXT(DATEVALUE(A\#(row-1))+7,"yyyy-mm-dd")"#
            weekly.append([dateFormula, weeklyFormula(row), speedFormula(row)])
        }
        let metricRows: [[String]] = [
            ["MUTATÓ", "ÉRTÉK", "EGYSÉG"],
            ["Heti futótáv", #"=IFERROR(SUM(ARRAYFORMULA(VALUE(FILTER(Edzesek!G2:G, REGEXMATCH(LOWER(Edzesek!B2:B),"fut"), LEFT(Edzesek!C2:C,10)>=TEXT(TODAY()-WEEKDAY(TODAY(),2)+1,"yyyy-mm-dd")))))/1000,0)"#, "km"],
            ["Havi futótáv", #"=IFERROR(SUM(ARRAYFORMULA(VALUE(FILTER(Edzesek!G2:G, REGEXMATCH(LOWER(Edzesek!B2:B),"fut"), LEFT(Edzesek!C2:C,7)=TEXT(TODAY(),"yyyy-mm")))))/1000,0)"#, "km"],
            ["Összes edzés", "=COUNTA(Edzesek!A2:A)", "db"],
            ["100 m szakaszok", "=COUNTA('100m'!A2:A)", "db"]
        ]
        let heartRows: [[String]] = [
            ["PULZUS (bpm)", "MINTÁK"],
            ["< 100", #"=COUNTIF(Pulzus!E2:E,"<100")"#],
            ["100–119", #"=COUNTIFS(Pulzus!E2:E,">=100",Pulzus!E2:E,"<120")"#],
            ["120–139", #"=COUNTIFS(Pulzus!E2:E,">=120",Pulzus!E2:E,"<140")"#],
            ["140–159", #"=COUNTIFS(Pulzus!E2:E,">=140",Pulzus!E2:E,"<160")"#],
            ["160+", #"=COUNTIF(Pulzus!E2:E,">=160")"#]
        ]
        let data: [[String:Any]] = [
            ["range":"'Dashboard'!A1", "values":[["ÓraNapló | FUTÁS & EGÉSZSÉG"]]],
            ["range":"'Dashboard'!A2", "values":[["Saját adataid a saját Google Drive-odon"]]],
            ["range":"'Dashboard'!A4", "values":metricRows],
            ["range":"'Dashboard'!A11", "values":weekly],
            ["range":"'Dashboard'!E11", "values":heartRows],
            ["range":"'Dashboard'!A21", "values":[["A pulzuscsoportok nem orvosi diagnózisok vagy személyes edzészónák."]]]
        ]
        _ = try await request("POST", "/\(sheetID)/values:batchUpdate", body:["valueInputOption":"USER_ENTERED", "data":data])
        let raw = try await request("GET", "/\(sheetID)?fields=sheets.properties(sheetId,title)")
        let obj = try JSONSerialization.jsonObject(with:raw) as? [String:Any] ?? [:]
        let props = (obj["sheets"] as? [[String:Any]] ?? []).compactMap { $0["properties"] as? [String:Any] }
        guard let dashID = props.first(where:{$0["title"] as? String == "Dashboard"})?["sheetId"] as? Int else { return }
        func rgb(_ red: Double,_ green: Double,_ blue: Double) -> [String:Double] {
            ["red":red,"green":green,"blue":blue]
        }
        let ink=rgb(0.035,0.067,0.11), steel=rgb(0.10,0.17,0.25)
        let accent=rgb(0.29,0.66,0.93), white=rgb(0.96,0.98,1)
        var requests: [[String:Any]] = [
            ["updateSheetProperties":["properties":["sheetId":dashID,"gridProperties":["hideGridlines":true,"frozenRowCount":2],"index":0],"fields":"gridProperties.hideGridlines,gridProperties.frozenRowCount,index"]],
            ["repeatCell":["range":["sheetId":dashID,"startRowIndex":0,"endRowIndex":35,"startColumnIndex":0,"endColumnIndex":9],"cell":["userEnteredFormat":["backgroundColor":ink,"textFormat":["foregroundColor":white,"fontSize":11]]],"fields":"userEnteredFormat"]],
            ["repeatCell":["range":["sheetId":dashID,"startRowIndex":0,"endRowIndex":1,"startColumnIndex":0,"endColumnIndex":9],"cell":["userEnteredFormat":["backgroundColor":steel,"textFormat":["foregroundColor":white,"fontSize":20,"bold":true]]],"fields":"userEnteredFormat"]],
            ["repeatCell":["range":["sheetId":dashID,"startRowIndex":3,"endRowIndex":4,"startColumnIndex":0,"endColumnIndex":3],"cell":["userEnteredFormat":["backgroundColor":steel,"textFormat":["foregroundColor":accent,"bold":true]]],"fields":"userEnteredFormat"]],
            ["updateDimensionProperties":["range":["sheetId":dashID,"dimension":"COLUMNS","startIndex":0,"endIndex":1],"properties":["pixelSize":210],"fields":"pixelSize"]],
            ["updateDimensionProperties":["range":["sheetId":dashID,"dimension":"COLUMNS","startIndex":1,"endIndex":9],"properties":["pixelSize":140],"fields":"pixelSize"]]
        ]
        func chart(_ title:String, _ kind:String, _ domain:Int, _ value:Int,
                   _ anchor:Int, _ first:Int, _ last:Int) -> [String:Any] {
            func range(_ column:Int) -> [String:Any] {
                ["sources":[["sheetId":dashID,"startRowIndex":first,"endRowIndex":last,
                             "startColumnIndex":column,"endColumnIndex":column+1]]]
            }
            let basic: [String:Any] = ["chartType":kind,"legendPosition":"NO_LEGEND","headerCount":1,
                "domains":[["domain":["sourceRange":range(domain)]]],
                "series":[["series":["sourceRange":range(value)],"targetAxis":"LEFT_AXIS","color":accent]]]
            let position: [String:Any] = ["overlayPosition":["anchorCell":["sheetId":dashID,
                "rowIndex":(title.hasPrefix("Pulzus") ? 43 : 24),"columnIndex":anchor],"widthPixels":480,"heightPixels":250]]
            return ["addChart":["chart":["spec":["title":title,"basicChart":basic],"position":position]]]
        }
        requests.append(chart("Heti megtett kilométer", "COLUMN", 0, 1, 0, 10, 19))
        requests.append(chart("100 m átlagsebesség", "LINE", 0, 2, 4, 10, 19))
        requests.append(chart("Pulzusminták eloszlása", "COLUMN", 4, 5, 0, 10, 17))
        _ = try await request("POST", "/\(sheetID):batchUpdate",body:["requests":requests])
    }

    /// Write the long-term on-device record and goal archive, not just the limited
    /// recent GPS tracks kept for local route previews.
    func updateRunAchievements(sheetID: String, records: [RunPersonalRecord], goals: RunGoalSummary) async throws {
        let time = ISO.string(Date())
        let recordsRows = [Catalog.recordHeader] + records.map { r in
            ["record:\(r.distanceMeters)",String(r.distanceMeters),String(r.seconds),r.runID.uuidString,ISO.string(r.recorded),"GPS-alapú, csak összefüggő útvonal"]
        }
        // Always clear up to four former PR rows when an older record disappears,
        // e.g. after deleting a run or revoking history. A shorter values update
        // alone would leave stale records visible below the refreshed range.
        let cleanRecords = recordsRows + Array(repeating: [String](repeating: "", count: Catalog.recordHeader.count),
                                               count: max(0, 1 + RunInsights.distances.count - recordsRows.count))
        let goalRows = [Catalog.goalHeader,
            ["weekly_km",String(goals.weeklyMeters/1000),time],
            ["monthly_km",String(goals.monthlyMeters/1000),time],
            ["weekly_goal_km",String(goals.weeklyGoalMeters/1000),time],
            ["weekly_streak",String(goals.weeklyStreak),time],
            ["active_days_this_week",String(goals.activeDaysThisWeek),time]]
        _ = try await request("POST", "/\(sheetID)/values:batchUpdate",body:["valueInputOption":"RAW","data":[
            ["range":"'Rekordok'!A1","values":cleanRecords],
            ["range":"'Celok'!A1","values":goalRows]]])
    }

    /// Explicit opt-in: place only age (not birthdate), biological sex, height and weight
    /// into the user's own spreadsheet for optional spreadsheet-bound rules.
    func updateProfile(_ profile: PersonalHealthProfile, sheetID: String) async throws {
        let timestamp = ISO.string(Date())
        let values: [[String]] = [
            Catalog.profileHeader,
            ["age_years", profile.ageYears.map { String($0) } ?? "", "Apple Health", timestamp],
            ["biological_sex", profile.biologicalSexKey.replacingOccurrences(of: "profile.sex.", with: ""), "Apple Health", timestamp],
            ["height_cm", profile.heightCM.map { String(format: "%.1f", $0) } ?? "", "Apple Health", timestamp],
            ["weight_kg", profile.weightKG.map { String(format: "%.1f", $0) } ?? "", "Apple Health", timestamp]
        ]
        _ = try await request("PUT", "/\(sheetID)/values/'Profil'!A1:D5?valueInputOption=RAW",
                              body: ["majorDimension": "ROWS", "values": values])
    }

    /// Reads optional observations written by the user's own bound Apps Script.
    /// A missing/unconfigured tab does not prevent local-only insights.
    func loadScriptObservations(sheetID: String) async throws -> [PersonalObservation] {
        let response = try await request("GET", "/\(sheetID)/values/'Megfigyelesek'!A2:F100?valueRenderOption=FORMATTED_VALUE")
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let data = object["values"] as? [[String]] else { return [] }
        return data.compactMap { fields in
            guard fields.count >= 6, !fields[0].isEmpty else { return nil }
            let code = fields[1]
            let known = ["bp.review", "bp.urgent", "activity.lower", "water.lower"]
            guard known.contains(code) else { return nil }
            let date = ISO.formatter.date(from: fields[2]) ?? Date()
            let level: PersonalObservation.Level = fields[4] == "urgent" ? .urgent :
                (fields[4] == "review" ? .review : .informational)
            let prefix = code == "bp.review" ? "profile.alert.bp.review" :
                (code == "bp.urgent" ? "profile.alert.bp.urgent" :
                (code == "activity.lower" ? "profile.alert.steps" : "profile.alert.water"))
            return PersonalObservation(id: "script.\(fields[0])", titleKey: prefix + ".title",
                messageKey: prefix + ".body", measurement: fields[3], date: date,
                level: level, sourceKey: "profile.source.sheets")
        }
    }

    /// Read the remote idempotency column in bounded blocks. It is used for
    /// uncertain uploads and first sync after local history was lost/reinstalled.
    /// Fail closed: never append when the remote state cannot be inspected.
    func remoteRowIDs(sheet: String, sheetID: String) async throws -> Set<String> {
        let safe = sheet.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sheet
        var ids = Set<String>()
        let chunkSize = 20_000
        for page in 0..<500 {
            let start = 2 + page * chunkSize
            let end = start + chunkSize - 1
            let data = try await request("GET", "/\(sheetID)/values/'\(safe)'!A\(start):A\(end)?valueRenderOption=FORMATTED_VALUE")
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let raw = object["values"] as? [[String]] ?? []
            ids.formUnion(raw.compactMap(\.first))
            if raw.count < chunkSize { return ids }
        }
        throw SyncError.config("A Google Sheets azonosítóoszlopának ellenőrzése túl nagy; feltöltés leállítva a duplikációk elkerülésére.")
    }

    /// Called only after a previous append might have succeeded without an ACK.
    func alreadyOnSheet(_ rows: [ExportRow], sheetID: String) async throws -> Set<String> {
        guard let sheet = rows.first?.sheet, !rows.isEmpty else { return [] }
        let remoteIDs = try await remoteRowIDs(sheet: sheet, sheetID: sheetID)
        return Set(rows.filter { remoteIDs.contains($0.id) ||
            // Pre-0.5.0 raw HealthKit rows used their unprefixed UUID in column A.
            ($0.id.hasPrefix("hk:") && remoteIDs.contains($0.values.first ?? ""))
        }.map(\.id))
    }

    func append(_ rows: [ExportRow], sheetID: String) async throws {
        guard let sheet = rows.first?.sheet, !rows.isEmpty else { return }
        let safe = sheet.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sheet
        // Column A is the idempotency key. The network must NEVER blindly retry
        // a non-idempotent Sheets append. Crash recovery reads column A instead.
        let values = rows.map { row -> [String] in
            var fields = row.values
            if !fields.isEmpty { fields[0] = row.id }
            return fields
        }
        _ = try await request("POST", "/\(sheetID)/values/'\(safe)'!A1:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS",
                              body: ["majorDimension": "ROWS", "values": values], allowRetry: false)
    }
}
