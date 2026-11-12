import SwiftUI
import HealthKit

private enum DashPalette {
    static let bg = Color(red:0.030,green:0.052,blue:0.083)
    static let card = Color(red:0.085,green:0.128,blue:0.173)
    static let blue = Color(red:0.29,green:0.65,blue:0.97)
    static let text = Color(red:0.72,green:0.79,blue:0.86)
}

private struct DashCard<Content:View>:View {
    var title:String
    var icon:String
    @ViewBuilder var content:() -> Content
    var body:some View {
        VStack(alignment:.leading,spacing:15) {
            Label(title,systemImage:icon)
                .font(.system(size:17,weight:.semibold,design:.rounded))
                .foregroundStyle(.white)
            content()
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(18)
        .background(DashPalette.card,in:RoundedRectangle(cornerRadius:22))
        .overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.09)))
    }
}

private struct DashStat:View {
    let label:String
    let value:String
    var symbol:String? = nil
    var body:some View {
        VStack(alignment:.center,spacing:5) {
            if let symbol { Image(systemName:symbol).foregroundStyle(DashPalette.blue).font(.system(size:18)) }
            Text(value).font(.system(size:18,weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(DashPalette.text).lineLimit(2).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity)
    }
}

private struct DashPage<Content:View>:View {
    @ViewBuilder var content:() -> Content
    var body:some View {
        ZStack {
            DashPalette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment:.leading,spacing:16){ content() }
                    .padding(.horizontal,17).padding(.vertical,23)
                    .frame(maxWidth:650).frame(maxWidth:.infinity)
            }.scrollIndicators(.hidden)
        }
    }
}

struct TodayDashboardView:View {
    @EnvironmentObject private var engine:SyncEngine
    @ObservedObject private var health = DailyHealthDashboard.shared
    @AppStorage("oranaplo.app.language") private var languageCode="hu"
    @AppStorage("oranaplo.daily.stepsGoal") private var dailyStepGoal=10000
    private var language:AppLanguage { AppLanguage(rawValue:languageCode) ?? .hu }
    private func t(_ key:String)->String { NewScreenText.t(key,language) }
    private func number(_ value:Double?,format:String="%.0f")->String { value.map { String(format:format,$0) } ?? "—" }
    private func duration(_ minutes:Double?)->String {
        guard let minutes,minutes >= 0 else { return "—" }
        let total=Int(minutes.rounded())
        return total >= 60 ? "\(total/60) \(t("today.hours")) \(total%60) \(t("today.minutes"))" : "\(total) \(t("today.minutes"))"
    }
    var body:some View {
        DashPage {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("ÓraNapló").font(.system(size:14,weight:.medium)).foregroundStyle(DashPalette.text)
                    Text(t("tab.today")).font(.system(size:31,weight:.bold,design:.rounded))
                }
                Spacer()
                Button { Task { await health.refresh() } } label: {
                    if health.busy { ProgressView().tint(DashPalette.blue) }
                    else { Image(systemName:"arrow.clockwise").font(.title3).foregroundStyle(DashPalette.blue) }
                }.accessibilityLabel(t("today.reload"))
            }
            VStack(spacing:11) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1),lineWidth:16)
                    Circle().trim(from:0,to: CGFloat(min(1,Double(health.snapshot.steps ?? 0)/Double(max(1,dailyStepGoal)))))
                        .stroke(AngularGradient(colors:[DashPalette.blue,Color.cyan,DashPalette.blue],center:.center),style:StrokeStyle(lineWidth:16,lineCap:.round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing:4) {
                        Image(systemName:"figure.walk").font(.system(size:25)).foregroundStyle(DashPalette.blue)
                        Text(health.snapshot.steps.map { $0.formatted() } ?? "—")
                            .font(.system(size:47,weight:.bold,design:.rounded)).minimumScaleFactor(0.65)
                        Text(t("today.steps")).font(.system(size:15)).foregroundStyle(DashPalette.text)
                    }
                }.frame(width:245,height:245).padding(.top,20)
                Text("\(t("today.goal")): \(dailyStepGoal.formatted())")
                    .font(.caption).foregroundStyle(DashPalette.text)
                HStack(spacing:5) {
                    DashStat(label:t("today.calories"),value:number(health.snapshot.activeKcal),symbol:"flame")
                    DashStat(label:t("today.distance"),value:health.snapshot.walkingRunningKM.map { String(format:"%.2f km",$0) } ?? "—",symbol:"point.topleft.down.curvedto.point.bottomright.up")
                    DashStat(label:t("today.activity"),value:duration(health.snapshot.exerciseMinutes),symbol:"clock")
                }.padding(.vertical,16)
            }
            .frame(maxWidth:.infinity)
            .padding(.horizontal,14)
            .background(DashPalette.card,in:RoundedRectangle(cornerRadius:28))
            .overlay(RoundedRectangle(cornerRadius:28).stroke(.white.opacity(0.09)))

            DashCard(title:t("today.sleep"),icon:"moon.stars.fill") {
                HStack(alignment:.firstTextBaseline) {
                    Text(duration(health.snapshot.lastNightMinutes))
                        .font(.system(size:31,weight:.bold,design:.rounded))
                    Spacer()
                    Text(t("today.lastNight")).font(.caption).foregroundStyle(DashPalette.text)
                }
                GeometryReader { geometry in
                    ZStack(alignment:.leading) {
                        Capsule().fill(.white.opacity(0.10))
                        Capsule().fill(LinearGradient(colors:[DashPalette.blue,.cyan],startPoint:.leading,endPoint:.trailing))
                            .frame(width:max(0,geometry.size.width*CGFloat(min(1,(health.snapshot.lastNightMinutes ?? 0)/480))))
                    }
                }.frame(height:9)
                let fraction=health.snapshot.comparisonFraction
                Text(fraction.map { $0 > 0.08 ? t("today.sleep.longer") : ($0 < -0.08 ? t("today.sleep.shorter") : t("today.sleep.similar")) } ?? t("today.sleep.unknown"))
                    .font(.subheadline).foregroundStyle(DashPalette.text)
                Text(t("today.sleep.source")).font(.caption2).foregroundStyle(DashPalette.text.opacity(0.85))
            }
            DashCard(title:t("today.pulse"),icon:"heart.fill") {
                HStack(spacing:0) {
                    DashStat(label:t("today.average"),value:number(health.snapshot.pulseMean)+" bpm")
                    Rectangle().fill(.white.opacity(0.12)).frame(width:1,height:40)
                    DashStat(label:t("today.low"),value:number(health.snapshot.pulseLow)+" bpm")
                    Rectangle().fill(.white.opacity(0.12)).frame(width:1,height:40)
                    DashStat(label:t("today.high"),value:number(health.snapshot.pulseHigh)+" bpm")
                }
            }
            if !engine.fullHealthFlowCompleted {
                DashCard(title:t("profile.health"),icon:"heart.text.square") {
                    Text(t("today.permission")).font(.footnote).foregroundStyle(DashPalette.text)
                    Button { Task { await engine.authorizeAllHealth(); await health.refresh() } } label: {
                        Text(t("today.fullAccess")).frame(maxWidth:.infinity).padding(12)
                            .background(DashPalette.blue,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(.black).fontWeight(.semibold)
                    }.disabled(!engine.basicHealthFlowCompleted)
                }
            }
        }
        .task(id:engine.fullHealthFlowCompleted) { await health.refresh() }
    }
}

struct AnalysisDashboardView:View {
    @EnvironmentObject private var engine:SyncEngine
    @AppStorage("oranaplo.app.language") private var languageCode="hu"
    @Environment(\.openURL) private var openURL
    @State private var rowCount:Int?
    @State private var loading=false
    @State private var showWellness=false
    @State private var failed=false
    private var language:AppLanguage { AppLanguage(rawValue:languageCode) ?? .hu }
    private func t(_ key:String)->String { NewScreenText.t(key,language) }
    var body:some View {
        DashPage {
            Text(t("tab.analysis")).font(.system(size:31,weight:.bold,design:.rounded))
            Text(t("analysis.subtitle")).font(.footnote).foregroundStyle(DashPalette.text)
            HStack(spacing:12) {
                DashCard(title:t("analysis.days"),icon:"calendar") {
                    Text("\(OraUsageClock.days)").font(.system(size:39,weight:.bold,design:.rounded))
                }
                DashCard(title:t("analysis.rows"),icon:"tablecells") {
                    Text(rowCount.map { $0.formatted() } ?? "—").font(.system(size:39,weight:.bold,design:.rounded)).minimumScaleFactor(0.55).lineLimit(1)
                }
            }
            DashCard(title:"Google Sheets",icon:"tablecells") {
                Text(engine.account.loggedIn ? engine.account.email : t("profile.notConnected"))
                    .foregroundStyle(DashPalette.text).font(.caption).lineLimit(2)
                if let url=engine.sheetURL {
                    Button { openURL(url) } label: {
                        Label(t("analysis.sheet"),systemImage:"arrow.up.right.square")
                            .frame(maxWidth:.infinity).padding(15)
                            .background(DashPalette.blue,in:RoundedRectangle(cornerRadius:15))
                            .foregroundStyle(.black).fontWeight(.bold)
                    }
                    Button { Task { await count() } } label: {
                        HStack { if loading { ProgressView() }; Text(t("analysis.refresh")) }
                    }.disabled(loading)
                    Text(t("analysis.recordNote")).font(.caption2).foregroundStyle(DashPalette.text)
                } else {
                    Button { Task { if !engine.account.loggedIn { await engine.login() } else { await engine.prepareGoogleSheet() } } } label: {
                        Text(t(engine.account.loggedIn ? "analysis.create" : "analysis.connect"))
                            .frame(maxWidth:.infinity).padding(13)
                            .background(DashPalette.blue,in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.black)
                    }
                }
                if failed { Text(t("analysis.error")).font(.caption).foregroundStyle(.orange) }
            }
            DashCard(title:NewScreenText.t("tab.analysis",language),icon:"heart.text.clipboard") {
                Button { showWellness = true } label: {
                    Label(language == "de" ? "Gesundheit, Schlaf, Medikamente und PDF" :
                          language == "en" ? "Health, sleep, medications and PDF" :
                          "Egészség, alvás, gyógyszerek és PDF",systemImage:"heart.text.clipboard")
                       .frame(maxWidth:.infinity).padding(12)
                       .background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                }
            }
            DashCard(title:t("analysis.sync"),icon:"arrow.triangle.2.circlepath") {
                HStack {
                    DashStat(label:t("analysis.sync"),value:engine.lastSync)
                    DashStat(label:t("analysis.pending"),value:"\(engine.pendingCount)")
                }
                Button { Task { await engine.sync() } } label: {
                    Label(t("analysis.upload"),systemImage:"arrow.clockwise")
                        .frame(maxWidth:.infinity).padding(13)
                        .background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
                }.disabled(engine.busy || !engine.account.loggedIn)
            }
            DashCard(title:OpsText.t("sync.title",language),icon:"arrow.triangle.2.circlepath.circle") {
                HStack(spacing:10) {
                    DashStat(label:OpsText.t("sync.lastSuccess",language),
                             value:engine.lastSuccessfulDate?.formatted(date:.abbreviated,time:.shortened) ?? "—")
                    DashStat(label:OpsText.t("sync.lastAttempt",language),
                             value:engine.lastAttemptDate?.formatted(date:.abbreviated,time:.shortened) ?? "—")
                }
                Divider().overlay(.white.opacity(0.1))
                HStack {
                    Text(OpsText.t("sync.pending",language)).foregroundStyle(DashPalette.text)
                    Spacer()
                    Text("\(engine.pendingCount)").fontWeight(.bold)
                }
                HStack {
                    Text(OpsText.t("sync.stage",language)).foregroundStyle(DashPalette.text)
                    Spacer()
                    Text(OpsText.t("sync.\(engine.syncProgress)",language)).fontWeight(.medium)
                }
                HStack {
                    Text(OpsText.t("sync.failure",language)).foregroundStyle(DashPalette.text)
                    Spacer()
                    Text(engine.lastFailureKind.isEmpty ? OpsText.t("sync.none",language) :
                         OpsText.t("sync.\(engine.lastFailureKind)",language))
                        .foregroundStyle(engine.lastFailureKind.isEmpty ? DashPalette.text : .orange)
                        .multilineTextAlignment(.trailing)
                }.font(.caption)
                if engine.autoSyncPaused {
                    Text(OpsText.t("sync.paused",language)).font(.footnote).foregroundStyle(.orange)
                    Button(OpsText.t("sync.resume",language)) { engine.resumeAutoSyncAfterErase() }
                        .buttonStyle(.borderedProminent).tint(DashPalette.blue)
                } else {
                    Text(OpsText.t("sync.help",language)).font(.caption2).foregroundStyle(DashPalette.text)
                }
            }
            Text(t("analysis.dataSince")).font(.caption2).foregroundStyle(DashPalette.text)
        }.task(id:engine.sheetID) { await count() }
        .sheet(isPresented:$showWellness) { WellnessDashboardView() }
    }
    private func count() async {
        guard !loading,engine.account.loggedIn,!engine.sheetID.isEmpty else { return }
        loading=true; defer { loading=false }
        do {
            rowCount=try await SheetsAPI(account:engine.account).countFilledRecords(sheetID:engine.sheetID)
            failed=false
        } catch { failed=true }
    }
}

struct LeaderboardDashboardView:View {
    @ObservedObject private var rankings=LeaderboardService.shared
    @AppStorage("oranaplo.app.language") private var languageCode="hu"
    @AppStorage("oranaplo.leaderboard.name") private var displayName=""
    @State private var selectedMode:RankingMode = .steps
    private var language:AppLanguage { AppLanguage(rawValue:languageCode) ?? .hu }
    private func t(_ key:String)->String { NewScreenText.t(key,language) }
    private func value(_ row:PublicRanking)->String {
        selectedMode == .steps ? row.total_steps.formatted() : String(format:"%.2f km",row.longest_run_m/1000)
    }
    var body:some View {
        DashPage {
            Text(t("tab.leaderboard")).font(.system(size:31,weight:.bold,design:.rounded))
            Text(t("leader.subtitle")).font(.footnote).foregroundStyle(DashPalette.text)
            DashCard(title:t("leader.myRank"),icon:"globe.europe.africa.fill") {
                HStack {
                    Spacer()
                    Text(rankings.worldRank.map { "#\($0.formatted())" } ?? "—")
                        .font(.system(size:49,weight:.bold,design:.rounded))
                    Spacer()
                }
                Text(rankings.worldRank == nil ? t("leader.notRanked") : t(selectedMode == .steps ? "leader.steps" : "leader.run"))
                    .frame(maxWidth:.infinity).font(.caption).foregroundStyle(DashPalette.text)
            }
            HStack(spacing:4) {
                modeButton(.steps,label:t("leader.steps"))
                modeButton(.run,label:t("leader.run"))
            }.padding(4).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:15))
            DashCard(title:t(selectedMode == .steps ? "leader.steps" : "leader.run"),icon:"trophy") {
                if rankings.busy { ProgressView().tint(DashPalette.blue).frame(maxWidth:.infinity) }
                if !rankings.isConfigured {
                    Text(t("leader.configure")).font(.footnote).foregroundStyle(DashPalette.text)
                } else if rankings.entries.isEmpty {
                    Text(t(rankings.messageKey.isEmpty ? "leader.empty" : rankings.messageKey))
                        .font(.footnote).foregroundStyle(DashPalette.text)
                }
                ForEach(rankings.entries.indices,id:\.self) { index in
                    let user=rankings.entries[index]
                    HStack(spacing:11) {
                        Text("\(index+1)").frame(width:25).fontWeight(.bold)
                            .foregroundStyle(index<3 ? DashPalette.blue : DashPalette.text)
                        Image(systemName:index==0 ? "crown.fill" : "person.crop.circle")
                            .foregroundStyle(index==0 ? Color.yellow : DashPalette.blue)
                        Text(user.display_name).lineLimit(1)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(value(user)).font(.system(size:13,weight:.bold,design:.rounded))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.vertical,7)
                    if index < rankings.entries.count-1 { Divider().overlay(.white.opacity(0.08)) }
                }
                Button { Task { await rankings.refresh(mode:selectedMode) } } label: {
                    Label(t("leader.refresh"),systemImage:"arrow.clockwise")
                        .frame(maxWidth:.infinity).padding(12)
                        .background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:13))
                }.disabled(rankings.busy || !rankings.isConfigured)
            }
            if !rankings.published {
                DashCard(title:t("leader.noConsent"),icon:"lock.shield") {
                    Text(t("leader.privacy")).font(.footnote).foregroundStyle(DashPalette.text)
                    Button { Task { await rankings.publish(name:displayName); await rankings.refresh(mode:selectedMode) } } label: {
                        Text(t("leader.publish")).frame(maxWidth:.infinity).padding(13)
                            .background(DashPalette.blue,in:RoundedRectangle(cornerRadius:14))
                            .foregroundStyle(.black)
                    }.disabled(!rankings.isConfigured || rankings.busy)
                    if !rankings.messageKey.isEmpty {
                        Text(t(rankings.messageKey)).font(.caption).foregroundStyle(DashPalette.text)
                    }
                }
            }
            Text(t("leader.selfReported")).font(.caption2).foregroundStyle(DashPalette.text)
        }.task { await rankings.refresh(mode:selectedMode) }
    }
    private func modeButton(_ mode:RankingMode,label:String)->some View {
        Button { selectedMode=mode;Task { await rankings.refresh(mode:mode) } } label: {
            Text(label).font(.system(size:12,weight:.semibold)).frame(maxWidth:.infinity).padding(.vertical,12)
                .foregroundStyle(selectedMode==mode ? .white : DashPalette.text)
                .background(selectedMode==mode ? DashPalette.blue.opacity(0.48) : .clear,
                            in:RoundedRectangle(cornerRadius:11))
        }
    }
}
