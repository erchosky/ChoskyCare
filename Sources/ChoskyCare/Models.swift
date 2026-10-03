import Foundation

struct StorageNode: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    var byteCount: Int64
    var fileCount: Int
    let isDirectory: Bool

    init(url: URL, byteCount: Int64, fileCount: Int, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.isDirectory = isDirectory
    }
}

struct FileRecord: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let byteCount: Int64
    let modificationDate: Date?
    /// When the item arrived in its folder (falls back to creation date).
    let addedDate: Date?
    /// Packages (apps, Photos libraries…) are reported as a single item.
    let isPackage: Bool

    var name: String { url.lastPathComponent }
    var sortableModificationDate: Date { modificationDate ?? .distantPast }
    var sortableAddedDate: Date { addedDate ?? modificationDate ?? .distantPast }
}

struct ScanOptions: Sendable, Equatable {
    var largeFileThreshold: Int64 = 250 * 1_024 * 1_024
    var includeHiddenFiles = true
    var oldDownloadMinimumBytes: Int64 = 20 * 1_024 * 1_024
    var oldDownloadAgeMonths = 6
    var maxRecords = 500

    static let thresholdDefaultsKey = "largeFileThresholdMB"
    static let includeHiddenDefaultsKey = "includeHiddenFiles"

    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> ScanOptions {
        var options = ScanOptions()
        let megabytes = defaults.object(forKey: thresholdDefaultsKey) as? Double ?? 250
        options.largeFileThreshold = Int64(max(1, megabytes) * 1_024 * 1_024)
        options.includeHiddenFiles = defaults.object(forKey: includeHiddenDefaultsKey) as? Bool ?? true
        return options
    }
}

struct StorageSnapshot: Sendable {
    let rootURL: URL
    var totalBytes: Int64
    var fileCount: Int
    let directoryCount: Int
    var topLevelNodes: [StorageNode]
    var largeFiles: [FileRecord]
    var oldDownloads: [FileRecord]
    let inaccessiblePaths: Int
    let scannedAt: Date
    let options: ScanOptions

    /// Drops records that were moved to the Trash and subtracts their size.
    func removing(_ urls: [URL]) -> StorageSnapshot {
        guard !urls.isEmpty else { return self }
        func isRemoved(_ url: URL) -> Bool { urls.contains { url.isSameOrDescendant(of: $0) } }

        var copy = self
        var seen = Set<URL>()
        for record in largeFiles + oldDownloads where isRemoved(record.url) && seen.insert(record.url).inserted {
            copy.totalBytes = max(0, copy.totalBytes - record.byteCount)
            copy.fileCount = max(0, copy.fileCount - 1)
            if let index = copy.topLevelNodes.firstIndex(where: { record.url.isSameOrDescendant(of: $0.url) }) {
                copy.topLevelNodes[index].byteCount = max(0, copy.topLevelNodes[index].byteCount - record.byteCount)
                copy.topLevelNodes[index].fileCount = max(0, copy.topLevelNodes[index].fileCount - 1)
            }
        }
        copy.topLevelNodes.removeAll { isRemoved($0.url) }
        copy.topLevelNodes.sort { $0.byteCount > $1.byteCount }
        copy.largeFiles.removeAll { isRemoved($0.url) }
        copy.oldDownloads.removeAll { isRemoved($0.url) }
        return copy
    }
}

struct ScanProgress: Sendable, Equatable {
    var currentPath: String
    var filesScanned: Int
    var bytesScanned: Int64

    static let starting = ScanProgress(currentPath: "", filesScanned: 0, bytesScanned: 0)
}

enum StorageScanEvent: Sendable {
    case progress(ScanProgress)
    case completed(StorageSnapshot)
}

struct RelatedItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let byteCount: Int64

    /// The Library folder it lives in, e.g. "Caches" or "Containers".
    var location: String { url.deletingLastPathComponent().lastPathComponent }
}

struct InstalledApplication: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let displayName: String
    let bundleIdentifier: String?
    let version: String?
    let byteCount: Int64
    let modificationDate: Date?
    let lastUsedDate: Date?
    var related: [RelatedItem]
    let isRemovable: Bool
    /// Another installed copy uses the same bundle ID, so its Library data is shared.
    var hasOtherCopies = false

    var relatedBytes: Int64 { related.reduce(0) { $0 + $1.byteCount } }
    var sortableLastUsed: Date { lastUsedDate ?? .distantPast }
    var bundleIdentifierOrDash: String { bundleIdentifier ?? "—" }
    var versionOrDash: String { version ?? "—" }
}

enum CleanupRisk: String, Sendable, Comparable {
    case low, review, high

    private var order: Int {
        switch self {
        case .low: 0
        case .review: 1
        case .high: 2
        }
    }

    static func < (lhs: CleanupRisk, rhs: CleanupRisk) -> Bool { lhs.order < rhs.order }
}

struct CleanupCandidate: Identifiable, Hashable, Sendable {
    /// Stable rule identifier, so selections survive a rescan.
    let id: String
    let url: URL
    let title: String
    let explanation: String
    let byteCount: Int64
    let risk: CleanupRisk
    let canRecreate: Bool
    /// Sub-folders handled by another candidate; never trashed by this one.
    let excluded: [URL]
    /// Informational candidates (e.g. the Trash) are shown but not selectable.
    let isActionable: Bool

    /// The items that are moved to the Trash: the folder's contents, not the folder itself.
    func itemsToTrash() -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        return children.filter { child in !excluded.contains { child.isSameOrDescendant(of: $0) } }
    }
}

struct CleanupFailure: Sendable, Hashable {
    let url: URL
    let reason: String
}

struct CleanupResult: Sendable {
    var moved: [URL] = []
    var failed: [CleanupFailure] = []
    var reclaimedBytes: Int64 = 0
}
