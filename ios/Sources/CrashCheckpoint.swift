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
