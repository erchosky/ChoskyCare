import QuickLook
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 235)
            .safeAreaInset(edge: .bottom) {
                PrivacyBadge()
                    .padding(12)
            }
        } detail: {
            Group {
                switch model.selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .storage: StorageView()
                case .largeFiles: LargeFilesView()
                case .downloads: DownloadsView()
                case .software: SoftwareCareView()
                case .safeCleanup: SafeCleanupView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) {
                if let banner = model.banner {
                    BannerView(banner: banner) { model.dismissBanner() }
                        .padding()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.banner)
        }
        .quickLookPreview($model.quickLookURL)
    }
}

private struct PrivacyBadge: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L("privacy.local"), systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
            Text(L("privacy.detail"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct BannerView: View {
    let banner: Banner
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(banner.message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("action.dismiss"))
        }
        .padding(12)
        .frame(maxWidth: 720)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var symbol: String {
        switch banner.kind {
        case .error: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .error: .red
        case .success: .green
        case .info: .blue
        }
    }
}
