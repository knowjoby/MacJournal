import Foundation
import GRDB

/// Reads only the selected regular profile's History database, never session or private-window files.
public enum ChromeHistory {
    public static let epochOffset: Double = 11_644_473_600
    public static func profiles(at root: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter {
            ($0 == "Default" || ($0.hasPrefix("Profile ") && Int($0.dropFirst(8)) != nil)) &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0 + "/History").path)
        }.sorted()
    }
    public static func read(root: URL, profile: String, since: Date, until: Date, exclusions: Exclusions) throws -> [Activity] {
        _ = try FileManager.default.contentsOfDirectory(atPath: root.path)
        guard profiles(at: root).contains(profile) else { throw failure("Selected Chrome profile is unavailable.") }
        let source = root.appendingPathComponent(profile + "/History")
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("MacJournal-history-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: folder) }
        let files = ["", "-journal", "-wal"]
        func stamps() throws -> [String] {
            try files.map { suffix in
                let path = source.path + suffix
                guard fm.fileExists(atPath: path) else { return "absent" }
                let a = try fm.attributesOfItem(atPath: path)
                return "\(a[.size] ?? 0)-\(a[.modificationDate] ?? "")-\(a[.systemFileNumber] ?? 0)"
            }
        }
        // Chrome may exclusively lock History. Copy a stable database and its journal,
        // then let SQLite recover the disposable copy without touching Chrome's files.
        var stable = false
        for _ in 0..<3 {
            let before = try stamps()
            for suffix in files {
                let target = folder.appendingPathComponent("History" + suffix)
                try? fm.removeItem(at: target)
                if fm.fileExists(atPath: source.path + suffix) {
                    try fm.copyItem(atPath: source.path + suffix, toPath: target.path)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                }
            }
            if try before == stamps() { stable = true; break }
        }
        guard stable else { throw failure("Chrome history is changing; retrying on the next sync.") }
        let queue = try DatabaseQueue(path: folder.appendingPathComponent("History").path)
        return try queue.read { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(visits)").map { (row: Row) -> String in row["name"] }
            // Exclude synced visits from other devices when Chrome exposes their origin.
            let localOnly = columns.contains("originator_cache_guid") ? " AND (v.originator_cache_guid IS NULL OR v.originator_cache_guid = '')" : ""
            let rows = try Row.fetchAll(db, sql: """
                SELECT v.id, v.visit_time, u.url, u.title FROM visits v JOIN urls u ON u.id = v.url
                WHERE v.visit_time >= ? AND v.visit_time < ? \(localOnly)
                ORDER BY v.visit_time, v.id
                """, arguments: [(since.timeIntervalSince1970 + epochOffset) * 1_000_000, (until.timeIntervalSince1970 + epochOffset) * 1_000_000])
            return rows.compactMap { row in
                let raw: String = row["url"], title: String = row["title"]
                guard !exclusions.blocks(app: "com.google.Chrome", title: title, url: raw), let url = Redactor.safeURL(raw) else { return nil }
                let time: Double = row["visit_time"]
                let date = Date(timeIntervalSince1970: time / 1_000_000 - epochOffset)
                let id: Int64 = row["id"]
                return Activity(id: "chrome-history|\(profile)|\(id)|\(time)", start: date, end: date, app: "com.google.Chrome", title: title.isEmpty ? url : Redactor.clean(title), url: url, kind: "history")
            }
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ChromeHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
