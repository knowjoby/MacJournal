// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "MacJournal", platforms: [.macOS(.v14)], products: [
    .executable(name: "MacJournal", targets: ["MacJournal"]),
    .executable(name: "MacJournalChecks", targets: ["MacJournalChecks"])
], dependencies: [
    .package(url: "https://github.com/sqlcipher/GRDB.swift.git", exact: "7.10.0")
], targets: [
    .target(name: "MacJournalCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
    .executableTarget(name: "MacJournal", dependencies: ["MacJournalCore"], linkerSettings: [.linkedFramework("Carbon")]),
    .executableTarget(name: "MacJournalChecks", dependencies: ["MacJournalCore"]),
    .testTarget(name: "MacJournalCoreTests", dependencies: ["MacJournalCore"])
], swiftLanguageModes: [.v5])
