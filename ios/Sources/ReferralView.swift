import SwiftUI
import AuthenticationServices
import StoreKit
import UIKit

struct ReferralView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var referrals = ReferralService.shared
    @State private var code = ""
    @State private var nonce = ""
    @State private var showRedeemSheet = false
    @AppStorage("oranaplo.app.language") private var languageCode = "hu"
    private var hu: Bool { languageCode == "hu" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ÓraNapló Pro").font(.title2.bold())
                            Text(hu ? "Meghívókód – 50% egy évre" : "Referral – planned 50% for one year")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "person.2.badge.plus").font(.largeTitle).foregroundStyle(.cyan)
                    }
                    GroupBox(hu ? "Hogyan működik?" : "How it works") {
                        Text(hu ? "Normál: tervezett 1000 Ft/év. Egy új felhasználó első regisztrációjakor egyszer válthat be meghívót. Az Apple által visszaigazolt kedvezményes éves előfizetés mindkét félnek 500 Ft-os évet adhat. A meghívott a kedvezményes éve lejárta után egyszer továbbhívhat." : "Planned price: 1000 HUF/year. A new account can redeem once at first signup. After verified Apple payment both parties may qualify for a 500 HUF year. The invitee can invite once after that year ends.")
                            .font(.callout)
                    }
                    if !referrals.configured {
                        Label(hu ? "Supabase nincs beállítva. Ez a fejlesztői előnézet." : "Supabase not configured; development preview.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if !ReferralService.publicOffersEnabled {
                        Label(hu ? "A kedvezményes vásárlás biztonsági okból le van tiltva, amíg nincs Apple-ajánlat és szerveres vásárlásellenőrzés." : "Discount purchases are locked until App Store offers and server verification are ready.", systemImage: "lock.shield")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if !referrals.signedIn {
                        Text(hu ? "A meghívási fiókhoz Apple-fiókos bejelentkezés szükséges." : "Sign in with Apple to use referrals.")
                            .font(.footnote)
                        SignInWithAppleButton(.signIn, onRequest: { request in
                            nonce = ReferralService.randomNonce()
                            request.requestedScopes = [.email]
                            request.nonce = ReferralService.hashedNonce(nonce)
                        }, onCompletion: { result in
                            if case .success(let auth) = result,
                               let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                                Task { await referrals.signIn(credential: credential, rawNonce: nonce) }
                            }
                        })
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .disabled(!referrals.configured)
                    } else {
                        if let state = referrals.status {
                            GroupBox(hu ? "Saját meghívókódod" : "Your invite code") {
                                HStack {
                                    Text(state.inviteCode).font(.title2.monospaced().bold()).textSelection(.enabled)
                                    Spacer()
                                    Button { UIPasteboard.general.string = state.inviteCode } label: { Image(systemName: "doc.on.doc") }
                                }
                                Text(state.canInvite ? (hu ? "Meghívhatsz egy ismerőst." : "You may invite one person.") : (hu ? "A meghívásod még nem jogosult vagy már felhasználtad." : "Inviting not yet eligible or already used."))
                                    .font(.footnote)
                            }
                            GroupBox(hu ? "Saját kedvezményed" : "Your discount") {
                                Text("Meghívottként: \(state.inviteeOffer)\nMeghívóként: \(state.inviterOffer)")
                                    .font(.callout.monospaced())
                            }
                        }
                        TextField(hu ? "Ismerős meghívókódja" : "Friend's invite code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button(hu ? "Meghívókód beváltása" : "Redeem invitation") { Task { await referrals.redeem(code) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(referrals.busy || !ReferralService.publicOffersEnabled)
                        Button(hu ? "Apple kedvezménykód igénylése" : "Request Apple offer code") { Task { await referrals.requestOffer() } }
                            .buttonStyle(.bordered)
                            .disabled(referrals.busy || !ReferralService.publicOffersEnabled)
                        if let appleCode = referrals.appleOfferCode {
                            Text(appleCode).font(.callout.monospaced()).textSelection(.enabled)
                            Button(hu ? "Beváltás az App Store-ban" : "Redeem in App Store") { showRedeemSheet = true }
                                .buttonStyle(.borderedProminent)
                                .offerCodeRedemption(isPresented: $showRedeemSheet) { _ in
                                    Task { await SubscriptionManager.shared.refreshEntitlement() }
                                }
                        }
                        Button(hu ? "Kijelentkezés" : "Sign out") { referrals.logout() }
                            .font(.footnote)
                    }
                    if !referrals.feedback.isEmpty { Text(referrals.feedback).foregroundStyle(.orange).font(.footnote) }
                    Text(hu ? "Nem orvosi funkció. A kedvezmény csak a tényleges Apple-vásárlási képernyőn feltüntetett feltételekkel érvényes." : "Not a medical feature. Final pricing and terms are determined by Apple checkout.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle(hu ? "Meghívások" : "Referrals")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(hu ? "Kész" : "Done") { dismiss() } } }
            .task { await referrals.reload() }
        }
    }
}
