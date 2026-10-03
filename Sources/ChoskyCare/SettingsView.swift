import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("showSafetyExplanations") private var showSafetyExplanations = true
    @AppStorage(ScanOptions.thresholdDefaultsKey) private var thresholdMB = 250.0
    @AppStorage(ScanOptions.includeHiddenDefaultsKey) private var includeHiddenFiles = true

    var body: some View {
        Form {
            Section(L("settings.safety")) {
                Toggle(L("settings.explanations"), isOn: $showSafetyExplanations)
                Text(L("settings.explanations_detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.scanning")) {
                LabeledContent(L("settings.large_threshold")) {
                    HStack {
                        Slider(value: $thresholdMB, in: 50...4_000, step: 50)
                            .frame(width: 180)
                        Text(Int64(thresholdMB * 1_024 * 1_024).formattedBytes)
                            .monospacedDigit()
                            .frame(width: 75, alignment: .trailing)
                    }
                }
                Toggle(L("settings.include_hidden"), isOn: $includeHiddenFiles)
                Text(L("settings.threshold_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.privacy")) {
                Label(L("settings.local_only"), systemImage: "lock.shield")
                Label(L("settings.no_telemetry"), systemImage: "network.slash")
                Label(L("settings.trash_first"), systemImage: "trash")
                Button(L("settings.open_full_disk_access")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text(L("settings.full_disk_access_detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
    }
}
