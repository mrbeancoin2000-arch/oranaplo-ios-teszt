import Foundation
import WatchConnectivity
import Combine

/// Local, paired-device link; health values are not sent to our servers.
/// Reachability is NOT guaranteed when the iPhone is locked or far from the watch.
@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()
    @Published private(set) var reachable = false
    @Published private(set) var watchBPM: Double?
    @Published private(set) var watchMeters: Double?
    @Published private(set) var watchElapsed: Double?
    @Published private(set) var lastWatchUpdate: Date?
    @Published private(set) var lastWatchMessage = "watch.status.disconnected"
    private var session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }
    func command(_ action: String) {
        guard ["start", "pause", "resume", "stop"].contains(action) else { return }
        guard let session, session.isReachable else {
            lastWatchMessage = "watch.status.disconnected"
            return
        }
        session.sendMessage(["kind":"control","action":action], replyHandler:nil) { [weak self] _ in
            Task { @MainActor in self?.lastWatchMessage = "watch.status.sendFailed" }
        }
    }
    private func receive(_ values: [String:Any]) {
        switch values["kind"] as? String {
        case "metrics":
            if let bpm = values["bpm"] as? Double, (25...250).contains(bpm) { watchBPM = bpm }
            if let meters = values["meters"] as? Double, meters >= 0 { watchMeters = meters }
            if let elapsed = values["elapsed"] as? Double, elapsed >= 0 { watchElapsed = elapsed }
            lastWatchUpdate = Date()
            lastWatchMessage = "watch.status.connected"
        case "control":
            guard let action = values["action"] as? String else { return }
            // Never make an unobservable/background workout promise: phone GPS can
            // only be started when permissions and iOS execution permit delivery.
            switch action {
            case "start":
                if RunTracker.shared.phase == .ready || RunTracker.shared.phase == .finished {
                    RunTracker.shared.requestPermissionAndStart(kilograms:SyncEngine.shared.profile?.weightKG,
                        centimeters:SyncEngine.shared.profile?.heightCM)
                }
            case "pause": RunTracker.shared.pause()
            case "resume": RunTracker.shared.resume()
            case "stop": RunTracker.shared.finish()
            default: break
            }
        default: break
        }
    }
}
extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.reachable = session.isReachable }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.isReachable }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String:Any]) {
        Task { @MainActor in self.receive(message) }
    }
}
