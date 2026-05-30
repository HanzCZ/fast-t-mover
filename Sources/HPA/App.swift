import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply persisted Dock visibility preference. Info.plist sets
        // LSUIElement=true (accessory) as the default; switching to .regular
        // here makes the icon appear if the user opted in.
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        NotificationManager.shared.setup()

        // Quietly check GitHub for a newer release; prompts only if one exists.
        let autoCheck = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true
        if autoCheck { UpdaterUI.checkOnLaunch() }
    }
}

@main
struct HPAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContents()
        } label: {
            // Text label + symbol for max visibility — easier to spot in a
            // crowded menu bar on a notched MacBook than a bare SF symbol.
            Label("HPA", systemImage: "person.crop.circle.badge.checkmark")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContents: View {
    var body: some View {
        Button("Move Files") {
            _ = Runner.run(force: true)
        }
        Button("Move Files (debug)") {
            _ = Runner.run(debug: true, force: true)
        }
        Divider()
        Button("Objednávkové / dodávkové listy…") {
            ListyWindowController.shared.show()
        }
        Divider()
        Button("Asana — generator Helpdesk Blockers…") {
            AsanaWindowController.shared.show(mode: .blockers)
        }
        Button("Asana — generator Sprint Passives…") {
            AsanaWindowController.shared.show(mode: .passives)
        }
        Divider()
        Button("Fakturoid — faktury…") {
            FakturoidWindowController.shared.show()
        }
        Divider()
        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        Button("Show Log") {
            NSWorkspace.shared.open(URL(fileURLWithPath: Config.logFile))
        }
        Button("Zkontrolovat aktualizace…") {
            UpdaterUI.checkInteractive()
        }
        Text("HPA \(Updater.currentVersion)")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
