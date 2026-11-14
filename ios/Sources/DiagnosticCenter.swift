import Foundation
import OSLog

// Only allowlisted operational metadata goes to logs. Never pass arbitrary errors,
// HealthKit values, emails, tokens, identifiers, GPS coordinates or request bodies.
enum DiagnosticArea: String, Codable, CaseIterable {
    case app, healthkit, queue, sync, sheets, watch, gps, storekit, referral, auth, backend, privacy
}
enum DiagnosticSeverity: String, Codable { case info, warning, failure }
enum DiagnosticCode: String, Codable {
    case startup, bootstrapOK, bootstrapFailed
    case healthPermissionBegin, healthPermissionFinished, healthPermissionFailed
    case healthImportBegin, healthImportFinished, healthImportFailed
    case syncBegin, syncFinished, syncFailed, syncSkipped
    case sheetsRequestBegin, sheetsRequestFinished, sheetsRequestFailed
    case queueRecovery, queueFailure
    case watchActivation, watchTransfer, watchTransferFailed
    case runStarted, runPaused, runFinished, runRecoveryFailed
    case storeProductsBegin, storeProductsReady, storeProductsFailed
    case purchaseBegin, purchaseVerified, purchaseUnverified, purchasePending, purchaseCancelled, purchaseFailed
    case entitlementRefresh, restoreFailed
    case referralLogin, referralClaimAttempt, referralClaimPending, referralClaimFailed
    case referralOfferUnavailable, referralConfigured
    case backgroundTaskStart, backgroundTaskEnd, backgroundTaskFailed
    case supportExport, logErase
}
struct DiagnosticRecord: Codable {
    let timestamp: Date
    let session: String
    let area: DiagnosticArea
    let code: DiagnosticCode
    let severity: DiagnosticSeverity
    let durationMS: Int?
    let count: Int?
}

enum DiagnosticCenter {
    private static let logger = Logger(subsystem: "hu.oranaplo.ios", category: "safe-diagnostics")
    private static let mutex = NSLock()
    private static let session = String(UUID().uuidString.prefix(8)) // ephemeral per launch
    private static let maxRecords = 750
    private static var records: [DiagnosticRecord] = []
    private static var initialized = false
    private static var storage: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("safe_diagnostics_v2.json")
    }
    private static func initializeLocked() {
        guard !initialized else { return }
        initialized = true
        guard let path = storage, let data = try? Data(contentsOf: path),
              let old = try? JSONDecoder().decode([DiagnosticRecord].self, from: data) else { return }
        records = Array(old.suffix(maxRecords))
    }
    private static func persistLocked() {
        guard let path = storage, let data = try? JSONEncoder().encode(records) else { return }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        } catch {
            // No recursive logging and no private error text in unified logs.
            logger.warning("diagnostics.persistence_failure")
        }
    }
    static func record(_ code: DiagnosticCode, area: DiagnosticArea,
                       severity: DiagnosticSeverity = .info,
                       durationMS: Int? = nil, count: Int? = nil) {
        mutex.lock()
        initializeLocked()
        let event = DiagnosticRecord(timestamp: Date(), session: session, area: area,
                                     code: code, severity: severity,
                                     durationMS: durationMS.map { min(3_600_000, max(0, $0)) },
                                     count: count.map { min(100_000, max(0, $0)) })
        records.append(event)
        if records.count > maxRecords { records.removeFirst(records.count - maxRecords) }
        persistLocked()
        mutex.unlock()
        logger.log(level: severity == .failure ? .error : (severity == .warning ? .notice : .info),
                   "area=\(area.rawValue, privacy: .public) code=\(code.rawValue, privacy: .public)")
    }
    static func exportText() -> String {
        mutex.lock()
        initializeLocked()
        let current = records
        mutex.unlock()
        let format = ISO8601DateFormatter()
        var lines = ["ÓraNapló – BIZTONSÁGOS DIAGNOSZTIKA", "Verzió: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", "Érzékeny adatok: KIZÁRVA (allowlist)", "Események: \(current.count)", ""]
        lines += current.map { event in
            let d = event.durationMS.map { " time_ms=\($0)" } ?? ""
            let n = event.count.map { " count=\($0)" } ?? ""
            return "\(format.string(from: event.timestamp)) session=\(event.session) \(event.severity.rawValue) \(event.area.rawValue).\(event.code.rawValue)\(d)\(n)"
        }
        return lines.joined(separator: "\n")
    }
    static func erase() {
        mutex.lock()
        records.removeAll()
        initialized = true
        if let path = storage { try? FileManager.default.removeItem(at: path) }
        mutex.unlock()
        logger.info("diagnostics.erased")
    }
}
