import Foundation

// Resolved Asana identifiers for the "Helpdesk blockers" bulk-create feature.
// All GIDs were introspected from the live workspace on 2026-05-29.
// Workspace: "To dáš + SSGH projekty" (1205885361319934).
enum AsanaConfig {
    static let projectGID = "1213719009291832"          // Internal IT v2
    static let sprintFieldGID = "1211636132322426"      // AL SPRINT (enum)
    static let estimateFieldGID = "1211636213898517"    // "Estimate original (h)" (number)
    static let stageFieldGID = "1211217441906541"       // Stage (enum)
    static let stageTodoOptionGID = "1211217441906545"  // Stage → Todo

    // Debug run targets: drop everything into Jan Hanák's personal "JH Tasks"
    // project and assign all tasks to himself, so a test never touches the
    // real Internal IT v2 board or notifies the four assignees. JH Tasks has
    // the same AL SPRINT + Estimate custom fields, so the payload is identical.
    static let debugProjectGID = "1211198655098271"     // JH Tasks
    static let janHanakGID = "1211175839412503"         // Jan Hanák

    // Browser permalinks (Asana permalink_url) for quick-open links in the UI.
    static let internalITURL = URL(string: "https://app.asana.com/1/1205885361319934/project/1213719009291832")!
    static let alSSGHURL     = URL(string: "https://app.asana.com/1/1205885361319934/project/1211340374914010")!
    static let jhTasksURL    = URL(string: "https://app.asana.com/1/1205885361319934/project/1211198655098271")!

    // Fixed description template (from the existing Asana rule).
    static let descriptionTemplate =
        "Sem si pište vyřešený seznam úkolů z helpdesku ideálně do subtasku ve formátu\nID - nazev - x h"

    struct Person: Identifiable, Hashable {
        var id: String { gid }
        let initials: String
        let name: String
        let gid: String
        var defaultEstimate: Double
    }

    // The four helpdesk-blocker assignees. defaultEstimate is just the initial
    // prefill; the UI lets you change it per sprint and remembers your last value.
    static let roster: [Person] = [
        Person(initials: "DŠ", name: "David Šubr",     gid: "1207294577358300", defaultEstimate: 25),
        Person(initials: "TV", name: "Tomáš Vocetka",  gid: "1207400270047716", defaultEstimate: 60),
        Person(initials: "VM", name: "Václav Macura",  gid: "1207400269581479", defaultEstimate: 17),
        Person(initials: "MŠ", name: "Michal Šefl",    gid: "1207400270087549", defaultEstimate: 20),
    ]

    // Bump when roster defaultEstimate values change, so AsanaBlockerSettings
    // re-seeds the persisted per-person estimates from the new defaults once.
    static let estimateDefaultsVersion = 2

    struct SprintOption: Identifiable, Hashable {
        var id: String { gid }
        let gid: String
        let label: String
    }

    // AL SPRINT enum options, in workspace order. New sprints can be appended
    // here (or we add a live refresh later). "K nacenění" kept last as it's a
    // bucket, not a date range.
    static let sprintOptions: [SprintOption] = [
        .init(gid: "1212974883693817", label: "S 15.02. - 28.02."),
        .init(gid: "1213361646179456", label: "S 16.03. - 30.03."),
        .init(gid: "1213679236302119", label: "S 01.04. - 15.04."),
        .init(gid: "1213759144891236", label: "S 16.04. - 30.04."),
        .init(gid: "1213997645651857", label: "S 01.05. - 15.05."),
        .init(gid: "1214251416566397", label: "S 16.05. - 30.05."),
        .init(gid: "1214387558727693", label: "S 01.06. - 15.06."),
        .init(gid: "1214387558727694", label: "S 16.06 - 30.06."),
        .init(gid: "1214387558727695", label: "S 01.07. - 15.07."),
        .init(gid: "1214387558727696", label: "S 16.07 - 30.07."),
        .init(gid: "1214387558727697", label: "S 01.08. - 15.08."),
        .init(gid: "1214387558727698", label: "S 16.08 - 30.08."),
        .init(gid: "1214387558727699", label: "S 01.09. - 15.09."),
        .init(gid: "1214387558727700", label: "S 16.09 - 30.09."),
        .init(gid: "1214387558727701", label: "S 01.10. - 15.10."),
        .init(gid: "1214387558727702", label: "S 16.10 - 30.10."),
        .init(gid: "1211636788219765", label: "K nacenění"),
    ]

    // The sprint shown in the source screenshot — used as the initial default.
    static let defaultSprintGID = "1214387558727693" // S 01.06. - 15.06.

    static func sprintLabel(_ gid: String) -> String {
        sprintOptions.first { $0.gid == gid }?.label ?? gid
    }

    // "Sprint Passives" — a single recurring task per sprint in AL x SSGH v2.
    // Field GIDs introspected 2026-05-29. Note: AL SPRINT + Dev Status are
    // workspace-shared fields (same GIDs as elsewhere); "Projekt" is multi_enum.
    enum Passives {
        static let projectGID = "1211340374914010"           // AL x SSGH v2
        static let taskName = "Sprint Passives"
        static let devStatusFieldGID = "1211340401376363"    // Dev Status (enum)
        static let devStatusTodoGID = "1211340401376367"     // Dev Status → Todo
        static let projektFieldGID = "1211575632003718"      // Projekt (multi_enum)
        static let projektReoccurringGID = "1211636123951584"// Projekt → Reoccurring
        static let estimateFieldGID = "1211342159582571"     // Estimate (h) (number)
        static let estimateUpdatedFieldGID = "1211636214832297" // Estimate updated (h)
        static let defaultEstimate: Double = 32
        static let defaultEstimateUpdated: Double = 12
        static let description =
            "AD hoc fixing bloker per sprint\nKomunikace + naceňování per sprint\nDeploy per sprint"

        // JH Tasks (debug target) lacks Projekt / Estimate (h) / Estimate
        // updated, but has these workspace-shared fields, so a debug run sets a
        // compatible subset.
        static let debugEstimateOriginalFieldGID = "1211636213898517" // Estimate original (h)
    }

    // Parse a sprint label like "S 01.06. - 15.06." (formats are inconsistent —
    // some lack trailing dots) into (start, end) dates in the given year.
    private static func parseRange(_ label: String, year: Int) -> (start: Date, end: Date)? {
        let rx = try! NSRegularExpression(pattern: #"(\d{1,2})\.(\d{1,2})"#)
        let ns = label as NSString
        let ms = rx.matches(in: label, range: NSRange(location: 0, length: ns.length))
        guard ms.count >= 2 else { return nil }   // "K nacenění" has no dates
        let cal = Calendar(identifier: .gregorian)
        func date(_ m: NSTextCheckingResult) -> Date? {
            let day = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let mon = Int(ns.substring(with: m.range(at: 2))) ?? 0
            return cal.date(from: DateComponents(year: year, month: mon, day: day))
        }
        guard let s = date(ms[0]), let e = date(ms[1]) else { return nil }
        return (s, e)
    }

    // Pick the sprint whose range contains `now`; if none, the next upcoming
    // sprint; else the built-in default. Used to pre-select by the PC date.
    static func sprintGIDForToday(_ now: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: now)
        let year = cal.component(.year, from: now)

        for o in sprintOptions {
            if let r = parseRange(o.label, year: year),
               today >= cal.startOfDay(for: r.start), today <= cal.startOfDay(for: r.end) {
                return o.gid
            }
        }
        let upcoming = sprintOptions
            .compactMap { o -> (String, Date)? in
                guard let r = parseRange(o.label, year: year) else { return nil }
                return (o.gid, cal.startOfDay(for: r.start))
            }
            .filter { $0.1 > today }
            .sorted { $0.1 < $1.1 }
        return upcoming.first?.0 ?? defaultSprintGID
    }
}
