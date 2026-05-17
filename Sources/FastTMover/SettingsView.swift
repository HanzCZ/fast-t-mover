import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("sourceDir") private var sourceDir  = "\(NSHomeDirectory())/Downloads"
    @AppStorage("smbURL")    private var smbURL     = "smb://192.168.0.249/shdd"
    @AppStorage("destSubdir") private var destSubdir = "new-torrents"
    @AppStorage("pattern")   private var pattern    = "*.torrent"
    @AppStorage("allowedSSIDs") private var allowedSSIDs = ""
    @AppStorage("intervalHours") private var intervalHours: Int = 24
    @AppStorage("maxAgeDays") private var maxAgeDays: Int = 0
    @AppStorage("autoRunEnabled") private var autoRunEnabled = false
    @AppStorage("showInDock") private var showInDock = false

    @State private var statusMessage = ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var verifyLines: [String] = []
    @State private var verifying = false

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            footer
        }
        .frame(width: 560)
    }

    private var form: some View {
        Form {
            Section("Source") {
                HStack {
                    TextField("Source folder", text: $sourceDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Pick…") { pickFolder() }
                }
                TextField("File pattern (glob)", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                Picker("Only files modified within", selection: $maxAgeDays) {
                    Text("All time").tag(0)
                    Text("Last week").tag(7)
                    Text("Last month").tag(30)
                    Text("Last year").tag(365)
                }
            }

            Section("Destination (SMB share)") {
                TextField("SMB URL", text: $smbURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Destination subfolder", text: $destSubdir)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Network gate") {
                HStack {
                    TextField("Allowed Wi-Fi SSIDs (comma-separated, empty = any)",
                              text: $allowedSSIDs)
                        .textFieldStyle(.roundedBorder)
                    Button("Add current") { addCurrentSSID() }
                }
                Text("If non-empty, the script only runs when connected to one of these Wi-Fis. Off-network ticks exit cleanly and retry on the next tick — the daily lock is only taken on success.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock, perform: applyShowInDock)
                Text("When off, the app lives only in the menu bar. Turn on if the menu bar item is hard to find (e.g. hidden by the notch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automation") {
                Toggle("Launch FastTMover at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, perform: applyLaunchAtLogin)
                Toggle("Run automatically (≈ on wake)",
                       isOn: $autoRunEnabled)
                    .onChange(of: autoRunEnabled, perform: applyAutoRun)
                Picker("Minimum interval between runs", selection: $intervalHours) {
                    Text("Every wake (no lock)").tag(0)
                    Text("Every hour").tag(1)
                    Text("Every 4 hours").tag(4)
                    Text("Every 12 hours").tag(12)
                    Text("Once a day").tag(24)
                }
                Text("LaunchAgent ticks every 15 min; the interval above gates the actual work. With Wi-Fi whitelist set, the first allowed-Wi-Fi tick after the interval elapses does the job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(20)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Save") { saveConfig() }
                    .keyboardShortcut(.defaultAction)
                Button("Verify Access") { runVerify() }
                    .disabled(verifying)
                Button("Run Now (debug)") { runDebug() }
                Spacer()
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !verifyLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(verifyLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxHeight: 160)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(16)
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
            destSubdir: destSubdir, pattern: pattern,
            allowedSSIDs: allowedSSIDs,
            intervalHours: intervalHours,
            maxAgeDays: maxAgeDays
        )
        statusMessage = "Saved to \(Config.configFile)"
    }

    private func addCurrentSSID() {
        guard let ssid = Config.currentSSID(), !ssid.isEmpty else {
            statusMessage = "Not connected to Wi-Fi."
            return
        }
        let existing = allowedSSIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if existing.contains(ssid) {
            statusMessage = "'\(ssid)' already in list."
            return
        }
        let combined = existing + [ssid]
        allowedSSIDs = combined.joined(separator: ", ")
        statusMessage = "Added '\(ssid)'. Click Save."
    }

    private func runVerify() {
        saveConfig()
        verifying = true
        verifyLines = ["• Running access checks…"]
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AccessCheck.run(
                sourceDir: sourceDir,
                smbURL: smbURL,
                destSubdir: destSubdir
            )
            DispatchQueue.main.async {
                verifyLines = result.lines
                verifying = false
                statusMessage = result.ok
                    ? "Verify Access: all OK"
                    : "Verify Access: see results"
                NotificationManager.shared.post(
                    title: "FastTMover",
                    body: result.ok
                        ? "Access verification passed."
                        : "Access verification failed — see Settings.",
                    kind: result.ok ? .success : .failure
                )
            }
        }
    }

    private func runDebug() {
        saveConfig()
        let result = Runner.run(debug: true, force: true)
        statusMessage = "Exit \(result.status). See Show Log for details."
    }

    private func applyShowInDock(_ enabled: Bool) {
        NSApp.setActivationPolicy(enabled ? .regular : .accessory)
        if enabled {
            // Bring the settings window back to front — switching policy can
            // shuffle focus.
            NSApp.activate(ignoringOtherApps: true)
        }
        statusMessage = enabled ? "Dock icon shown." : "Dock icon hidden."
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if let err = LoginItem.setEnabled(enabled) {
            statusMessage = "Login item: \(err)"
            launchAtLogin = LoginItem.isEnabled   // revert toggle to truth
        } else {
            statusMessage = enabled
                ? "Will launch at login."
                : "Will not launch at login."
        }
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
