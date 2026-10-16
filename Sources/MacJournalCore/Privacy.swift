import Foundation

public struct Exclusions: Codable, Equatable {
    public var apps: [String]
    public var urls: [String]
    public var keywords: [String]
    public init(apps: [String] = ["com.1password", "com.agilebits", "com.bitwarden", "com.apple.keychainaccess", "com.keepass", "com.dashlane", "org.mozilla.firefox", "com.brave", "com.microsoft.edgemac", "company.thebrowser", "com.operasoftware", "com.vivaldi"], urls: [String] = ["bank", "banking", "paypal.com", "accounts.google.com", "login", "signin"], keywords: [String] = ["private", "incognito", "password", "banking", "sign in", "log in"]) {
        self.apps = apps; self.urls = urls; self.keywords = keywords
    }
    public func blocks(app: String, title: String, url: String?) -> Bool {
        apps.contains { !$0.isEmpty && app.localizedCaseInsensitiveContains($0) } ||
        keywords.contains { !$0.isEmpty && title.localizedCaseInsensitiveContains($0) } ||
        urls.contains { !$0.isEmpty && (url ?? "").localizedCaseInsensitiveContains($0) }
    }
}

public enum Redactor {
    public static func clean(_ input: String) -> String {
        let patterns = [
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"\b(?:\d[ -]?){13,19}\b"#,
            #"(?i)\b(?:bearer\s+|(?:api[_-]?key|token|secret|password)\s*[:=]\s*)[^\s,;]+"#,
            #"\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b"#
        ]
        return patterns.reduce(input) { text, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
            return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
        }
    }
    public static func safeURL(_ input: String?) -> String? {
        guard let input, var parts = URLComponents(string: input), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else { return nil }
        let host = parts.host?.lowercased() ?? ""
        let videoID = (host == "youtube.com" || host.hasSuffix(".youtube.com")) && parts.path == "/watch"
            ? parts.queryItems?.first(where: { $0.name == "v" })?.value : nil
        parts.user = nil; parts.password = nil; parts.query = nil; parts.fragment = nil
        // A public video ID is identity, not a tracking/search query. Keep only v.
        if let videoID, videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
            parts.queryItems = [URLQueryItem(name: "v", value: videoID)]
        }
        return parts.string.map(clean)
    }
}
