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
                    await engine.refreshCount()
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

struct ContentView: View {
    @EnvironmentObject var engine: SyncEngine
    private let ink = Color(red: 0.045, green: 0.075, blue: 0.115)
    private let panel = Color(red: 0.09, green: 0.13, blue: 0.19)
    private let accent = Color(red: 0.44, green: 0.70, blue: 0.96)
    @State private var journalKind = "Közérzet"
    @State private var journalText = ""
    var body: some View {
        ZStack {
            LinearGradient(colors: [ink, .black], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(accent)
                        Text("ÓraNapló").font(.title2.weight(.semibold))
                        Spacer()
                        Text("BÉTA").font(.system(size: 10, weight: .bold, design: .rounded)).padding(7)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }.padding(.top, 12)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Az adataid.\nA saját táblázatodban.")
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1.2)
                        Text("Apple Health → Google Sheets. Nem készítünk külön adatnéző oldalt, és nem kérünk Gmail-jelszót.")
                            .foregroundStyle(.white.opacity(0.7)).font(.subheadline)
                    }.padding(.vertical, 10)
                    statusCard
                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            section("1. Engedélyek", icon: "lock.shield")
                            Button { Task { await engine.authorizeHealth() } } label: { buttonLabel("Apple Egészség engedélyezése", "heart.text.square", secondary: true) }
                            Button { Task { await engine.login() } } label: { buttonLabel(engine.account.loggedIn ? "Google: \(engine.account.email)" : "Google-fiók csatlakoztatása", "person.crop.circle") }
                            if engine.account.loggedIn {
                                Button("Google-fiók leválasztása") { engine.account.signOut() }.font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 16) {
                            section("2. Mit mentsünk?", icon: "slider.horizontal.3")
                            ForEach(Catalog.groups, id: \.0) { group in
                                Toggle(group.1, isOn: Binding(get: { engine.enabledGroups.contains(group.0) }, set: { _ in engine.toggleGroup(group.0) }))
                                    .tint(accent)
                            }
                            Divider().overlay(.white.opacity(0.1))
                            Text("Előzmények importálása").font(.subheadline.weight(.medium))
                            Picker("Időszak", selection: Binding(get: { engine.selectedDays }, set: { engine.setDays($0) })) {
                                Text("30 nap").tag(30); Text("1 év").tag(365); Text("5 év").tag(1825)
                            }.pickerStyle(.segmented)
                            Text("A teljes előzmény nagy mennyiségű adat lehet. Az első próba 30 nappal ajánlott.")
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            section("3. Adatmentés", icon: "square.and.arrow.up")
                            Button { Task { await engine.sync() } } label: { buttonLabel(engine.busy ? "Dolgozunk…" : "Adatok mentése Google Sheetsbe", "arrow.triangle.2.circlepath") }
                                .disabled(engine.busy || !engine.account.loggedIn)
                            if let url = engine.sheetURL {
                                Link(destination: url) { buttonLabel("Google Sheets megnyitása", "arrow.up.right.square", secondary: true) }
                            }
                            Text("Az adatok először helyben sorba kerülnek. Internetkimaradáskor a következő próbálkozáskor folytatjuk. A háttérfutás idejét az iOS határozza meg.")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            section("Egyéni napló", icon: "square.and.pencil")
                            Picker("Bejegyzés típusa", selection: $journalKind) {
                                Text("Közérzet").tag("Közérzet")
                                Text("Gyógyszerbevétel").tag("Gyógyszerbevétel")
                                Text("Egyéb").tag("Egyéb")
                            }.pickerStyle(.segmented)
                            TextField("Rövid feljegyzés…", text: $journalText, axis: .vertical)
                                .lineLimit(2...4).padding(12)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            Button {
                                let content = journalText
                                journalText = ""
                                Task { await engine.addJournalEntry(kind: journalKind, note: content) }
                            } label: { buttonLabel("Naplóbejegyzés mentése", "square.and.arrow.down") }
                            Text("Az egészségadatokhoz nem írunk hozzá; a megjegyzés a saját táblázat Naplo fülére kerül.")
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            section("Fontos korlátok", icon: "info.circle")
                            Text("A 100 méteres futó- és gyalogló szakaszokat csak mentett, megfelelő GPS-útvonal alapján lehet kiszámítani. Pulzusérték csak meglévő mintákból kerül melléjük.")
                            Text("Apple Watch akkumulátor, alkalmazásonkénti képernyőidő és szoba CO₂ nem olvasható ki a HealthKitből. Ezek nem részei ennek az iPhone-változatnak.")
                        }.font(.footnote).foregroundStyle(.white.opacity(0.72))
                    }
                    Text("ÓraNapló · helyi és saját Google-fiókos adatkezelés · orvosi diagnózisra nem alkalmas")
                        .font(.caption2).foregroundStyle(.white.opacity(0.42)).frame(maxWidth: .infinity)
                }.padding(20).frame(maxWidth: 700)
            }
        }
    }
    private var statusCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: engine.busy ? "clock.arrow.circlepath" : "checkmark.shield").foregroundStyle(accent).font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text("Rendszerállapot").font(.headline)
                Text(engine.status).font(.footnote).foregroundStyle(.white.opacity(0.7))
                Text("Utolsó szinkron: \(engine.lastSync) · Várakozó sorok: \(engine.pendingCount)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(LinearGradient(colors: [Color.blue.opacity(0.23), panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }
    private func section(_ name: String, icon: String) -> some View {
        HStack { Image(systemName: icon).foregroundStyle(accent); Text(name).font(.headline) }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))
    }
    private func buttonLabel(_ label: String, _ icon: String, secondary: Bool = false) -> some View {
        HStack { Image(systemName: icon); Text(label).font(.subheadline.weight(.semibold)); Spacer() }
            .foregroundStyle(secondary ? .white : ink)
            .padding(14).background(secondary ? Color.white.opacity(0.08) : accent, in: RoundedRectangle(cornerRadius: 12))
    }
}
