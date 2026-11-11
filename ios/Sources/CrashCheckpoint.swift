import Foundation

/// Bounded local diagnostic ring: no sensor values, Google tokens, or email addresses.
/// The user can voluntarily copy diagnostics from Settings for technical support.
enum CrashCheckpoint {
    static let key = "diagnostic.lastStep"
    static let historyKey = "diagnostic.recentSteps.v2"
    static func mark(_ message: String) {
        let scrubbed = message
            .replacingOccurrences(of: #"[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
                                  with: "[email]", options: .regularExpression)
            .replacingOccurrences(of: #"ya29\.[A-Za-z0-9._\-]+"#,
                                  with: "[token]", options: .regularExpression)
            .prefix(500)
        let event = "\(Date().formatted(date: .numeric, time: .standard)): \(scrubbed)"
        UserDefaults.standard.set(event, forKey: key)
        var events = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        events.append(event)
        UserDefaults.standard.set(Array(events.suffix(80)), forKey: historyKey)
    }
    static var last: String {
        UserDefaults.standard.string(forKey: key) ?? "Még nincs diagnosztikai esemény"
    }
    static var recentHistory: String {
        (UserDefaults.standard.stringArray(forKey: historyKey) ?? []).joined(separator: "\n")
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
