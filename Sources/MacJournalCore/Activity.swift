import Foundation
import GRDB

public struct Activity: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public static let databaseTableName = "activity"
    public var id: String
    public var start: Date
    public var end: Date
    public var app: String
    public var title: String
    public var url: String?
    public var kind: String
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public init(id: String = UUID().uuidString, start: Date, end: Date, app: String, title: String, url: String? = nil, kind: String = "app") {
        self.id = id; self.start = start; self.end = end; self.app = app; self.title = title; self.url = url; self.kind = kind
    }
}
public struct Session: Equatable {
    public var events: [Activity]
    public var topic: String
}
public enum SessionGrouper {
    public static func group(_ events: [Activity], gap: TimeInterval = 900) -> [Session] {
        var result: [Session] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            let topic = event.url.flatMap { URL(string: $0)?.host } ?? event.app
            if let last = result.last, let end = last.events.map(\.end).max(), event.start.timeIntervalSince(end) <= gap, last.topic == topic {
                result[result.count - 1].events.append(event)
            } else { result.append(Session(events: [event], topic: topic)) }
        }
        return result
    }
}

public final class ActivityStore {
    private let db: DatabaseQueue
    public init(path: String, key: String) throws {
        guard !key.isEmpty else { throw StoreError.emptyKey }
        var config = Configuration()
        config.prepareDatabase { db in
            try db.usePassphrase(key)
            guard try String.fetchOne(db, sql: "PRAGMA cipher_version") != nil else { throw StoreError.noEncryption }
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        db = try DatabaseQueue(path: path, configuration: config)
        var migration = DatabaseMigrator()
        migration.registerMigration("activity-v1") { db in
            try db.create(table: "activity") { t in
                t.column("id", .text).primaryKey()
                t.column("start", .datetime).notNull().indexed()
                t.column("end", .datetime).notNull()
                t.column("app", .text).notNull()
                t.column("title", .text).notNull()
                t.column("url", .text)
                t.column("kind", .text).notNull()
            }
        }
        try migration.migrate(db)
    }
    public func save(_ event: Activity) throws { try db.write { try event.save($0) } }
    public func saveHistory(_ events: [Activity]) throws { try db.write { db in for event in events { try event.save(db) } } }
    public func timeline(on day: Date? = nil) throws -> [Activity] {
        try db.read { database in
            if let day, let interval = Calendar.current.dateInterval(of: .day, for: day) {
                return try Activity.filter(Column("start") < interval.end && (Column("end") > interval.start || (Column("kind") == "history" && Column("start") >= interval.start))).order(Column("start").desc).fetchAll(database)
            }
            return try Activity.order(Column("start").desc).fetchAll(database)
        }
    }
    public func delete(since: Date?) throws {
        try db.write { database in
            if let since {
                try database.execute(sql: "DELETE FROM activity WHERE start >= ?", arguments: [since])
                try database.execute(sql: "UPDATE activity SET end = ? WHERE start < ? AND end > ?", arguments: [since, since, since])
            } else { try database.execute(sql: "DELETE FROM activity") }
        }
        try db.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }
    public enum StoreError: Error { case emptyKey, noEncryption }
}
