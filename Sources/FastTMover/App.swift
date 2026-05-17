import SwiftUI
import AppKit

@main
struct FastTMoverApp: App {
    @AppStorage("autoRunEnabled") private var autoRunEnabled = false

    var body: some Scene {
        MenuBarExtra {
            MenuContents()
        } label: {
            // Text label + symbol for max visibility — easier to spot in a
            // crowded menu bar on a notched MacBook than a bare SF symbol.
            Label("FTM", systemImage: "externaldrive.fill.badge.plus")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

struct MenuContents: View {
    @AppStorage("autoRunEnabled") private var autoRunEnabled = false

    var body: some View {
        Button("Run Now") {
            _ = Runner.run(debug: false)
        }
        Button("Run Now (debug)") {
            _ = Runner.run(debug: true)
        }
        Divider()
        Toggle("Auto-run on wake", isOn: $autoRunEnabled)
            .onChange(of: autoRunEnabled) { newValue in
                if newValue, let script = Runner.scriptPath {
                    try? LaunchAgent.install(scriptPath: script)
                } else {
                    LaunchAgent.uninstall()
                }
            }
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Button("Show Log") {
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.logFile))
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
