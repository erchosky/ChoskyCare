import CoreServices
import Foundation

struct SoftwareScanner: Sendable {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var applicationRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]

    /// Library folders searched for leftovers of an application.
    static let relatedLibraryFolders = [
        "Library/Application Support",
        "Library/Caches",
        "Library/Preferences",
        "Library/Logs",
        "Library/Saved Application State",
        "Library/Containers",
        "Library/Group Containers",
        "Library/HTTPStorages",
        "Library/WebKit",
        "Library/Application Scripts",
        "Library/Cookies"
    ]

    // MARK: Applications

    func scanApplications() throws -> [InstalledApplication] {
        let fm = FileManager.default
        var bundles: [URL] = []
        var seen = Set<String>()

        func collect(_ url: URL) {
            let key = url.resolvingSymlinksInPath().standardizedFileURL.path
            if seen.insert(key).inserted { bundles.append(url) }
        }

        for root in applicationRoots where fm.fileExists(atPath: root.path) {
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for child in children {
                if child.pathExtension.lowercased() == "app" {
                    collect(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // Vendors often install into a sub-folder, e.g. /Applications/Utilities or /Applications/Adobe X/.
                    let nested = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    nested.filter { $0.pathExtension.lowercased() == "app" }.forEach(collect)
                }
            }
        }

        let libraryEntries = listLibraryEntries()
        var applications: [InstalledApplication] = []
        var bundleIDs: [String] = []

        for url in bundles {
            try Task.checkCancellation()
            let bundle = Bundle(url: url)
            let info = bundle?.infoDictionary ?? [:]
            let bundleID = bundle?.bundleIdentifier
            let name = (info["CFBundleDisplayName"] as? String).nonEmpty
                ?? (info["CFBundleName"] as? String).nonEmpty
                ?? url.deletingPathExtension().lastPathComponent
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])

            if let bundleID { bundleIDs.append(bundleID) }
            applications.append(InstalledApplication(
                url: url,
                displayName: name,
                bundleIdentifier: bundleID,
                version: info["CFBundleShortVersionString"] as? String,
                byteCount: DiskUsage.allocatedSize(of: url),
                modificationDate: values?.contentModificationDate,
                lastUsedDate: Self.lastUsedDate(of: url),
                related: [],
                isRemovable: fm.isDeletableFile(atPath: url.path)
            ))
        }

        // Attribute every Library entry to the most specific installed bundle ID,
        // so e.g. "com.vendor.App.beta" data goes to the beta app, not the release one.
        var entriesByOwner: [String: [URL]] = [:]
        for entry in libraryEntries {
            if let owner = Self.owner(of: entry.lastPathComponent, among: bundleIDs) {
                entriesByOwner[owner, default: []].append(entry)
            }
        }
        let copies = Dictionary(grouping: bundleIDs, by: { $0 }).mapValues(\.count)
        for index in applications.indices {
            try Task.checkCancellation()
            guard let bundleID = applications[index].bundleIdentifier else { continue }
            // Two copies of the same app share their Library data: removing one copy
            // must not take the other copy's settings with it.
            if copies[bundleID, default: 0] > 1 {
                applications[index].hasOtherCopies = true
                continue
            }
            applications[index].related = (entriesByOwner[bundleID] ?? [])
                .map { RelatedItem(url: $0, byteCount: DiskUsage.allocatedSize(of: $0)) }
                .sorted { $0.byteCount > $1.byteCount }
        }

        return applications.sorted { $0.byteCount > $1.byteCount }
    }

    private func listLibraryEntries() -> [URL] {
        Self.relatedLibraryFolders
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .flatMap { root in
                (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            }
    }

    /// Whether a Library entry name belongs to `bundleID`:
    /// `com.x.app`, `com.x.app.plist`, `com.x.app.savedState`, `TEAMID.com.x.app`, `group.com.x.app`.
    static func name(_ name: String, matches bundleID: String) -> Bool {
        let name = name.lowercased()
        let id = bundleID.lowercased()
        guard !id.isEmpty else { return false }
        return name == id || name.hasPrefix(id + ".") || name.hasSuffix("." + id)
    }

    static func owner(of entryName: String, among bundleIDs: [String]) -> String? {
        bundleIDs
            .filter { name(entryName, matches: $0) }
            .max { $0.count < $1.count }
    }

    static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Cleanup candidates

    struct CleanupRule: Sendable {
        let id: String
        let path: String
        let risk: CleanupRisk
        let canRecreate: Bool
        var isActionable = true
    }

    static let cleanupRules: [CleanupRule] = [
        CleanupRule(id: "user_caches", path: "Library/Caches", risk: .review, canRecreate: true),
        CleanupRule(id: "user_logs", path: "Library/Logs", risk: .review, canRecreate: true),
        CleanupRule(id: "xcode_derived_data", path: "Library/Developer/Xcode/DerivedData", risk: .low, canRecreate: true),
        CleanupRule(id: "simulator_caches", path: "Library/Developer/CoreSimulator/Caches", risk: .low, canRecreate: true),
        CleanupRule(id: "xcode_archives", path: "Library/Developer/Xcode/Archives", risk: .high, canRecreate: false),
        CleanupRule(id: "ios_device_support", path: "Library/Developer/Xcode/iOS DeviceSupport", risk: .review, canRecreate: true),
        CleanupRule(id: "homebrew_cache", path: "Library/Caches/Homebrew", risk: .low, canRecreate: true),
        CleanupRule(id: "npm_cache", path: ".npm/_cacache", risk: .low, canRecreate: true),
        CleanupRule(id: "trash", path: ".Trash", risk: .review, canRecreate: false, isActionable: false)
    ]

    func scanCleanupCandidates() throws -> [CleanupCandidate] {
        let fm = FileManager.default
        let ruleURLs = Self.cleanupRules.map { home.appendingPathComponent($0.path, isDirectory: true) }

        var candidates: [CleanupCandidate] = []
        for (rule, url) in zip(Self.cleanupRules, ruleURLs) {
            try Task.checkCancellation()
            guard fm.fileExists(atPath: url.path) else { continue }
            // A folder nested inside another rule (Homebrew inside Caches) is its own
            // candidate: exclude it here so its size is not counted twice.
            let excluded = ruleURLs.filter { $0.isStrictDescendant(of: url) }
            let size = DiskUsage.allocatedSize(of: url) - excluded.reduce(0) { $0 + DiskUsage.allocatedSize(of: $1) }
            guard size > 0 else { continue }
            candidates.append(CleanupCandidate(
                id: rule.id,
                url: url,
                title: L("rule.\(rule.id).title"),
                explanation: L("rule.\(rule.id).detail"),
                byteCount: size,
                risk: rule.risk,
                canRecreate: rule.canRecreate,
                excluded: excluded,
                isActionable: rule.isActionable
            ))
        }
        return candidates.sorted { $0.byteCount > $1.byteCount }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return self
    }
}
