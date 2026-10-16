import AppKit
import MacJournalCore

final class Recorder: ObservableObject {
    static let shared = Recorder()
    let isDemo = Bundle.main.bundleIdentifier == "local.MacJournal.demo"
    @Published var recording = false
    @Published var idle = false
    @Published var sleeping = false
    @Published var events: [Activity] = []
    @Published var history: [Activity] = []
    @Published var error: String?
    @Published var notesStatus = "Preparing daily notes…"
    @Published var savedCount = 0
    let notesFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MacJournal Notes", isDirectory: true)
    func openNotes() { NSWorkspace.shared.open(notesFolder) }
    func syncNotes() {
        do {
            guard let store else {
                notesStatus = "Daily notes unchanged: encrypted storage is unavailable."
                return
            }
            let saved = try store.timeline()
            history = saved
            savedCount = saved.count
            let days = try JournalNotes.sync(saved, to: notesFolder)
            notesStatus = "Saved \(saved.count) entries across \(days) daily notes."
        } catch { notesStatus = "Daily notes failed: \(error.localizedDescription). Database records are retained." }
    }
    @Published private var chromeRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
    func chooseChromeHistoryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Chrome history folder"
        panel.message = "Choose the Chrome folder in Library/Application Support/Google. MacJournal reads only the selected regular profile's history and saves visits locally."
        panel.prompt = "Allow folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = chromeRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
        guard url.standardizedFileURL == expected.standardizedFileURL else {
            historyStatus = "Please choose Library/Application Support/Google/Chrome in your home folder."
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "chromeHistoryFolderBookmark")
            historyGeneration += 1
            chromeRoot = url
            if !chromeProfiles.contains(historyProfile), let first = chromeProfiles.first { historyProfile = first }
            syncChromeHistory()
        } catch { historyStatus = "Folder access could not be saved: \(error.localizedDescription)" }
    }
    var chromeProfiles: [String] { ChromeHistory.profiles(at: chromeRoot) }
    @Published var historyEnabled = true
    @Published var historyProfile = "Default"
    @Published var historyStatus = "Preparing Chrome history…"
    private var historyTimer: Timer?
    private var historyBusy = false
    private var historyGeneration = 0
    private var historySince: Date {
        get { (UserDefaults.standard.object(forKey: "chromeHistorySince") as? Date) ?? Calendar.current.startOfDay(for: Date()) }
        set { UserDefaults.standard.set(newValue, forKey: "chromeHistorySince") }
    }
    private func skipPendingHistory() { historyGeneration += 1; historySince = Date() }
    func setHistoryEnabled(_ enabled: Bool) {
        skipPendingHistory(); historyEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "chromeHistoryEnabled")
        historyStatus = enabled ? "History enabled from now." : "History import disabled."
        if enabled { syncChromeHistory() }
    }
    func setHistoryProfile(_ profile: String) {
        guard chromeProfiles.contains(profile) else { return }
        skipPendingHistory(); historyProfile = profile
        UserDefaults.standard.set(profile, forKey: "chromeHistoryProfile")
        syncChromeHistory()
    }
    func syncChromeHistory() {
        guard historyEnabled, browserEnabled, recording, !sleeping, error == nil, let store else {
            historyStatus = "History sync paused with browser capture or recording."
            return
        }
        guard !historyBusy else { return }
        historyBusy = true
        let since = historySince, until = Date(), generation = historyGeneration
        let root = chromeRoot, profile = historyProfile, rules = exclusions
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try ChromeHistory.read(root: root, profile: profile, since: since, until: until, exclusions: rules) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.historyBusy = false
                guard generation == self.historyGeneration, self.recording, self.historyEnabled, self.browserEnabled else { return }
                do {
                    let visits = try result.get()
                    try store.saveHistory(visits)
                    self.historySince = until
                    self.historyStatus = "Chrome \(profile) · synced \(visits.count) visits · " + DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
                    self.reload(); self.syncNotes()
                } catch { self.historyStatus = "Chrome history unavailable: \(error.localizedDescription) Retrying automatically." }
            }
        }
    }
    @Published var browserEnabled = true
    @Published var browserStatus = "Browser URLs enabled · Automation access may be requested."
    @Published var exclusions: Exclusions
    @Published var hotkeyReady = false
    private var displayedDay = Date()
    private var store: ActivityStore?
    private var current: Activity?
    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var browserTimer: Timer?
    private var checkpointTimer: Timer?
    private var hotkey: PauseHotkey?
    private var unavailableBrowsers = Set<String>()
    var status: String { isDemo ? "Demo preview" : error != nil ? "Needs attention" : !recording ? "Paused" : sleeping ? "Sleeping" : idle ? "Idle · paused" : "Recording" }
    var active: Bool { recording && !idle && !sleeping && error == nil }
    init() {
        exclusions = (UserDefaults.standard.data(forKey: "exclusions").flatMap { try? JSONDecoder().decode(Exclusions.self, from: $0) }) ?? Exclusions()
        if isDemo {
            history = DemoActivities.make(); events = history
            browserEnabled = false; historyEnabled = false
            notesStatus = "Demo preview · synthetic sample activities; no personal history"
            return
        }
        // Migrate legacy browser blocks that existed because window capture needed AX.
        if !UserDefaults.standard.bool(forKey: "urlOnlyCaptureV1") {
            exclusions.apps.removeAll { ["com.brave", "com.microsoft.edgemac", "com.operasoftware", "com.vivaldi"].contains($0) }
            UserDefaults.standard.set(try? JSONEncoder().encode(exclusions), forKey: "exclusions")
            UserDefaults.standard.set(true, forKey: "urlOnlyCaptureV1")
        }
        if let bookmark = UserDefaults.standard.data(forKey: "chromeHistoryFolderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                chromeRoot = url
            }
        }
        historyEnabled = (UserDefaults.standard.object(forKey: "chromeHistoryEnabled") as? Bool) ?? true
        historyProfile = UserDefaults.standard.string(forKey: "chromeHistoryProfile") ?? chromeProfiles.first ?? "Default"
        if UserDefaults.standard.object(forKey: "chromeHistorySince") == nil { historySince = Calendar.current.startOfDay(for: Date()) }
        browserEnabled = (UserDefaults.standard.object(forKey: "browserURLsEnabled") as? Bool) ?? true
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("MacJournal", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            store = try ActivityStore(path: base.appendingPathComponent("activity.sqlite").path, key: DatabaseKey.load())
            reload()
            syncNotes()
        } catch { self.error = "Encrypted storage unavailable: \(error.localizedDescription)" }
        hotkey = PauseHotkey { [weak self] in self?.toggle() }
        hotkeyReady = hotkey?.registered ?? false
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.shutdown() })
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.wake() })
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.checkIdle() }
        idleTimer?.tolerance = 3
        // Browser URL changes have no NSWorkspace notification. Sample only the active browser.
        browserTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkIdle()
            guard self.active, let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  BrowserPolicy.supportsURLCapture(bundle) else { return }
            self.refresh()
        }
        browserTimer?.tolerance = 0.5
        checkpointTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.checkpoint() }
        checkpointTimer?.tolerance = 3
        historyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.syncChromeHistory() }
        historyTimer?.tolerance = 3
        // Explicit user preference: capture on every launch. A manual pause persists.
        if !UserDefaults.standard.bool(forKey: "captureManuallyPaused"), store != nil, error == nil {
            recording = true
            checkIdle()
            DispatchQueue.main.async { [weak self] in self?.refresh(); self?.syncChromeHistory() }
        }
    }
    func toggle() {
        guard !isDemo else { return }
        skipPendingHistory()
        if recording {
            finish(); recording = false
            UserDefaults.standard.set(true, forKey: "captureManuallyPaused")
        } else {
            guard store != nil, error == nil else { return }
            UserDefaults.standard.set(false, forKey: "captureManuallyPaused")
            recording = true; checkIdle(); refresh()
        }
    }
    func saveExclusions() {
        skipPendingHistory()
        UserDefaults.standard.set(try? JSONEncoder().encode(exclusions), forKey: "exclusions")
        finish()
        if active { refresh() }
    }
    func setBrowser(_ enabled: Bool) {
        skipPendingHistory()
        finish(); browserEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "browserURLsEnabled")
        if active { refresh() }
    }
    func checkChromeTitleAccess() {
        guard browserEnabled else { browserStatus = "Browser capture is disabled."; return }
        guard let metadata = browserMetadata("com.google.Chrome") else { return }
        guard !exclusions.blocks(app: "com.google.Chrome", title: metadata.title ?? "", url: metadata.url) else {
            browserStatus = "This tab matches an exclusion and is skipped."; return
        }
        if let title = metadata.title { browserStatus += " Title: " + Redactor.clean(title) }
    }
    func retryBrowserAccess() {
        unavailableBrowsers.removeAll()
        browserStatus = "Retrying Automation access when a supported browser is active."
        if active { refresh() }
    }
    func delete(_ interval: TimeInterval?) {
        skipPendingHistory()
        current = nil
        do { try store?.delete(since: interval.map { Date().addingTimeInterval(-$0) }); reload(); syncNotes(); if active { refresh() } }
        catch { fail(error) }
    }
    func showDay(_ day: Date) { displayedDay = day; reload() }
    func shutdown() { finish() }
    private func fail(_ failure: Error) { current = nil; recording = false; error = "Capture stopped: \(failure.localizedDescription)" }
    private func reload() {
        do { events = try store?.timeline(on: displayedDay) ?? [] } catch { fail(error) }
    }
    private func checkpoint(validateBrowser: Bool = true) {
        checkIdle()
        if validateBrowser, active, let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           BrowserPolicy.supportsURLCapture(bundle) { refresh() }
        guard active, var event = current else { return }
        event.end = Date()
        do { try store?.save(event); reload(); syncNotes() } catch { fail(error) }
    }
    private func finish(at date: Date = Date()) {
        guard var event = current else { return }
        current = nil; event.end = max(event.start, date)
        guard event.duration > 0 else { return }
        do { try store?.save(event); reload(); syncNotes() } catch { fail(error) }
    }
    private func checkIdle() {
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: UInt32.max)!)
        let newIdle = seconds >= 300
        if newIdle != idle {
            if newIdle { finish(at: Date().addingTimeInterval(-seconds + 300)) }
            idle = newIdle
            if !newIdle && active { refresh() }
        }
    }
    private func suspend() { finish(); sleeping = true }
    private func wake() { sleeping = false; checkIdle(); if active { refresh() } }
    private func refresh() {
        guard active else { return }
        guard let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier else { finish(); return }
        let name = app.localizedName ?? bundle
        guard bundle != Bundle.main.bundleIdentifier, !exclusions.blocks(app: bundle, title: name, url: nil),
              !BrowserPolicy.unsupportedBrowser(bundle) else { finish(); return }
        var rawURL: String?
        var mediaTitle: String?
        if BrowserPolicy.supportsURLCapture(bundle) {
            guard browserEnabled, !unavailableBrowsers.contains(bundle) else { finish(); return }
            // A verified normal window is required before recording browser metadata.
            guard let metadata = browserMetadata(bundle) else { finish(); return }
            rawURL = metadata.url
            mediaTitle = metadata.title
        }
        guard !exclusions.blocks(app: bundle, title: mediaTitle ?? name, url: rawURL) else { finish(); return }
        let cleanURL = Redactor.safeURL(rawURL)
        guard rawURL == nil || cleanURL != nil else { finish(); return }
        var label = mediaTitle.map(Redactor.clean) ?? cleanURL ?? Redactor.clean(name)
        // Netflix hides player controls between interactions. Keep a known title for
        // the SAME episode URL, never carry it across an episode change.
        if let rawURL, BrowserPolicy.isNetflixWatch(rawURL), let event = current,
           event.url == cleanURL, event.title.hasPrefix("Netflix · "), !label.hasPrefix("Netflix · ") {
            label = event.title
        }
        // Upgrade a loading placeholder in place once the tab title arrives.
        if var event = current, event.app == bundle, event.url == cleanURL,
           (event.title == cleanURL || (rawURL.map(BrowserPolicy.isNetflixWatch) == true && !event.title.hasPrefix("Netflix · "))), label != event.title {
            event.title = label
            current = event
            checkpoint(validateBrowser: false)
            return
        }
        if current?.app != bundle || current?.title != label || current?.url != cleanURL {
            finish()
            current = Activity(start: Date(), end: Date(), app: bundle, title: label, url: cleanURL)
            checkpoint(validateBrowser: false)
        }
    }
    private func browserMetadata(_ bundle: String) -> (url: String, title: String?)? {
        // bundle is selected from the known adapter registry, not interpolated user text.
        guard let source = BrowserPolicy.metadataScript(bundle) else { return nil }
        var scriptError: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&scriptError)
        if let scriptError {
            let code = (scriptError[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if BrowserPolicy.requiresPermissionRetry(code) { unavailableBrowsers.insert(bundle) }
            browserStatus = code == -1743 ? "Automation access denied for \(bundle). Allow MacJournal in System Settings → Privacy & Security → Automation, then retry." : "Browser read temporarily unavailable (\(code)). Retrying automatically; application capture continues."
            return nil
        }
        guard let result, result.numberOfItems == 3,
              let url = result.atIndex(1)?.stringValue, !url.isEmpty else {
            browserStatus = "No readable normal browser tab. Private windows are skipped."
            return nil
        }
        unavailableBrowsers.remove(bundle)
        let title = result.atIndex(2)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleStatus = result.atIndex(3)?.stringValue
        if titleStatus?.hasPrefix("player-access-disabled") == true {
            browserStatus = "Netflix player title access is disabled. In Chrome choose View → Developer → Allow JavaScript from Apple Events. URLs still save; private windows stay excluded. " + Redactor.clean(titleStatus ?? "")
        } else if titleStatus == "waiting-player" {
            browserStatus = "Netflix player title is not visible yet. Move the pointer over the player or pause briefly to show its title."
        } else {
            browserStatus = titleStatus == "page-heading" ? "Article, thread, or product heading captured. Private windows are skipped." : titleStatus == "page-tab-fallback" ? "Page heading access unavailable; saving the browser tab title." : titleStatus == "article" ? "Substack article heading captured. Private windows are skipped." : titleStatus == "article-tab-fallback" ? "Substack article reader unavailable; saving the browser tab title. Check JavaScript from Apple Events if the title is generic." : titleStatus == "player" ? "Netflix show and episode title captured. Private windows are skipped." : "Capturing normal browser URLs and page titles. Private windows are skipped."
        }
        return (url, title?.isEmpty == false ? title : nil)
    }
}
