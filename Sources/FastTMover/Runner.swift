import Foundation

enum Runner {
    /// Path to the bundled worker script (Contents/Resources/move_torrents.sh).
    static var scriptPath: String? {
        Bundle.main.path(forResource: "move_torrents", ofType: "sh")
    }

    /// Run the worker script.
    /// - Parameter debug: verbose + loose match (matches files with the
    ///   pattern body anywhere in the name, for testing renamed files).
    /// - Parameter force: bypass the configured interval lock. Set true for
    ///   any user-initiated "Run Now" so the action isn't silently skipped
    ///   just because the interval hasn't elapsed.
    @discardableResult
    static func run(debug: Bool = false, force: Bool = false) -> (status: Int32, output: String) {
        guard let path = scriptPath else {
            return (-1, "Worker script not found in app bundle.")
        }
        var args = [path]
        if debug { args.append("--debug") }
        if force { args.append("--force") }
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return (-1, "Failed to launch: \(error)")
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, out)
    }
}
