import XCTest
@testable import MacJournalCore
final class CoreTests: XCTestCase {
    func testBrowserAdapters() {
        XCTAssertTrue(BrowserPolicy.supportsURLCapture("com.google.Chrome"))
        XCTAssertTrue(BrowserPolicy.supportsURLCapture("com.brave.Browser"))
        XCTAssertTrue(BrowserPolicy.supportsURLCapture("com.microsoft.edgemac"))
        XCTAssertFalse(BrowserPolicy.supportsURLCapture("unknown.browser"))
        XCTAssertTrue(BrowserPolicy.unsupportedBrowser("com.apple.Safari"))
        XCTAssertFalse(BrowserPolicy.unsupportedBrowser("com.apple.TextEdit"))
    }
    func testRedaction() {
        let text = Redactor.clean("mail me@example.com card 4111 1111 1111 1111 token=abc123 Bearer secret123 sk-abcdefghijklmno")
        for secret in ["me@example.com", "4111", "abc123", "secret123", "sk-abcdefghijklmno"] { XCTAssertFalse(text.contains(secret)) }
        XCTAssertEqual(Redactor.clean("Read the design notes"), "Read the design notes")
    }
    func testURLPrivacy() {
        XCTAssertEqual(Redactor.safeURL("https://name:secret@example.com/docs?token=secret#private"), "https://example.com/docs")
        XCTAssertNil(Redactor.safeURL("file:///private/passwords"))
    }
    func testExclusions() {
        let rules = Exclusions()
        XCTAssertTrue(rules.blocks(app: "com.agilebits.onepassword7", title: "Vault", url: nil))
        XCTAssertTrue(rules.blocks(app: "com.google.Chrome", title: "New Incognito Tab", url: nil))
        XCTAssertTrue(rules.blocks(app: "Safari", title: "Account", url: "https://mybank.com"))
        XCTAssertFalse(rules.blocks(app: "TextEdit", title: "Notes", url: nil))
    }
    func testGroupingGapTopicAndSort() {
        func event(_ time: Double, _ app: String) -> Activity { Activity(start: Date(timeIntervalSince1970: time), end: Date(timeIntervalSince1970: time + 60), app: app, title: "Notes") }
        XCTAssertEqual(SessionGrouper.group([event(2000,"A"), event(0,"A"), event(100,"A"), event(2100,"B")]).map { $0.events.count }, [2,1,1])
        XCTAssertEqual(SessionGrouper.group([]), [])
        XCTAssertEqual(SessionGrouper.group([event(0,"A"), event(960,"A")]).count, 1)
    }
    func testEncryptedStorageAndDeletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try ActivityStore(path: url.path, key: "test-key")
        let event = Activity(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100), app: "Test", title: "secret title")
        try store.save(event)
        XCTAssertEqual(try store.timeline().count, 1)
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("secret title"))
        XCTAssertThrowsError(try ActivityStore(path: url.path, key: "wrong"))
        try store.delete(since: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(try store.timeline().first?.duration, 50)
        try store.delete(since: nil)
        XCTAssertTrue(try store.timeline().isEmpty)
    }
}
