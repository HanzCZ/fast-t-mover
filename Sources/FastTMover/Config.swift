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
        pattern: String
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
        """
        try? body.write(toFile: configFile, atomically: true, encoding: .utf8)
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
