import Foundation

/// Lifetime stats written by the worker script after each run.
/// Format is the same key=value style as the config file.
struct Stats {
    var totalMoved: Int = 0
    var lastRunTs: TimeInterval? = nil
    var lastRunMoved: Int = 0
    var lastRunFailed: Int = 0

    static var filePath: String {
        "\(NSHomeDirectory())/.local/state/fast_t_mover/stats"
    }

    static func load() -> Stats {
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8)
        else { return Stats() }
        var s = Stats()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let val = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            switch key {
            case "TOTAL_MOVED":     s.totalMoved = Int(val) ?? 0
            case "LAST_RUN_TS":     s.lastRunTs  = TimeInterval(val)
            case "LAST_RUN_MOVED":  s.lastRunMoved = Int(val) ?? 0
            case "LAST_RUN_FAILED": s.lastRunFailed = Int(val) ?? 0
            default: break
            }
        }
        return s
    }

    var lastRunDate: Date? {
        lastRunTs.map { Date(timeIntervalSince1970: $0) }
    }
}
