import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 250), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("dashboard.title"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(L("dashboard.subtitle"))
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }

                HStack(spacing: 12) {
                    PrimaryActionButton(
                        title: L("action.scan_home"),
                        symbol: "externaldrive.badge.magnifyingglass",
                        isWorking: model.isScanningStorage
                    ) { model.scanHomeDirectory() }

                    Button {
                        model.scanSoftware()
                    } label: {
                        Label(L("action.scan_software"), systemImage: "shippingbox.and.arrow.backward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isScanningSoftware)
                }

                if model.isScanningStorage {
                    ScanProgressCard(progress: model.scanProgress, root: model.scanningRoot) {
                        model.cancelStorageScan()
                    }
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    DashboardCard(
                        title: L("dashboard.storage"),
                        value: snapshot?.totalBytes.formattedBytes ?? "—",
                        detail: snapshot.map { L("count.files", $0.fileCount) } ?? L("dashboard.not_scanned"),
                        symbol: "externaldrive.fill",
                        section: .storage
                    )

                    DashboardCard(
                        title: L("dashboard.large_files"),
                        value: snapshot.map { $0.largeFiles.count.formattedCount } ?? "—",
                        detail: L("dashboard.over_threshold", (snapshot?.options ?? .fromUserDefaults()).largeFileThreshold.formattedBytes),
                        symbol: "doc.badge.ellipsis",
                        section: .largeFiles
                    )

                    DashboardCard(
                        title: L("dashboard.apps"),
                        value: model.applications.isEmpty ? "—" : model.applications.count.formattedCount,
                        detail: model.applications.first.map { L("dashboard.largest_app", $0.displayName, $0.byteCount.formattedBytes) }
                            ?? L("dashboard.not_scanned"),
                        symbol: "shippingbox.fill",
                        section: .software
                    )

                    DashboardCard(
                        title: L("dashboard.safe_candidates"),
                        value: model.cleanupCandidates.isEmpty ? "—" : model.reviewableCleanupBytes.formattedBytes,
                        detail: model.cleanupCandidates.isEmpty
                            ? L("dashboard.not_scanned")
                            : L("count.categories", model.cleanupCandidates.filter(\.isActionable).count),
                        symbol: "checkmark.shield.fill",
                        section: .safeCleanup
                    )
                }

                if let snapshot {
                    Text(L("dashboard.last_scan", snapshot.rootURL.path, snapshot.scannedAt.formattedMedium))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(L("dashboard.promise"), systemImage: "hand.raised.fill")
                        .font(.headline)
                    Text(L("dashboard.promise_detail"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(28)
        }
    }

    private var snapshot: StorageSnapshot? { model.storageSnapshot }
}

private struct DashboardCard: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let section: AppModel.Section

    var body: some View {
        Button {
            model.selection = section
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let symbol: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isWorking)
    }
}

struct ScanProgressCard: View {
    let progress: ScanProgress
    let root: URL?
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(root.map { L("scan.running_in", $0.lastPathComponent) } ?? L("scan.running"))
                    .font(.headline)
                Spacer()
                Button(L("action.cancel"), action: cancel)
            }
            Text(progress.currentPath.isEmpty ? L("scan.preparing") : progress.currentPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(L("count.files", progress.filesScanned) + " · " + progress.bytesScanned.formattedBytes)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
