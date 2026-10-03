import Foundation

struct StorageScanner: Sendable {
    /// Scans `root` on a background task. Cancelling the consuming task (or
    /// dropping the stream) cancels the scan.
    func scan(root: URL, options: ScanOptions) -> AsyncThrowingStream<StorageScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let snapshot = try Self.performScan(root: root, options: options) { progress in
                        continuation.yield(.progress(progress))
                    }
                    continuation.yield(.completed(snapshot))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private final class ErrorCounter: @unchecked Sendable {
        var count = 0
    }

    static func performScan(
        root: URL,
        options: ScanOptions,
        downloadsURL: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
        now: Date = Date(),
        progress: (ScanProgress) -> Void = { _ in }
    ) throws -> StorageSnapshot {
        let keys = DiskUsage.sizeKeys.union([
            .isDirectoryKey,
            .isPackageKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey
        ])

        var enumeratorOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHiddenFiles {
            enumeratorOptions.insert(.skipsHiddenFiles)
        }

        let errors = ErrorCounter()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: enumeratorOptions,
            errorHandler: { _, _ in
                errors.count += 1
                return true
            }
        ) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: root.path])
        }

        var totalBytes: Int64 = 0
        var fileCount = 0
        var directoryCount = 0
        var unreadable = 0
        var topLevel: [URL: StorageNode] = [:]
        var currentTopLevel: URL?
        var largeFiles: [FileRecord] = []
        var oldDownloads: [FileRecord] = []
        var lastProgress = ContinuousClock.now
        let oldThreshold = Calendar.current.date(byAdding: .month, value: -options.oldDownloadAgeMonths, to: now) ?? .distantPast
        let downloads = downloadsURL?.standardizedFileURL

        for case let url as URL in enumerator {
            try Task.checkCancellation()

            guard let values = try? url.resourceValues(forKeys: keys) else {
                unreadable += 1
                continue
            }
            if values.isSymbolicLink == true { continue }

            let isDirectory = values.isDirectory == true
            if enumerator.level == 1 {
                currentTopLevel = url
                topLevel[url] = StorageNode(url: url, byteCount: 0, fileCount: 0, isDirectory: isDirectory)
            }

            let bytes: Int64
            let files: Int
            let isPackage = isDirectory && values.isPackage == true
            if isPackage {
                // Count everything inside the package but report it as one item, so
                // nobody is invited to delete files from inside an app or a Photos library.
                enumerator.skipDescendants()
                let totals = DiskUsage.totals(of: url)
                try Task.checkCancellation()
                bytes = totals.bytes
                files = totals.files
            } else if isDirectory {
                directoryCount += 1
                continue
            } else if values.isRegularFile == true {
                bytes = DiskUsage.fileBytes(values)
                files = 1
            } else {
                continue
            }

            fileCount += files
            totalBytes += bytes
            if let currentTopLevel {
                topLevel[currentTopLevel]?.byteCount += bytes
                topLevel[currentTopLevel]?.fileCount += files
            }

            let added = values.addedToDirectoryDate ?? values.creationDate
            func record() -> FileRecord {
                FileRecord(
                    url: url,
                    byteCount: bytes,
                    modificationDate: values.contentModificationDate,
                    addedDate: added,
                    isPackage: isPackage
                )
            }

            if bytes >= options.largeFileThreshold {
                largeFiles.append(record())
            }

            if let downloads,
               bytes >= options.oldDownloadMinimumBytes,
               url.isStrictDescendant(of: downloads),
               let age = added ?? values.contentModificationDate,
               age < oldThreshold {
                oldDownloads.append(record())
            }

            if ContinuousClock.now - lastProgress > .milliseconds(120) {
                progress(ScanProgress(currentPath: url.path, filesScanned: fileCount, bytesScanned: totalBytes))
                lastProgress = .now
            }
        }

        try Task.checkCancellation()

        largeFiles.sort { $0.byteCount > $1.byteCount }
        oldDownloads.sort { $0.byteCount > $1.byteCount }
        progress(ScanProgress(currentPath: root.path, filesScanned: fileCount, bytesScanned: totalBytes))

        return StorageSnapshot(
            rootURL: root,
            totalBytes: totalBytes,
            fileCount: fileCount,
            directoryCount: directoryCount,
            topLevelNodes: topLevel.values.sorted { $0.byteCount > $1.byteCount },
            largeFiles: Array(largeFiles.prefix(options.maxRecords)),
            oldDownloads: Array(oldDownloads.prefix(options.maxRecords)),
            inaccessiblePaths: errors.count + unreadable,
            scannedAt: now,
            options: options
        )
    }
}
