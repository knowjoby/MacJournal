import SwiftUI
import AppKit
import MacJournalCore

// Avoid the newer SDK State macro; use the macOS 14-compatible property wrapper.
typealias ViewState<Value> = SwiftUI.State<Value>

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var journalWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "MacJournal", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        Self.shared = self
        showJournal()
    }
    func showJournal() {
        if journalWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MacJournal"
            window.contentView = NSHostingView(rootView: JournalView(recorder: Recorder.shared).frame(minWidth: 860, minHeight: 620))
            window.minSize = NSSize(width: 860, height: 620)
            window.isReleasedWhenClosed = false
            window.center()
            journalWindow = window
        }
        journalWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showJournal()
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { Recorder.shared.shutdown(); return .terminateNow }
}
@main
struct MacJournalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var recorder = Recorder.shared
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Label(recorder.status, systemImage: recorder.active ? "record.circle.fill" : "pause.circle")
                Button(recorder.recording ? "Pause recording" : "Start recording") { recorder.toggle() }
                Text("No key contents captured").font(.caption).foregroundStyle(.secondary)
                Text("Pause shortcut: ⌘⌥⇧P").font(.caption)
                Divider()
                OpenJournalButton()
                Button("Quit MacJournal") { NSApp.terminate(nil) }
            }.padding().frame(width: 260)
        } label: {
            Image(systemName: recorder.active ? "record.circle.fill" : "pause.circle")
                .accessibilityLabel("MacJournal: \(recorder.status)")
        }.menuBarExtraStyle(.window)

    }
}
struct OpenJournalButton: View {
    var body: some View { Button("Open timeline & privacy settings") { AppDelegate.shared?.showJournal() } }
}
struct JournalView: View {
    @ObservedObject var recorder: Recorder
    @ViewState private var page = "Dashboard"
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                Label("MacJournal", systemImage: "book.closed.fill").font(.title2.bold()).padding(.top, 18)
                Text("A quiet record of your day.").font(.caption).foregroundStyle(.secondary)
                List(selection: $page) {
                    Label("Dashboard", systemImage: "chart.bar.xaxis").tag("Dashboard")
                    Label("Timeline", systemImage: "clock").tag("Timeline")
                    Label("Privacy & capture", systemImage: "hand.raised").tag("Privacy")
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label(recorder.status, systemImage: recorder.active ? "record.circle.fill" : "pause.circle").foregroundStyle(recorder.active ? .green : .secondary)
                    Text("On this Mac only").font(.caption).foregroundStyle(.secondary)
                    Button(recorder.recording ? "Pause" : "Start recording") { recorder.toggle() }.buttonStyle(.borderedProminent)
                }.padding(.bottom, 20)
            }.padding(.horizontal, 16).navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(spacing: 0) {
                if let error = recorder.error {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text(error); Spacer(); Button("Dismiss") { recorder.error = nil } }
                        .padding().background(.orange.opacity(0.12))
                }
                if page == "Privacy" { PrivacyView(recorder: recorder) } else if page == "Dashboard" { DashboardView(recorder: recorder) } else { TimelineView(recorder: recorder) }
            }
        }
    }
}
struct TimelineView: View {
    @ObservedObject var recorder: Recorder
    @ViewState private var search = ""
    @ViewState private var selectedDate = Date()
    @ViewState private var followsToday = true
    var dayEvents: [Activity] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: selectedDate) else { return [] }
        return recorder.events.map { event in
            var clipped = event
            clipped.start = max(event.start, interval.start)
            clipped.end = min(event.end, interval.end)
            return clipped
        }.filter { $0.duration > 0 || $0.kind == "history" }
    }
    var filtered: [Activity] { dayEvents.filter { search.isEmpty || [$0.title, $0.app, $0.url ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your activity, in context").font(.largeTitle.bold())
                    Text("Choose a date to see saved history. Daily notes are also saved in Documents/MacJournal Notes.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate } label: { Image(systemName: "chevron.left") }.help("Previous day")
                Button("Today") { selectedDate = Date() }
                DatePicker("Day", selection: $selectedDate, displayedComponents: .date).labelsHidden().frame(width: 140)
            }
            HStack(spacing: 16) {
                Metric(value: duration(dayEvents.reduce(0) { $0 + $1.duration }), label: "Captured time")
                Metric(value: "\(Set(dayEvents.filter { $0.kind == "app" }.map(\.app)).count)", label: "Applications")
                Metric(value: "\(dayEvents.count)", label: "Timeline entries")
            }
            TextField("Search titles, apps, and URLs", text: $search).textFieldStyle(.roundedBorder)
            if filtered.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Your day starts here" : "No matching activity", systemImage: search.isEmpty ? "sun.max" : "magnifyingglass", description: Text(search.isEmpty ? "Application names and normal browser URLs appear here as you work. Capture starts automatically." : "Try another search or day."))
            } else {
                List(filtered) { event in
                    HStack(alignment: .top, spacing: 16) {
                        Text(event.start, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 75, alignment: .leading)
                        Image(systemName: event.kind == "app" ? "app" : "doc").font(.title3).foregroundStyle(.teal).frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title.isEmpty ? "Untitled window" : event.title).font(.headline).textSelection(.enabled)
                            Text(event.app).font(.caption).foregroundStyle(.secondary)
                            if let url = event.url { Text(url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        Spacer()
                        Text(event.kind == "history" ? "History visit · time unknown" : event.kind == "app" ? duration(event.duration) : "File change").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }.listStyle(.inset)
            }
            Text("Application names, browser URLs, and page titles. URLs omit credentials, tracking queries, and fragments; YouTube video IDs are retained.").font(.caption).foregroundStyle(.secondary)
        }.padding(28)
        .onAppear { recorder.showDay(selectedDate) }
        .onChange(of: selectedDate) { _, date in
            followsToday = Calendar.current.isDateInToday(date)
            recorder.showDay(date)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if followsToday { selectedDate = Date(); recorder.showDay(selectedDate) }
        }
    }
    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : minutes > 0 ? "\(minutes)m" : "\(Int(seconds))s"
    }
}
struct Metric: View {
    var value: String; var label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { Text(value).font(.title.bold()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct PrivacyView: View {
    @ObservedObject var recorder: Recorder
    @ViewState private var deletion: Double?
    @ViewState private var confirmDelete = false
    var body: some View {
        Form {
            Section {
                Text("You decide what becomes a record.").font(.title2.bold())
                Text("Encrypted SQLite on this Mac. No analytics, network requests, models, or screenshots in Step 1.").foregroundStyle(.secondary)
            }
            Section("Capture · no Accessibility needed") {
                Text("MacJournal records application names and supported browser URLs automatically. Normal browser page titles are included, including videos, blog headlines, Reddit threads, Substack articles, and Amazon product names. Only title metadata is read; article bodies, comments, product descriptions, forms, keystrokes, and screenshots are not captured.")
                Text("Application changes are event-driven. Active browser URLs are checked every 3 seconds while you are using a supported browser.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Saved history & daily notes") {
                Text("Encrypted SQLite keeps the history across restarts. Plain-text Markdown mirrors are saved automatically in Documents/MacJournal Notes, compatible with Obsidian.")
                Text(recorder.notesStatus).foregroundStyle(.secondary)
                Text("\(recorder.savedCount) saved database entries · checkpoints every 15 seconds")
                Button("Open daily notes folder") { recorder.openNotes() }
                Button("Refresh daily notes") { recorder.syncNotes() }
                Text("Generated notes are replaced on update. Keep personal writing in separate files. Deleting activity also updates these mirrors; copies and backups are independent.").font(.caption)
            }
            Section("Chrome history") {
                Toggle("Import normal Chrome history", isOn: Binding(get: { recorder.historyEnabled }, set: { recorder.setHistoryEnabled($0) }))
                Picker("Chrome profile", selection: Binding(get: { recorder.historyProfile }, set: { recorder.setHistoryProfile($0) })) {
                    ForEach(recorder.chromeProfiles, id: \.self) { Text($0).tag($0) }
                }
                Text(recorder.historyStatus).font(.caption).foregroundStyle(.secondary)
                Button("Choose Chrome history folder…") { recorder.chooseChromeHistoryFolder() }
                Button("Sync Chrome history now") { recorder.syncChromeHistory() }
                Text("Starts with today's visits from the selected regular profile, then syncs every 30 seconds while recording. Exclusions apply before saving. History visits add no playback or foreground time. Chrome history may use the latest title for a URL. Incognito history is not stored by Chrome. Pausing or deleting skips pending history so it is not imported later.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Browser URLs") {
                Toggle("Capture browser URLs and page titles", isOn: Binding(get: { recorder.browserEnabled }, set: { recorder.setBrowser($0) }))
                Text("Chrome, Chromium, Brave, Edge, Vivaldi, and Opera adapters require a verified normal window. Each browser may ask for macOS Automation permission. Unsupported or private windows are skipped.").font(.caption).foregroundStyle(.secondary)
                Text(recorder.browserStatus).font(.caption).foregroundStyle(.secondary)
                Text("Netflix uses a generic tab title. Show and episode titles require Chrome → View → Developer → Allow JavaScript from Apple Events. This permits browser automation to run page scripts; MacJournal reads only the Netflix player title after verifying a normal window. Show the player controls or pause briefly for the title to appear.").font(.caption).foregroundStyle(.secondary)
                Button("Check Chrome title access") { recorder.checkChromeTitleAccess() }
                Button("Retry browser Automation access") { recorder.retryBrowserAccess() }
                Text("Safari, Firefox, and Arc URLs are not captured: their private-window state is not safely available through this adapter.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Exclusions · checked before storage") {
                ExclusionEditor(label: "App bundle IDs or fragments", values: $recorder.exclusions.apps)
                ExclusionEditor(label: "URL fragments", values: $recorder.exclusions.urls)
                ExclusionEditor(label: "Application name keywords", values: $recorder.exclusions.keywords)
                Text("One rule per line, case-insensitive. Add the domains of your banks and any sensitive apps. Private browser windows and unsupported browsers are skipped.").font(.caption).foregroundStyle(.secondary)
                Button("Apply exclusions") { recorder.saveExclusions() }
            }
            Section("Recording controls") {
                Text("Global pause / resume: ⌘⌥⇧P")
                if !recorder.hotkeyReady { Text("Shortcut registration failed. Use the visible menu bar pause control.").foregroundStyle(.orange) }
                Text("A filled record icon means capture is active; a pause icon means capture is stopped, idle, or sleeping. Capture starts automatically on launch; a manual pause persists until you resume.").font(.caption).foregroundStyle(.secondary)
                Text("Screen Recording: not requested. Screenshots and OCR are deferred.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Delete captured data") {
                HStack {
                    Button("Delete last hour", role: .destructive) { deletion = 3600; confirmDelete = true }
                    Button("Delete last day", role: .destructive) { deletion = 86400; confirmDelete = true }
                    Button("Delete everything", role: .destructive) { deletion = nil; confirmDelete = true }
                }
                Text("Deletes journal records and compacts the encrypted database. Existing system backups are outside MacJournal's control.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(8)
        .confirmationDialog("Delete captured data? This cannot be undone.", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { recorder.delete(deletion) }
        }
    }
}
struct ExclusionEditor: View {
    var label: String
    @Binding var values: [String]
    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption)
            TextEditor(text: Binding(get: { values.joined(separator: "\n") }, set: { values = $0.components(separatedBy: "\n") }))
                .font(.system(.caption, design: .monospaced)).frame(height: 76)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
        }
    }
}
