import Foundation
import MacJournalCore
import GRDB

var passed = 0
func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try condition() else { throw NSError(domain: "MacJournalChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed: \(name)"]) }
    passed += 1
    print("PASS \(name)")
}
func event(_ start: Double, _ end: Double, _ app: String = "Editor", url: String? = nil) -> Activity {
    Activity(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end), app: app, title: "Private test fixture", url: url)
}
let path = FileManager.default.temporaryDirectory.appendingPathComponent("MacJournalChecks-" + UUID().uuidString)
defer {
    for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: path.path + suffix) }
}
do {
    let cleaned = Redactor.clean("me@example.com 4111 1111 1111 1111 token=abc123 Bearer secret123 sk-abcdefghijklmno eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature")
    for secret in ["me@example.com", "4111", "abc123", "secret123", "sk-abcdefghijklmno", "eyJhbGci"] {
        try check(!cleaned.contains(secret), "Redacts \(secret.prefix(5)) pattern")
    }
    try check(Redactor.clean("Read café design notes") == "Read café design notes", "Preserves ordinary Unicode text")
    try check(Redactor.safeURL("https://name:secret@example.com/docs?token=secret#private") == "https://example.com/docs", "Strips URL credentials and query")
    try check(Redactor.safeURL("file:///private/notes") == nil, "Rejects non-web URLs")
    let exclusions = Exclusions()
    try check(exclusions.blocks(app: "com.agilebits.onepassword7", title: "Vault", url: nil), "Excludes password manager")
    try check(exclusions.blocks(app: "Chrome", title: "New INCOGNITO Tab", url: nil), "Excludes private title case-insensitively")
    try check(exclusions.blocks(app: "Chrome", title: "Account", url: "https://mybank.com"), "Excludes banking URL")
    try check(!exclusions.blocks(app: "TextEdit", title: "Notes", url: nil), "Allows ordinary app context")
    try check(SessionGrouper.group([]).isEmpty, "Empty grouping")
    try check(SessionGrouper.group([event(2000,2060), event(0,60), event(100,160), event(2100,2160,"Browser")]).map { $0.events.count } == [2,1,1], "Sorts and separates gap/topic")
    try check(SessionGrouper.group([event(0,60),event(960,1020)]).count == 1, "Inclusive gap boundary")
    try check(SessionGrouper.group([event(0,60,"Safari",url:"https://example.com/a"),event(100,160,"Chrome",url:"https://example.com/b")]).count == 1, "Shared topic host across apps")
    try check(BrowserPolicy.capturesMediaTitle("https://www.youtube.com/watch?v=abc"), "YouTube title capture")
    try check(BrowserPolicy.capturesMediaTitle("https://www.primevideo.com/detail/abc"), "Prime Video title capture")
    try check(BrowserPolicy.capturesMediaTitle("https://www.amazon.in/gp/video/detail/abc"), "Amazon video title capture")
    try check(!BrowserPolicy.capturesMediaTitle("https://youtube.com.example.com/watch") && !BrowserPolicy.capturesMediaTitle("https://www.amazon.in/orders"), "Media title host and path boundaries")
    try check(BrowserPolicy.supportsURLCapture("com.google.Chrome"), "Chrome URL adapter")
    try check(BrowserPolicy.supportsURLCapture("com.brave.Browser") && BrowserPolicy.supportsURLCapture("com.microsoft.edgemac"), "Brave and Edge URL adapters")
    try check(!BrowserPolicy.supportsURLCapture("unknown.browser") && BrowserPolicy.unsupportedBrowser("com.apple.Safari"), "Unsupported browser fails closed")
    try check(!BrowserPolicy.unsupportedBrowser("com.apple.TextEdit"), "Ordinary app remains eligible without AX")
    let store = try ActivityStore(path: path.path, key: "integration-test-only-key")
    try store.save(event(0,100))
    try store.save(event(100,120,"Browser"))
    try check(try store.timeline().count == 2, "Encrypted persistence")
    try check(!String(decoding: Data(contentsOf: path), as: UTF8.self).contains("Private test fixture"), "No plaintext fixture at rest")
    try check(!Data(contentsOf: path).starts(with: Data("SQLite format 3".utf8)), "Encrypted database header")
    var rejectedWrongKey = false
    do { _ = try ActivityStore(path: path.path, key: "wrong-key") } catch { rejectedWrongKey = true }
    try check(rejectedWrongKey, "Rejects wrong database key")
    try store.delete(since: Date(timeIntervalSince1970: 50))
    try check(try store.timeline().count == 1, "Deletes events inside deletion range")
    try check(try store.timeline().first?.duration == 50, "Truncates crossing interval")
    try store.delete(since: nil)
    try check(try store.timeline().isEmpty, "Deletes all activity")
    let day = Calendar.current.startOfDay(for: Date())
    try store.save(Activity(start: day.addingTimeInterval(-60), end: day.addingTimeInterval(60), app: "Editor", title: "Midnight crossing"))
    try store.save(Activity(start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(-3000), app: "Editor", title: "Yesterday"))
    try check(try store.timeline(on: day).count == 1, "Day query includes overlap and excludes yesterday")
    let reopened = try ActivityStore(path: path.path, key: "integration-test-only-key")
    try check(try reopened.timeline().count == 2, "History survives database reopen")
    let notes = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: notes) }
    try check(try JournalNotes.sync(reopened.timeline(), to: notes) == 2, "Notes split across midnight")
    let files = try FileManager.default.contentsOfDirectory(at: notes, includingPropertiesForKeys: nil)
    let content = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
    try check(content.contains("Midnight crossing") && content.contains("Yesterday"), "Historical records exported")
    _ = try JournalNotes.sync(reopened.timeline(), to: notes)
    try check(try FileManager.default.contentsOfDirectory(atPath: notes.path).count == 2, "Repeated exports do not duplicate notes")
    let personal = notes.appendingPathComponent("personal.md")
    try "My writing".write(to: personal, atomically: true, encoding: .utf8)
    _ = try JournalNotes.sync([], to: notes)
    try check(try FileManager.default.contentsOfDirectory(atPath: notes.path) == ["personal.md"], "Deletion synchronizes generated notes and preserves personal files")
    let clipStart = Date(timeIntervalSince1970: 50)
    let clipEnd = Date(timeIntervalSince1970: 150)
    let clipped = ActivityAnalytics.clipped([event(0,100), event(100,200), event(300,400)], from: clipStart, to: clipEnd)
    try check(clipped.count == 2 && clipped.reduce(0, { $0 + $1.duration }) == 100, "Analytics clips intervals to selected period")
    let video = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "A movie - Prime Video", url: "https://www.primevideo.com/detail/abc")
    try check(ActivityAnalytics.totals([video], media: true).first?.seconds == 100, "Media ranking uses captured title and duration")
    let home = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "YouTube", url: "https://www.youtube.com/")
    try check(ActivityAnalytics.totals([home], media: true).isEmpty, "Media analytics excludes provider home page")
    try check(ActivityAnalytics.totals([event(0,100),event(100,200)]).first?.visits == 2, "App visit counts use saved segments")
    let script = BrowserPolicy.metadataScript("com.google.Chrome")!
    try check(script.range(of: "mode of captureWindow is not")!.lowerBound < script.range(of: "set tabURL")!.lowerBound, "Private window guard runs before URL and title reads")
    try check(BrowserPolicy.metadataScript("unknown.browser") == nil, "Unknown browsers cannot run metadata adapter")
    let reddit = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "A useful Reddit thread", url: "https://www.reddit.com/r/books/comments/abc/title/")
    try check(ActivityAnalytics.contexts([reddit]).first?.title == reddit.title, "Reddit titles preserved in activity dashboard")
    try check(ActivityAnalytics.serviceTotals([video]).first?.name == "Prime Video", "Streaming time attributed to service instead of browser")
    let netflix = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "A series", url: "https://www.netflix.com/watch/123")
    try check(ActivityAnalytics.mediaName(netflix) == "A series", "Netflix watch titles recognized")
    let yt1 = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "Video one", url: "https://www.youtube.com/watch")
    let yt2 = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "Video two", url: "https://www.youtube.com/watch")
    try check(ActivityAnalytics.contexts([yt1,yt2]).count == 2, "Distinct YouTube titles survive query stripping")
    try check(Redactor.safeURL("https://www.youtube.com/watch?v=jNQXAC9IVRw&token=secret&list=private#t=30") == "https://www.youtube.com/watch?v=jNQXAC9IVRw", "Keeps YouTube video identity but strips tracking and secrets")
    try check(Redactor.safeURL("https://youtube.com.example.com/watch?v=jNQXAC9IVRw") == "https://youtube.com.example.com/watch", "YouTube ID exception requires genuine domain")
    try check(Redactor.safeURL("https://www.youtube.com/watch?v=secret-value-too-long") == "https://www.youtube.com/watch", "Rejects invalid YouTube video IDs")
    try check(BrowserPolicy.isNetflixWatch("https://www.netflix.com/watch/81340700") && !BrowserPolicy.isNetflixWatch("https://netflix.com.example.com/watch/123"), "Netflix player reader checks domain and watch path")
    try check(script.range(of: "mode of captureWindow is not")!.lowerBound < script.range(of: "execute captureTab")!.lowerBound, "Netflix player script runs only after private window guard")
    try check(script.contains("on error") && script.contains("player-access-disabled"), "Player title failure preserves ordinary tab capture")
    try check(!BrowserPolicy.requiresPermissionRetry(-1712) && !BrowserPolicy.requiresPermissionRetry(-1728), "Transient browser failures retry automatically")
    try check(BrowserPolicy.requiresPermissionRetry(-1743), "Explicit Automation denial does not repeatedly prompt")
    try check(BrowserPolicy.isSubstackArticle("https://substack.com/home/post/p-123") && BrowserPolicy.isSubstackArticle("https://author.substack.com/p/article"), "Substack reader and publication article routes")
    try check(!BrowserPolicy.isSubstackArticle("https://substack.com/") && !BrowserPolicy.isSubstackArticle("https://substack.com.evil.test/p/article"), "Substack reader excludes feed and lookalike domains")
    let postA = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "Weekly notes", url: "https://author.substack.com/p/one")
    let postB = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "Weekly notes", url: "https://author.substack.com/p/two")
    try check(ActivityAnalytics.contexts([postA,postB]).count == 2 && ActivityAnalytics.service(postA) == "Substack", "Substack groups service but preserves different posts with same title")
    var genericPost = postA; genericPost.title = "Substack"
    try check(ActivityAnalytics.contexts([postA,genericPost]).first?.title == "Weekly notes" && ActivityAnalytics.contexts([postA,genericPost]).first?.seconds == 200, "Article placeholder merges into resolved title without losing time")
    try check(BrowserPolicy.isAmazonProduct("https://www.amazon.in/Book/dp/B012345678") && BrowserPolicy.isAmazonProduct("https://www.amazon.co.uk/gp/product/B012345678"), "Amazon product routes and regional storefronts")
    try check(!BrowserPolicy.isAmazonProduct("https://amazon.in.evil.test/dp/B012345678") && !BrowserPolicy.isAmazonProduct("https://www.amazon.in/orders"), "Amazon product classifier rejects lookalikes and account pages")
    let product = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "A useful book", url: "https://www.amazon.in/dp/B012345678")
    try check(ActivityAnalytics.service(product) == "Amazon" && ActivityAnalytics.contexts([product]).first?.title == "A useful book", "Amazon product name and service appear in analytics")
    let productOther = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "A useful book", url: "https://www.amazon.in/dp/B098765432")
    try check(ActivityAnalytics.contexts([product,productOther]).count == 2, "Same-title products with different URLs remain separate")
    var productPlaceholder = product; productPlaceholder.title = product.url!
    try check(ActivityAnalytics.contexts([product,productPlaceholder]).count == 1 && ActivityAnalytics.contexts([product,productPlaceholder]).first?.seconds == 200, "Product loading placeholder merges without dropping time")
    let searchOne = Activity(start: clipStart, end: clipEnd, app: "Chrome", title: "Watercolour brushes - Google Search", url: "https://www.google.com/search")
    var searchTwo = searchOne; searchTwo.title = "Journalling - Google Search"
    try check(ActivityAnalytics.contexts([searchOne,searchTwo]).count == 2, "Query-stripped search pages keep distinct titles")
    let personalCollision = notes.appendingPathComponent("MacJournal-1970-01-01.md")
    try "My personal diary".write(to: personalCollision, atomically: true, encoding: .utf8)
    var collisionRejected = false
    do { _ = try JournalNotes.sync([event(0,60)], to: notes) } catch { collisionRejected = true }
    try check(collisionRejected && (try String(contentsOf: personalCollision, encoding: .utf8)) == "My personal diary", "Export preserves personal files with generated daily filenames")
    var earlierTitle = postA; earlierTitle.title = "Old title"; earlierTitle.start = Date(timeIntervalSince1970: 1); earlierTitle.end = Date(timeIntervalSince1970: 30)
    var latestTitle = postA; latestTitle.title = "Corrected title"; latestTitle.start = Date(timeIntervalSince1970: 50); latestTitle.end = Date(timeIntervalSince1970: 80)
    try check(ActivityAnalytics.contexts([earlierTitle,latestTitle]).first?.title == "Corrected title", "Newest saved page title wins regardless of input order")
    var genericNetflix = netflix; genericNetflix.title = "Netflix"
    try check(ActivityAnalytics.mediaName(genericNetflix) == nil, "Generic Netflix tab label does not count as a known video title")
    let midnightEnd = Activity(start: day.addingTimeInterval(-60), end: day, app: "Midnight fixture", title: "Previous day only")
    try store.save(midnightEnd)
    try check(try !store.timeline(on: day).contains(where: { $0.id == midnightEnd.id }), "Midnight-ending record stays out of next day counts")
    try check(ActivityCategory.category(for: postA) == .articles && ActivityCategory.category(for: reddit) == .articles, "Substack and Reddit belong to Articles")
    try check(ActivityCategory.category(for: product) == .shopping && ActivityCategory.category(for: searchOne) == .articles, "Amazon products belong to Shopping and web searches to Articles")
    try check(ActivityCategory.category(for: yt1) == .youtube && ActivityCategory.category(for: netflix) == .streaming && ActivityCategory.category(for: video) == .streaming, "YouTube separate from Netflix and Prime streaming")
    try check(ActivityCategory.category(for: event(0,60)) == nil, "App-only records stay in app time summary")
    var publisherHelp = product; publisherHelp.url = "https://kdp.amazon.com/en_US/help/topic/example"
    try check(ActivityCategory.category(for: publisherHelp) == .articles, "Amazon publishing help is reading rather than shopping")
    try check(ActivityAnalytics.contexts([earlierTitle, latestTitle]).first?.lastSeen == latestTitle.end, "Article summaries retain latest visit time for recent sorting")
    let chromeFixture = FileManager.default.temporaryDirectory.appendingPathComponent("MacJournalChromeFixture-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: chromeFixture) }
    try FileManager.default.createDirectory(at: chromeFixture.appendingPathComponent("Default"), withIntermediateDirectories: true)
    let chromeDB = try DatabaseQueue(path: chromeFixture.appendingPathComponent("Default/History").path)
    let visitDate = Calendar.current.startOfDay(for: Date()).addingTimeInterval(60)
    let chromeTime = (visitDate.timeIntervalSince1970 + ChromeHistory.epochOffset) * 1_000_000
    try chromeDB.write { db in
        try db.execute(sql: "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT); CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER, originator_cache_guid TEXT)")
        let urls = ["https://www.reddit.com/r/books/comments/abc/topic?tracking=1", "https://bank.example/account", "file:///secret", "https://example.org/remote", "https://www.reddit.com/r/books/comments/abc/topic?tracking=1"]
        for (offset, raw) in urls.enumerated() {
            try db.execute(sql: "INSERT INTO urls VALUES (?, ?, ?)", arguments: [offset + 1, raw, "Thread from history"])
            try db.execute(sql: "INSERT INTO visits VALUES (?, ?, ?, ?)", arguments: [offset + 1, offset + 1, chromeTime + Double(offset), offset == 3 ? "other-device" : ""])
        }
    }
    let imported = try ChromeHistory.read(root: chromeFixture, profile: "Default", since: visitDate, until: visitDate.addingTimeInterval(10), exclusions: Exclusions())
    try check(imported.count == 2, "History excludes blocked URLs, non-web schemes, and foreign-device visits")
    try check(imported.allSatisfy { $0.kind == "history" && $0.duration == 0 && $0.url?.contains("?") == false }, "History retains source and strips tracking without fabricating duration")
    try check(abs(imported[0].start.timeIntervalSince(visitDate)) < 0.001, "Chrome microseconds since 1601 convert correctly")
    try store.saveHistory(imported); try store.saveHistory(imported)
    try check(try store.timeline().filter { $0.kind == "history" }.count == 2, "Repeated history import is idempotent")
    try check(try store.timeline(on: visitDate).contains(where: { $0.id == imported[0].id }), "Zero-duration history visits appear on their calendar day")
    let historyContexts = ActivityAnalytics.contexts(imported)
    try check(historyContexts.count == 1 && historyContexts[0].historyVisits == 2 && historyContexts[0].seconds == 0, "Repeated visits group into one page without inventing time")
    var liveVisit = imported[0]; liveVisit.id = UUID().uuidString; liveVisit.kind = "app"; liveVisit.title = "Actual live heading"; liveVisit.end = liveVisit.start.addingTimeInterval(45)
    let mergedHistory = ActivityAnalytics.contexts(imported + [liveVisit])
    try check(mergedHistory.count == 1 && mergedHistory[0].seconds == 45 && mergedHistory[0].title == "Actual live heading", "History merges with live capture while preserving its title and foreground duration")
    try check(ActivityAnalytics.clipped(imported, from: visitDate, to: visitDate.addingTimeInterval(10)).count == 2 && ActivityAnalytics.serviceTotals(imported).isEmpty, "History visits survive date filters and contribute no app time")
    let historyNotes = chromeFixture.appendingPathComponent("notes")
    _ = try JournalNotes.sync(imported, to: historyNotes)
    let historyNote = try String(contentsOf: FileManager.default.contentsOfDirectory(at: historyNotes, includingPropertiesForKeys: nil)[0], encoding: .utf8)
    try check(historyNote.contains("Chrome history visit; duration unknown"), "Daily notes include history visits with an explicit unknown duration")
    let afterRange = try ChromeHistory.read(root: chromeFixture, profile: "Default", since: visitDate.addingTimeInterval(20), until: visitDate.addingTimeInterval(30), exclusions: Exclusions())
    try check(afterRange.isEmpty, "History import respects its time boundary")
    let blockedHistory = try ChromeHistory.read(root: chromeFixture, profile: "Default", since: visitDate, until: visitDate.addingTimeInterval(10), exclusions: Exclusions(apps: ["com.google.Chrome"]))
    try check(blockedHistory.isEmpty, "Chrome application exclusion also blocks history import")
    try check(ChromeHistory.profiles(at: chromeFixture) == ["Default"], "History restricts reading to regular profile directories")
    if CommandLine.arguments.contains("--probe-chrome-history") {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
        let profiles = ChromeHistory.profiles(at: root)
        guard let profile = profiles.first else { throw NSError(domain: "HistoryProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "No readable regular Chrome profile"]) }
        let visits = try ChromeHistory.read(root: root, profile: profile, since: Calendar.current.startOfDay(for: Date()), until: Date(), exclusions: Exclusions())
        print("Live Chrome reader: \(visits.count) eligible visits, \(Set(visits.compactMap(\.url)).count) distinct URLs; no titles or URLs printed or saved")
    }
    print("\(passed) checks passed")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
