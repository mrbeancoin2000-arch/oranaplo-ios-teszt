import Foundation
import OSLog
// watchOS unified log; no HealthKit samples or user-identifying fields.
enum WatchDiagnostic {
    private static let log = Logger(subsystem: "hu.oranaplo.ios.watchkitapp", category: "safe-diagnostics")
    static func event(_ code: Code) {
        log.info("watch.event=\(code.rawValue, privacy: .public)")
    }
    enum Code: String { case launch, workoutStarted, workoutStopped, connectionActivated, transferAttempt, transferFailed }
}
