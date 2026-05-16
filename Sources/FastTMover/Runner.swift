import Foundation

enum Runner {
    /// Path to the bundled worker script (Contents/Resources/move_torrents.sh).
    static var scriptPath: String? {
        Bundle.main.path(forResource: "move_torrents", ofType: "sh")
    }

    /// Run the worker script. `debug=true` bypasses the once-per-day lock.
    @discardableResult
    static func run(debug: Bool) -> (status: Int32, output: String) {
        guard let path = scriptPath else {
            return (-1, "Worker script not found in app bundle.")
        }
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = debug ? [path, "--debug"] : [path]

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
