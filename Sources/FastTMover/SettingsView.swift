import SwiftUI
import AppKit
import CoreLocation

struct SettingsView: View {
    @AppStorage("sourceDir")    private var sourceDir   = "\(NSHomeDirectory())/Downloads"
    @AppStorage("smbURL")       private var smbURL      = "smb://192.168.0.249/shdd"
    @AppStorage("destSubdir")   private var destSubdir  = "new-torrents"
    @AppStorage("pattern")      private var pattern     = "*.torrent"
    @AppStorage("allowedSSIDs") private var allowedSSIDs = ""
    @AppStorage("intervalHours") private var intervalHours: Int = 24
    @AppStorage("maxAgeDays")   private var maxAgeDays: Int = 0
    @AppStorage("autoRunEnabled") private var autoRunEnabled = false
    @AppStorage("showInDock")   private var showInDock = false

    @State private var statusMessage = ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var verifyLines: [String] = []
    @State private var verifying = false
    @State private var stats = Stats.load()

    // Refresh stats periodically so the hero card stays live while the
    // window is open and the script runs in the background.
    private let statsTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
            Divider()
            ScrollView { form }
            Divider()
            footer
        }
        .frame(width: 620, height: 720)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(statsTimer) { _ in stats = Stats.load() }
        .onAppear { stats = Stats.load() }
    }

    // MARK: - Hero header (stats + status pill)

    private var heroHeader: some View {
        HStack(spacing: 18) {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(stats.totalMoved)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(stats.totalMoved == 1 ? "file moved" : "files moved")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text(lastRunDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var statusPill: some View {
        let active = autoRunEnabled
        let title  = active ? "Active" : "Paused"
        let color: Color = active ? .green : .secondary
        let symbol = active ? "circle.fill" : "pause.circle.fill"
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.18), in: Capsule())
    }

    private var lastRunDescription: String {
        guard let date = stats.lastRunDate else {
            return "No runs yet — click Run Now (debug) below to test."
        }
        let rel = Self.rel.localizedString(for: date, relativeTo: Date())
        var bits = ["Last run \(rel)"]
        if stats.lastRunMoved > 0 {
            bits.append("\(stats.lastRunMoved) moved")
        }
        if stats.lastRunFailed > 0 {
            bits.append("\(stats.lastRunFailed) failed")
        }
        return bits.joined(separator: " · ")
    }

    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    // MARK: - Form sections

    private var form: some View {
        Form {
            Section {
                LabeledField("Folder") {
                    HStack {
                        TextField("", text: $sourceDir)
                            .textFieldStyle(.roundedBorder)
                        Button("Pick…") { pickFolder() }
                    }
                }
                LabeledField("Pattern") {
                    TextField("", text: $pattern)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Max file age") {
                    Picker("", selection: $maxAgeDays) {
                        Text("All time").tag(0)
                        Text("Last week").tag(7)
                        Text("Last month").tag(30)
                        Text("Last year").tag(365)
                    }
                    .labelsHidden()
                }
            } header: {
                SectionHeader(icon: "folder.fill", tint: .blue, title: "Source")
            }

            Section {
                LabeledField("SMB URL") {
                    TextField("", text: $smbURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Subfolder") {
                    TextField("", text: $destSubdir)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                SectionHeader(icon: "externaldrive.fill", tint: .purple, title: "Destination")
            }

            Section {
                LabeledField("Allowed SSIDs") {
                    HStack {
                        TextField("comma-separated, empty = any", text: $allowedSSIDs)
                            .textFieldStyle(.roundedBorder)
                        Button("Add current") { addCurrentSSID() }
                    }
                }
                Text("Type your Wi-Fi name into the field — manual entry always works. The Add current button requests Location Services (required on macOS 14.4+ to read SSID).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader(icon: "wifi", tint: .teal, title: "Network gate")
            }

            Section {
                Toggle("Launch FastTMover at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, perform: applyLaunchAtLogin)
                Toggle("Run automatically (≈ on wake)", isOn: $autoRunEnabled)
                    .onChange(of: autoRunEnabled, perform: applyAutoRun)
                LabeledField("Minimum interval") {
                    Picker("", selection: $intervalHours) {
                        Text("Every wake (no lock)").tag(0)
                        Text("Every hour").tag(1)
                        Text("Every 4 hours").tag(4)
                        Text("Every 12 hours").tag(12)
                        Text("Once a day").tag(24)
                    }
                    .labelsHidden()
                }
                Text("LaunchAgent ticks every 15 min; the interval above gates the actual work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader(icon: "clock.fill", tint: .orange, title: "Automation")
            }

            Section {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock, perform: applyShowInDock)
                Text("Useful if the menu bar item is hard to find (e.g. notch overflow).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader(icon: "paintbrush.fill", tint: .pink, title: "Appearance")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Footer (actions + status + verify panel)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Save") { saveConfig() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                Button("Verify Access") { runVerify() }
                    .disabled(verifying)
                Button("Run Now (debug)") { runDebug() }
                Spacer()
                if verifying {
                    ProgressView().controlSize(.small)
                }
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
                .frame(maxHeight: 180)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

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
        statusMessage = "Saved."
    }

    private func addCurrentSSID() {
        LocationPermissionManager.shared.ensureAuthorized { status in
            switch status {
            case .authorizedAlways, .authorized:
                self.appendCurrentSSID()
            case .denied, .restricted:
                self.statusMessage = "Location Services denied. Type SSID manually, or enable in System Settings → Privacy & Security → Location Services → FastTMover."
            case .notDetermined:
                self.statusMessage = "Permission prompt dismissed. Try again, or type SSID manually."
            @unknown default:
                self.statusMessage = "Unknown Location Services state. Type SSID manually."
            }
        }
    }

    private func appendCurrentSSID() {
        guard let ssid = Config.currentSSID(), !ssid.isEmpty else {
            statusMessage = "Could not read Wi-Fi name. Type it manually above."
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
                statusMessage = result.ok ? "Verify Access: all OK" : "Verify Access: see results"
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
        stats = Stats.load()
    }

    private func applyShowInDock(_ enabled: Bool) {
        NSApp.setActivationPolicy(enabled ? .regular : .accessory)
        if enabled { NSApp.activate(ignoringOtherApps: true) }
        statusMessage = enabled ? "Dock icon shown." : "Dock icon hidden."
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if let err = LoginItem.setEnabled(enabled) {
            statusMessage = "Login item: \(err)"
            launchAtLogin = LoginItem.isEnabled
        } else {
            statusMessage = enabled ? "Will launch at login." : "Will not launch at login."
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

// MARK: - Small reusable UI pieces

private struct SectionHeader: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.headline)
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        LabeledContent {
            content()
        } label: {
            Text(label)
        }
    }
}
