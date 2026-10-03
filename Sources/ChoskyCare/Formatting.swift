import Foundation

/// Looks up a localized string in this package's resource bundle.
///
/// SwiftUI's `Text("key")` resolves keys against `Bundle.main`, but a Swift
/// package keeps its `.strings` files in `Bundle.module`, so every user-facing
/// string must go through here.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

/// Localized format string (supports `.stringsdict` plural rules).
func L(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}

extension Int64 {
    var formattedBytes: String {
        formatted(.byteCount(style: .file))
    }
}

extension Int {
    var formattedCount: String {
        formatted(.number)
    }
}

extension Date {
    var formattedMedium: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDay: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

extension Optional where Wrapped == Date {
    var formattedMediumOrDash: String {
        map(\.formattedMedium) ?? "—"
    }
}

extension URL {
    /// True when `self` is `other` or lives inside it, compared by path components
    /// (so `/Users/bob` does not contain `/Users/bobby`).
    func isSameOrDescendant(of other: URL) -> Bool {
        let mine = standardizedFileURL.pathComponents
        let theirs = other.standardizedFileURL.pathComponents
        guard mine.count >= theirs.count else { return false }
        return Array(mine.prefix(theirs.count)) == theirs
    }

    func isStrictDescendant(of other: URL) -> Bool {
        isSameOrDescendant(of: other) &&
            standardizedFileURL.pathComponents.count > other.standardizedFileURL.pathComponents.count
    }
}
