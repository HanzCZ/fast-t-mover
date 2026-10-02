import SwiftUI
import AppKit

// Persisted settings for the Kompas task generators: per-person estimate
// hours (remembers your last values) and lifetime counts. UserDefaults keys
// keep their "asana…" names from before the move to Kompas so nothing resets.
final class KompasTaskSettings: ObservableObject {
    static let shared = KompasTaskSettings()
    private let d = UserDefaults.standard

    // Selected sprint (Kompas id "YYYY-MM-N"); not persisted — re-derived from
    // today's date whenever the window opens.
    @Published var sprintID: String
    @Published var estimates: [String: Double] {   // keyed by person initials
        didSet { d.set(estimates, forKey: "asanaEstimates") }
    }
    // Lifetime statistics of generated helpdesk blockers.
    @Published var realCreated: Int {
        didSet { d.set(realCreated, forKey: "asanaRealCreated") }
    }
    @Published var debugCreated: Int {
        didSet { d.set(debugCreated, forKey: "asanaDebugCreated") }
    }
    // Sprint Passives: editable estimates + lifetime counts.
    @Published var passivesEstimate: Double {
        didSet { d.set(passivesEstimate, forKey: "asanaPassivesEstimate") }
    }
    @Published var passivesEstimateUpdated: Double {
        didSet { d.set(passivesEstimateUpdated, forKey: "asanaPassivesEstimateUpdated") }
    }
    @Published var passivesCreated: Int {
        didSet { d.set(passivesCreated, forKey: "asanaPassivesCreated") }
    }
    @Published var passivesDebugCreated: Int {
        didSet { d.set(passivesDebugCreated, forKey: "asanaPassivesDebugCreated") }
    }

    // Pre-select the sprint matching the current PC date. Called when the
    // window opens, so the dropdown always defaults to today's sprint (the
    // user can still pick another for that session).
    func selectSprintForToday() {
        sprintID = KompasConfig.sprintID()
    }

    func recordCreated(_ n: Int, debug: Bool) {
        guard n > 0 else { return }
        if debug { debugCreated += n } else { realCreated += n }
    }

    func recordPassivesCreated(debug: Bool) {
        if debug { passivesDebugCreated += 1 } else { passivesCreated += 1 }
    }

    private init() {
        sprintID = KompasConfig.sprintID()
        realCreated = d.integer(forKey: "asanaRealCreated")
        debugCreated = d.integer(forKey: "asanaDebugCreated")
        passivesEstimate = d.object(forKey: "asanaPassivesEstimate") as? Double
            ?? KompasConfig.Passives.defaultEstimate
        passivesEstimateUpdated = d.object(forKey: "asanaPassivesEstimateUpdated") as? Double
            ?? KompasConfig.Passives.defaultEstimateUpdated
        passivesCreated = d.integer(forKey: "asanaPassivesCreated")
        passivesDebugCreated = d.integer(forKey: "asanaPassivesDebugCreated")
        let storedVersion = d.integer(forKey: "asanaEstimatesVersion")
        let seed = Dictionary(uniqueKeysWithValues:
            KompasConfig.roster.map { ($0.id, $0.defaultEstimate) })
        if let raw = d.dictionary(forKey: "asanaEstimates") as? [String: Double],
           storedVersion == KompasConfig.estimateDefaultsVersion {
            estimates = raw
        } else {
            // First run, or roster defaults changed — (re)seed from defaults.
            estimates = seed
            d.set(seed, forKey: "asanaEstimates")
            d.set(KompasConfig.estimateDefaultsVersion, forKey: "asanaEstimatesVersion")
        }
    }

    func estimate(for p: KompasConfig.Person) -> Double {
        estimates[p.id] ?? p.defaultEstimate
    }
    func setEstimate(_ v: Double, for p: KompasConfig.Person) {
        estimates[p.id] = v
    }
}

struct KompasBlockersView: View {
    @ObservedObject var settings = KompasTaskSettings.shared
    @State private var running = false
    @State private var log: [String] = []
    @State private var doneOK = false

    private var count: Int { KompasConfig.roster.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Helpdesk blockery → Kompas").font(.title2).bold()
            Text("Založí \(count) tasky „Helpdesk Blocker <iniciály>“ do projektu Internal IT v2, "
                 + "každému svému člověku, se stejným sprintem a vlastním odhadem.")
                .font(.callout).foregroundStyle(.secondary)
            Link(destination: KompasConfig.webURL) {
                Label("kompas.ssgh.cz", systemImage: "arrow.up.right.square")
            }
            .font(.callout)

            HStack {
                Text("Sprint").frame(width: 110, alignment: .leading)
                Picker("", selection: $settings.sprintID) {
                    ForEach(KompasConfig.sprintOptions()) { o in
                        Text(o.label).tag(o.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }
            HStack {
                Text("Stage").frame(width: 110, alignment: .leading)
                Text("Todo").foregroundStyle(.secondary)
            }
            HStack {
                Text("Due date").frame(width: 110, alignment: .leading)
                Text("— žádné —").foregroundStyle(.secondary)
            }

            if !KompasClient.hasToken {
                Label("Chybí Kompas API token (Settings → Kompas — připojení) — bez něj nelze zakládat.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Iniciály").frame(width: 70, alignment: .leading)
                Text("Člověk").frame(maxWidth: .infinity, alignment: .leading)
                Text("Estimate (h)").frame(width: 110, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.top, 10)

            List {
                ForEach(KompasConfig.roster) { p in
                    HStack {
                        Text(p.initials).bold().frame(width: 70, alignment: .leading)
                        Text(p.name).frame(maxWidth: .infinity, alignment: .leading)
                        TextField("h", value: Binding(
                            get: { settings.estimate(for: p) },
                            set: { settings.setEstimate($0, for: p) }
                        ), format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)

            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(log, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Sprint: ").foregroundColor(.secondary)
                + Text(KompasConfig.sprintLabel(settings.sprintID)).bold()
            Spacer()
            if running { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button {
                Task { await create(debug: true) }
            } label: {
                Label("Debug run", systemImage: "ladybug")
            }
            .controlSize(.large)
            .tint(.orange)
            .disabled(running || !KompasClient.hasToken)
            .help("Založí ty samé tasky do projektu JH Tasks a přiřadí je tobě (Jan Hanák) — bezpečný test, nikoho neotravuje.")

            Button {
                Task { await create(debug: false) }
            } label: {
                Label("Vytvořit \(count) blockery v Kompasu", systemImage: "paperplane.fill")
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(running || !KompasClient.hasToken)
        }
        .padding(16)
    }

    @MainActor
    private func confirm(title: String, text: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .warning
        a.addButton(withTitle: "Vytvořit další")
        a.addButton(withTitle: "Zrušit")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func create(debug: Bool) async {
        running = true; doneOK = false
        defer { running = false }
        let sprint = settings.sprintID
        let sprintLabel = KompasConfig.sprintLabel(sprint)
        let project = debug ? KompasConfig.debugProject : KompasConfig.blockersProject
        let projectLabel = debug ? "JH Tasks (debug)" : "Internal IT v2"

        // Duplicate guard: warn if this sprint already has blockers in the
        // target project.
        log = ["• Kontroluji existující blockery v \(sprintLabel)…"]
        do {
            let existing = try await KompasClient.existingTasks(
                project: project, sprintID: sprint, namePrefix: "Helpdesk Blocker")
            if !existing.isEmpty {
                let initials = existing
                    .map { $0.replacingOccurrences(of: "Helpdesk Blocker ", with: "") }
                    .joined(separator: ", ")
                let proceed = confirm(
                    title: "Ve sprintu už blockery jsou",
                    text: "V projektu \(projectLabel) už pro \(sprintLabel) "
                        + "existuje \(existing.count) blockerů (\(initials)).\n\nVytvořit další \(count)?")
                if !proceed {
                    log.append("Zrušeno — duplicitní sprint.")
                    return
                }
            }
        } catch {
            log.append("⚠︎ Kontrolu duplicit se nepodařilo provést (\(error.localizedDescription)) — pokračuji.")
        }

        log.append(debug
            ? "• DEBUG: zakládám do JH Tasks, vše na Jana Hanáka…"
            : "• Zakládám tasky do Internal IT v2…")
        // Land in "Todo" when the project has such a column; otherwise Kompas
        // uses the project's first column.
        let todo = try? await KompasClient.todoStageID(project: project)
        var ok = 0, fail = 0
        for p in KompasConfig.roster {
            let t = KompasClient.NewTask(
                name: "Helpdesk Blocker \(p.initials)",
                assignee: debug ? KompasConfig.debugAssignee : p.name,
                project: project,
                stageID: todo,
                sprintID: sprint,
                notes: KompasConfig.descriptionTemplate,
                estimateOriginal: settings.estimate(for: p),
                estimateUpdated: nil
            )
            do {
                try await KompasClient.createTask(t)
                ok += 1
                log.append("✓ \(p.initials) — \(formatHours(settings.estimate(for: p))) h"
                    + (debug ? " → JH" : " → \(p.name)"))
            } catch {
                fail += 1
                log.append("✗ \(p.initials) — \(error.localizedDescription)")
            }
        }
        settings.recordCreated(ok, debug: debug)
        log.append("Hotovo. Vytvořeno \(ok), chyb \(fail).")
        doneOK = fail == 0
        let where_ = debug ? "JH Tasks (debug)" : sprintLabel
        NotificationManager.shared.post(
            title: "HPA — Kompas",
            body: fail == 0 ? "Vytvořeno \(ok) blockerů — \(where_)."
                            : "Vytvořeno \(ok), chyb \(fail). Viz okno.",
            kind: fail == 0 ? .success : .failure
        )
    }
}
