import Foundation

// Legacy launchd agent. No longer installed — MoverScheduler runs the mover
// from inside the app — but still needed to detect and remove an agent left
// by HPA ≤ 1.4.3.
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
