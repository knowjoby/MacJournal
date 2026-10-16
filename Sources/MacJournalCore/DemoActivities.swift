import Foundation

/// Synthetic data for a clearly labelled public preview. Never reads a browser or journal.
public enum DemoActivities {
    public static func make(now: Date = Date()) -> [Activity] {
        let start = Calendar.current.startOfDay(for: now)
        let samples: [(String, String?, String, Double)] = [
            ("How to Do Great Work", "https://paulgraham.com/greatwork.html", "com.google.Chrome", 1_200),
            ("What are you building this weekend?", "https://www.reddit.com/r/SideProject/", "com.google.Chrome", 480),
            ("A guide to building better habits", "https://example.substack.com/p/better-habits", "com.google.Chrome", 900),
            ("SwiftUI: Build your first Mac app", "https://www.youtube.com/watch?v=abcdefghijk", "com.google.Chrome", 2_400),
            ("Designing a calm workspace", "https://www.youtube.com/watch?v=lmnopqrstuv", "com.google.Chrome", 1_200),
            ("Netflix · A documentary evening", "https://www.netflix.com/watch/12345678", "com.google.Chrome", 7_200),
            ("Prime Video: A weekend movie", "https://www.primevideo.com/detail/DEMO", "com.google.Chrome", 5_400),
            ("Kindle Paperwhite", "https://www.amazon.com/dp/B0CFPJYX7P", "com.google.Chrome", 600),
            ("Obsidian", nil, "md.obsidian", 3_600),
            ("Xcode", nil, "com.apple.dt.Xcode", 2_700),
            ("Notes", nil, "com.apple.Notes", 900)
        ]
        return samples.enumerated().flatMap { index, sample -> [Activity] in
            let date = min(start.addingTimeInterval(Double(index + 1) * 1_800), now.addingTimeInterval(-sample.3 - 60))
            let live = Activity(start: date, end: date.addingTimeInterval(sample.3), app: sample.2, title: sample.0, url: sample.1)
            guard sample.1 != nil else { return [live] }
            let visit = Activity(start: date, end: date, app: sample.2, title: sample.0, url: sample.1, kind: "history")
            return [live, visit]
        }
    }
}
