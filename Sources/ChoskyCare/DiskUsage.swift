import Foundation

enum DiskUsage {
    struct Totals: Sendable, Equatable {
        var bytes: Int64 = 0
        var files: Int = 0
    }

    static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]

    /// Allocated size of a single regular file (0 for anything else).
    static func fileBytes(_ values: URLResourceValues) -> Int64 {
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return 0 }
        let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        return Int64(max(0, size))
    }

    /// Allocated size of a file, package or folder, including hidden files and
    /// package contents. Symbolic links are not followed.
    static func totals(of url: URL, isCancelled: () -> Bool = { Task.isCancelled }) -> Totals {
        guard let values = try? url.resourceValues(forKeys: sizeKeys.union([.isDirectoryKey])) else {
            return Totals()
        }
        if values.isSymbolicLink == true { return Totals() }
        if values.isDirectory != true {
            return Totals(bytes: fileBytes(values), files: values.isRegularFile == true ? 1 : 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return Totals() }

        var totals = Totals()
        for case let item as URL in enumerator {
            if totals.files % 2_048 == 0, isCancelled() { break }
            guard let itemValues = try? item.resourceValues(forKeys: sizeKeys),
                  itemValues.isRegularFile == true else { continue }
            totals.bytes += fileBytes(itemValues)
            totals.files += 1
        }
        return totals
    }

    static func allocatedSize(of url: URL) -> Int64 {
        totals(of: url).bytes
    }
}
