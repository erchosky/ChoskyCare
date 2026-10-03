import AppKit
import Foundation
import SwiftUI

struct Banner: Equatable, Identifiable {
    enum Kind { case error, success, info }

    let id = UUID()
    let kind: Kind
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard
        case storage
        case largeFiles
        case downloads
        case software
        case safeCleanup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: L("nav.dashboard")
            case .storage: L("nav.storage")
            case .largeFiles: L("nav.large_files")
            case .downloads: L("nav.downloads")
            case .software: L("nav.software")
            case .safeCleanup: L("nav.safe_cleanup")
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: "sparkles.rectangle.stack"
            case .storage: "externaldrive.fill"
            case .largeFiles: "doc.fill"
            case .downloads: "arrow.down.circle.fill"
            case .software: "shippingbox.fill"
            case .safeCleanup: "trash.slash.fill"
            }
        }
    }

    @Published var selection: Section? = .dashboard
    @Published private(set) var storageSnapshot: StorageSnapshot?
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var cleanupCandidates: [CleanupCandidate] = []
    @Published private(set) var isScanningStorage = false
    @Published private(set) var isScanningApplications = false
    @Published private(set) var isScanningCleanup = false
    @Published private(set) var isTrashing = false
    @Published private(set) var scanProgress = ScanProgress.starting
    @Published private(set) var scanningRoot: URL?
    @Published var banner: Banner?
    @Published var quickLookURL: URL?

    private let storageScanner = StorageScanner()
    private let softwareScanner = SoftwareScanner()
    private let cleanupService = CleanupService()
    private var storageTask: Task<Void, Never>?
    private var storageScanToken: UUID?
    private var bannerTask: Task<Void, Never>?

    var isScanningSoftware: Bool { isScanningApplications || isScanningCleanup }

    var reviewableCleanupBytes: Int64 {
        cleanupCandidates.filter(\.isActionable).reduce(0) { $0 + $1.byteCount }
    }

    // MARK: Storage

    func scanHomeDirectory() {
        scanStorage(url: FileManager.default.homeDirectoryForCurrentUser)
    }

    func scanStorage(url: URL) {
        storageTask?.cancel()
        let token = UUID()
        storageScanToken = token
        isScanningStorage = true
        scanningRoot = url
        scanProgress = .starting
        dismissBanner()

        let options = ScanOptions.fromUserDefaults()
        let stream = storageScanner.scan(root: url, options: options)
        storageTask = Task { [weak self] in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            var failure: Error?
            do {
                for try await event in stream {
                    guard let self, self.storageScanToken == token else { return }
                    switch event {
                    case .progress(let progress):
                        self.scanProgress = progress
                    case .completed(let snapshot):
                        self.storageSnapshot = snapshot
                    }
                }
                if Task.isCancelled { failure = CancellationError() }
            } catch {
                failure = error
            }

            // A newer scan may have replaced this one; it owns the state now.
            guard let self, self.storageScanToken == token else { return }
            switch failure {
            case nil: break
            case is CancellationError: self.show(.info, L("error.scan_cancelled"))
            case let error?: self.show(.error, error.localizedDescription)
            }
            self.isScanningStorage = false
            self.scanningRoot = nil
            self.storageTask = nil
        }
    }

    func cancelStorageScan() {
        storageTask?.cancel()
    }

    // MARK: Software

    func scanSoftware() {
        scanApplications()
        scanCleanupCandidates()
    }

    func scanApplications() {
        guard !isScanningApplications else { return }
        isScanningApplications = true
        let scanner = softwareScanner
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try scanner.scanApplications() }
            }.value
            guard let self else { return }
            switch result {
            case .success(let apps): self.applications = apps
            case .failure(let error): self.show(.error, error.localizedDescription)
            }
            self.isScanningApplications = false
        }
    }

    func scanCleanupCandidates() {
        guard !isScanningCleanup else { return }
        isScanningCleanup = true
        let scanner = softwareScanner
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try scanner.scanCleanupCandidates() }
            }.value
            guard let self else { return }
            switch result {
            case .success(let candidates): self.cleanupCandidates = candidates
            case .failure(let error): self.show(.error, error.localizedDescription)
            }
            self.isScanningCleanup = false
        }
    }

    // MARK: Cleanup

    /// Moves items to the Trash, updates every list that showed them and reports the outcome.
    @discardableResult
    func trash(_ urls: [URL]) async -> CleanupResult {
        guard !urls.isEmpty, !isTrashing else { return CleanupResult() }
        isTrashing = true
        defer { isTrashing = false }

        let service = cleanupService
        let result = await Task.detached(priority: .userInitiated) {
            service.moveToTrash(urls)
        }.value

        if !result.moved.isEmpty {
            storageSnapshot = storageSnapshot?.removing(result.moved)
            applications.removeAll { app in result.moved.contains { app.url.isSameOrDescendant(of: $0) } }
            for index in applications.indices {
                applications[index].related.removeAll { item in result.moved.contains { item.url.isSameOrDescendant(of: $0) } }
            }
        }
        report(result)
        return result
    }

    func uninstall(_ app: InstalledApplication, including related: [RelatedItem]) async {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL
        }
        if running {
            show(.error, L("software.error.running", app.displayName))
            return
        }
        await trash([app.url] + related.map(\.url))
    }

    func clean(_ candidates: [CleanupCandidate]) async {
        let urls = candidates.filter(\.isActionable).flatMap { $0.itemsToTrash() }
        if urls.isEmpty {
            show(.info, L("cleanup.nothing_to_move"))
        } else {
            await trash(urls)
        }
        scanCleanupCandidates()
    }

    private func report(_ result: CleanupResult) {
        if result.failed.isEmpty {
            show(.success, L("cleanup.result.success", result.moved.count, result.reclaimedBytes.formattedBytes))
            return
        }
        let details = result.failed.prefix(5)
            .map { "• \($0.url.lastPathComponent): \($0.reason)" }
            .joined(separator: "\n")
        let more = result.failed.count > 5 ? "\n" + L("cleanup.result.more", result.failed.count - 5) : ""
        let summary = L("cleanup.result.partial", result.moved.count, result.reclaimedBytes.formattedBytes, result.failed.count)
        show(.error, summary + "\n" + details + more)
    }

    // MARK: Banner

    func show(_ kind: Banner.Kind, _ message: String) {
        let banner = Banner(kind: kind, message: message)
        self.banner = banner
        bannerTask?.cancel()
        guard kind != .error else { return }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, self?.banner?.id == banner.id else { return }
            self?.banner = nil
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    // MARK: Finder helpers

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func quickLook(_ url: URL) {
        quickLookURL = url
    }
}
