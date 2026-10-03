import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: L("storage.title"), subtitle: L("storage.subtitle")) {
                Button {
                    showingImporter = true
                } label: {
                    Label(L("action.choose_folder"), systemImage: "folder.badge.plus")
                }
                .controlSize(.large)
                PrimaryActionButton(
                    title: L("action.scan_home"),
                    symbol: "externaldrive.badge.magnifyingglass",
                    isWorking: model.isScanningStorage
                ) { model.scanHomeDirectory() }
            }

            if model.isScanningStorage {
                ScanProgressCard(progress: model.scanProgress, root: model.scanningRoot) {
                    model.cancelStorageScan()
                }
                .padding([.horizontal, .top])
            }

            if let snapshot = model.storageSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        LocationBar(snapshot: snapshot)

                        HStack(spacing: 14) {
                            MetricPill(value: snapshot.totalBytes.formattedBytes, label: L("storage.scanned"))
                            MetricPill(value: snapshot.fileCount.formattedCount, label: L("storage.files"))
                            MetricPill(value: snapshot.inaccessiblePaths.formattedCount, label: L("storage.inaccessible"))
                                .help(L("storage.inaccessible_help"))
                        }

                        TreemapView(nodes: snapshot.topLevelNodes) { node in
                            if node.isDirectory { model.scanStorage(url: node.url) }
                        }
                        .frame(height: 330)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("storage.top_folders"))
                                .font(.title2.bold())
                            ForEach(snapshot.topLevelNodes.prefix(30)) { node in
                                NodeRow(node: node, total: snapshot.totalBytes)
                                Divider()
                            }
                        }
                    }
                    .padding(24)
                }
            } else if !model.isScanningStorage {
                EmptyState(
                    symbol: "externaldrive.badge.magnifyingglass",
                    title: L("storage.empty_title"),
                    detail: L("storage.empty_detail")
                )
            } else {
                Spacer()
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.scanStorage(url: url) }
            case .failure(let error):
                model.show(.error, error.localizedDescription)
            }
        }
    }
}

private struct LocationBar: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: StorageSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.scanStorage(url: snapshot.rootURL.deletingLastPathComponent())
            } label: {
                Label(L("storage.parent"), systemImage: "chevron.up")
            }
            .disabled(snapshot.rootURL.pathComponents.count <= 1 || model.isScanningStorage)
            .help(L("storage.parent_help"))

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(snapshot.rootURL.path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer()
            Text(L("storage.scanned_at", snapshot.scannedAt.formattedMedium))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NodeRow: View {
    @EnvironmentObject private var model: AppModel
    let node: StorageNode
    let total: Int64

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .lineLimit(1)
                Text(node.isDirectory ? L("count.files", node.fileCount) : L("storage.file"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView(value: total > 0 ? Double(node.byteCount) / Double(total) : 0)
                .frame(width: 120)
            Text(node.byteCount.formattedBytes)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            FileActions(url: node.url, scannable: node.isDirectory)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if node.isDirectory { model.scanStorage(url: node.url) }
        }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: L("large.title"),
                subtitle: L("large.subtitle", threshold.formattedBytes)
            ) {
                PrimaryActionButton(
                    title: L("action.scan_home"),
                    symbol: "magnifyingglass",
                    isWorking: model.isScanningStorage
                ) { model.scanHomeDirectory() }
            }

            if let records = model.storageSnapshot?.largeFiles, !records.isEmpty {
                FileRecordsList(records: records, dateColumn: .modified)
            } else {
                EmptyState(
                    symbol: "doc.badge.ellipsis",
                    title: L("large.empty_title"),
                    detail: L("large.empty_detail", threshold.formattedBytes)
                )
            }
        }
    }

    private var threshold: Int64 {
        (model.storageSnapshot?.options ?? .fromUserDefaults()).largeFileThreshold
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: L("downloads.title"), subtitle: L("downloads.subtitle")) {
                PrimaryActionButton(
                    title: L("action.scan_home"),
                    symbol: "magnifyingglass",
                    isWorking: model.isScanningStorage
                ) { model.scanHomeDirectory() }
            }

            if let records = model.storageSnapshot?.oldDownloads, !records.isEmpty {
                FileRecordsList(records: records, dateColumn: .added)
            } else {
                EmptyState(symbol: "arrow.down.circle", title: L("downloads.empty_title"), detail: L("downloads.empty_detail"))
            }
        }
    }
}

private struct FileRecordsList: View {
    enum DateColumn {
        case modified, added

        var title: String { self == .modified ? L("table.modified") : L("table.added") }

        var keyPath: KeyPath<FileRecord, Date> {
            self == .modified ? \.sortableModificationDate : \.sortableAddedDate
        }

        func date(of record: FileRecord) -> Date? {
            self == .modified ? record.modificationDate : record.addedDate ?? record.modificationDate
        }
    }

    let records: [FileRecord]
    let dateColumn: DateColumn
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<FileRecord.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileRecord.byteCount, order: .reverse)]
    @State private var showingConfirmation = false

    private var sortedRecords: [FileRecord] {
        records.sorted(using: sortOrder)
    }

    private var selectedRecords: [FileRecord] {
        records.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(sortedRecords, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L("table.name"), value: \.name) { item in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .lineLimit(1)
                            Text(item.url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .help(item.url.path)
                }
                TableColumn(L("table.size"), value: \.byteCount) { item in
                    Text(item.byteCount.formattedBytes)
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100)

                TableColumn(dateColumn.title, value: dateColumn.keyPath) { item in
                    Text(dateColumn.date(of: item).formattedMediumOrDash)
                }
                .width(min: 120, ideal: 165)

                TableColumn("") { item in
                    FileActions(url: item.url)
                }
                .width(44)
            }
            .contextMenu(forSelectionType: FileRecord.ID.self) { ids in
                if !ids.isEmpty {
                    Button(L("action.reveal_finder")) { model.revealInFinder(Array(ids)) }
                    if let first = ids.first, ids.count == 1 {
                        Button(L("action.quick_look")) { model.quickLook(first) }
                    }
                    Divider()
                    Button(L("cleanup.move_to_trash"), role: .destructive) {
                        selection = ids
                        showingConfirmation = true
                    }
                }
            } primaryAction: { ids in
                if let first = ids.first { model.quickLook(first) }
            }
            .onKeyPress(.space) {
                guard let first = selection.first else { return .ignored }
                model.quickLook(first)
                return .handled
            }

            SelectionBar(
                count: selection.count,
                bytes: selectedRecords.reduce(0) { $0 + $1.byteCount },
                isWorking: model.isTrashing
            ) {
                showingConfirmation = true
            }
        }
        .onChange(of: records) {
            // Drop selections for items that are no longer listed (e.g. moved to the Trash).
            selection.formIntersection(records.map(\.id))
        }
        .confirmationDialog(
            L("cleanup.confirm_title"),
            isPresented: $showingConfirmation
        ) {
            Button(L("cleanup.move_count_to_trash", selectedRecords.count), role: .destructive) {
                let urls = selectedRecords.map(\.url)
                Task {
                    await model.trash(urls)
                    selection.removeAll()
                }
            }
        } message: {
            Text(L("cleanup.confirm_detail_size", selectedRecords.count, selectedRecords.reduce(0) { $0 + $1.byteCount }.formattedBytes))
        }
    }
}

struct SectionHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                actions()
            }
        }
        .padding(24)
        .background(.bar)
    }
}

struct MetricPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FileActions: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    var scannable = false

    var body: some View {
        Menu {
            Button(L("action.reveal_finder")) {
                model.revealInFinder([url])
            }
            Button(L("action.quick_look")) {
                model.quickLook(url)
            }
            if scannable {
                Divider()
                Button(L("action.scan_this_folder")) {
                    model.scanStorage(url: url)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L("action.more"))
    }
}

struct SelectionBar: View {
    let count: Int
    let bytes: Int64
    let isWorking: Bool
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("count.selected", count))
                if count > 0 {
                    Text(bytes.formattedBytes)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isWorking {
                ProgressView().controlSize(.small)
            }
            Button(L("cleanup.review_and_trash"), role: .destructive, action: delete)
                .disabled(count == 0 || isWorking)
        }
        .padding(12)
        .background(.bar)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
