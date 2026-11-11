import Foundation

/// An intentionally tiny, whitelisted event trail. No timestamps, identifiers,
/// coordinates, measurements, free-text logs, network responses, or OAuth data.
/// Only these enumerated codes are eligible for email support reports.
enum SafeDiagnosticEvent: String, CaseIterable {
    case syncStarted = "sync.started"
    case syncFinished = "sync.finished"
    case syncFailed = "sync.failed"
    case sheetStarted = "sheet.started"
    case sheetFinished = "sheet.finished"
    case sheetFailed = "sheet.failed"
    case runStarted = "run.started"
    case runPaused = "run.paused"
    case runResumed = "run.resumed"
    case runFinished = "run.finished"
    case runInterrupted = "run.interrupted"
    case runStorageDamaged = "run.storage_damaged"
    case runErased = "run.erased"
    case rankDeleted = "ranking.deleted"
    case reportFailed = "report.failed"
}

enum SafeDiagnosticTrail {
    private static let key = "oranaplo.safeDiagnostic.v1"
    static func mark(_ event: SafeDiagnosticEvent) {
        var list = UserDefaults.standard.stringArray(forKey:key) ?? []
        list.append(event.rawValue)
        UserDefaults.standard.set(Array(list.suffix(30)),forKey:key)
    }
    static func lastCodes() -> [String] {
        (UserDefaults.standard.stringArray(forKey:key) ?? [])
            .compactMap { SafeDiagnosticEvent(rawValue:$0)?.rawValue }
            .suffix(12).map { $0 }
    }
    static func erase() { UserDefaults.standard.removeObject(forKey:key) }
}
