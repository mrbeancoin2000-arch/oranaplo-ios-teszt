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
    @Published private(set) var watchBatteryPercent: Int?
    @Published private(set) var watchCharging = false
    @Published private(set) var watchMeters: Double?
    @Published private(set) var watchElapsed: Double?
    @Published private(set) var lastWatchUpdate: Date?
    @Published private(set) var lastCompletedWatchWorkout: Date?
    @Published private(set) var lastCompletedWatchWorkoutID = ""
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
        case "watchStatus":
            if let percent=values["battery"] as? Int,(0...100).contains(percent) { watchBatteryPercent=percent }
            if let charging=values["charging"] as? Bool { watchCharging=charging }
            lastWatchUpdate=Date()
        case "water":
            guard let identifier=values["id"] as? String,let uuid=UUID(uuidString:identifier),
                  let ml=values["milliliters"] as? Int, [200,300].contains(ml),
                  let timestamp=values["at"] as? Double, timestamp.isFinite,
                  abs(Date().timeIntervalSince1970-timestamp) < 365*86400 else { return }
            // Persist first; a failed write must not become a false acknowledgement.
            do {
                try WellnessDiary.shared.addWater(ml,source:"Apple Watch",at:Date(timeIntervalSince1970:timestamp),id:uuid)
                // Acknowledgement comes AFTER atomic disk write. The watch retries
                // until this durable acknowledgement is received.
                if let session,session.activationState == .activated {
                    session.transferUserInfo(["kind":"waterAck","id":identifier])
                }
            } catch { lastWatchMessage = "watch.status.sendFailed" }

        case "metrics":
            if let bpm = values["bpm"] as? Double, (25...250).contains(bpm) { watchBPM = bpm }
            if let meters = values["meters"] as? Double, meters >= 0 { watchMeters = meters }
            if let elapsed = values["elapsed"] as? Double, elapsed >= 0 { watchElapsed = elapsed }
            lastWatchUpdate = Date()
            lastWatchMessage = "watch.status.connected"
        case "completed":
            // transferUserInfo may be redelivered. Persist the receipt ID before
            // applying the summary; replay must not create multiple workout rows.
            guard let id = values["id"] as? String, UUID(uuidString: id) != nil,
                  let meters = values["meters"] as? Double, meters.isFinite, (0...1_000_000).contains(meters),
                  let elapsed = values["elapsed"] as? Double, elapsed.isFinite, (0...604_800).contains(elapsed) else { return }
            let key = "oranaplo.watch.received.completed.v1"
            var received = UserDefaults.standard.stringArray(forKey: key) ?? []
            guard !received.contains(id) else { return }
            received.append(id)
            UserDefaults.standard.set(Array(received.suffix(5000)), forKey: key)
            watchMeters = meters
            watchElapsed = elapsed
            if let bpm = values["bpm"] as? Double, (25...250).contains(bpm) { watchBPM = bpm }
            lastCompletedWatchWorkoutID = id
            lastCompletedWatchWorkout = Date(timeIntervalSince1970: (values["ended"] as? Double) ?? Date().timeIntervalSince1970)
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
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String:Any]) {
        Task { @MainActor in self.receive(userInfo) }
    }
}
