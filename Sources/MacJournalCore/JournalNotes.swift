import Foundation

/// These files are generated mirrors; personal notes belong in separate files.
public enum JournalNotes {
    public static func sync(_ events: [Activity], to folder: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dayFormat = DateFormatter(); dayFormat.dateFormat = "yyyy-MM-dd"
        let timeFormat = DateFormatter(); timeFormat.dateFormat = "HH:mm:ss"
        let calendar = Calendar.current
        var days: [String: [Activity]] = [:]
        for event in events where event.end > event.start || event.kind == "history" {
            var cursor = calendar.startOfDay(for: event.start)
            repeat {
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                var part = event
                part.start = max(event.start, cursor); part.end = min(event.end, next)
                days[dayFormat.string(from: cursor), default: []].append(part)
                cursor = next
            } while cursor < event.end
        }
        let marker = "<!-- MacJournal generated activity; edits are replaced. -->"
        let names = Set(days.keys.map { "MacJournal-\($0).md" })
        // Preflight every target before changing any mirrors. Never overwrite a
        // user's note merely because it has the same daily filename.
        for name in names {
            let file = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path), !(try String(contentsOf: file, encoding: .utf8)).hasPrefix(marker) {
                throw NSError(domain: "MacJournalNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Existing personal file \(name) was preserved. Rename it or move it out of this generated notes folder, then refresh."])
            }
        }
        for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix("MacJournal-") && file.pathExtension == "md" && !names.contains(file.lastPathComponent) {
            if (try? String(contentsOf: file, encoding: .utf8).hasPrefix(marker)) == true { try fm.removeItem(at: file) }
        }
        func plain(_ value: String) -> String {
            value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "|", with: "&#124;").replacingOccurrences(of: "[", with: "&#91;").replacingOccurrences(of: "]", with: "&#93;")
        }
        for (day, entries) in days {
            var text = "\(marker)\n# Activity · \(day)\n\nLocal activity log. Times reflect this Mac's current timezone. Page titles do not confirm playback.\nKeep personal writing in a separate note; this file updates automatically.\n\n| From | To | Seconds | Activity | App | URL |\n| --- | --- | ---: | --- | --- | --- |\n"
            for event in entries.sorted(by: { $0.start < $1.start }) {
                text += "| \(timeFormat.string(from: event.start)) | \(timeFormat.string(from: event.end)) | \(Int(event.duration)) | \(plain(event.title + (event.kind == "history" ? " [Chrome history visit; duration unknown]" : ""))) | \(plain(event.app)) | \(plain(event.url ?? "")) |\n"
            }
            let file = folder.appendingPathComponent("MacJournal-\(day).md")
            if (try? String(contentsOf: file, encoding: .utf8)) != text {
                try text.write(to: file, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
        }
        return days.count
    }
}
