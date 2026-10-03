import XCTest
@testable import ChoskyCare

final class TreemapTests: XCTestCase {
    func testProducesOneRectanglePerWeight() {
        let rects = TreemapLayout.layout(weights: [10, 8, 3, 1], in: CGRect(x: 0, y: 0, width: 100, height: 60))
        XCTAssertEqual(rects.count, 4)
        XCTAssertTrue(rects.allSatisfy { $0.width >= 0 && $0.height >= 0 })
    }

    func testStaysWithinBoundsAndPreservesArea() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let weights: [Double] = [100, 50, 25, 10, 5, 5, 1]
        let rects = TreemapLayout.layout(weights: weights, in: bounds)
        for rect in rects {
            XCTAssertGreaterThanOrEqual(rect.minX, bounds.minX - 0.001)
            XCTAssertGreaterThanOrEqual(rect.minY, bounds.minY - 0.001)
            XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX + 0.001)
            XCTAssertLessThanOrEqual(rect.maxY, bounds.maxY + 0.001)
        }
        let total = weights.reduce(0, +)
        for (weight, rect) in zip(weights, rects) {
            let expected = Double(bounds.width * bounds.height) * weight / total
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: 0.5)
        }
    }

    func testZeroAndInvalidWeightsDoNotCrash() {
        XCTAssertEqual(TreemapLayout.layout(weights: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).count, 0)
        let rects = TreemapLayout.layout(weights: [0, .nan, 5, -3], in: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(rects[2].width * rects[2].height, 100, accuracy: 0.001)
        XCTAssertEqual(rects[0].size, .zero)
        XCTAssertEqual(TreemapLayout.layout(weights: [1, 2], in: .zero).count, 2)
    }
}

final class PathTests: XCTestCase {
    func testDescendantUsesPathComponents() {
        let bob = URL(fileURLWithPath: "/Users/bob")
        XCTAssertTrue(URL(fileURLWithPath: "/Users/bob/Library").isStrictDescendant(of: bob))
        XCTAssertFalse(URL(fileURLWithPath: "/Users/bobby/Library").isSameOrDescendant(of: bob))
        XCTAssertTrue(bob.isSameOrDescendant(of: URL(fileURLWithPath: "/Users/bob/")))
        XCTAssertFalse(bob.isStrictDescendant(of: bob))
        XCTAssertFalse(URL(fileURLWithPath: "/Users/bob/../alice").isSameOrDescendant(of: bob))
    }
}

final class CleanupServiceTests: XCTestCase {
    private let service = CleanupService(
        home: URL(fileURLWithPath: "/Users/bob", isDirectory: true),
        applicationsFolder: URL(fileURLWithPath: "/Applications", isDirectory: true),
        runningAppBundle: URL(fileURLWithPath: "/Applications/ChoskyCare.app", isDirectory: true)
    )

    private func allowed(_ path: String) -> Bool {
        service.isAllowed(URL(fileURLWithPath: path))
    }

    func testAllowsItemsInsideHomeAndApplications() {
        XCTAssertTrue(allowed("/Users/bob/Downloads/movie.mov"))
        XCTAssertTrue(allowed("/Users/bob/Library/Caches/com.example.app"))
        XCTAssertTrue(allowed("/Applications/Example.app"))
    }

    func testRejectsSiblingHomeWithSharedPrefix() {
        XCTAssertFalse(allowed("/Users/bobby/Documents/file.txt"))
    }

    func testRejectsHomeAndEssentialFolders() {
        for path in ["/Users/bob", "/Users/bob/", "/Users/bob/Library", "/Users/bob/Documents",
                     "/Users/bob/Library/Caches", "/Users/bob/Library/Containers", "/Users/bob/.Trash"] {
            XCTAssertFalse(allowed(path), path)
        }
    }

    func testRejectsTrashContentsSystemPathsAndTraversal() {
        XCTAssertFalse(allowed("/Users/bob/.Trash/old.zip"))
        XCTAssertFalse(allowed("/System/Library/CoreServices"))
        XCTAssertFalse(allowed("/Applications"))
        XCTAssertFalse(allowed("/Users/bob/../alice/secret"))
        XCTAssertFalse(allowed("/usr/bin"))
    }

    func testRejectsTheRunningApp() {
        XCTAssertFalse(allowed("/Applications/ChoskyCare.app"))
        XCTAssertFalse(allowed("/Applications/ChoskyCare.app/Contents/MacOS/ChoskyCare"))
    }

    func testTopmostRemovesDuplicatesAndChildren() {
        let urls = [
            URL(fileURLWithPath: "/Users/bob/A/B/c.txt"),
            URL(fileURLWithPath: "/Users/bob/A"),
            URL(fileURLWithPath: "/Users/bob/A"),
            URL(fileURLWithPath: "/Users/bob/AB")
        ]
        XCTAssertEqual(Set(CleanupService.topmost(urls).map(\.path)), ["/Users/bob/A", "/Users/bob/AB"])
    }

    func testMovesFilesToTrashAndReportsFailures() throws {
        let sandbox = try TemporaryDirectory()
        let file = sandbox.url.appendingPathComponent("junk.bin")
        try Data(count: 4_096).write(to: file)
        // Delete instead of trashing so the test never touches the real Trash.
        let service = CleanupService(home: sandbox.url, runningAppBundle: nil) { url in
            try FileManager.default.removeItem(at: url)
        }

        let result = service.moveToTrash([file, sandbox.url.appendingPathComponent("missing.bin")])

        XCTAssertEqual(result.moved, [file.standardizedFileURL])
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertGreaterThan(result.reclaimedBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

final class SoftwareScannerTests: XCTestCase {
    func testBundleIdentifierMatching() {
        let id = "com.example.Editor"
        XCTAssertTrue(SoftwareScanner.name("com.example.Editor", matches: id))
        XCTAssertTrue(SoftwareScanner.name("com.example.editor.plist", matches: id))
        XCTAssertTrue(SoftwareScanner.name("com.example.Editor.savedState", matches: id))
        XCTAssertTrue(SoftwareScanner.name("ABCDE12345.com.example.Editor", matches: id))
        XCTAssertTrue(SoftwareScanner.name("group.com.example.Editor", matches: id))
        XCTAssertFalse(SoftwareScanner.name("com.example.EditorPro", matches: id))
        XCTAssertFalse(SoftwareScanner.name("com.example", matches: id))
        XCTAssertFalse(SoftwareScanner.name("anything", matches: ""))
    }

    func testEntriesGoToTheMostSpecificInstalledApp() {
        let ids = ["com.example.Editor", "com.example.Editor.beta"]
        XCTAssertEqual(SoftwareScanner.owner(of: "com.example.Editor.beta.plist", among: ids), "com.example.Editor.beta")
        XCTAssertEqual(SoftwareScanner.owner(of: "com.example.Editor.plist", among: ids), "com.example.Editor")
        XCTAssertNil(SoftwareScanner.owner(of: "com.other.App", among: ids))
    }

    func testDuplicateCopiesDoNotOfferSharedLeftovers() throws {
        let home = try TemporaryDirectory()
        let fm = FileManager.default
        func makeApp(_ path: String, id: String) throws {
            let contents = home.url.appendingPathComponent(path).appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "Demo", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeApp("A/Demo.app", id: "com.example.Demo")
        try makeApp("B/Demo.app", id: "com.example.Demo")
        try makeApp("A/Solo.app", id: "com.example.Solo")
        let prefs = home.url.appendingPathComponent("Library/Preferences")
        try fm.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data(count: 10).write(to: prefs.appendingPathComponent("com.example.Demo.plist"))
        try Data(count: 10).write(to: prefs.appendingPathComponent("com.example.Solo.plist"))

        let scanner = SoftwareScanner(
            home: home.url,
            applicationRoots: [home.url.appendingPathComponent("A"), home.url.appendingPathComponent("B")]
        )
        let apps = try scanner.scanApplications()

        XCTAssertEqual(apps.count, 3)
        for demo in apps where demo.bundleIdentifier == "com.example.Demo" {
            XCTAssertTrue(demo.hasOtherCopies)
            XCTAssertTrue(demo.related.isEmpty)
        }
        let solo = try XCTUnwrap(apps.first { $0.bundleIdentifier == "com.example.Solo" })
        XCTAssertEqual(solo.related.map(\.url.lastPathComponent), ["com.example.Solo.plist"])
    }

    func testEveryCleanupRuleIsLocalized() {
        for rule in SoftwareScanner.cleanupRules {
            XCTAssertNotEqual(L("rule.\(rule.id).title"), "rule.\(rule.id).title")
            XCTAssertNotEqual(L("rule.\(rule.id).detail"), "rule.\(rule.id).detail")
        }
    }

    func testCleanupCandidatesDoNotDoubleCountNestedRules() throws {
        let home = try TemporaryDirectory()
        let caches = home.url.appendingPathComponent("Library/Caches")
        let brew = caches.appendingPathComponent("Homebrew")
        try FileManager.default.createDirectory(at: brew, withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: caches.appendingPathComponent("app.cache"))
        try Data(count: 300_000).write(to: brew.appendingPathComponent("bottle.tar.gz"))

        let scanner = SoftwareScanner(home: home.url, applicationRoots: [])
        let candidates = try scanner.scanCleanupCandidates()
        let userCaches = try XCTUnwrap(candidates.first { $0.id == "user_caches" })
        let homebrew = try XCTUnwrap(candidates.first { $0.id == "homebrew_cache" })

        XCTAssertLessThan(userCaches.byteCount, homebrew.byteCount)
        XCTAssertEqual(userCaches.itemsToTrash().map(\.lastPathComponent), ["app.cache"])
        XCTAssertEqual(homebrew.itemsToTrash().map(\.lastPathComponent), ["bottle.tar.gz"])
    }
}

final class StorageScannerTests: XCTestCase {
    func testScanCountsHiddenFilesPackagesAndTopLevelItems() throws {
        let root = try TemporaryDirectory()
        let fm = FileManager.default
        let docs = root.url.appendingPathComponent("Docs")
        let package = root.url.appendingPathComponent("Big.app/Contents/Resources")
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(count: 50_000).write(to: docs.appendingPathComponent("a.txt"))
        try Data(count: 50_000).write(to: docs.appendingPathComponent(".hidden"))
        try Data(count: 2_000_000).write(to: package.appendingPathComponent("payload.bin"))
        try Data(count: 10).write(to: root.url.appendingPathComponent("loose.txt"))

        var options = ScanOptions()
        options.largeFileThreshold = 1_000_000
        let snapshot = try StorageScanner.performScan(root: root.url, options: options, downloadsURL: nil)

        XCTAssertEqual(snapshot.fileCount, 4)
        XCTAssertEqual(Set(snapshot.topLevelNodes.map(\.name)), ["Docs", "Big.app", "loose.txt"])
        let docsNode = try XCTUnwrap(snapshot.topLevelNodes.first { $0.name == "Docs" })
        XCTAssertEqual(docsNode.fileCount, 2)
        XCTAssertTrue(docsNode.isDirectory)
        XCTAssertEqual(snapshot.topLevelNodes.first?.name, "Big.app")
        XCTAssertEqual(snapshot.totalBytes, snapshot.topLevelNodes.reduce(0) { $0 + $1.byteCount })

        // The package is reported as one large item, never its internal files.
        XCTAssertEqual(snapshot.largeFiles.map(\.name), ["Big.app"])
        XCTAssertTrue(snapshot.largeFiles[0].isPackage)

        var noHidden = options
        noHidden.includeHiddenFiles = false
        let visibleOnly = try StorageScanner.performScan(root: root.url, options: noHidden, downloadsURL: nil)
        XCTAssertEqual(visibleOnly.fileCount, 3)
    }

    func testOldDownloadsUseAgeAndSize() throws {
        let root = try TemporaryDirectory()
        let downloads = root.url.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let old = downloads.appendingPathComponent("old.dmg")
        let small = downloads.appendingPathComponent("small.pdf")
        try Data(count: 300_000).write(to: old)
        try Data(count: 10).write(to: small)

        var options = ScanOptions()
        options.oldDownloadMinimumBytes = 100_000
        let future = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
        let snapshot = try StorageScanner.performScan(root: root.url, options: options, downloadsURL: downloads, now: future)
        XCTAssertEqual(snapshot.oldDownloads.map(\.name), ["old.dmg"])

        let today = try StorageScanner.performScan(root: root.url, options: options, downloadsURL: downloads)
        XCTAssertTrue(today.oldDownloads.isEmpty)
    }

    func testRemovingRecordsUpdatesTotals() throws {
        let root = try TemporaryDirectory()
        let folder = root.url.appendingPathComponent("Movies")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let big = folder.appendingPathComponent("big.mov")
        try Data(count: 2_000_000).write(to: big)
        try Data(count: 1_000).write(to: folder.appendingPathComponent("small.txt"))

        var options = ScanOptions()
        options.largeFileThreshold = 1_000_000
        let snapshot = try StorageScanner.performScan(root: root.url, options: options, downloadsURL: nil)
        let bigBytes = try XCTUnwrap(snapshot.largeFiles.first).byteCount

        let updated = snapshot.removing([big])
        XCTAssertTrue(updated.largeFiles.isEmpty)
        XCTAssertEqual(updated.totalBytes, snapshot.totalBytes - bigBytes)
        XCTAssertEqual(updated.fileCount, snapshot.fileCount - 1)
        XCTAssertEqual(updated.topLevelNodes.first?.byteCount, snapshot.topLevelNodes.first.map { $0.byteCount - bigBytes })
    }

    func testStreamCompletes() async throws {
        let root = try TemporaryDirectory()
        try Data(count: 10).write(to: root.url.appendingPathComponent("f.txt"))
        var completed: StorageSnapshot?
        for try await event in StorageScanner().scan(root: root.url, options: ScanOptions()) {
            if case .completed(let snapshot) = event { completed = snapshot }
        }
        XCTAssertEqual(completed?.fileCount, 1)
    }

    func testScanOfMissingFolderReportsNothing() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let snapshot = try StorageScanner.performScan(root: missing, options: ScanOptions(), downloadsURL: nil)
        XCTAssertEqual(snapshot.fileCount, 0)
    }
}

final class LocalizationTests: XCTestCase {
    func testStringsResolveFromModuleBundle() {
        XCTAssertNotEqual(L("nav.dashboard"), "nav.dashboard")
        XCTAssertFalse(L("count.files", 3).contains("%"))
    }

    func testBothLanguagesHaveTheSameKeys() throws {
        func keys(_ language: String, _ file: String) throws -> Set<String> {
            let bundle = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)))
            let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: file))
            let dictionary = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: Any])
            return Set(dictionary.keys)
        }
        XCTAssertEqual(try keys("en", "strings"), try keys("es", "strings"))
        XCTAssertEqual(try keys("en", "stringsdict"), try keys("es", "stringsdict"))
    }

    func testByteFormattingIsNotEmpty() {
        XCTAssertFalse(Int64(1_024).formattedBytes.isEmpty)
    }
}

/// A temporary folder removed when the test finishes.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChoskyCareTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
