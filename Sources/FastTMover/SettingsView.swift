import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("sourceDir") private var sourceDir  = "\(NSHomeDirectory())/Downloads"
    @AppStorage("smbURL")    private var smbURL     = "smb://192.168.0.249/shdd"
    @AppStorage("destSubdir") private var destSubdir = "new-torrents"
    @AppStorage("pattern")   private var pattern    = "*.torrent"
    @AppStorage("autoRunEnabled") private var autoRunEnabled = false

    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("Source") {
                HStack {
                    TextField("Source folder", text: $sourceDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Pick…") { pickFolder() }
                }
                TextField("File pattern (glob)", text: $pattern)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Destination (SMB share)") {
                TextField("SMB URL", text: $smbURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Destination subfolder", text: $destSubdir)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Automation") {
                Toggle("Run automatically (≈ on wake, max 1×/day)",
                       isOn: $autoRunEnabled)
                    .onChange(of: autoRunEnabled, perform: applyAutoRun)
                Text("Uses a launchd agent that polls every 15 min; an internal lock keeps it to one effective run per day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Save") { saveConfig() }
                        .keyboardShortcut(.defaultAction)
                    Button("Run Now (debug)") { runDebug() }
                    Spacer()
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: sourceDir)
        if panel.runModal() == .OK, let url = panel.url {
            sourceDir = url.path
        }
    }

    private func saveConfig() {
        Config.writeConfig(
            sourceDir: sourceDir, smbURL: smbURL,
            destSubdir: destSubdir, pattern: pattern
        )
        statusMessage = "Saved to \(Config.configFile)"
    }

    private func runDebug() {
        saveConfig()
        let result = Runner.run(debug: true)
        statusMessage = "Exit \(result.status). See Show Log for details."
    }

    private func applyAutoRun(_ enabled: Bool) {
        saveConfig()
        if enabled {
            guard let script = Runner.scriptPath else {
                statusMessage = "Worker script missing from bundle."
                autoRunEnabled = false
                return
            }
            do {
                try LaunchAgent.install(scriptPath: script)
                statusMessage = "Auto-run enabled."
            } catch {
                statusMessage = "Failed to install launch agent: \(error)"
                autoRunEnabled = false
            }
        } else {
            LaunchAgent.uninstall()
            statusMessage = "Auto-run disabled."
        }
    }
}
