import SwiftUI
import MacJournalCore

struct DashboardView: View {
    @ObservedObject var recorder: Recorder
    @ViewState private var range = 7
    @ViewState private var recentFirst = true
    @ViewState private var search = ""
    @ViewState private var category: ActivityCategory = .articles
    @ViewState private var expandedSections: Set<String> = []
    private var events: [Activity] {
        let start = range == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -(range - 1), to: Calendar.current.startOfDay(for: Date()))!
        return ActivityAnalytics.clipped(recorder.history, from: start, to: Date())
    }
    private func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : m > 0 ? "\(m)m" : "\(Int(seconds))s"
    }
    private func contextSummary(_ item: ContextTotal) -> String {
        let visits = item.historyVisits > 0 ? "\(item.historyVisits) visit\(item.historyVisits == 1 ? "" : "s") · " : ""
        return visits + (item.seconds > 0 ? duration(item.seconds) : "time unknown")
    }
    private func serviceItems(_ name: String) -> [ContextTotal] {
        let items = ActivityAnalytics.contexts(events.filter { ActivityAnalytics.service($0) == name })
        // Put resolved player titles ahead of older generic Netflix records.
        return name == "Netflix" ? items.sorted {
            let left = $0.title.hasPrefix("Netflix · "), right = $1.title.hasPrefix("Netflix · ")
            return left != right ? left : $0.seconds > $1.seconds
        } : items
    }
    private var youtubeTitles: [ContextTotal] {
        serviceItems("YouTube").filter { $0.title != $0.url }
    }
    private var youtubeLegacy: [ContextTotal] {
        serviceItems("YouTube").filter { $0.title == $0.url }
    }
    private func categoryEvents(_ category: ActivityCategory) -> [Activity] {
        events.filter { ActivityCategory.category(for: $0) == category }
    }
    private func categoryItems(_ category: ActivityCategory) -> [ContextTotal] {
        let items = ActivityAnalytics.contexts(categoryEvents(category))
        let matching = items.filter { search.isEmpty || [$0.title, $0.service, $0.url ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) }
        if recentFirst { return matching.sorted { $0.lastSeen > $1.lastSeen } }
        return category == .streaming ? matching.sorted {
            let left = $0.title != $0.url && $0.title != "Netflix"
            let right = $1.title != $1.url && $1.title != "Netflix"
            return left != right ? left : $0.seconds > $1.seconds
        } : matching
    }
    private func icon(_ category: ActivityCategory) -> String {
        switch category {
        case .articles: "doc.text"
        case .shopping: "bag"
        case .youtube: "play.rectangle"
        case .streaming: "film"
        }
    }
    private var emptyMessage: String {
        switch category {
        case .articles: "Blog articles, Reddit threads, Substack posts, and other visited pages appear here."
        case .shopping: "Amazon products and shopping pages appear here."
        case .youtube: "YouTube videos and channel pages appear here."
        case .streaming: "Netflix and Prime Video titles appear here."
        }
    }
    private func activitySection(_ title: String, icon: String, items: [ContextTotal], empty: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: icon).font(.title2.bold())
                if items.isEmpty { Text(empty).foregroundStyle(.secondary) }
                ForEach(expandedSections.contains(title) ? items : Array(items.prefix(40))) { item in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title == item.url ? "\(item.service) page · title unavailable" : item.title).font(.headline).textSelection(.enabled)
                            Text(item.service).font(.caption).foregroundStyle(.teal)
                            if let raw = item.url { Text(raw).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        Spacer()
                        Text(contextSummary(item)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    }
                    Divider()
                }
                if items.count > 40 {
                    Button(expandedSections.contains(title) ? "Show fewer" : "Show all \(items.count) entries") {
                        if expandedSections.contains(title) { expandedSections.remove(title) } else { expandedSections.insert(title) }
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What filled your day").font(.largeTitle.bold())
                        Text(recorder.isDemo ? "DEMO PREVIEW · Synthetic sample activities" : "Videos, threads, pages, and time spent.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Set(events.map(\.app)).count) apps used").font(.caption).padding(9).background(.teal.opacity(0.15), in: Capsule())
                    Picker("Period", selection: $range) {
                        Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("All time").tag(0)
                    }.frame(width: 145)
                }
                HStack(spacing: 12) {
                    ForEach(ActivityCategory.allCases) { option in
                        Button { category = option } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(option.rawValue, systemImage: icon(option)).font(.headline)
                                Text("\(categoryItems(option).count) entries · \(duration(categoryEvents(option).reduce(0) { $0 + $1.duration }))").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(category == option ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(category == option ? Color.teal : Color.clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityLabel(option.rawValue)
                            .accessibilityAddTraits(category == option ? .isSelected : [])
                    }
                }
                HStack {
                    TextField("Search titles, sites, and links", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $recentFirst) { Text("Recent").tag(true); Text("Time spent").tag(false) }.pickerStyle(.segmented).frame(width: 190)
                }
                activitySection(category.rawValue, icon: icon(category), items: categoryItems(category).filter { category != .youtube || $0.title != $0.url }, empty: search.isEmpty ? emptyMessage : "No matching activity in this category and period.")
                if category == .youtube && !youtubeLegacy.isEmpty {
                    DisclosureGroup("Older YouTube records · \(duration(youtubeLegacy.reduce(0) { $0 + $1.seconds })) · no saved titles") {
                        Text("These entries predate title capture. Watch URLs had their video IDs removed, so their titles cannot be recovered reliably.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        ForEach(youtubeLegacy) { item in
                            HStack { Text(item.url ?? "YouTube").font(.caption).textSelection(.enabled); Spacer(); Text(duration(item.seconds)).font(.caption) }
                        }
                    }
                }
                DisclosureGroup("Time across all apps & sites") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ActivityAnalytics.serviceTotals(events).prefix(15)) { item in
                            HStack {
                                Text(item.name); Spacer()
                                Text(duration(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("History supplies visits and page titles; visit counts come from Chrome history only. Time is captured foreground activity, not verified playback or completion. Idle pauses still apply. Earlier URL-only records cannot recover titles. Obsidian time is available at app level; vault and note names are not captured yet. Private/incognito windows are excluded before metadata is read.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}
