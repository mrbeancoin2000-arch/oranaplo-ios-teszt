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
    @State private var journalKind = "Közérzet"
    @State private var journalText = ""
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            home.tabItem { Label("Áttekintés", systemImage: "square.grid.2x2") }.tag(0)
            measurements.tabItem { Label("Mérések", systemImage: "waveform.path.ecg") }.tag(1)
            journal.tabItem { Label("Napló", systemImage: "square.and.pencil") }.tag(2)
            settings.tabItem { Label("Beállítások", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .tint(Atelier.azure)
        .toolbarBackground(Atelier.graphite, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
    }

    private var home: some View {
        AppCanvas {
            brandHeader
            hero
            mainSheetCard
            syncCard
            statusCard
            Text("Az adatok a saját Google-fiókodban maradnak.")
                .font(.system(size: 12)).foregroundStyle(Atelier.mist.opacity(0.7))
                .frame(maxWidth: .infinity).padding(.top, 6)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Atelier.ice)
                .frame(width: 39, height: 39)
                .background(Atelier.steel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Atelier.line))
            Text("óranapló")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(-0.6).foregroundStyle(.white)
            Spacer()
            Text("BÉTA").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Atelier.ice.opacity(0.8))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Atelier.steel.opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(Atelier.line))
        }.padding(.bottom, 5)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.22, blue: 0.30), Atelier.graphite],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .stroke(Atelier.azure.opacity(0.13), lineWidth: 1)
                .frame(width: 190, height: 190)
                .offset(x: 230, y: -95)
            Circle()
                .fill(Atelier.azure.opacity(0.10))
                .frame(width: 150, height: 150)
                .blur(radius: 35)
                .offset(x: 260, y: -60)
            VStack(alignment: .leading, spacing: 16) {
                MicroHeading(text: "A saját egészségadat-archívumod")
                Text("Minden mérés.\nEgy táblázat.")
                    .font(.system(size: 35, weight: .bold, design: .rounded))
                    .tracking(-1.3).lineSpacing(0)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Atelier.mint)
                    Text("Privát · A saját Google Drive-odban")
                        .foregroundStyle(Atelier.ice.opacity(0.90))
                        .font(.system(size: 12, weight: .medium))
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.14)))
    }

    private var mainSheetCard: some View {
        MetalSurface(prominent: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "tablecells.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Atelier.mint)
                        .frame(width: 46, height: 46)
                        .background(Atelier.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Sheets").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text(engine.sheetURL == nil ? "Még nincs létrehozott táblázat" : "A táblázatod használatra kész")
                            .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                    Spacer()
                    if engine.sheetURL != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Atelier.mint).font(.system(size: 21))
                    }
                }
                if engine.account.loggedIn {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle").foregroundStyle(Atelier.mist)
                        Text(engine.account.email).lineLimit(1).truncationMode(.middle)
                            .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                }
                if let url = engine.sheetURL {
                    Button { openURL(url) } label: {
                        ActionLabel(title: "Saját Google Sheets megnyitása", symbol: "arrow.up.right.square")
                    }.buttonStyle(PressFeedback())
                    .accessibilityHint("Megnyitja a bejelentkezett fiókhoz létrehozott ÓraNapló-táblázatot")
                    Button { Task { await engine.prepareGoogleSheet() } } label: {
                        ActionLabel(title: "Függő adatok feltöltése", symbol: "arrow.clockwise", primary: false, trailing: "chevron.right")
                    }.disabled(engine.busy).buttonStyle(PressFeedback())
                } else if engine.account.loggedIn {
                    Button { Task { await engine.prepareGoogleSheet() } } label: {
                        ActionLabel(title: "Google Sheets létrehozása", symbol: "plus.square.on.square")
                    }.disabled(engine.busy).buttonStyle(PressFeedback())
                } else {
                    Button { Task { await engine.login() } } label: {
                        ActionLabel(title: "Google-fiók csatlakoztatása", symbol: "person.crop.circle.badge.checkmark", trailing: "arrow.right")
                    }.buttonStyle(PressFeedback())
                }
            }
        }
    }

    private var syncCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: "Adatmentés", symbol: "arrow.triangle.2.circlepath")
                    if engine.busy { ProgressView().tint(Atelier.azure) }
                }
                HStack(spacing: 12) {
                    smallValue(title: "Utolsó mentés", value: engine.lastSync == "–" ? "Még nincs" : "Elérhető")
                    Rectangle().fill(Atelier.line).frame(width: 1, height: 42)
                    smallValue(title: "Várakozó sorok", value: "\(engine.pendingCount)")
                }
                Button { Task { await engine.sync() } } label: {
                    ActionLabel(title: engine.busy ? "Szinkronizálás…" : "Egészségadatok szinkronizálása", symbol: "heart.text.square", primary: false, trailing: "arrow.clockwise")
                }.disabled(engine.busy || !engine.account.loggedIn).buttonStyle(PressFeedback())
                if !engine.fullHealthFlowCompleted {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(Atelier.azure)
                        Text("Ehhez engedélyezett HealthKit-hozzáférés kell. Az ingyenes Sideloadly-aláírásból ez hiányozhat.")
                            .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                }
            }
        }
    }

    private func smallValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(Atelier.mist)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        MetalSurface {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Rendszerállapot", symbol: "checkmark.shield")
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(engine.busy ? Atelier.azure : Atelier.mint)
                        .frame(width: 8, height: 8).padding(.top, 5)
                    Text(engine.status)
                        .font(.system(size: 13)).foregroundStyle(Atelier.ice.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if engine.busy {
                    ProgressView().tint(Atelier.azure)
                }
            }
        }
    }

    private var measurements: some View {
        AppCanvas {
            pageHeader(eyebrow: "ADATGYŰJTÉS", title: "Mérések", subtitle: "Válaszd ki, mely adatokat szeretnéd a saját táblázatodba menteni.")
            MetalSurface {
                VStack(spacing: 14) {
                    SectionTitle(title: "Adatkategóriák", symbol: "waveform.path.ecg")
                    ForEach(Catalog.groups, id: \.0) { group in
                        HStack(spacing: 12) {
                            Image(systemName: groupIcon(group.0))
                                .foregroundStyle(Atelier.azure)
                                .frame(width: 26)
                            Toggle(group.1, isOn: Binding(
                                get: { engine.enabledGroups.contains(group.0) },
                                set: { _ in engine.toggleGroup(group.0) }
                            ))
                            .tint(Atelier.azure)
                            .font(.system(size: 14, weight: .medium))
                        }
                        if group.0 != Catalog.groups.last?.0 {
                            Rectangle().fill(Atelier.line).frame(height: 1)
                        }
                    }
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: "Korábbi adatok", symbol: "clock.arrow.circlepath")
                    Text("Előzmények beolvasása").font(.system(size: 13)).foregroundStyle(Atelier.mist)
                    Picker("Időszak", selection: Binding(get: { engine.selectedDays }, set: { engine.setDays($0) })) {
                        Text("30 nap").tag(30)
                        Text("1 év").tag(365)
                        Text("5 év").tag(1825)
                    }.pickerStyle(.segmented)
                    Text("Első próbához 30 napot ajánlunk. Hosszabb időszakban sok mérés gyűlhetett össze.")
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    Button { Task { await engine.sync() } } label: {
                        ActionLabel(title: "Adatok mentése Google Sheetsbe", symbol: "arrow.up.doc", trailing: "arrow.clockwise")
                    }.disabled(engine.busy || !engine.account.loggedIn).buttonStyle(PressFeedback())
                }
            }
            if !engine.fullHealthFlowCompleted {
                Text("A HealthKit hozzáférés beállítását a Beállítások fülön találod.")
                    .font(.system(size: 12)).foregroundStyle(Atelier.mist).padding(.horizontal, 4)
            }
        }
    }

    private var journal: some View {
        AppCanvas {
            pageHeader(eyebrow: "SZEMÉLYES NAPLÓ", title: "Jegyezd fel.", subtitle: "Az eseményeket időbélyeggel a saját Naplo-munkalapodra mentjük.")
            MetalSurface {
                VStack(alignment: .leading, spacing: 17) {
                    SectionTitle(title: "Új bejegyzés", symbol: "square.and.pencil")
                    Picker("Bejegyzés típusa", selection: $journalKind) {
                        Text("Közérzet").tag("Közérzet")
                        Text("Gyógyszer").tag("Gyógyszerbevétel")
                        Text("Egyéb").tag("Egyéb")
                    }.pickerStyle(.segmented)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.055))
                        if journalText.isEmpty {
                            Text("Mi történt? Írj egy rövid feljegyzést…")
                                .font(.system(size: 14)).foregroundStyle(Atelier.mist.opacity(0.7))
                                .padding(.horizontal, 15).padding(.vertical, 16)
                        }
                        TextEditor(text: $journalText)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 10)
                            .frame(minHeight: 126)
                    }.frame(minHeight: 126)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Atelier.line))
                    Button {
                        let note = journalText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !note.isEmpty else { return }
                        journalText = ""
                        Task { await engine.addJournalEntry(kind: journalKind, note: note) }
                    } label: {
                        ActionLabel(title: "Naplóbejegyzés mentése", symbol: "square.and.arrow.down", trailing: "checkmark")
                    }.disabled(!engine.account.loggedIn || journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(PressFeedback())
                    if !engine.account.loggedIn {
                        Text("A napló használatához először csatlakoztasd a Google-fiókodat.")
                            .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                    }
                }
            }
            if let url = engine.sheetURL {
                Button { openURL(url) } label: {
                    ActionLabel(title: "Naplóm megnyitása Google Sheetsben", symbol: "tablecells", primary: false)
                }.buttonStyle(PressFeedback())
            }
        }
    }

    private var settings: some View {
        AppCanvas {
            pageHeader(eyebrow: "BEÁLLÍTÁSOK", title: "A te rendszered.", subtitle: "Hozzáférések, fiók és műszaki állapot.")
            MetalSurface {
                VStack(alignment: .leading, spacing: 15) {
                    SectionTitle(title: "Google-fiók", symbol: "person.crop.circle")
                    Text(engine.account.loggedIn ? engine.account.email : "Nincs csatlakoztatott Google-fiók")
                        .font(.system(size: 13)).foregroundStyle(Atelier.mist)
                    if engine.account.loggedIn {
                        Button { Task { await engine.disconnectGoogle() } } label: {
                            ActionLabel(title: "Fiók leválasztása", symbol: "rectangle.portrait.and.arrow.right", primary: false, trailing: "chevron.right")
                        }.buttonStyle(PressFeedback())
                    } else {
                        Button { Task { await engine.login() } } label: {
                            ActionLabel(title: "Google-fiók csatlakoztatása", symbol: "person.crop.circle.badge.checkmark")
                        }.buttonStyle(PressFeedback())
                    }
                    if let url = engine.sheetURL {
                        Button { openURL(url) } label: {
                            ActionLabel(title: "Saját Google Sheets megnyitása", symbol: "tablecells", primary: false)
                        }.buttonStyle(PressFeedback())
                    }
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 15) {
                    SectionTitle(title: "Apple Egészség", symbol: "heart.text.square")
                    Button { Task { await engine.authorizeHealth() } } label: {
                        ActionLabel(title: "Pulzusengedély ellenőrzése", symbol: "heart", primary: false, trailing: "chevron.right")
                    }.buttonStyle(PressFeedback())
                    Button { Task { await engine.authorizeAllHealth() } } label: {
                        ActionLabel(title: "Teljes HealthKit engedélyezése", symbol: "checkmark.shield", primary: false, trailing: "chevron.right")
                    }.disabled(!engine.basicHealthFlowCompleted).buttonStyle(PressFeedback())
                    Text("A teljes hozzáférés csak sikeres alapteszt után kérhető. Ingyenes Sideloadly-aláírásból hiányozhat a HealthKit-jogosultság.")
                        .font(.system(size: 12)).foregroundStyle(Atelier.mist)
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Diagnosztika", symbol: "stethoscope")
                    Text("Legutóbbi művelet: \(CrashCheckpoint.last)")
                        .font(.system(size: 12)).foregroundStyle(Atelier.ice)
                    Text(CrashCheckpoint.environmentSummary)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Atelier.mist)
                    Button {
                        let id = Bundle.main.bundleIdentifier ?? "ismeretlen"
                        UIPasteboard.general.string = "ÓraNapló diagnosztika\nApp ID: \(id)\nUtolsó lépés: \(CrashCheckpoint.last)\n\(CrashCheckpoint.environmentSummary)"
                        engine.status = "Diagnosztika a vágólapra másolva."
                    } label: {
                        ActionLabel(title: "Diagnosztika másolása", symbol: "doc.on.doc", primary: false, trailing: "checkmark")
                    }.buttonStyle(PressFeedback())
                }
            }
            MetalSurface {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Tudnivalók", symbol: "info.circle")
                    Text("A 100 méteres sportelemzéshez megfelelő GPS-útvonal és tényleges pulzusmérések szükségesek. A szinkronizálás időpontját az iOS szabályozza.")
                    Text("Apple Watch akkumulátor, alkalmazásonkénti képernyőidő és szoba CO₂ nem olvasható ki közvetlenül a HealthKitből.")
                    Text("Az alkalmazás nem orvosi diagnosztikai eszköz.")
                }.font(.system(size: 12)).foregroundStyle(Atelier.mist)
            }
        }
    }

    private func pageHeader(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            MicroHeading(text: eyebrow)
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.9).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Atelier.mist)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 10)
    }

    private func groupIcon(_ key: String) -> String {
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
