import Foundation

/// Release-only public pages. Enter the HTTPS root of your verified Cloudflare
/// Pages/custom-domain website after publishing `website/`.
/// Keep empty during local development: do not publish fictitious legal links.
enum ReleaseLinks {
    static let websiteRoot = "" // e.g. https://YOUR-VERIFIED-DOMAIN (no trailing slash)

    static func page(_ path: String, language: AppLanguage) -> URL? {
        let root = websiteRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty, root.hasPrefix("https://"),
              !root.contains("YOUR-VERIFIED-DOMAIN"),
              var components = URLComponents(string: root),
              components.host != nil, components.user == nil, components.password == nil else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = components.path.isEmpty ? "" : "/" + components.path
        components.path = prefix + "/" + language.rawValue + "/" + path + ".html"
        return components.url
    }
}
