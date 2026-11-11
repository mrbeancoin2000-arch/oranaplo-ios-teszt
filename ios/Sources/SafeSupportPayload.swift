import Foundation

/// A deliberately minimal report contract: no notes, names, HealthKit samples,
/// route, GPS position, spreadsheet IDs, account addresses or access tokens.
struct SafeSupportPayload: Encodable {
    enum Category: String, CaseIterable, Identifiable {
        case sync, running, google, watch, purchase, other
        var id: String { rawValue }
    }
    let category: String
    let app_version: String
    let platform: String
    let reason_code: String
    let event_codes: [String]

    init(category: Category, reasonCode: String, version: String) {
        self.category = category.rawValue
        self.app_version = String(version.prefix(32))
        self.platform = "iOS"
        let allowed: Set<String> = ["none", "network", "authorization", "quota", "unknown"]
        self.reason_code = allowed.contains(reasonCode) ? reasonCode : "unknown"
        self.event_codes = SafeDiagnosticTrail.lastCodes()
    }
}
