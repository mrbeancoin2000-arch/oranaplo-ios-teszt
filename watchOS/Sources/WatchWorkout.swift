import SwiftUI
import HealthKit
import WatchConnectivity
import WatchKit

@MainActor
final class WatchWorkout: NSObject, ObservableObject {
    enum Phase: String { case ready, running, paused, finishing, finished }
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var bpm: Double?
    @Published private(set) var meters: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var info = ""
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var batteryCharging = false
    @Published private(set) var lastWaterML = 0
    private let health = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var beganAt: Date?
    private var pausedAt: Date?
    private var pausedSeconds: TimeInterval = 0
    private var clock: Timer?
    private var connect: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var workoutID = UUID().uuidString
    private static let pendingKey = "oranaplo.watch.pending.completed.v1"
    private var lastBeat: Double?
    private var lastBatteryTransfer = Date.distantPast
    override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        refreshBattery()
        connect?.delegate = self
        connect?.activate()
    }
    func refreshBattery() {
        let device=WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level=device.batteryLevel
        batteryPercent=level >= 0 ? Int(level*100) : nil
        batteryCharging=device.batteryState == .charging || device.batteryState == .full
        let payload:[String:Any]=["kind":"watchStatus","battery":batteryPercent ?? -1,
                                   "charging":batteryCharging,"at":Date().timeIntervalSince1970]
        if let connect,connect.isReachable {
            connect.sendMessage(payload,replyHandler:nil,errorHandler:nil)
        } else if Date().timeIntervalSince(lastBatteryTransfer) >= 3600,
                  let connect,connect.activationState == .activated {
            // Hourly durable status, not a transfer for every one-second clock tick.
            connect.transferUserInfo(payload)
            lastBatteryTransfer=Date()
        }
    }
    // Data is saved locally on the watch before the durable WatchConnectivity transfer.
    func logWater(_ milliliters:Int) {
        guard milliliters == 200 || milliliters == 300 else { return }
        let payload:[String:Any]=["kind":"water","id":UUID().uuidString,
                                   "milliliters":milliliters,"at":Date().timeIntervalSince1970]
        let key="oranaplo.watch.pending.water.v1"
        var buffer=UserDefaults.standard.array(forKey:key) as? [[String:Any]] ?? []
        buffer.append(payload)
        UserDefaults.standard.set(buffer,forKey:key)
        lastWaterML=milliliters
        flushCompletedWorkouts()
    }
    func start() {
        guard phase == .ready || phase == .finished else { return }
        Task {
            guard HKHealthStore.isHealthDataAvailable() else { info = "Apple Health not available"; return }
            let hr = HKQuantityType(.heartRate)
            let distance = HKQuantityType(.distanceWalkingRunning)
            do {
                try await health.requestAuthorization(toShare:[HKObjectType.workoutType()],read:[hr,distance])
                let config = HKWorkoutConfiguration()
                config.activityType = .running
                config.locationType = .outdoor
                let session = try HKWorkoutSession(healthStore:health,configuration:config)
                let live = session.associatedWorkoutBuilder()
                live.dataSource = HKLiveWorkoutDataSource(healthStore:health,workoutConfiguration:config)
                session.delegate = self
                live.delegate = self
                workout = session; builder = live
                workoutID=UUID().uuidString
                meters=0; bpm=nil; elapsed=0; pausedSeconds=0; lastBeat=nil
                beganAt=Date();pausedAt=nil
                session.startActivity(with:beganAt!)
                try await live.beginCollection(at:beganAt!)
                phase = .running
                sendControl("start")
                startClock()
            } catch { info = error.localizedDescription }
        }
    }
    func pause() {
        guard phase == .running else { return }
        workout?.pause()
        pausedAt = Date()
        phase = .paused
        sendControl("pause")
        sendMetrics()
    }
    func resume() {
        guard phase == .paused else { return }
        if let pausedAt { pausedSeconds += Date().timeIntervalSince(pausedAt) }
        self.pausedAt = nil
        workout?.resume()
        phase = .running
        sendControl("resume")
    }
    func finish() {
        guard phase == .running || phase == .paused else { return }
        if phase == .paused, let pausedAt { pausedSeconds += Date().timeIntervalSince(pausedAt) }
        if let beganAt { elapsed = max(0, Date().timeIntervalSince(beganAt) - pausedSeconds) }
        clock?.invalidate();clock=nil
        phase = .finishing
        sendControl("stop")
        workout?.end()
        Task {
            do {
                try await builder?.endCollection(at:Date())
                _ = try await builder?.finishWorkout()
                sendCompletedWorkout()
                phase = .finished
            } catch { info = error.localizedDescription; phase = .finished }
        }
    }
    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let beganAt = self.beganAt, self.phase == .running else { return }
                self.elapsed = max(0,Date().timeIntervalSince(beganAt)-self.pausedSeconds)
                self.refreshBattery()
                self.sendMetrics()
            }
        }
    }
    // Real-time sendMessage is best effort and stops when the phone is unreachable.
    // Final summaries also use a durable transfer; never send raw health/GPS traces.
    private func sendCompletedWorkout() {
        let payload: [String: Any] = ["kind": "completed", "id": workoutID,
            "started": (beganAt ?? Date()).timeIntervalSince1970,
            "ended": Date().timeIntervalSince1970,
            "meters": meters, "elapsed": max(0, elapsed),
            "bpm": lastBeat ?? 0]
        var buffer = UserDefaults.standard.array(forKey: Self.pendingKey) as? [[String:Any]] ?? []
        buffer.append(payload)
        UserDefaults.standard.set(buffer, forKey: Self.pendingKey)
        flushCompletedWorkouts()
    }
    private func flushCompletedWorkouts() {
        guard let connect, connect.activationState == .activated else { return }
        let buffer = UserDefaults.standard.array(forKey: Self.pendingKey) as? [[String:Any]] ?? []
        for payload in buffer { connect.transferUserInfo(payload) }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        let key="oranaplo.watch.pending.water.v1"
        let water=UserDefaults.standard.array(forKey:key) as? [[String:Any]] ?? []
        // Keep locally until the iPhone confirms durable storage. Resends use UUID IDs.
        for payload in water { connect.transferUserInfo(payload) }
    }
    private func sendControl(_ action:String) {
        guard let connect, connect.isReachable else { return }
        connect.sendMessage(["kind":"control","action":action],replyHandler:nil,errorHandler:nil)
    }
    private func sendMetrics() {
        guard let connect, connect.isReachable else { return }
        var values: [String:Any] = ["kind":"metrics","meters":meters,"elapsed":elapsed]
        if let bpm { values["bpm"] = bpm }
        connect.sendMessage(values,replyHandler:nil,errorHandler:nil)
    }
    private func apply(_ values:[String:Any]) {
        if values["kind"] as? String == "waterAck",let id=values["id"] as? String {
            let key="oranaplo.watch.pending.water.v1"
            var pending=UserDefaults.standard.array(forKey:key) as? [[String:Any]] ?? []
            pending.removeAll { ($0["id"] as? String) == id }
            UserDefaults.standard.set(pending,forKey:key)
            return
        }
        guard values["kind"] as? String == "control", let action=values["action"] as? String else { return }
        switch action {
        case "start": start()
        case "pause": pause()
        case "resume": resume()
        case "stop": finish()
        default: break
        }
    }
}
extension WatchWorkout: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) { }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.info = error.localizedDescription }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes:Set<HKSampleType>) {
        Task { @MainActor in
            let heart = HKQuantityType(.heartRate)
            if collectedTypes.contains(heart),
               let q = workoutBuilder.statistics(for:heart)?.mostRecentQuantity() {
                self.bpm=q.doubleValue(for:HKUnit.count().unitDivided(by:.minute()))
                self.lastBeat = self.bpm
            }
            let distance = HKQuantityType(.distanceWalkingRunning)
            if collectedTypes.contains(distance),
               let q = workoutBuilder.statistics(for:distance)?.sumQuantity() {
                self.meters=max(0,q.doubleValue(for:.meter()))
            }
            self.sendMetrics()
        }
    }
}
extension WatchWorkout: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.flushCompletedWorkouts() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.flushCompletedWorkouts() }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo:[String:Any]) {
        Task { @MainActor in self.apply(userInfo) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message:[String:Any]) {
        Task { @MainActor in self.apply(message) }
    }
}
