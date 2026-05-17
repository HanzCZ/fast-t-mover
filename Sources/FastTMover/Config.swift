import Foundation

enum Config {
    static let configDir  = "\(NSHomeDirectory())/.config/fast_t_mover"
    static let configFile = "\(configDir)/config"
    static let stateDir   = "\(NSHomeDirectory())/.local/state/fast_t_mover"
    static let logFile    = "\(stateDir)/torrent_mover.log"

    static func writeConfig(
        sourceDir: String,
        smbURL: String,
        destSubdir: String,
        pattern: String,
        allowedSSIDs: String,
        intervalHours: Int,
        maxAgeDays: Int
    ) {
        try? FileManager.default.createDirectory(
            atPath: configDir, withIntermediateDirectories: true
        )
        // Quote values so shell `source` handles spaces and special chars.
        let body = """
        SOURCE_DIR=\(shellQuote(sourceDir))
        SMB_URL=\(shellQuote(smbURL))
        DEST_SUBDIR=\(shellQuote(destSubdir))
        PATTERN=\(shellQuote(pattern))
        ALLOWED_SSIDS=\(shellQuote(allowedSSIDs))
        INTERVAL_HOURS=\(intervalHours)
        MAX_AGE_DAYS=\(maxAgeDays)
        """
        try? body.write(toFile: configFile, atomically: true, encoding: .utf8)
    }

    /// Return the current Wi-Fi SSID, or nil if not on Wi-Fi.
    static func currentSSID() -> String? {
        guard let iface = currentWiFiInterface() else { return nil }
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-getairportnetwork", iface]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        guard let range = out.range(of: "Current Wi-Fi Network: ") else { return nil }
        return out[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentWiFiInterface() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-listallhardwareports"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        let lines = out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.contains("Hardware Port: Wi-Fi"), i + 1 < lines.count {
                let dev = lines[i + 1]
                if let r = dev.range(of: "Device: ") {
                    return String(dev[r.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
