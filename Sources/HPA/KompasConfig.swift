import Foundation

// Targets for the "Helpdesk blockers" / "Sprint Passives" generators in Kompas
// (kompas.ssgh.cz), which replaced Asana for these boards.
enum KompasConfig {
    static let base = "https://kompas.ssgh.cz"
    static let webURL = URL(string: base)!

    // Projects are addressed by any reference the Kompas API accepts: the
    // project's cuid, its numeric Kompas GID (Nastavení projektu → Time
    // Tracker API) or its original Asana gid. The defaults are the Asana gids
    // the boards had before the move, which keep working for projects that
    // were imported from Asana; override in Settings otherwise.
    static let defaultBlockersProject = "1213719009291832"   // Internal IT v2
    static let defaultPassivesProject = "1211340374914010"   // AL x SSGH v2
    static let defaultDebugProject = "1211198655098271"      // JH Tasks

    static let blockersProjectKey = "kompasBlockersProject"
    static let passivesProjectKey = "kompasPassivesProject"
    static let debugProjectKey = "kompasDebugProject"

    private static func project(_ key: String, _ fallback: String) -> String {
        let v = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? fallback : v
    }

    static var blockersProject: String { project(blockersProjectKey, defaultBlockersProject) }
    static var passivesProject: String { project(passivesProjectKey, defaultPassivesProject) }
    // Debug run target: Jan Hanák's personal "JH Tasks" project, everything
    // assigned to himself, so a test never touches the real boards or
    // notifies the assignees.
    static var debugProject: String { project(debugProjectKey, defaultDebugProject) }
    static let debugAssignee = "Jan Hanák"

    // Fixed description template (from the original Asana rule).
    static let descriptionTemplate =
        "Sem si pište vyřešený seznam úkolů z helpdesku ideálně do subtasku ve formátu\nID - nazev - x h"

    struct Person: Identifiable, Hashable {
        var id: String { initials }
        let initials: String
        // Must match the person's display name in Kompas — the API resolves
        // the assignee by exact name.
        let name: String
        var defaultEstimate: Double
    }

    // The helpdesk-blocker assignees. defaultEstimate is just the initial
    // prefill; the UI lets you change it per sprint and remembers your last value.
    static let roster: [Person] = [
        Person(initials: "DŠ", name: "David Šubr",     defaultEstimate: 25),
        Person(initials: "TV", name: "Tomáš Vocetka",  defaultEstimate: 60),
        Person(initials: "VM", name: "Václav Macura",  defaultEstimate: 17),
    ]

    // Bump when the roster or its defaultEstimate values change, so
    // KompasTaskSettings re-seeds the persisted per-person estimates once.
    // (3 = estimates re-keyed from Asana user gid to initials.)
    static let estimateDefaultsVersion = 3

    struct SprintOption: Identifiable, Hashable {
        let id: String      // Kompas sprint id "YYYY-MM-1" / "YYYY-MM-2"
        let label: String   // "S 01.10. - 15.10."
    }

    // Kompas sprints are deterministic from the calendar: 1st–15th is
    // "YYYY-MM-1", 16th–end of month is "YYYY-MM-2".
    static func sprintID(for date: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%d", c.year ?? 2026, c.month ?? 1, (c.day ?? 1) <= 15 ? 1 : 2)
    }

    static func sprintLabel(_ id: String) -> String {
        let p = id.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return id }
        let (year, month, half) = (p[0], p[1], p[2])
        let cal = Calendar(identifier: .gregorian)
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let lastDay = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        return half == 1
            ? String(format: "S 01.%02d. - 15.%02d.", month, month)
            : String(format: "S 16.%02d. - %02d.%02d.", month, lastDay, month)
    }

    // The two previous sprints, the current one and the next five — enough to
    // back-fill a missed sprint or prepare the upcoming ones.
    static func sprintOptions(around date: Date = Date()) -> [SprintOption] {
        let p = sprintID(for: date).split(separator: "-").compactMap { Int($0) }
        // Index sprints as half-months since year 0 so stepping is plain arithmetic.
        let current = (p[0] * 12 + (p[1] - 1)) * 2 + (p[2] - 1)
        return (current - 2 ... current + 5).map { i in
            let id = String(format: "%04d-%02d-%d", i / 24, (i / 2) % 12 + 1, i % 2 + 1)
            return SprintOption(id: id, label: sprintLabel(id))
        }
    }

    // "Sprint Passives" — a single recurring task per sprint in AL x SSGH v2.
    enum Passives {
        static let taskName = "Sprint Passives"
        static let defaultEstimate: Double = 32
        static let defaultEstimateUpdated: Double = 12
        static let description =
            "AD hoc fixing bloker per sprint\nKomunikace + naceňování per sprint\nDeploy per sprint"
    }
}
