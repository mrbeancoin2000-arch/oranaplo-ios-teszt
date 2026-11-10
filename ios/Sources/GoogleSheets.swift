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
            email = user.profile?.email ?? "Google-fiók"
        } catch { loggedIn = false; email = "" }
    }
    func signIn() async throws {
        guard !AppConfig.googleClientID.hasPrefix("ADD_") else {
            throw SyncError.config("Hiányzik a Google iOS OAuth Client ID. Lásd: GOOGLE_BEALLITAS.md")
        }
        guard let controller = UIViewController.topMost else { throw SyncError.config("Nem található bejelentkezési ablak") }
        var user = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller).user
        if user.grantedScopes?.contains(Self.scope) != true {
            user = try await user.addScopes([Self.scope], presenting: controller).user
        }
        loggedIn = true
        email = user.profile?.email ?? "Google-fiók"
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
    private func request(_ method: String, _ path: String, body: Any? = nil) async throws -> Data {
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
                if [429,500,502,503,504].contains(status) && attempt < 3 {
                    try await Task.sleep(for: .seconds(Double(1 << attempt))); continue
                }
                throw SyncError.api(status, String(data: data, encoding: .utf8) ?? "ismeretlen hiba")
            } catch {
                if attempt < 3 && !(error is SyncError) {
                    try await Task.sleep(for: .seconds(Double(1 << attempt))); continue
                }
                throw error
            }
        }
        throw SyncError.config("Sikertelen adatküldés")
    }
    func createSpreadsheet() async throws -> String {
        let sheets: [[String: Any]] = Catalog.sheets.map { ["properties": ["title": $0, "gridProperties": ["frozenRowCount": 1]]] }
        let data = try await request("POST", "", body: ["properties": ["title": "ÓraNapló – Egészségadatok"], "sheets": sheets])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String:Any], let id = obj["spreadsheetId"] as? String else { throw SyncError.config("Nem érkezett táblázatazonosító") }
        let ranges: [[String:Any]] = Catalog.sheets.map { sheet in
            let header = sheet == "100m" ? Catalog.segmentHeader : (sheet == "Edzesek" ? Catalog.workoutHeader : Catalog.rawHeader)
            return ["range": "'\(sheet)'!A1", "values": [header]]
        }
        _ = try await request("POST", "/\(id)/values:batchUpdate", body: ["valueInputOption":"RAW", "data":ranges])
        return id
    }
    func append(_ rows: [ExportRow], sheetID: String) async throws {
        guard let sheet = rows.first?.sheet, !rows.isEmpty else { return }
        let safe = sheet.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sheet
        _ = try await request("POST", "/\(sheetID)/values/'\(safe)'!A1:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS", body: ["majorDimension":"ROWS", "values":rows.map(\.values)])
    }
}
