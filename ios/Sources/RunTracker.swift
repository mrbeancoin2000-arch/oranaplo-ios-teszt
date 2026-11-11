import Foundation
import CoreLocation
import CoreMotion
import HealthKit
import MapKit
import Combine

/// On-device outdoor run recorder. Heart rate is enriched from *real* HealthKit samples
/// after the run; an iPhone has no built-in heart-rate sensor.
@MainActor
final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = RunTracker()
    enum Phase: String { case ready, recording, paused, finished }
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var current: RecordedRun?
    @Published private(set) var history: [RecordedRun] = []
    @Published private(set) var message = ""
    @Published private(set) var authorization = CLAuthorizationStatus.notDetermined
    @Published private(set) var elapsedNow: Double = 0
    @Published private(set) var latestSpeedKmh: Double?
    @Published private(set) var heartLoading = false

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var tick: Timer?
    private var activeStart: Date?
    private var accumulated: Double = 0
    private var lastFix: CLLocation?
    private var awaitingFixAfterPause = true
    private var stepBase: Int = 0
    private var stepSegmentStart: Date?
    private var lastCheckpoint = Date.distantPast
    private var pendingStart = false
    private var pendingMapPreview = false
    private var lastPowerConfiguration = Date.distantPast
    @Published private(set) var storageDamaged = false
    @Published private(set) var recentlyBrokenRecords: [RunPersonalRecord] = []
    @Published private(set) var archivedRecords: [RunPersonalRecord] = []
    private var longTermRuns: [UUID:RunHistoryEntry] = [:]

    private let file: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OraNaplo/RunTracker",isDirectory: true)
        try? FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        return folder.appendingPathComponent("runs.json")
    }()

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 4
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        load()
    }
    var meters: Double { current?.gpsMeters ?? 0 }
    var steps: Int? { current?.steps }
    var kcal: Double? { RunMath.estimatedRunningKcal(meters: meters, kilograms: current?.kilograms) }
    var averageKmh: Double? { RunMath.speed(seconds: elapsedNow, meters: meters) }
    var pace: Double? { RunMath.pace(seconds: elapsedNow, meters: meters) }
    var splits: [RunHundredMeters] { current?.splits ?? [] }
    var routeCoordinates: [CLLocationCoordinate2D] {
        (current?.route ?? []).map { CLLocationCoordinate2D(latitude: $0.latitude,longitude: $0.longitude) }
    }
    var routeSegments: [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        var segment: [CLLocationCoordinate2D] = []
        for point in current?.route ?? [] {
            if point.breakBefore && !segment.isEmpty {
                result.append(segment)
                segment = []
            }
            segment.append(CLLocationCoordinate2D(latitude:point.latitude,longitude:point.longitude))
        }
        if !segment.isEmpty { result.append(segment) }
        return result
    }
    var lastCompleted: RecordedRun? { history.first(where: { $0.completed }) }
    var longestCompletedRunMeters: Double { longTermRuns.values.map(\.gpsMeters).max() ?? 0 }
    var personalRecords: [RunPersonalRecord] { archivedRecords.sorted { $0.distanceMeters < $1.distanceMeters } }
    var weeklySummary: RunGoalSummary {
        let stored = UserDefaults.standard.double(forKey:"oranaplo.run.weeklyGoalKM")
        return RunInsights.historicalGoals(Array(longTermRuns.values),weeklyGoalKM:stored > 0 ? stored : 15)
    }
    func weeklyGoalChanged() { objectWillChange.send() }

    private func load() {
        let backup = file.deletingLastPathComponent().appendingPathComponent("runs.backup.json")
        let primaryExists = FileManager.default.fileExists(atPath: file.path)
        let backupExists = FileManager.default.fileExists(atPath: backup.path)
        let primary = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([RecordedRun].self, from: $0) }
        let recovered = primary ?? (try? Data(contentsOf: backup)).flatMap { try? JSONDecoder().decode([RecordedRun].self, from: $0) }
        // A damaged local database must NEVER be silently overwritten by an empty list.
        if (primaryExists || backupExists) && recovered == nil {
            storageDamaged = true
            message = "run.status.storageDamaged"
            CrashCheckpoint.mark("run.storage.damaged")
            SafeDiagnosticTrail.mark(.runStorageDamaged)
            return
        }
        let runs = recovered ?? []
        if primary == nil && recovered != nil { message = "run.status.backupRestored" }
        history = runs.filter { $0.completed }.sorted { $0.started > $1.started }
        let archiveFile=file.deletingLastPathComponent().appendingPathComponent("record-archive.json")
        if let recordData=try? Data(contentsOf:archiveFile),
           let archived=try? JSONDecoder().decode([RunPersonalRecord].self,from:recordData) {
            archivedRecords=archived
        }
        let summaryFile=file.deletingLastPathComponent().appendingPathComponent("run-summary.json")
        if let summaryData=try? Data(contentsOf:summaryFile),
           let entries=try? JSONDecoder().decode([RunHistoryEntry].self,from:summaryData) {
            longTermRuns=Dictionary(uniqueKeysWithValues:entries.map { ($0.id,$0) })
        }
        for run in history {
            if longTermRuns[run.id] == nil {
                longTermRuns[run.id]=RunHistoryEntry(id:run.id,started:run.started,gpsMeters:run.gpsMeters)
            }
        }
        for record in RunInsights.records(history) {
            if let old=archivedRecords.firstIndex(where:{$0.distanceMeters==record.distanceMeters}) {
                if record.seconds < archivedRecords[old].seconds { archivedRecords[old]=record }
            } else { archivedRecords.append(record) }
        }
        if let unfinished = runs.first(where: { !$0.completed }) {
            var snapshot = unfinished
            // Never silently resume GPS recording after a crash or OS termination.
            snapshot.interrupted = true
            if let index = snapshot.activeWindows.indices.last, snapshot.activeWindows[index].ended == nil {
                snapshot.activeWindows[index].ended = snapshot.route.last?.date ?? snapshot.activeWindows[index].started
            }
            snapshot.activeSeconds = max(snapshot.activeSeconds, snapshot.route.last?.activeSeconds ?? 0)
            current = snapshot
            accumulated = snapshot.activeSeconds
            elapsedNow = accumulated
            phase = .paused
            awaitingFixAfterPause = true
            message = "run.status.restored"
            SafeDiagnosticTrail.mark(.runInterrupted)
        }
    }
    private func persist() {
        guard !storageDamaged else { return }
        guard let data = try? JSONEncoder().encode((current?.completed == false ? [current!] : []) + Array(history.prefix(25))) else {
            message = "run.status.saveError"; return
        }
        do {
            // Background GPS checkpoints must remain writable after the device is locked,
            // but files stay protected until the first unlock after reboot.
            let backup = file.deletingLastPathComponent().appendingPathComponent("runs.backup.json")
            // Two atomic copies: if the phone is killed during a checkpoint, the
            // previous good copy can recover the run without overwriting data.
            try data.write(to:backup,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            let routeFree=Array(longTermRuns.values)
            let summaryFile=file.deletingLastPathComponent().appendingPathComponent("run-summary.json")
            try JSONEncoder().encode(routeFree).write(to:summaryFile,
                options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            let archiveFile=file.deletingLastPathComponent().appendingPathComponent("record-archive.json")
            try JSONEncoder().encode(archivedRecords).write(to:archiveFile,
                options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        } catch { message = "run.status.saveError" }
    }
    private func checkpoint(force: Bool = false) {
        if force || Date().timeIntervalSince(lastCheckpoint) > 5 {
            lastCheckpoint = Date(); persist()
        }
    }

    /// GPS preview is separate from starting an exercise; no route is recorded here.
    func requestMapPosition() {
        guard CLLocationManager.locationServicesEnabled() else { message="run.status.locationOff";return }
        let status=manager.authorizationStatus
        if status == .notDetermined { pendingMapPreview = true; manager.requestWhenInUseAuthorization() }
        else if status == .authorizedWhenInUse || status == .authorizedAlways { manager.requestLocation() }
        else { message="run.status.permissionDenied" }
    }

    func requestPermissionAndStart(kilograms: Double?, centimeters: Double?) {
        guard phase == .ready || phase == .finished else { return }
        guard !storageDamaged else { message = "run.status.storageDamaged"; return }
        guard CLLocationManager.locationServicesEnabled() else { message = "run.status.locationOff"; return }
        requestedWeight = kilograms
        requestedHeight = centimeters
        let status = manager.authorizationStatus
        authorization = status
        if status == .notDetermined {
            pendingStart = true
            // Health data / Google account is NOT needed to start a local GPS run.
            manager.requestWhenInUseAuthorization()
            return
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            message = "run.status.permissionDenied"; return
        }
        start(kilograms: kilograms, centimeters: centimeters)
    }
    private var requestedWeight: Double?
    private var requestedHeight: Double?
    func configureProfile(kilograms: Double?, centimeters: Double?) {
        requestedWeight = kilograms
        requestedHeight = centimeters
    }
    private func start(kilograms: Double?, centimeters: Double?) {
        let now = Date()
        let kg = kilograms ?? requestedWeight
        let cm = centimeters ?? requestedHeight
        current = RecordedRun(id: UUID(),started: now,ended: nil,activeSeconds: 0,gpsMeters: 0,steps: nil,
            estimatedKcal: nil,kilograms: kg,centimeters: cm,route: [],heart: [],stepHistory: CMPedometer.isStepCountingAvailable() ? [RunStepPoint(activeSeconds:0,totalSteps:0)] : [],
            activeWindows: [RunActiveWindow(started: now,ended: nil,secondsBefore: 0)],completed:false,interrupted:false)
        activeStart = now; accumulated = 0; elapsedNow = 0; stepBase = 0; stepSegmentStart = nil
        lastFix = nil; awaitingFixAfterPause = true; latestSpeedKmh = nil; message = "run.status.recording"
        phase = .recording
        SafeDiagnosticTrail.mark(.runStarted)
        configureActiveGPS() // only while an explicitly started run is active
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        startPedometer(now)
        startClock()
        checkpoint(force: true)
    }
    func pause() {
        guard phase == .recording, let activeStart else { return }
        let now = Date()
        accumulated += max(0,now.timeIntervalSince(activeStart))
        elapsedNow = accumulated
        if let index = current?.activeWindows.indices.last { current?.activeWindows[index].ended = now }
        current?.activeSeconds = accumulated
        self.activeStart = nil
        phase = .paused
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        stopPedometer(at: now)
        tick?.invalidate();tick=nil
        lastFix = nil; awaitingFixAfterPause = true
        message = "run.status.paused"
        SafeDiagnosticTrail.mark(.runPaused)
        checkpoint(force: true)
    }
    func resume() {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            message = "run.status.permissionDenied"
            return
        }
        guard phase == .paused, current?.interrupted == false else {
            // Crash recovery can be resumed explicitly too; never auto-resume.
            if phase == .paused, current != nil { current?.interrupted = false } else { return }
            return resume()
        }
        let now = Date()
        activeStart = now
        current?.activeWindows.append(RunActiveWindow(started:now,ended:nil,secondsBefore:accumulated))
        lastFix = nil; awaitingFixAfterPause = true; latestSpeedKmh = nil
        phase = .recording
        configureActiveGPS()
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        startPedometer(now)
        startClock()
        message = "run.status.recording"
        SafeDiagnosticTrail.mark(.runResumed)
        checkpoint(force: true)
    }
    func finish() {
        guard phase == .recording || phase == .paused, var run = current else { return }
        if phase == .recording { pause() ; run = current ?? run }
        let now = Date()
        run.ended = now
        run.activeSeconds = accumulated
        run.completed = true
        // Preserve a visible interruption marker on archived sessions.
        run.interrupted = run.interrupted || current?.interrupted == true
        run.estimatedKcal = RunMath.estimatedRunningKcal(meters: run.gpsMeters,kilograms: run.kilograms)
        current = run
        history.removeAll(where: { $0.id == run.id })
        // Compare with archived results too, not only the last 25 detailed routes.
        let candidates=RunInsights.records([run])
        recentlyBrokenRecords=[]
        for candidate in candidates {
            if let i=archivedRecords.firstIndex(where:{$0.distanceMeters==candidate.distanceMeters}) {
                if candidate.seconds + 0.5 < archivedRecords[i].seconds {
                    archivedRecords[i]=candidate
                    recentlyBrokenRecords.append(candidate)
                }
            } else {
                archivedRecords.append(candidate)
                recentlyBrokenRecords.append(candidate)
            }
        }
        longTermRuns[run.id]=RunHistoryEntry(id:run.id,started:run.started,gpsMeters:run.gpsMeters)
        history.insert(run,at:0)
        history = Array(history.prefix(25))
        phase = .finished
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        pedometer.stopUpdates()
        tick?.invalidate(); tick = nil
        message = "run.status.saved"
        SafeDiagnosticTrail.mark(.runFinished)
        checkpoint(force: true)
        Task { await reconcileSteps(run.id) }
        Task { await enrichHeart(run.id) }
    }
    /// A restored workout remains paused until the runner explicitly resumes or saves it.
    var hasInterruptedWorkout: Bool { phase == .paused && current?.interrupted == true }

    func discardInterruptedWorkout() {
        guard hasInterruptedWorkout else { return }
        current = nil
        accumulated = 0
        elapsedNow = 0
        activeStart = nil
        phase = .ready
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        pedometer.stopUpdates()
        tick?.invalidate(); tick = nil
        message = "run.status.discarded"
        checkpoint(force:true)
    }

    /// Removes local GPS routes, workout history, PRs and cached summaries ONLY.
    /// Apple Health workouts and the user's remote Google Sheet are unaffected.
    func eraseAllLocalRuns() throws {
        guard phase != .recording else { throw RunStorageError.activeWorkout }
        let names = ["runs.json", "runs.backup.json", "record-archive.json", "run-summary.json"]
        for name in names {
            let path = file.deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.fileExists(atPath:path.path) { try FileManager.default.removeItem(at:path) }
        }
        pedometer.stopUpdates()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        tick?.invalidate(); tick = nil
        history=[]; current=nil; archivedRecords=[]; longTermRuns=[:]; recentlyBrokenRecords=[]
        phase = .ready; accumulated=0; elapsedNow=0; activeStart=nil
        lastFix=nil; storageDamaged=false; message=""
        SafeDiagnosticTrail.mark(.runErased)
    }

    func newRun() {
        guard phase != .recording else { return }
        current = nil
        phase = .ready
        elapsedNow = 0; accumulated = 0
        message = ""
        checkpoint(force: true)
    }
    func select(_ run: RecordedRun) {
        guard phase != .recording && phase != .paused else { return }
        current = run
        elapsedNow = run.activeSeconds
        phase = .finished
    }
    func delete(_ id: UUID) {
        guard phase != .recording && phase != .paused else { return }
        history.removeAll { $0.id == id }
        longTermRuns.removeValue(forKey:id)
        if archivedRecords.contains(where:{$0.runID == id}) {
            archivedRecords.removeAll(where:{$0.runID==id})
            for candidate in RunInsights.records(history) {
                if !archivedRecords.contains(where:{$0.distanceMeters==candidate.distanceMeters}) {
                    archivedRecords.append(candidate)
                }
            }
        }
        if current?.id == id { current = nil; phase = .ready }
        checkpoint(force: true)
    }
    private func startClock() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClock() }
        }
        if let tick { RunLoop.main.add(tick,forMode: .common) }
    }
    private func updateClock() {
        guard phase == .recording,let activeStart else { return }
        elapsedNow = accumulated + max(0,Date().timeIntervalSince(activeStart))
        current?.activeSeconds = elapsedNow
        checkpoint()
    }
    private func startPedometer(_ date: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        stepSegmentStart = date
        let base = current?.steps ?? 0
        stepBase = base
        // Each active interval is queried separately; steps during a pause are excluded.
        pedometer.startUpdates(from: date) { [weak self] data, error in
            guard let self, error == nil, let data else { return }
            Task { @MainActor in
                guard self.phase == .recording, self.stepSegmentStart == date else { return }
                let count = self.stepBase + data.numberOfSteps.intValue
                self.current?.steps = max(count,self.current?.steps ?? 0)
                self.current?.stepHistory.append(RunStepPoint(activeSeconds:self.elapsedNow,totalSteps:count))
                if self.current!.stepHistory.count > 15000 { self.current!.stepHistory.removeFirst(2500) }
                self.checkpoint()
            }
        }
    }
    private func stopPedometer(at end: Date) {
        pedometer.stopUpdates()
        guard let start = stepSegmentStart else { return }
        let baseline = stepBase
        let pausedElapsed = accumulated
        stepSegmentStart = nil
        pedometer.queryPedometerData(from: start,to:end) { [weak self] data,_ in
            guard let self,let data else { return }
            Task { @MainActor in
                guard self.current?.activeWindows.contains(where: { $0.started == start }) == true else { return }
                let count = baseline + data.numberOfSteps.intValue
                // The pedometer callback can arrive after finish; keep both the current
                // snapshot and the persistent history in sync.
                let recorded = max(count,self.current?.steps ?? 0)
                self.current?.steps = recorded
                self.current?.stepHistory.append(RunStepPoint(activeSeconds:pausedElapsed,totalSteps:recorded))
                if let id=self.current?.id, let i=self.history.firstIndex(where:{$0.id == id}) {
                    self.history[i].steps = recorded
                    self.history[i].stepHistory = self.current?.stepHistory ?? []
                }
                self.checkpoint(force:true)
            }
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if self.pendingMapPreview {
                self.pendingMapPreview = false
                if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                    manager.requestLocation()
                }
            }
            if self.pendingStart {
                self.pendingStart = false
                if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                    self.start(kilograms:self.requestedWeight,centimeters:self.requestedHeight)
                } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                    self.message = "run.status.permissionDenied"
                }
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.accept(location) }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.message = "run.status.gpsUnavailable" }
    }
    /// Standard continuous GPS is active only during an explicitly started run.
    /// Avoid switching accuracy on every GPS callback (drains battery).
    private func configureActiveGPS() {
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 4
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        lastPowerConfiguration = Date()
    }
    private func adaptGPSForPower(speedMetersPerSecond: Double) {
        guard Date().timeIntervalSince(lastPowerConfiguration) > 50 else { return }
        lastPowerConfiguration = Date()
        // Running requires precise fixes; use coarser distanceFilter only for slow movement.
        if speedMetersPerSecond > 1.2 {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 4
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 8
        }
    }
    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.phase == .recording {
                self.message = "run.status.gpsPaused"
                self.manager.startUpdatingLocation()
            }
        }
    }
    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in if self.phase == .recording { self.message = "run.status.recording" } }
    }
    private func accept(_ point: CLLocation) {
        guard phase == .recording, let activeStart, point.horizontalAccuracy >= 0,
              point.horizontalAccuracy <= 30, abs(point.timestamp.timeIntervalSinceNow) < 25,
              point.coordinate.latitude.isFinite, point.coordinate.longitude.isFinite,
              point.timestamp >= activeStart else { return }
        let elapsed = accumulated + max(0,point.timestamp.timeIntervalSince(activeStart))
        guard elapsed >= 0 else { return }
        let routePoint = RunRoutePoint(date: point.timestamp,latitude:point.coordinate.latitude,
            longitude:point.coordinate.longitude,horizontalAccuracy:point.horizontalAccuracy,
            activeSeconds:elapsed,cumulativeMeters:current?.gpsMeters ?? 0,
            breakBefore:awaitingFixAfterPause)
        if let previous = lastFix {
            let delta = point.timestamp.timeIntervalSince(previous.timestamp)
            let meters = point.distance(from: previous)
            // Discard impossible speed and stale gaps; begin a new segment, no phantom kilometres.
            guard delta > 0.2, meters >= 0 else { return }
            if delta > 25 || meters/delta > 12 || meters > 180 {
                lastFix = point
                current?.route.append(RunRoutePoint(date:point.timestamp,latitude:point.coordinate.latitude,
                    longitude:point.coordinate.longitude,horizontalAccuracy:point.horizontalAccuracy,
                    activeSeconds:elapsed,cumulativeMeters:current?.gpsMeters ?? 0,breakBefore:true))
                checkpoint(); return
            }
            // Ignore sub-3m jitter to reduce stationary GPS drift.
            guard meters >= 3 else { return }
            current?.gpsMeters += meters
            latestSpeedKmh = (meters / delta) * 3.6
            adaptGPSForPower(speedMetersPerSecond:meters/delta)
            var updated = routePoint
            updated.cumulativeMeters = current?.gpsMeters ?? 0
            updated.breakBefore = false
            current?.route.append(updated)
        } else {
            current?.route.append(routePoint)
        }
        lastFix = point; awaitingFixAfterPause = false
        checkpoint()
    }
    /// Post-run pulse enrichment is best effort: only samples actually stored in HealthKit
    /// and permitted by the user are included, filtered to active running windows.
    func enrichHeart(_ id: UUID) async {
        guard !heartLoading,let run = history.first(where: { $0.id == id }),let end = run.ended else { return }
        // Avoid invoking HealthKit when the user has never authorized pulse access;
        // missing sideload entitlements cannot be repaired by a local query.
        guard UserDefaults.standard.bool(forKey:"healthBasicCompleted") else {
            message = "run.status.noHeart"; return
        }
        heartLoading = true
        defer { heartLoading = false }
        guard let samples = try? await HealthReader.shared.heartSamples(from: run.started,to:end) else {
            message = "run.status.noHeart"; return
        }
        let accepted = samples.compactMap { sample -> RunPulsePoint? in
            guard let sec = RunMath.activeTime(of:sample.0,windows:run.activeWindows) else { return nil }
            return RunPulsePoint(date:sample.0,activeSeconds:sec,bpm:sample.1)
        }
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].heart = accepted
            if current?.id == id { current?.heart = accepted }
            checkpoint(force:true)
            message = accepted.isEmpty ? "run.status.noHeart" : "run.status.heartLoaded"
        }
    }
    /// Reconcile *actual* steps of each active window after finish. Live pedometer
    /// updates are best-effort and may arrive late after pause.
    func reconcileSteps(_ id: UUID) async {
        guard CMPedometer.isStepCountingAvailable(), let run = history.first(where: { $0.id == id }) else { return }
        var total = 0
        var windowsRead = 0
        var checkpoints = [RunStepPoint(activeSeconds:0,totalSteps:0)]
        for window in run.activeWindows {
            guard let end = window.ended, end > window.started else { continue }
            let count: Int? = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: window.started, to: end) { data,_ in
                    continuation.resume(returning:data?.numberOfSteps.intValue)
                }
            }
            if let count {
                total += max(0,count)
                windowsRead += 1
                checkpoints.append(RunStepPoint(activeSeconds:window.secondsBefore+end.timeIntervalSince(window.started),totalSteps:total))
            }
        }
        guard windowsRead == run.activeWindows.filter({$0.ended != nil}).count, windowsRead > 0 else { return }
        if let index = history.firstIndex(where:{$0.id == id}) {
            history[index].steps = total
            // Accurate per-window totals + original live samples for within-window
            // interpolation. Recorded step time stamps can still be approximate.
            history[index].stepHistory = checkpoints
            if current?.id == id {
                current?.steps = total
                current?.stepHistory = checkpoints
            }
            checkpoint(force:true)
        }
    }

    /// Shareable GPX file is generated locally; no route is sent to any server.
    func gpxURL(for run: RecordedRun) -> URL? {
        guard !run.route.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        var sections: [[RunRoutePoint]] = []
        var section: [RunRoutePoint] = []
        for point in run.route {
            if point.breakBefore && !section.isEmpty { sections.append(section); section=[] }
            section.append(point)
        }
        if !section.isEmpty { sections.append(section) }
        let track = sections.map { oneSection in
            let pts = oneSection.map { p in
                "<trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\"><time>\(formatter.string(from:p.date))</time></trkpt>"
            }.joined(separator:"\n")
            return "<trkseg>\n\(pts)\n</trkseg>"
        }.joined(separator:"\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="OraNaplo" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>OraNaplo run</name>
        \(track)
        </trk></gpx>
        """
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("OraNaplo_\(run.id.uuidString).gpx")
        try? xml.write(to:dest,atomically:true,encoding:.utf8)
        return FileManager.default.fileExists(atPath:dest.path) ? dest : nil
    }
}


enum RunStorageError: LocalizedError {
    case activeWorkout
    var errorDescription: String? { "Az aktív edzést előbb szüneteltesd és fejezd be." }
}
