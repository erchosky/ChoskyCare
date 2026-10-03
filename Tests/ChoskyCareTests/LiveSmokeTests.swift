import XCTest
@testable import ChoskyCare

/// Read-only checks against the real machine. Run with `CHOSKY_LIVE=1 swift test --filter LiveSmokeTests`.
final class LiveSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CHOSKY_LIVE"] == "1", "Set CHOSKY_LIVE=1 to run")
    }

    func testApplicationsScan() throws {
        let start = Date()
        let apps = try SoftwareScanner().scanApplications()
        let elapsed = Date().timeIntervalSince(start)
        print("LIVE apps: \(apps.count) in \(String(format: "%.1f", elapsed))s; largest: \(apps.prefix(3).map { "\($0.displayName) \($0.byteCount.formattedBytes)" })")
        print("LIVE apps with leftovers: \(apps.filter { !$0.related.isEmpty }.count); last-used known: \(apps.filter { $0.lastUsedDate != nil }.count)")
        XCTAssertFalse(apps.isEmpty)
        XCTAssertEqual(Set(apps.map(\.url)).count, apps.count, "duplicate apps")
        let related = apps.flatMap(\.related).map(\.url)
        let shared = Dictionary(grouping: apps.flatMap { app in app.related.map { ($0.url, app) } }, by: \.0)
            .filter { $0.value.count > 1 }
        for (url, owners) in shared {
            print("LIVE shared leftover \(url.lastPathComponent): \(owners.map { "\($0.1.url.path) [\($0.1.bundleIdentifier ?? "-")]" })")
        }
        XCTAssertTrue(shared.isEmpty, "a leftover was attributed to two apps")
    }

    func testCleanupCandidatesScan() throws {
        let start = Date()
        let candidates = try SoftwareScanner().scanCleanupCandidates()
        print("LIVE cleanup in \(String(format: "%.1f", Date().timeIntervalSince(start)))s: \(candidates.map { "\($0.id)=\($0.byteCount.formattedBytes)" })")
        let service = CleanupService()
        for candidate in candidates where candidate.isActionable {
            for item in candidate.itemsToTrash() {
                XCTAssertTrue(service.isAllowed(item), "would refuse \(item.path)")
            }
        }
    }

    func testDownloadsScan() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let start = Date()
        let snapshot = try StorageScanner.performScan(root: home.appendingPathComponent("Downloads"), options: .init())
        print("LIVE Downloads: \(snapshot.fileCount) files, \(snapshot.totalBytes.formattedBytes), large=\(snapshot.largeFiles.count), old=\(snapshot.oldDownloads.count), inaccessible=\(snapshot.inaccessiblePaths) in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        XCTAssertEqual(snapshot.totalBytes, snapshot.topLevelNodes.reduce(0) { $0 + $1.byteCount })
    }
}
