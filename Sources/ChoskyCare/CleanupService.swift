import Foundation

struct CleanupService: Sendable {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var applicationsFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)
    var runningAppBundle: URL? = Bundle.main.bundleURL
    var trashItem: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Folders that must never be trashed as a whole, even though they live in the home folder.
    static let protectedHomeFolders = [
        "", "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
        "Applications", ".Trash",
        "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
        "Library/Logs", "Library/Preferences", "Library/Mobile Documents", "Library/Keychains",
        "Library/Developer", "Library/Developer/Xcode"
    ]

    func moveToTrash(_ urls: [URL]) -> CleanupResult {
        var result = CleanupResult()

        for url in Self.topmost(urls) {
            guard isAllowed(url) else {
                result.failed.append(CleanupFailure(url: url, reason: L("cleanup.error.protected")))
                continue
            }

            let bytes = DiskUsage.allocatedSize(of: url)
            do {
                try trashItem(url)
                result.moved.append(url)
                result.reclaimedBytes += bytes
            } catch {
                result.failed.append(CleanupFailure(url: url, reason: error.localizedDescription))
            }
        }
        return result
    }

    func isAllowed(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        guard target.isFileURL else { return false }

        if let runningAppBundle, runningAppBundle.isSameOrDescendant(of: target) || target.isSameOrDescendant(of: runningAppBundle) {
            return false
        }

        if target.isStrictDescendant(of: applicationsFolder) {
            return true
        }

        guard target.isStrictDescendant(of: home) else { return false }
        // Items already in the Trash are left alone; emptying it is the user's call.
        if target.isSameOrDescendant(of: home.appendingPathComponent(".Trash")) { return false }
        return !Self.protectedHomeFolders.contains { relative in
            target.pathComponents == home.appendingPathComponent(relative).standardizedFileURL.pathComponents
        }
    }

    /// Removes duplicates and items whose parent folder is also in the list.
    static func topmost(_ urls: [URL]) -> [URL] {
        let unique = Array(Set(urls.map(\.standardizedFileURL)))
            .sorted { $0.pathComponents.count < $1.pathComponents.count }
        var kept: [URL] = []
        for url in unique where !kept.contains(where: { url.isSameOrDescendant(of: $0) }) {
            kept.append(url)
        }
        return kept
    }
}
