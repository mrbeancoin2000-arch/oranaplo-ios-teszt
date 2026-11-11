import SwiftUI
import MapKit
import CoreLocation

/// Native iPhone workout screen. Runs without a Google account; HealthKit pulse is optional.
struct RunTrackerView: View {
    @ObservedObject private var tracker = RunTracker.shared
    @ObservedObject private var premium = SubscriptionManager.shared
    @ObservedObject private var watch = WatchBridge.shared
    @EnvironmentObject private var engine: SyncEngine
    @AppStorage("oranaplo.app.language") private var languageCode = "hu"
    @State private var camera: MapCameraPosition = .userLocation(followsHeading:false,fallback:.automatic)
    @State private var manualWeight = ""
    @State private var weeklyGoalText = ""
    @State private var shareCardURL: URL?
    @State private var shareCardError = ""
    @State private var generatingCard = false
    @State private var showDeleteConfirmation = false
    @State private var exportMessageKey = ""
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .hu }
    private func t(_ key: String) -> String { L10n.t(key,language) }
    private let bg = Color(red:0.035,green:0.055,blue:0.085)
    private let card = Color(red:0.11,green:0.15,blue:0.20)
    private let blue = Color(red:0.44,green:0.73,blue:0.99)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    header
                    mapCard
                    metrics
                    goalsAndRecords
                    watchStatus
                    controls
                    if let run = tracker.current, tracker.phase == .finished {
                        finished(run)
                    } else if tracker.phase == .ready, let recent = tracker.lastCompleted {
                        recentCard(recent)
                    }
                    if tracker.phase != .recording && tracker.phase != .paused, !tracker.history.isEmpty {
                        history
                    }
                    Text(t("run.accuracy.disclaimer"))
                        .font(.caption).foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal:false,vertical:true)
                }
                .padding(18)
                .frame(maxWidth:650)
                .frame(maxWidth:.infinity)
            }.scrollIndicators(.hidden)
        }
        .onAppear {
            let stored=UserDefaults.standard.double(forKey:"oranaplo.run.weeklyGoalKM")
            weeklyGoalText = String(format:"%.0f",stored > 0 ? stored : 15)
        }
        .onChange(of: tracker.current?.id) { _, _ in camera = .automatic }
        .onChange(of: tracker.routeCoordinates.count) { _, count in
            guard count >= 1, tracker.phase == .recording, let last = tracker.routeCoordinates.last else { return }
            camera = .region(MKCoordinateRegion(center:last,span:MKCoordinateSpan(latitudeDelta:0.008,longitudeDelta:0.008)))
        }
        .alert(t("run.delete.confirm"),isPresented:$showDeleteConfirmation) {
            Button(t("run.delete"),role:.destructive) {
                if let run=tracker.current { tracker.delete(run.id) }
            }
            Button(t("run.cancel"),role:.cancel) { }
        } message: { Text(t("run.delete.disclosure")) }
    }

    private var header: some View {
        VStack(alignment:.leading,spacing:7) {
            Label(t("run.title"),systemImage:"figure.run.circle.fill")
                .font(.system(size:25,weight:.bold,design:.rounded)).foregroundStyle(.white)
            Text(t("run.subtitle"))
                .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            HStack(spacing:8) {
                Image(systemName: tracker.phase == .recording ? "circle.fill" : "circle.dotted")
                    .foregroundStyle(tracker.phase == .recording ? Color.green : blue)
                Text(t("run.phase." + tracker.phase.rawValue))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                if tracker.heartLoading { ProgressView().tint(.white) }
            }.padding(.top,7)
            if !tracker.message.isEmpty {
                Text(t(tracker.message)).font(.caption).foregroundStyle(blue)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private var mapCard: some View {
        VStack(alignment:.leading,spacing:10) {
            Label(t("run.map"),systemImage:"map").font(.headline).foregroundStyle(.white)
            if !tracker.routeCoordinates.isEmpty {
                Map(position:$camera) {
                    ForEach(tracker.routeSegments.indices,id: \.self) { index in
                        if tracker.routeSegments[index].count > 1 {
                            MapPolyline(coordinates:tracker.routeSegments[index]).stroke(blue,lineWidth:5)
                        }
                    }
                    if let first=tracker.routeCoordinates.first {
                        Annotation(t("run.startPoint"),coordinate:first) {
                            Image(systemName:"flag.fill").foregroundStyle(.white)
                                .padding(8).background(Color.green,in:Circle())
                        }
                    }
                    if let last=tracker.routeCoordinates.last {
                        Annotation(t("run.lastPoint"),coordinate:last) {
                            Image(systemName:"location.circle.fill").foregroundStyle(.white)
                                .padding(8).background(blue,in:Circle())
                        }
                    }
                }
                .mapStyle(.standard(elevation:.realistic))
                .frame(height:280)
                .clipShape(RoundedRectangle(cornerRadius:19))
                .accessibilityLabel(t("run.map.accessibility"))
                .overlay(alignment:.bottomLeading) {
                    Text(t("run.map.gps"))
                        .font(.caption2).padding(.horizontal,8).padding(.vertical,5)
                        .background(.ultraThinMaterial,in:Capsule()).padding(10)
                }
            } else {
                ZStack(alignment:.bottomTrailing) {
                    Map(position:$camera) { UserAnnotation() }
                        .mapStyle(.standard(elevation:.realistic))
                        .frame(height:265)
                    Button { tracker.requestMapPosition() } label: {
                        Label(t("run.map.gps"),systemImage:"location.fill")
                            .font(.caption.weight(.semibold))
                            .padding(10).background(.ultraThinMaterial,in:Capsule())
                    }.padding(12)
                }.clipShape(RoundedRectangle(cornerRadius:19))
                Text(t("run.map.waiting")).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
        }.padding(16).background(card,in:RoundedRectangle(cornerRadius:23))
    }
    private var metrics: some View {
        let grid = [GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10)]
        return LazyVGrid(columns:grid,spacing:10) {
            tile("run.metric.time",RunFormatting.duration(tracker.elapsedNow),"timer")
            tile("run.metric.distance",String(format:"%.2f km",tracker.meters/1000),"point.topleft.down.curvedto.point.bottomright.up")
            tile("run.metric.speed",tracker.averageKmh.map { String(format:"%.2f km/h",$0) } ?? "—","speedometer")
            tile("run.metric.pace",tracker.pace.map(RunFormatting.pace) ?? "—","figure.run")
            tile("run.metric.steps",tracker.steps.map { String($0) } ?? "—","figure.walk")
            tile("run.metric.calories",tracker.kcal.map { String(format:"~%.0f kcal",$0) } ?? "—","flame")
            tile("run.metric.hr",tracker.current?.heart.last.map { String(format:"%.0f bpm",$0.bpm) } ?? "—","heart")
            tile("run.metric.splits",String(tracker.splits.count),"square.stack.3d.up")
        }
    }
    private func tile(_ key:String,_ value:String,_ icon:String) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Label(t(key),systemImage:icon)
                .font(.caption).foregroundStyle(.white.opacity(0.67)).lineLimit(2)
            Text(value).font(.system(size:19,weight:.bold,design:.rounded))
                .foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth:.infinity,minHeight:74,alignment:.leading)
        .padding(14).background(card,in:RoundedRectangle(cornerRadius:17))
    }
    private var watchStatus: some View {
        VStack(alignment:.leading,spacing:8) {
            Label(t("run.watch.title"),systemImage:"applewatch").font(.headline)
            Text(t(watch.reachable ? "watch.status.connected" : "watch.status.disconnected"))
                .foregroundStyle(watch.reachable ? Color.green : Color.orange)
                .font(.caption)
            if let date = watch.lastWatchUpdate,
               Date().timeIntervalSince(date) < 30,
               let bpm = watch.watchBPM {
                Text(String(format:"%.0f bpm · %@",bpm,
                    date.formatted(date:.omitted,time:.shortened))).font(.headline)
            }
            Text(t("run.watch.note")).font(.caption2).foregroundStyle(.white.opacity(0.60))
        }.padding(15).frame(maxWidth:.infinity,alignment:.leading)
            .background(card,in:RoundedRectangle(cornerRadius:20))
    }
    private var goalsAndRecords: some View {
        let summary=tracker.weeklySummary
        return VStack(alignment:.leading,spacing:12) {
            Label(t("run.goals.title"),systemImage:"target").font(.headline)
            Text(String(format:"%.2f / %.0f km",summary.weeklyMeters/1000,summary.weeklyGoalMeters/1000))
                .font(.system(size:23,weight:.bold,design:.rounded))
            ProgressView(value:summary.weeklyGoalMeters > 0
                         ? min(1,summary.weeklyMeters/summary.weeklyGoalMeters) : 0)
                .tint(blue)
            HStack {
                Label("\(summary.weeklyStreak) \(t("run.goals.streak"))",systemImage:"flame.fill")
                Spacer()
                Text(String(format:"%@ %.1f km",t("run.goals.monthly"),summary.monthlyMeters/1000))
            }.font(.caption).foregroundStyle(.white.opacity(0.75))
            HStack {
                Text(t("run.goals.weeklyTarget")).font(.subheadline)
                TextField("15",text:$weeklyGoalText).keyboardType(.decimalPad)
                    .frame(width:65).multilineTextAlignment(.trailing)
                    .padding(8).background(Color.black.opacity(0.18),in:RoundedRectangle(cornerRadius:9))
                Text("km").font(.caption)
                Button(t("run.goals.save")) {
                    if let value=Double(weeklyGoalText.replacingOccurrences(of:",",with:".")),
                       (1...500).contains(value) {
                        UserDefaults.standard.set(value,forKey:"oranaplo.run.weeklyGoalKM")
                        tracker.weeklyGoalChanged()
                    }
                }.font(.caption.bold())
            }
            if !tracker.personalRecords.isEmpty {
                Text(t("run.pr.title")).font(.headline)
                ForEach(tracker.personalRecords) { record in
                    HStack {
                        Text(record.distanceMeters == 21_097 ? "21.097 km" :
                             "\(record.distanceMeters/1000) km")
                        Spacer()
                        Text(RunFormatting.duration(record.seconds)).fontWeight(.semibold)
                    }.font(.caption)
                }
            }
        }.padding(15).frame(maxWidth:.infinity,alignment:.leading)
            .background(card,in:RoundedRectangle(cornerRadius:20))
    }
    private var controls: some View {
        VStack(alignment:.leading,spacing:12) {
            if tracker.phase == .ready || tracker.phase == .finished {
                if tracker.phase == .ready {
                    Text(t("run.profile.note")).font(.caption).foregroundStyle(.white.opacity(0.65))
                    HStack {
                        Text(t("run.weight.optional")).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        TextField(t("run.weight.placeholder"),text:$manualWeight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width:112).padding(11)
                            .background(Color.black.opacity(0.25),in:RoundedRectangle(cornerRadius:10))
                            .foregroundStyle(.white)
                    }
                }
                Button {
                    if tracker.phase == .finished { tracker.newRun() }
                    let manual = Double(manualWeight.replacingOccurrences(of:",",with:"."))
                    let valid = (manual ?? 0) >= 20 && (manual ?? 0) <= 400 ? manual : nil
                    tracker.configureProfile(kilograms:valid ?? engine.profile?.weightKG,centimeters:engine.profile?.heightCM)
                    watch.command("start")
                    tracker.requestPermissionAndStart(kilograms:valid ?? engine.profile?.weightKG,
                        centimeters:engine.profile?.heightCM)
                } label: { Label(t("run.start"),systemImage:"play.fill")
                    .frame(maxWidth:.infinity).padding(16).background(blue,in:RoundedRectangle(cornerRadius:15))
                    .foregroundStyle(.black).fontWeight(.bold) }
            } else {
                HStack(spacing:12) {
                    if tracker.phase == .recording {
                        Button { tracker.pause(); watch.command("pause") } label: { Label(t("run.pause"),systemImage:"pause.fill")
                            .frame(maxWidth:.infinity).padding(15).background(Color.orange.opacity(0.9),in:RoundedRectangle(cornerRadius:13)) }
                    } else {
                        Button { tracker.resume(); watch.command("resume") } label: { Label(t("run.resume"),systemImage:"play.fill")
                            .frame(maxWidth:.infinity).padding(15).background(Color.green.opacity(0.9),in:RoundedRectangle(cornerRadius:13)) }
                    }
                    Button { tracker.finish(); watch.command("stop") } label: { Label(t("run.stop"),systemImage:"stop.fill")
                        .frame(maxWidth:.infinity).padding(15).background(Color.red.opacity(0.85),in:RoundedRectangle(cornerRadius:13)) }
                }.foregroundStyle(.white).font(.system(size:14,weight:.bold))
            }
            if tracker.phase == .recording {
                Label(t("run.background"),systemImage:"location.fill")
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }.padding(15).background(card,in:RoundedRectangle(cornerRadius:22))
    }
    private func finished(_ run:RecordedRun) -> some View {
        VStack(alignment:.leading,spacing:13) {
            Text(t("run.complete.title")).font(.headline).foregroundStyle(.white)
            if run.interrupted {
                Text(t("run.interrupted.disclaimer")).font(.caption).foregroundStyle(.orange)
            }
            if !run.heart.isEmpty {
                let avg = run.heart.reduce(0) { $0+$1.bpm }/Double(run.heart.count)
                Text(String(format:"%@: %.0f / %.0f / %.0f bpm",t("run.heart.summary"),avg,run.heart.map(\.bpm).min() ?? 0,run.heart.map(\.bpm).max() ?? 0))
                    .font(.subheadline).foregroundStyle(.white)
            } else {
                Text(t("run.heart.later")).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Button { Task { await tracker.enrichHeart(run.id) } } label: {
                Label(t("run.heart.refresh"),systemImage:"heart.text.square")
                    .frame(maxWidth:.infinity).padding(12).background(Color.white.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
            }
            .disabled(tracker.heartLoading)
            if !tracker.recentlyBrokenRecords.isEmpty && tracker.current?.id == run.id {
                VStack(alignment:.leading,spacing:7) {
                    Text(t("run.pr.new")).font(.headline).foregroundStyle(blue)
                    ForEach(tracker.recentlyBrokenRecords) { record in
                        Text("\(record.distanceMeters)m · \(RunFormatting.duration(record.seconds))")
                            .font(.subheadline).foregroundStyle(.white)
                    }
                }
            }
            if !run.splits.isEmpty {
                HStack {
                    Text(t("run.splits.title")).font(.headline)
                    Spacer()
                    Text("\(run.splits.count) × 100 m").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                ForEach(run.splits) { s in
                    VStack(alignment:.leading,spacing:5) {
                        HStack {
                            Text("\(s.index * 100) m").fontWeight(.bold)
                            Spacer()
                            Text(RunFormatting.duration(s.elapsedSeconds))
                            Text(RunFormatting.pace(s.paceSecondsPerKm)).foregroundStyle(blue)
                        }
                        HStack(spacing:12) {
                            Text(String(format:"%.2f km/h",s.kmh))
                            Text(s.avgHeart.map { String(format:"%.0f bpm",$0) } ?? t("run.noheart"))
                            if let steps=s.steps { Text("\(steps) \(t("run.step.unit"))") }
                            if let c=s.estimatedKcal { Text(String(format:"~%.0f kcal",c)) }
                        }.font(.caption).foregroundStyle(.white.opacity(0.65))
                    }.padding(11).background(Color.black.opacity(0.2),in:RoundedRectangle(cornerRadius:12))
                }
            } else {
                Text(t("run.splits.waiting")).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Button {
                generatingCard = true
                shareCardError = ""
                Task {
                    do { shareCardURL = try await RunShareCard.create(run,language:language) }
                    catch { shareCardError = error.localizedDescription }
                    generatingCard = false
                }
            } label: {
                Label(t("run.share.card.create"),systemImage:"photo")
                    .frame(maxWidth:.infinity).padding(12)
                    .background(Color.white.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
            }.disabled(generatingCard)
            if let shareCardURL {
                ShareLink(item:shareCardURL) {
                    Label(t("run.share.card.share"),systemImage:"square.and.arrow.up")
                        .frame(maxWidth:.infinity).padding(12)
                        .background(blue,in:RoundedRectangle(cornerRadius:12))
                        .foregroundStyle(.black)
                }
            }
            if !shareCardError.isEmpty {
                Text(shareCardError).font(.caption).foregroundStyle(.orange)
            }
            Text(t("run.share.privacy")).font(.caption2).foregroundStyle(.white.opacity(0.6))
            if let url=tracker.gpxURL(for:run) {
                ShareLink(item:url) {
                    Label(t("run.share.gpx"),systemImage:"square.and.arrow.up")
                        .frame(maxWidth:.infinity).padding(12).background(Color.white.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                }
            }
            if premium.proActive {
                Button {
                    Task {
                        await engine.exportRecordedRun(run)
                        exportMessageKey = "run.export.attempted"
                    }
                } label: { Label(t("run.export.sheets"),systemImage:"tablecells")
                    .frame(maxWidth:.infinity).padding(12).background(blue,in:RoundedRectangle(cornerRadius:12))
                    .foregroundStyle(.black).fontWeight(.semibold) }
                .disabled(!engine.account.loggedIn || engine.busy)
                if !engine.account.loggedIn { Text(t("run.export.login"))
                    .font(.caption).foregroundStyle(.white.opacity(0.65)) }
                if !exportMessageKey.isEmpty { Text(t(exportMessageKey)).font(.caption).foregroundStyle(.white.opacity(0.65)) }
            } else {
                Text(t("run.export.pro"))
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Button(role:.destructive) { showDeleteConfirmation=true } label: {
                Label(t("run.delete"),systemImage:"trash")
                    .frame(maxWidth:.infinity).padding(10)
            }
        }.padding(16).background(card,in:RoundedRectangle(cornerRadius:22))
    }
    private func recentCard(_ run:RecordedRun) -> some View {
        Button { tracker.select(run) } label: {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(t("run.last.title")).font(.subheadline.weight(.bold))
                    Text(run.started.formatted(date:.abbreviated,time:.shortened))
                    Text(String(format:"%.2f km · %@",run.gpsMeters/1000,RunFormatting.duration(run.activeSeconds)))
                }
                Spacer(); Image(systemName:"chevron.right")
            }.foregroundStyle(.white).padding(15).background(card,in:RoundedRectangle(cornerRadius:18))
        }
    }
    private var history: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(t("run.history")).font(.headline).foregroundStyle(.white)
            ForEach(tracker.history.prefix(12)) { run in
                Button { tracker.select(run) } label: {
                    HStack {
                        VStack(alignment:.leading,spacing:3) {
                            Text(run.started.formatted(date:.abbreviated,time:.shortened))
                            Text(String(format:"%.2f km · %@",run.gpsMeters/1000,RunFormatting.duration(run.activeSeconds)))
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer(); Image(systemName:"map")
                    }.foregroundStyle(.white).padding(13).background(card,in:RoundedRectangle(cornerRadius:13))
                }
            }
        }
    }
}

enum RunFormatting {
    static func duration(_ seconds:Double) -> String {
        let total = Int(max(0,seconds).rounded(.down))
        return String(format:"%02d:%02d:%02d",total/3600,(total/60)%60,total%60)
    }
    static func pace(_ seconds:Double) -> String {
        guard seconds.isFinite,seconds>=0,seconds<36000 else { return "—" }
        let sec = Int(seconds.rounded())
        return String(format:"%d:%02d min/km",sec/60,sec%60)
    }
}
