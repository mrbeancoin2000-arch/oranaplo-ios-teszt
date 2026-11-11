import Foundation

@main struct OpsRuntimeTests {
    static func main() throws {
        for language in AppLanguage.allCases {
            for key in ["sync.title", "sync.lastSuccess", "sync.pending", "sync.failure", "sync.network", "privacy.confirm", "privacy.localHelp", "support.title", "support.sent", "support.rateLimited", "run.recover.title", "run.recover.resume", "run.recover.damaged"] {
                let text = OpsText.t(key, language)
                precondition(!text.isEmpty && text != key, "Missing localized text: \(language.rawValue) \(key)")
            }
        }
        SafeDiagnosticTrail.mark(.syncStarted)
        SafeDiagnosticTrail.mark(.syncFailed)
        let payload = SafeSupportPayload(category: .sync, reasonCode: "185 bpm 47.1,19.4", version: "0.6.0")
        let serialized = try JSONEncoder().encode(payload)
        let text = String(decoding: serialized, as: UTF8.self)
        precondition(payload.reason_code == "unknown")
        precondition(!text.contains("185") && !text.contains("47.1"))
        precondition(payload.event_codes.suffix(2) == ["sync.started","sync.failed"])
        let decoded = try JSONSerialization.jsonObject(with:serialized) as! [String:Any]
        precondition(Set(decoded.keys) == Set(["category","reason_code","app_version","platform","event_codes"]))
        print("PASS: 3 locales + only-safe-support-fields")
    }
}
