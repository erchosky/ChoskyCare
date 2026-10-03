import AppKit
import SwiftUI

@main
struct ChoskyCareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("menu.scan")) {
                Button(L("action.scan_home")) { appModel.scanHomeDirectory() }
                    .keyboardShortcut("r")
                Button(L("action.scan_software")) { appModel.scanSoftware() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(appModel.isScanningSoftware)
                Divider()
                Button(L("action.cancel_scan")) { appModel.cancelStorageScan() }
                    .keyboardShortcut(".")
                    .disabled(!appModel.isScanningStorage)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .frame(width: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched as a bare executable (`swift run`, Xcode package scheme)
        // macOS treats the process as a background tool; make it a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
