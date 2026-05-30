import SwiftUI
import AppKit

// Persisted settings: the selected AL SPRINT (the one "constant" the user
// asked for) and per-person estimate hours (remembers your last values).
final class AsanaBlockerSettings: ObservableObject {
    static let shared = AsanaBlockerSettings()
    private let d = UserDefaults.standard

    @Published var sprintGID: String {
        didSet { d.set(sprintGID, forKey: "asanaSprintGID") }
    }
    @Published var estimates: [String: Double] {   // keyed by person GID
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
        sprintGID = AsanaConfig.sprintGIDForToday()
    }

    func recordCreated(_ n: Int, debug: Bool) {
        guard n > 0 else { return }
        if debug { debugCreated += n } else { realCreated += n }
    }

    func recordPassivesCreated(debug: Bool) {
        if debug { passivesDebugCreated += 1 } else { passivesCreated += 1 }
    }

    private init() {
        sprintGID = AsanaConfig.sprintGIDForToday()
        realCreated = d.integer(forKey: "asanaRealCreated")
        debugCreated = d.integer(forKey: "asanaDebugCreated")
        passivesEstimate = d.object(forKey: "asanaPassivesEstimate") as? Double
            ?? AsanaConfig.Passives.defaultEstimate
        passivesEstimateUpdated = d.object(forKey: "asanaPassivesEstimateUpdated") as? Double
            ?? AsanaConfig.Passives.defaultEstimateUpdated
        passivesCreated = d.integer(forKey: "asanaPassivesCreated")
        passivesDebugCreated = d.integer(forKey: "asanaPassivesDebugCreated")
        let storedVersion = d.integer(forKey: "asanaEstimatesVersion")
        let seed = Dictionary(uniqueKeysWithValues:
            AsanaConfig.roster.map { ($0.gid, $0.defaultEstimate) })
        if let raw = d.dictionary(forKey: "asanaEstimates") as? [String: Double],
           storedVersion == AsanaConfig.estimateDefaultsVersion {
            estimates = raw
        } else {
            // First run, or roster defaults changed — (re)seed from defaults.
            estimates = seed
            d.set(seed, forKey: "asanaEstimates")
            d.set(AsanaConfig.estimateDefaultsVersion, forKey: "asanaEstimatesVersion")
        }
    }

    func estimate(for p: AsanaConfig.Person) -> Double {
        estimates[p.gid] ?? p.defaultEstimate
    }
    func setEstimate(_ v: Double, for p: AsanaConfig.Person) {
        estimates[p.gid] = v
    }
}

struct AsanaBlockersView: View {
    @ObservedObject var settings = AsanaBlockerSettings.shared
    @State private var running = false
    @State private var log: [String] = []
    @State private var doneOK = false

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
            Text("Helpdesk blockery → Asana").font(.title2).bold()
            Text("Založí 4 tasky „Helpdesk Blocker <iniciály>“ do projektu Internal IT v2, "
                 + "každému svému člověku, se stejným sprintem a vlastním odhadem.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Link(destination: AsanaConfig.internalITURL) {
                    Label("Internal IT v2", systemImage: "arrow.up.right.square")
                }
                Link(destination: AsanaConfig.jhTasksURL) {
                    Label("JH Tasks (debug)", systemImage: "arrow.up.right.square")
                }
            }
            .font(.callout)

            HStack {
                Text("AL SPRINT").frame(width: 110, alignment: .leading)
                Picker("", selection: $settings.sprintGID) {
                    ForEach(AsanaConfig.sprintOptions) { o in
                        Text(o.label).tag(o.gid)
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

            if !AsanaClient.hasToken {
                Label("Chybí Asana token v ~/.config/hpa/asana_token — bez něj nelze zakládat.",
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
                ForEach(AsanaConfig.roster) { p in
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
                + Text(AsanaConfig.sprintLabel(settings.sprintGID)).bold()
            Spacer()
            if running { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button {
                Task { await create(debug: true) }
            } label: {
                Label("Debug run", systemImage: "ladybug")
            }
            .controlSize(.large)
            .tint(.orange)
            .disabled(running || !AsanaClient.hasToken)
            .help("Založí ty samé 4 tasky do projektu JH Tasks a přiřadí je tobě (Jan Hanák) — bezpečný test, nikoho neotravuje.")

            Button {
                Task { await create(debug: false) }
            } label: {
                Label("Vytvořit 4 blockery v Asaně", systemImage: "paperplane.fill")
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(running || !AsanaClient.hasToken)
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
        let sprint = settings.sprintGID
        let project = debug ? AsanaConfig.debugProjectGID : AsanaConfig.projectGID
        let projectLabel = debug ? "JH Tasks (debug)" : "Internal IT v2"

        // Duplicate guard: warn if this sprint already has blockers in the
        // target project.
        log = ["• Kontroluji existující blockery v \(AsanaConfig.sprintLabel(sprint))…"]
        do {
            let existing = try await AsanaClient.existingTasks(
                projectGID: project, sprintOptionGID: sprint,
                namePrefix: "Helpdesk Blocker")
            if !existing.isEmpty {
                let initials = existing
                    .map { $0.replacingOccurrences(of: "Helpdesk Blocker ", with: "") }
                    .joined(separator: ", ")
                let proceed = confirm(
                    title: "Ve sprintu už blockery jsou",
                    text: "V projektu \(projectLabel) už pro \(AsanaConfig.sprintLabel(sprint)) "
                        + "existuje \(existing.count) blockerů (\(initials)).\n\nVytvořit další 4?")
                if !proceed {
                    log.append("Zrušeno — duplicitní sprint.")
                    running = false
                    return
                }
            }
        } catch {
            log.append("⚠︎ Kontrolu duplicit se nepodařilo provést (\(error.localizedDescription)) — pokračuji.")
        }

        log.append(debug
            ? "• DEBUG: zakládám do JH Tasks, vše na Jana Hanáka…"
            : "• Zakládám tasky do Internal IT v2…")
        var ok = 0, fail = 0
        for p in AsanaConfig.roster {
            let t = AsanaClient.NewTask(
                name: "Helpdesk Blocker \(p.initials)",
                assigneeGID: debug ? AsanaConfig.janHanakGID : p.gid,
                projectGID: project,
                dueOn: nil,
                notes: AsanaConfig.descriptionTemplate,
                customFields: [
                    AsanaConfig.sprintFieldGID: sprint,
                    AsanaConfig.estimateFieldGID: settings.estimate(for: p),
                    AsanaConfig.stageFieldGID: AsanaConfig.stageTodoOptionGID,
                ]
            )
            do {
                _ = try await AsanaClient.createTask(t)
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
        running = false
        let where_ = debug ? "JH Tasks (debug)" : AsanaConfig.sprintLabel(sprint)
        NotificationManager.shared.post(
            title: "HPA — Asana",
            body: fail == 0 ? "Vytvořeno \(ok) blockerů — \(where_)."
                            : "Vytvořeno \(ok), chyb \(fail). Viz okno.",
            kind: fail == 0 ? .success : .failure
        )
    }
}
