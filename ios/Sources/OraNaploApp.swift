import SwiftUI
import UIKit
import BackgroundTasks
import GoogleSignIn
import UserNotifications

@main
struct OraNaploApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var engine = SyncEngine()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(engine)
                .preferredColorScheme(.dark)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    await engine.bootstrap()
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let taskID = "hu.oranaplo.ios.refresh"
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            Task { @MainActor in
                // Apple's scheduling is opportunistic; never promise interval accuracy.
                let engine = SyncEngine()
                await engine.account.restore()
                await engine.sync()
                task.setTaskCompleted(success: true)
                Self.schedule()
            }
        }
        Self.schedule()
        return true
    }
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}


// MARK: - Premium, privacy-first interface

private enum Atelier {
    static let midnight = Color(red: 0.035, green: 0.055, blue: 0.085)
    static let graphite = Color(red: 0.073, green: 0.094, blue: 0.127)
    static let steel = Color(red: 0.115, green: 0.145, blue: 0.190)
    static let ice = Color(red: 0.75, green: 0.86, blue: 0.99)
    static let azure = Color(red: 0.41, green: 0.67, blue: 0.95)
    static let mist = Color(red: 0.61, green: 0.69, blue: 0.80)
    static let mint = Color(red: 0.45, green: 0.83, blue: 0.73)
    static let line = Color.white.opacity(0.105)
}

private struct MetalSurface<Content: View>: View {
    var prominent = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(LinearGradient(colors: prominent ?
                        [Color(red: 0.105, green: 0.165, blue: 0.23), Atelier.graphite] :
                        [Atelier.steel.opacity(0.95), Atelier.graphite],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.04), Atelier.azure.opacity(0.12)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
    }
}

private struct PressFeedback: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct ActionLabel: View {
    let title: String
    let symbol: String
    var primary = true
    var trailing = "arrow.up.right"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer(minLength: 4)
            Image(systemName: trailing).font(.system(size: 13, weight: .semibold))
                .opacity(primary ? 0.8 : 0.55)
        }
        .foregroundStyle(primary ? Atelier.midnight : Atelier.ice)
        .padding(.horizontal, 18).frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(primary ? LinearGradient(colors: [Atelier.ice, Atelier.azure], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(primary ? 0.33 : 0.10), lineWidth: 1))
    }
}

private struct MicroHeading: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(2.0).foregroundStyle(Atelier.mist)
    }
}

private struct SectionTitle: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Atelier.azure).font(.system(size: 17, weight: .medium))
                .frame(width: 24)
            Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }
}

private struct AppCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            Atelier.midnight.ignoresSafeArea()
            LinearGradient(colors: [Atelier.azure.opacity(0.09), .clear, .black.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 44)
                    .frame(maxWidth: 650)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @AppStorage("oranaplo.app.language") private var languageCode = "hu"
    @State private var selectedTab = 0
    @State private var journalKind = "journal.mood"
    @State private var journalText = ""
    @State private var showTechnicalDetails = false

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .hu }
    private func t(_ key: String) -> String { L10n.t(key, language) }

    var body: some View {
        TabView(selection: $selectedTab) {
            home.tabItem { Label(t("tab.home"), systemImage: "square.grid.2x2") }.tag(0)
            measurements.tabItem { Label(t("tab.metrics"), systemImage: "waveform.path.ecg") }.tag(1)
            journal.tabItem { Label(t("tab.journal"), systemImage: "square.and.pencil") }.tag(2)
            settings.tabItem { Label(t("tab.settings"), systemImage: "slider.horizontal.3") }.tag(3)
        }
        .tint(Atelier.azure)
        .toolbarBackground(Atelier.graphite, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: languageCode))
        .onChange(of: scenePhase) { _, next in
            if next == .active { Task { await subscriptions.refreshEntitlement() } }
        }
    }

    private var home: some View {
        AppCanvas {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Atelier.azure)
                    .frame(width: 42, height: 42)
                    .background(Atelier.steel, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ÓraNapló").font(.system(size: 22, weight: .bold, design: .rounded))
                    MicroHeading(text: t("brand.subtitle"))
                }
                Spacer()
                Text(subscriptions.proActive ? t("common.pro") : t("common.free"))
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(subscriptions.proActive ? Atelier.mint : Atelier.ice)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Atelier.steel, in: Capsule())
            }.padding(.bottom, 5)

            MetalSurface(prominent: true) {
                VStack(alignment: .leading, spacing: 13) {
                    MicroHeading(text: subscriptions.proActive ? t("tier.pro") : t("tier.free"))
                    Text(t("hero.title"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-1.0).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(t("hero.desc"))
                        .font(.system(size: 13)).foregroundStyle(Atelier.mist)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                        Text(t("settings.privacy"))
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(Atelier.mint)
                }
            }
            if !engine.basicHealthFlowCompleted || !engine.account.loggedIn || engine.sheetURL == nil {
                onboardingCard
            }
            sheetCard
            workoutCard
            observationsCard
            syncCard
            planCard
            statusCard
        }
    }

    private var onboardingCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(title: t("onboard.title"), symbol: "list.number")
                Text(t("onboard.subtitle"))
                    .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                onboardingStep(1, "onboard.health", engine.basicHealthFlowCompleted) {
                    Task { await engine.authorizeHealth() }
                }
                onboardingStep(2, "onboard.google", engine.account.loggedIn) {
                    Task { await engine.login() }
                }
                onboardingStep(3, "onboard.sheets", engine.sheetURL != nil) {
                    Task { await engine.prepareGoogleSheet() }
                }
            }
        }
    }

    private func onboardingStep(_ number: Int, _ key: String, _ completed: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: completed ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(completed ? Atelier.mint : Atelier.azure)
                    .font(.system(size: 21))
                Text(t(key)).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Atelier.ice)
                Spacer()
                if !completed { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Atelier.mist) }
            }.padding(12)
            .background(Atelier.midnight.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(completed || (number == 3 && !engine.account.loggedIn))
        .buttonStyle(PressFeedback())
    }

    private var sheetCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 15) {
                SectionTitle(title: t("sheet.title"), symbol: "tablecells")
                HStack(spacing: 9) {
                    Circle().fill(engine.sheetURL == nil ? Atelier.mist : Atelier.mint)
                        .frame(width: 7, height: 7)
                    Text(engine.sheetURL == nil ? t("sheet.notfound") : t("sheet.ready"))
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = engine.sheetURL {
                    Button { openURL(url) } label: {
                        ActionLabel(title: t("sheet.open"), symbol: "arrow.up.right.square")
                    }.buttonStyle(PressFeedback())
                    Button { Task { await engine.prepareGoogleSheet() } } label: {
                        ActionLabel(title: t("sheet.upload"), symbol: "arrow.clockwise", primary: false)
                    }.buttonStyle(PressFeedback()).disabled(engine.busy)
                } else if engine.account.loggedIn {
                    Button { Task { await engine.prepareGoogleSheet() } } label: {
                        ActionLabel(title: t("sheet.create"), symbol: "plus.square.on.square")
                    }.buttonStyle(PressFeedback()).disabled(engine.busy)
                    Button { Task { await engine.findPreviousSheet() } } label: {
                        ActionLabel(title: t("sheet.find"), symbol: "magnifyingglass", primary: false)
                    }.buttonStyle(PressFeedback())
                } else {
                    Button { Task { await engine.login() } } label: {
                        ActionLabel(title: t("sheet.login"), symbol: "person.crop.circle.badge.checkmark")
                    }.buttonStyle(PressFeedback())
                }
            }
        }
    }

    private var workoutCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: t("workout.title"), symbol: "figure.run")
                if let workout = engine.lastWorkout {
                    HStack {
                        Text(t(workout.kindKey)).font(.system(size: 19, weight: .bold, design: .rounded))
                        Spacer()
                        Text(formattedDate(workout.started))
                            .font(.system(size: 11)).foregroundStyle(Atelier.mist)
                    }
                    HStack(spacing: 8) {
                        statistic(t("workout.duration"), String(format: "%.0f %@", workout.seconds / 60, t("common.min")))
                        statistic(t("workout.distance"), workout.distanceMeters.map { String(format: "%.2f km", $0 / 1000) } ?? t("common.noData"))
                    }
                    HStack(spacing: 8) {
                        statistic(t("workout.hr.avg"), workout.averageBPM.map { String(format: "%.0f bpm", $0) } ?? t("workout.nohr"))
                        statistic(t("workout.hr.range"), (workout.minBPM != nil && workout.maxBPM != nil) ? String(format: "%.0f–%.0f", workout.minBPM!, workout.maxBPM!) : t("common.noData"))
                    }
                    if subscriptions.proActive {
                        HStack(spacing: 8) {
                            statistic(t("workout.calories"), workout.energyKcal.map { String(format: "%.0f kcal", $0) } ?? t("common.noData"))
                            statistic(t("workout.splits"), workout.hundredMeterSegments.map { String($0) } ?? t("workout.nogps"))
                        }
                    }
                } else {
                    Text(t("workout.none")).font(.system(size: 13)).foregroundStyle(Atelier.mist)
                }
            }
        }
    }

    private var observationsCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(title: t("attention.title"), symbol: "exclamationmark.circle")
                if engine.observations.isEmpty {
                    Text(t("attention.none")).font(.system(size: 13)).foregroundStyle(Atelier.mist)
                } else {
                    ForEach(engine.observations) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill").foregroundStyle(Atelier.azure)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t(item.titleKey)).font(.system(size: 13, weight: .medium))
                                Text(formattedDate(item.date)).font(.system(size: 11)).foregroundStyle(Atelier.mist)
                            }
                        }
                    }
                }
                Text(t("attention.disclaimer"))
                    .font(.system(size: 11)).foregroundStyle(Atelier.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var syncCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: t("sync.title"), symbol: "arrow.triangle.2.circlepath")
                HStack(spacing: 10) {
                    statistic(t("sync.last"), engine.lastSync == "–" ? t("sync.never") : engine.lastSync)
                    statistic(t("sync.pending"), String(engine.pendingCount))
                }
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Atelier.mint)
                    Text(t("sync.uploaded") + ": " + String(engine.lastUploadedCount))
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                }
                if let last = engine.lastSuccessfulDate,
                   Date().timeIntervalSince(last) > 24 * 3600 {
                    Label(t("sync.stale"), systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 11)).foregroundStyle(Atelier.azure)
                }
                Button { Task { await engine.sync() } } label: {
                    ActionLabel(title: engine.busy ? t("sync.running") : t("sync.action"), symbol: "arrow.clockwise", primary: false)
                }.buttonStyle(PressFeedback()).disabled(engine.busy || !engine.account.loggedIn)
                Text(t("sync.background"))
                    .font(.system(size: 11)).foregroundStyle(Atelier.mist)
                Text(t("sync.offline"))
                    .font(.system(size: 11)).foregroundStyle(Atelier.mist)
            }
        }
    }

    private var planCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle(title: t("tier.current"), symbol: "checkmark.seal")
                Text(subscriptions.proActive ? t("tier.pro") : t("tier.free"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subscriptions.proActive ? t("tier.pro.desc") : t("tier.free.desc"))
                    .font(.system(size: 13)).foregroundStyle(Atelier.mist)
                if !subscriptions.proActive {
                    Divider().overlay(Atelier.line)
                    Text(subscriptions.product.map { $0.displayPrice + " / " + t("metrics.365") } ?? t("tier.pro.price"))
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    Text(t("tier.price.note")).font(.system(size: 11)).foregroundStyle(Atelier.mist)
                    if subscriptions.product != nil {
                        Button { Task { await subscriptions.purchase() } } label: {
                            ActionLabel(title: t("tier.buy"), symbol: "crown")
                        }.buttonStyle(PressFeedback()).disabled(subscriptions.busy)
                    } else {
                        Text(t("tier.unavailable")).font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                } else {
                    Label(t("tier.verified"), systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12)).foregroundStyle(Atelier.mint)
                }
                Text(t(subscriptions.messageKey))
                    .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                Button { Task { await subscriptions.restore() } } label: {
                    ActionLabel(title: t("tier.restore"), symbol: "arrow.counterclockwise", primary: false)
                }.buttonStyle(PressFeedback()).disabled(subscriptions.busy)
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    Button { openURL(url) } label: {
                        ActionLabel(title: t("tier.manage"), symbol: "gearshape", primary: false)
                    }.buttonStyle(PressFeedback())
                }
            }
        }
    }

    private var statusCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: t("settings.technical"), symbol: "checkmark.shield")
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(engine.syncHadError ? Color.orange : Atelier.mint)
                        .frame(width: 8, height: 8).padding(.top, 5)
                    Text(t(statusKey)).font(.system(size: 13)).foregroundStyle(Atelier.ice)
                }
                if engine.busy { ProgressView().tint(Atelier.azure) }
            }
        }
    }

    private var statusKey: String {
        if engine.busy { return "sync.status.busy" }
        if engine.syncHadError { return "sync.status.error" }
        if !engine.account.loggedIn { return "sync.status.connect" }
        if !engine.basicHealthFlowCompleted { return "sync.status.health" }
        return engine.lastSync == "–" ? "sync.status.ready" : "sync.status.done"
    }

    private var measurements: some View {
        AppCanvas {
            heading(t("metrics.eyebrow"), t("metrics.title"), t("metrics.desc"))
            MetalSurface {
                VStack(alignment: .leading, spacing: 15) {
                    SectionTitle(title: t("tab.metrics"), symbol: "waveform.path.ecg")
                    HStack {
                        Text(t("group.sziv")).font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(t("common.free")).font(.system(size: 11, weight: .bold)).foregroundStyle(Atelier.mint)
                    }
                    Divider().overlay(Atelier.line)
                    ForEach(Catalog.groups, id: \.0) { group in
                        HStack(spacing: 11) {
                            Image(systemName: categorySymbol(group.0)).foregroundStyle(Atelier.azure)
                                .frame(width: 24)
                            Toggle(t("group." + group.0), isOn: Binding(
                                get: { engine.enabledGroups.contains(group.0) },
                                set: { _ in engine.toggleGroup(group.0) }
                            ))
                            .tint(Atelier.azure)
                            .disabled(!subscriptions.proActive)
                            .font(.system(size: 14))
                            if !subscriptions.proActive {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11)).foregroundStyle(Atelier.mist)
                            }
                        }
                    }
                    if !subscriptions.proActive {
                        Text(t("tier.free.only"))
                            .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(title: t("metrics.history"), symbol: "clock.arrow.circlepath")
                    Picker(t("metrics.period"), selection: Binding(get: { engine.selectedDays }, set: { engine.setDays($0) })) {
                        Text(t("metrics.30")).tag(30)
                        Text(t("metrics.365")).tag(365)
                        Text(t("metrics.1825")).tag(1825)
                    }.pickerStyle(.segmented).disabled(!subscriptions.proActive)
                    Button { Task { await engine.sync() } } label: {
                        ActionLabel(title: t("metrics.import"), symbol: "square.and.arrow.down", trailing: "arrow.clockwise")
                    }.buttonStyle(PressFeedback())
                        .disabled(engine.busy || !engine.account.loggedIn || !subscriptions.proActive)
                    Text(t(subscriptions.proActive ? "metrics.import.note" : "metrics.pro.lock"))
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                }
            }
        }
    }

    private var journal: some View {
        AppCanvas {
            heading(t("journal.eyebrow"), t("journal.title"), t("journal.desc"))
            MetalSurface {
                VStack(alignment: .leading, spacing: 15) {
                    Picker(t("journal.title"), selection: $journalKind) {
                        Text(t("journal.mood")).tag("journal.mood")
                        Text(t("journal.medication")).tag("journal.medication")
                        Text(t("journal.other")).tag("journal.other")
                    }.pickerStyle(.segmented)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16).fill(Atelier.midnight.opacity(0.5))
                        if journalText.isEmpty {
                            Text(t("journal.placeholder"))
                                .foregroundStyle(Atelier.mist).padding(14)
                        }
                        TextEditor(text: $journalText)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(.white)
                            .padding(9).frame(height: 135)
                    }.frame(height: 135)
                    Button {
                        let value = journalText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        journalText = ""
                        Task { await engine.addJournalEntry(kind: t(journalKind), note: value) }
                    } label: {
                        ActionLabel(title: t("journal.save"), symbol: "square.and.arrow.down")
                    }.buttonStyle(PressFeedback())
                        .disabled(!subscriptions.proActive || !engine.account.loggedIn || journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !subscriptions.proActive {
                        Text(t("tier.free.only")).font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    } else if !engine.account.loggedIn {
                        Text(t("journal.needgoogle")).font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                }
            }
            if let url = engine.sheetURL {
                Button { openURL(url) } label: {
                    ActionLabel(title: t("sheet.open"), symbol: "tablecells", primary: false)
                }.buttonStyle(PressFeedback())
            }
        }
    }

    private var settings: some View {
        AppCanvas {
            heading(t("settings.eyebrow"), t("settings.title"), t("settings.desc"))
            MetalSurface {
                VStack(alignment: .leading, spacing: 13) {
                    SectionTitle(title: t("settings.language"), symbol: "globe")
                    Picker(t("settings.language"), selection: $languageCode) {
                        Text(t("settings.hu")).tag("hu")
                        Text(t("settings.en")).tag("en")
                        Text(t("settings.de")).tag("de")
                    }.pickerStyle(.segmented)
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 13) {
                    SectionTitle(title: t("sheet.account"), symbol: "person.crop.circle")
                    Text(engine.account.loggedIn ? engine.account.email : t("sheet.noaccount"))
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    Button {
                        Task {
                            if engine.account.loggedIn { await engine.disconnectGoogle() }
                            else { await engine.login() }
                        }
                    } label: {
                        ActionLabel(title: t(engine.account.loggedIn ? "sheet.disconnect" : "sheet.login"),
                                    symbol: "person.crop.circle", primary: false)
                    }.buttonStyle(PressFeedback())
                    if let url = engine.sheetURL {
                        Button { openURL(url) } label: {
                            ActionLabel(title: t("sheet.open"), symbol: "tablecells", primary: false)
                        }.buttonStyle(PressFeedback())
                    }
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 13) {
                    SectionTitle(title: t("settings.health"), symbol: "heart.text.square")
                    Button { Task { await engine.authorizeHealth() } } label: {
                        ActionLabel(title: t("settings.health.pulse"), symbol: "heart", primary: false)
                    }.buttonStyle(PressFeedback())
                    Button { Task { await engine.authorizeAllHealth() } } label: {
                        ActionLabel(title: t("settings.health.full"), symbol: "checkmark.shield", primary: false)
                    }.buttonStyle(PressFeedback())
                        .disabled(!subscriptions.proActive || !engine.basicHealthFlowCompleted)
                    Text(t(subscriptions.proActive ? "settings.health.sideload" : "settings.health.pro"))
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                }
            }
            planCard
            MetalSurface {
                VStack(alignment: .leading, spacing: 13) {
                    SectionTitle(title: t("settings.diagnostics"), symbol: "stethoscope")
                    Button {
                        showTechnicalDetails.toggle()
                    } label: {
                        ActionLabel(title: t("settings.showTechnical"), symbol: "chevron.down", primary: false)
                    }.buttonStyle(PressFeedback())
                    if showTechnicalDetails {
                        Text(CrashCheckpoint.last)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Atelier.mist)
                        Text(CrashCheckpoint.environmentSummary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Atelier.mist)
                            .textSelection(.enabled)
                    }
                    Button {
                        UIPasteboard.general.string = "ÓraNapló / " + t("settings.diagnostics") + "\n" +
                            CrashCheckpoint.last + "\n" + CrashCheckpoint.environmentSummary +
                            "\n" + engine.status + "\n" + subscriptions.technicalError
                    } label: {
                        ActionLabel(title: t("settings.copy"), symbol: "doc.on.doc", primary: false)
                    }.buttonStyle(PressFeedback())
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 9) {
                    SectionTitle(title: t("settings.help"), symbol: "info.circle")
                    Text(t("settings.limit"))
                    Text(t("settings.note"))
                    Text(t("settings.privacy"))
                }.font(.system(size: 12)).foregroundStyle(Atelier.mist)
            }
        }
    }

    private func statistic(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(Atelier.mist)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Atelier.midnight.opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
    }

    private func heading(_ eyebrow: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroHeading(text: eyebrow)
            Text(title).font(.system(size: 33, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Atelier.mist)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 7)
    }

    private func formattedDate(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: languageCode)
        format.dateStyle = .medium
        format.timeStyle = .short
        return format.string(from: date)
    }

    private func categorySymbol(_ key: String) -> String {
        switch key {
        case "sziv": return "heart"
        case "alvas": return "moon.stars"
        case "aktivitas": return "figure.walk"
        case "edzes": return "figure.run"
        case "test": return "scalemass"
        case "taplalkozas": return "fork.knife"
        default: return "thermometer"
        }
    }
}
