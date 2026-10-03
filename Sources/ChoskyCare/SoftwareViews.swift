import AppKit
import SwiftUI

struct SoftwareCareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: InstalledApplication.ID?
    @State private var sortOrder = [KeyPathComparator(\InstalledApplication.byteCount, order: .reverse)]
    @State private var searchText = ""

    private var selectedApp: InstalledApplication? {
        model.applications.first { $0.id == selection }
    }

    private var visibleApplications: [InstalledApplication] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? model.applications : model.applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
                ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: L("software.title"), subtitle: L("software.subtitle")) {
                PrimaryActionButton(
                    title: L("action.scan_software"),
                    symbol: "shippingbox.and.arrow.backward",
                    isWorking: model.isScanningApplications
                ) { model.scanApplications() }
            }

            if model.applications.isEmpty {
                if model.isScanningApplications {
                    ProgressView(L("software.scanning"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(symbol: "shippingbox", title: L("software.empty_title"), detail: L("software.empty_detail"))
                }
            } else {
                HSplitView {
                    Table(visibleApplications, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn(L("table.app"), value: \.displayName) { app in
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable()
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading) {
                                    Text(app.displayName)
                                    Text(app.bundleIdentifierOrDash)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        TableColumn(L("table.size"), value: \.byteCount) { app in
                            Text(app.byteCount.formattedBytes)
                                .monospacedDigit()
                        }
                        .width(min: 70, ideal: 90)
                        TableColumn(L("table.last_used"), value: \.sortableLastUsed) { app in
                            Text(app.lastUsedDate.map(\.formattedDay) ?? "—")
                                .foregroundStyle(isStale(app) ? .orange : .primary)
                                .help(isStale(app) ? L("software.stale_help") : "")
                        }
                        .width(min: 90, ideal: 110)
                        TableColumn(L("table.version"), value: \.versionOrDash) { app in
                            Text(app.versionOrDash)
                                .lineLimit(1)
                        }
                        .width(min: 60, ideal: 80)
                    }
                    .searchable(text: $searchText, placement: .toolbar, prompt: L("software.search"))
                    .frame(minWidth: 520)

                    Group {
                        if let app = selectedApp {
                            ApplicationInspector(app: app)
                                .id(app.id)
                        } else {
                            ContentUnavailableView(L("software.select"), systemImage: "cursorarrow.click")
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 380, maxHeight: .infinity)
                }
            }
        }
    }

    private func isStale(_ app: InstalledApplication) -> Bool {
        guard let lastUsed = app.lastUsedDate else { return false }
        return lastUsed < Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? .distantPast
    }
}

private struct ApplicationInspector: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApplication
    @State private var includedRelated: Set<URL>
    @State private var showingUninstall = false

    init(app: InstalledApplication) {
        self.app = app
        _includedRelated = State(initialValue: Set(app.related.map(\.url)))
    }

    private var selectedRelated: [RelatedItem] {
        app.related.filter { includedRelated.contains($0.url) }
    }

    private var totalToRemove: Int64 {
        app.byteCount + selectedRelated.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text(app.displayName)
                            .font(.title2.bold())
                        Text(app.versionOrDash)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    InspectorRow(label: L("table.size"), value: app.byteCount.formattedBytes)
                    InspectorRow(label: L("software.bundle_id"), value: app.bundleIdentifierOrDash)
                    InspectorRow(label: L("software.location"), value: app.url.deletingLastPathComponent().path)
                    InspectorRow(label: L("table.modified"), value: app.modificationDate.formattedMediumOrDash)
                    InspectorRow(label: L("table.last_used"), value: app.lastUsedDate.formattedMediumOrDash)
                    InspectorRow(label: L("software.related"), value: L("software.related_summary", app.related.count, app.relatedBytes.formattedBytes))
                }

                Divider()

                if app.hasOtherCopies {
                    Label(L("software.other_copies"), systemImage: "square.on.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if app.related.isEmpty {
                    Text(L("software.no_related"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("software.related_explanation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(app.related) { item in
                        Toggle(isOn: binding(for: item)) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.url.lastPathComponent)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(item.location)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.byteCount.formattedBytes)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .help(item.url.path)
                        .contextMenu {
                            Button(L("action.reveal_finder")) { model.revealInFinder([item.url]) }
                        }
                    }
                }

                HStack {
                    Button(L("action.reveal_finder")) {
                        model.revealInFinder([app.url])
                    }
                    Spacer()
                    Button(L("software.uninstall"), role: .destructive) {
                        showingUninstall = true
                    }
                    .disabled(!app.isRemovable || model.isTrashing)
                }

                if !app.isRemovable {
                    Label(L("software.not_removable"), systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .confirmationDialog(
            L("software.uninstall_title", app.displayName),
            isPresented: $showingUninstall
        ) {
            Button(L("software.move_app_and_selected", selectedRelated.count), role: .destructive) {
                let related = selectedRelated
                Task { await model.uninstall(app, including: related) }
            }
        } message: {
            Text(L("software.uninstall_detail", totalToRemove.formattedBytes))
        }
    }

    private func binding(for item: RelatedItem) -> Binding<Bool> {
        Binding(
            get: { includedRelated.contains(item.url) },
            set: { isOn in
                if isOn { includedRelated.insert(item.url) } else { includedRelated.remove(item.url) }
            }
        )
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct SafeCleanupView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("showSafetyExplanations") private var showSafetyExplanations = true
    @State private var selected = Set<CleanupCandidate.ID>()
    @State private var confirm = false

    private var selectedCandidates: [CleanupCandidate] {
        model.cleanupCandidates.filter { selected.contains($0.id) && $0.isActionable }
    }

    private var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: L("cleanup.title"), subtitle: L("cleanup.subtitle")) {
                PrimaryActionButton(
                    title: L("action.scan_cleanup"),
                    symbol: "checkmark.shield",
                    isWorking: model.isScanningCleanup
                ) { model.scanCleanupCandidates() }
            }

            if model.cleanupCandidates.isEmpty {
                if model.isScanningCleanup {
                    ProgressView(L("cleanup.scanning"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(symbol: "checkmark.shield", title: L("cleanup.empty_title"), detail: L("cleanup.empty_detail"))
                }
            } else {
                List(selection: $selected) {
                    ForEach(model.cleanupCandidates) { candidate in
                        CleanupCandidateRow(candidate: candidate, showExplanation: showSafetyExplanations)
                            .tag(candidate.id)
                            .selectionDisabled(!candidate.isActionable)
                    }
                }
                .listStyle(.inset)
                .onChange(of: model.cleanupCandidates) {
                    selected.formIntersection(model.cleanupCandidates.filter(\.isActionable).map(\.id))
                }

                SelectionBar(count: selectedCandidates.count, bytes: selectedBytes, isWorking: model.isTrashing) {
                    confirm = true
                }
            }
        }
        .confirmationDialog(L("cleanup.confirm_title"), isPresented: $confirm) {
            Button(L("cleanup.move_to_trash"), role: .destructive) {
                let candidates = selectedCandidates
                Task {
                    await model.clean(candidates)
                    selected.removeAll()
                }
            }
        } message: {
            Text(L("cleanup.confirm_candidates", selectedCandidates.map(\.title).joined(separator: ", "), selectedBytes.formattedBytes))
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
    let showExplanation: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(style)
                .frame(width: 30)
                .help(riskLabel)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(candidate.title)
                        .font(.headline)
                    Text(candidate.byteCount.formattedBytes)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    Text(riskLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style)
                }
                if showExplanation {
                    Text(candidate.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(candidate.canRecreate ? L("cleanup.recreated") : L("cleanup.not_recreated"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(candidate.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            FileActions(url: candidate.url)
        }
        .padding(.vertical, 7)
        .opacity(candidate.isActionable ? 1 : 0.75)
    }

    private var riskLabel: String {
        guard candidate.isActionable else { return L("risk.info") }
        switch candidate.risk {
        case .low: return L("risk.low")
        case .review: return L("risk.review")
        case .high: return L("risk.high")
        }
    }

    private var icon: String {
        guard candidate.isActionable else { return "info.circle.fill" }
        switch candidate.risk {
        case .low: return "checkmark.circle.fill"
        case .review: return "eye.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        }
    }

    private var style: Color {
        guard candidate.isActionable else { return .secondary }
        switch candidate.risk {
        case .low: return .green
        case .review: return .orange
        case .high: return .red
        }
    }
}
