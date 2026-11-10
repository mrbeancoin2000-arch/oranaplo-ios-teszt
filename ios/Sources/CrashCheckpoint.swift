import Foundation

/// Only stores the most recent diagnostic step, never health data, tokens or passwords.
enum CrashCheckpoint {
    static let key = "diagnostic.lastStep"
    static func mark(_ message: String) {
        UserDefaults.standard.set("\(Date().formatted(date: .numeric, time: .standard)): \(message)", forKey: key)
        UserDefaults.standard.synchronize()
    }
    static var last: String {
        UserDefaults.standard.string(forKey: key) ?? "Még nincs diagnosztikai esemény"
    }
}


extension CrashCheckpoint {
    static var environmentSummary: String {
        let bundle = Bundle.main
        let share = !(bundle.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String ?? "").isEmpty
        let update = !(bundle.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") as? String ?? "").isEmpty
        let urls = (bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return "App ID: \(bundle.bundleIdentifier ?? "nincs")\nHealthKit Info.plist: olvasás=\(share), írás=\(update)\nGoogle URL-sémák: \(urls.joined(separator: ", "))\nA tényleges HealthKit aláírási jogosultság itt nem igazolható."
    }
}
