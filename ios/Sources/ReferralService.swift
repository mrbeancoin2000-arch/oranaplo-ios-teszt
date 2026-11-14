import Foundation
import Combine
import Security
import AuthenticationServices
import CryptoKit
import StoreKit

private struct ReferralConfig: Decodable {
    let supabase_url: String
    let supabase_publishable_key: String
    var valid: Bool {
        supabase_url.hasPrefix("https://") && !supabase_url.contains("YOUR_")
        && supabase_publishable_key.count > 35 && !supabase_publishable_key.contains("YOUR_")
    }
    static var current: Self? {
        guard let url = Bundle.main.url(forResource: "leaderboard_config", withExtension: "json"),
              let bytes = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: bytes)
    }
}
private struct ReferralSession: Codable {
    let userID: UUID
    let access: String
    let refresh: String
    let expiresAt: Date
}
private enum ReferralSessionStorage {
    static let key = "hu.oranaplo.referral.apple.session.v1"
    static func read() -> ReferralSession? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecMatchLimit as String: kSecMatchLimitOne,
                                kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let bytes = item as? Data else { return nil }
        return try? JSONDecoder().decode(ReferralSession.self, from: bytes)
    }
    static func save(_ session: ReferralSession) {
        guard let bytes = try? JSONEncoder().encode(session) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccount as String: key,
                                     kSecValueData as String: bytes,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(attrs as CFDictionary, nil)
    }
    static func erase() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

struct ReferralStatus: Decodable {
    let inviteCode: String
    let claimState: String
    let inviteeOffer: String
    let inviterOffer: String
    let discountYearEnd: String?
    let canInvite: Bool
    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code", claimState = "claim_state"
        case inviteeOffer = "invitee_offer", inviterOffer = "inviter_offer"
        case discountYearEnd = "discount_year_end", canInvite = "can_invite"
    }
}

@MainActor
final class ReferralService: ObservableObject {
    static let shared = ReferralService()
    @Published private(set) var status: ReferralStatus?
    @Published private(set) var appleOfferCode: String?
    @Published private(set) var signedIn = ReferralSessionStorage.read() != nil
    @Published private(set) var busy = false
    @Published private(set) var feedback = ""
    // PRE-LAUNCH LOCK: enable only after server-side Apple JWS validation, pricing and abuse testing.
    // This is not permission to use simulated purchases in production.
    static let publicOffersEnabled = false
    var configured: Bool { ReferralConfig.current?.valid == true }
    // A verified Supabase Apple account UUID can be attached to standard StoreKit purchases.
    // Apple offer-code redemption requires separate, verified transaction/account matching.
    var appAccountToken: UUID? { ReferralSessionStorage.read()?.userID }

    static func randomNonce() -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._")
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
    static func hashedNonce(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func signIn(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async {
        guard configured, let data = credential.identityToken,
              let idToken = String(data: data, encoding: .utf8), !idToken.isEmpty else {
            feedback = "Apple-bejelentkezés vagy Supabase konfiguráció hiányzik."; return
        }
        busy = true; defer { busy = false }
        do {
            let obj = try await requestAuth(grant: "id_token", body: [
                "provider": "apple", "id_token": idToken, "nonce": rawNonce])
            try storeSession(obj)
            signedIn = true
            DiagnosticCenter.record(.referralLogin, area: .auth)
            await reload()
        } catch {
            feedback = "Nem sikerült az Apple-bejelentkezés. Ellenőrizd a Supabase Apple providert."
            DiagnosticCenter.record(.referralClaimFailed, area: .auth, severity: .failure)
        }
    }
    func logout() {
        ReferralSessionStorage.erase()
        status = nil; appleOfferCode = nil; signedIn = false
        feedback = "Kijelentkeztél a meghívási fiókból."
    }
    private func storeSession(_ object: [String: Any]) throws {
        guard let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String else { throw URLError(.userAuthenticationRequired) }
        let newUser = object["user"] as? [String: Any]
        let userIDString = (newUser?["id"] as? String)
        let uuid = userIDString.flatMap(UUID.init(uuidString:)) ?? ReferralSessionStorage.read()?.userID
        guard let userID = uuid else { throw URLError(.userAuthenticationRequired) }
        let expiration = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        ReferralSessionStorage.save(ReferralSession(userID: userID, access: access, refresh: refresh,
                                                     expiresAt: Date().addingTimeInterval(max(60, expiration))))
    }
    private func requestAuth(grant: String, body: [String: Any]) async throws -> [String: Any] {
        guard let config = ReferralConfig.current, config.valid,
              let url = URL(string: config.supabase_url + "/auth/v1/token?grant_type=" + grant) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.supabase_publishable_key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.userAuthenticationRequired)
        }
        return dict
    }
    private func accessToken() async throws -> String {
        guard let value = ReferralSessionStorage.read() else { throw URLError(.userAuthenticationRequired) }
        if value.expiresAt > Date().addingTimeInterval(120) { return value.access }
        let obj = try await requestAuth(grant: "refresh_token", body: ["refresh_token": value.refresh])
        try storeSession(obj)
        guard let token = ReferralSessionStorage.read()?.access else { throw URLError(.userAuthenticationRequired) }
        return token
    }
    private func rpc(_ function: String, payload: [String: Any] = [:]) async throws -> Any {
        let allowed: Set<String> = ["oranaplo_referral_status", "oranaplo_referral_redeem", "oranaplo_referral_get_offer"]
        guard allowed.contains(function), let config = ReferralConfig.current, config.valid,
              let url = URL(string: config.supabase_url + "/rest/v1/rpc/" + function) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabase_publishable_key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
    func reload() async {
        guard signedIn else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await rpc("oranaplo_referral_status")
            let data = try JSONSerialization.data(withJSONObject: result)
            status = try JSONDecoder().decode(ReferralStatus.self, from: data)
            feedback = ""
        } catch {
            feedback = "Meghívási állapot nem érhető el."
            DiagnosticCenter.record(.referralClaimFailed, area: .referral, severity: .warning)
        }
    }
    func redeem(_ code: String) async {
        guard Self.publicOffersEnabled else {
            feedback = "A kedvezményes előfizetés még nem éles."
            DiagnosticCenter.record(.referralOfferUnavailable, area: .referral, severity: .warning)
            return
        }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 12, normalized.allSatisfy({ $0.isHexDigit }) else {
            feedback = "A kód pontosan 12 hexadecimális karakterből áll."; return
        }
        busy = true
        DiagnosticCenter.record(.referralClaimAttempt, area: .referral)
        do {
            _ = try await rpc("oranaplo_referral_redeem", payload: ["the_code": normalized])
            feedback = "Meghívókód rögzítve, az Apple-kedvezmény még ellenőrzésre vár."
            DiagnosticCenter.record(.referralClaimPending, area: .referral)
            busy = false
            await reload()
        } catch {
            busy = false
            feedback = "A kód nem váltható be (lejárt, felhasznált vagy nem jogosult)."
            DiagnosticCenter.record(.referralClaimFailed, area: .referral, severity: .failure)
        }
    }
    func requestOffer() async {
        guard Self.publicOffersEnabled else { feedback = "A kedvezmény még nem éles."; return }
        busy = true; defer { busy = false }
        do {
            appleOfferCode = try await rpc("oranaplo_referral_get_offer") as? String
            feedback = appleOfferCode == nil ? "Még nincs rendelkezésre álló Apple-ajánlatkód." : "Apple-ajánlatkód kiadva. A végső árat az Apple felületén ellenőrizd."
        } catch {
            feedback = "A kedvezménykód nem kérhető le."
        }
    }
}
