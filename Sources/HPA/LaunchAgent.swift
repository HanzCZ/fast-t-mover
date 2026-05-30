import Foundation

enum LaunchAgent {
    static let label = "com.hanak.torrentmover"
    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
    }

    static func isLoaded() -> Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", label]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    static func install(scriptPath: String) throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(scriptPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>900</integer>
            <key>StandardOutPath</key>
            <string>\(NSHomeDirectory())/.local/state/fast_t_mover/launchd.out.log</string>
            <key>StandardErrorPath</key>
            <string>\(NSHomeDirectory())/.local/state/fast_t_mover/launchd.err.log</string>
        </dict>
        </plist>
        """
        let dir = "\(NSHomeDirectory())/Library/LaunchAgents"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: "\(NSHomeDirectory())/.local/state/fast_t_mover",
            withIntermediateDirectories: true)
        if isLoaded() { _ = launchctl("unload", plistPath) }
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        _ = launchctl("load", plistPath)
    }

    static func uninstall() {
        if isLoaded() { _ = launchctl("unload", plistPath) }
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    @discardableResult
    private static func launchctl(_ verb: String, _ path: String) -> Int32 {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = [verb, path]
        do { try task.run() } catch { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
