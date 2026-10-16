import Foundation

public struct UsageTotal: Identifiable {
    public var id: String { name }
    public let name: String
    public var seconds: TimeInterval
    public var visits: Int
}

public enum ActivityAnalytics {
    public static func clipped(_ events: [Activity], from start: Date, to end: Date) -> [Activity] {
        events.compactMap { event in
            if event.kind == "history" { return event.start >= start && event.start < end ? event : nil }
            guard event.start < end, event.end > start else { return nil }
            var part = event
            part.start = max(start, event.start); part.end = min(end, event.end)
            return part.duration > 0 ? part : nil
        }
    }
    public static func mediaName(_ event: Activity) -> String? {
        guard let raw = event.url, BrowserPolicy.capturesMediaTitle(raw), let url = URL(string: raw),
              !event.title.isEmpty, event.title != raw, !["netflix", "youtube", "prime video"].contains(event.title.lowercased()) else { return nil }
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" || host.hasSuffix("youtube.com") {
            guard url.path == "/watch" || url.path.hasPrefix("/shorts/") || host == "youtu.be" else { return nil }
        } else {
            guard url.path.contains("/detail/") || url.path.contains("/video/") || url.path.hasPrefix("/watch/") else { return nil }
        }
        return event.title
    }
    public static func totals(_ events: [Activity], media: Bool = false) -> [UsageTotal] {
        var values: [String: UsageTotal] = [:]
        for event in events where event.duration > 0 {
            guard let name = media ? mediaName(event) : event.app else { continue }
            var value = values[name] ?? UsageTotal(name: name, seconds: 0, visits: 0)
            value.seconds += event.duration; value.visits += 1
            values[name] = value
        }
        return values.values.sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
}

public struct ContextTotal: Identifiable {
    public var id: String
    public var title: String
    public var service: String
    public var url: String?
    public var seconds: TimeInterval
    public var lastSeen: Date
    public var historyVisits: Int
}

extension ActivityAnalytics {
    public static func service(_ event: Activity) -> String {
        if let raw = event.url, let host = URL(string: raw)?.host?.lowercased() {
            func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
            if matches("youtube.com") || matches("youtu.be") { return "YouTube" }
            if matches("netflix.com") { return "Netflix" }
            if matches("primevideo.com") || (capturesAmazonVideo(raw)) { return "Prime Video" }
            if BrowserPolicy.isAmazonProduct(raw) { return "Amazon" }
            if matches("substack.com") { return "Substack" }
            if matches("reddit.com") || matches("redd.it") { return "Reddit" }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if event.app.lowercased().contains("obsidian") { return "Obsidian" }
        if event.app.lowercased().contains("netflix") { return "Netflix" }
        if event.app.lowercased().contains("primevideo") { return "Prime Video" }
        return event.title
    }
    private static func capturesAmazonVideo(_ raw: String) -> Bool {
        BrowserPolicy.capturesMediaTitle(raw) && URL(string: raw)?.host?.contains("amazon.") == true
    }
    public static func contexts(_ events: [Activity]) -> [ContextTotal] {
        var values: [String: ContextTotal] = [:]
        for event in events.sorted(by: { $0.kind == "history" && $1.kind != "history" ? false : $0.kind != "history" && $1.kind == "history" ? true : $0.start > $1.start }) where (event.duration > 0 || event.kind == "history") && event.url != nil {
            let service = service(event)
            // Legacy YouTube watch URLs lost the video ID; only those need title identity.
            let legacyWatch = service == "YouTube" && URL(string: event.url ?? "")?.path == "/watch" && URLComponents(string: event.url ?? "")?.queryItems?.contains(where: { $0.name == "v" }) != true
            let searchPath = URL(string: event.url ?? "")?.path ?? ""
            let querylessSearch = ["/search", "/results", "/s"].contains(searchPath)
            let key = (legacyWatch || querylessSearch) && event.title != event.url ? service + "|" + event.title : (event.url ?? "")
            var value = values[key] ?? ContextTotal(id: key, title: event.title, service: service, url: event.url, seconds: 0, lastSeen: event.end, historyVisits: 0)
            if (value.title == value.url || ["Substack", "YouTube", "Netflix"].contains(value.title)), event.title != event.url && !["Substack", "YouTube", "Netflix"].contains(event.title) {
                value.title = event.title
            }
            value.lastSeen = max(value.lastSeen, event.end)
            if event.kind == "history" { value.historyVisits += 1 }
            value.seconds += event.duration; values[key] = value
        }
        return values.values.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
    }
    public static func serviceTotals(_ events: [Activity]) -> [UsageTotal] {
        var values: [String: UsageTotal] = [:]
        for event in events where event.duration > 0 {
            let name = service(event)
            guard !["loginwindow", "SecurityAgent"].contains(name) else { continue }
            var value = values[name] ?? UsageTotal(name: name, seconds: 0, visits: 0)
            value.seconds += event.duration; value.visits += 1; values[name] = value
        }
        return values.values.sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
}

public enum ActivityCategory: String, CaseIterable, Identifiable {
    case articles = "Articles", shopping = "Shopping", youtube = "YouTube", streaming = "Streaming"
    public var id: String { rawValue }
    public static func category(for event: Activity) -> ActivityCategory? {
        guard let raw = event.url else { return nil }
        let service = ActivityAnalytics.service(event)
        if service == "YouTube" { return .youtube }
        if ["Netflix", "Prime Video"].contains(service) { return .streaming }
        let host = URL(string: raw)?.host?.lowercased() ?? ""
        let retailHost = host.hasPrefix("amazon.") || ["www.", "smile.", "m."].contains(where: { host.hasPrefix($0 + "amazon.") })
        if BrowserPolicy.isAmazonStore(raw), retailHost { return .shopping }
        return .articles
    }
}
