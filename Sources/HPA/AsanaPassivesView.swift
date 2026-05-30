import SwiftUI
import AppKit

// Shared confirmation alert (used by both Asana generators).
@MainActor
func asanaConfirm(title: String, text: String) -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = .warning
    a.addButton(withTitle: "Vytvořit")
    a.addButton(withTitle: "Zrušit")
    NSApp.activate(ignoringOtherApps: true)
    return a.runModal() == .alertFirstButtonReturn
}

// Which generator tab is showing. Held outside the view so the menu can open
// the window straight onto a specific tab.
final class AsanaUIState: ObservableObject {
    static let shared = AsanaUIState()
    enum Mode: String, CaseIterable { case blockers, passives }
    @Published var mode: Mode = .blockers
    private init() {}
}

// Root Asana window: shared mode switch between the two generators.
struct AsanaView: View {
    @ObservedObject private var ui = AsanaUIState.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $ui.mode) {
                Text("Helpdesk blockery").tag(AsanaUIState.Mode.blockers)
                Text("Sprint Passives").tag(AsanaUIState.Mode.passives)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Divider()

            switch ui.mode {
            case .blockers: AsanaBlockersView()
            case .passives: AsanaPassivesView()
            }
        }
        .frame(minWidth: 600, minHeight: 560)
    }
}

struct AsanaPassivesView: View {
    @ObservedObject var settings = AsanaBlockerSettings.shared
    @State private var running = false
    @State private var log: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sprint Passives → AL x SSGH v2").font(.title2).bold()
            Text("Založí jeden task „Sprint Passives“ pro vybraný sprint s pevnými parametry "
                 + "(Dev Status Todo, Projekt Reoccurring, bez assignee a termínu).")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Link(destination: AsanaConfig.alSSGHURL) {
                    Label("AL x SSGH v2", systemImage: "arrow.up.right.square")
                }
                Link(destination: AsanaConfig.jhTasksURL) {
                    Label("JH Tasks (debug)", systemImage: "arrow.up.right.square")
                }
            }
            .font(.callout)

            HStack {
                Text("AL SPRINT").frame(width: 130, alignment: .leading)
                Picker("", selection: $settings.sprintGID) {
                    ForEach(AsanaConfig.sprintOptions) { o in Text(o.label).tag(o.gid) }
                }
                .labelsHidden().frame(maxWidth: 240)
            }
            infoRow("Dev Status", "Todo")
            infoRow("Projekt", "Reoccurring")
            infoRow("Assignee / Due", "— žádné —")

            if !AsanaClient.hasToken {
                Label("Chybí Asana token v ~/.config/hpa/asana_token.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            Text(value).foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Estimate (h)").frame(width: 130, alignment: .leading)
                TextField("", value: $settings.passivesEstimate, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Estimate updated (h)").frame(width: 130, alignment: .leading)
                TextField("", value: $settings.passivesEstimateUpdated, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Popis").font(.caption).foregroundStyle(.secondary)
                Text(AsanaConfig.Passives.description)
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(log, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(height: 90)
                .background(Color(nsColor: .textBackgroundColor))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Text("Sprint: ").foregroundColor(.secondary)
                + Text(AsanaConfig.sprintLabel(settings.sprintGID)).bold()
            Spacer()
            if running { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button { Task { await create(debug: true) } } label: {
                Label("Debug run", systemImage: "ladybug")
            }
            .controlSize(.large).tint(.orange)
            .disabled(running || !AsanaClient.hasToken)
            .help("Založí Sprint Passives do JH Tasks (na tebe), s kompatibilní podmnožinou polí — bezpečný test.")

            Button { Task { await create(debug: false) } } label: {
                Label("Vytvořit Sprint Passives", systemImage: "paperplane.fill")
            }
            .controlSize(.large).keyboardShortcut(.defaultAction)
            .disabled(running || !AsanaClient.hasToken)
        }
        .padding(16)
    }

    @MainActor
    private func create(debug: Bool) async {
        running = true
        let sprint = settings.sprintGID
        let project = debug ? AsanaConfig.debugProjectGID : AsanaConfig.Passives.projectGID
        let projectLabel = debug ? "JH Tasks (debug)" : "AL x SSGH v2"

        log = ["• Kontroluji existující Sprint Passives v \(AsanaConfig.sprintLabel(sprint))…"]
        do {
            let existing = try await AsanaClient.existingTasks(
                projectGID: project, sprintOptionGID: sprint,
                namePrefix: AsanaConfig.Passives.taskName)
            if !existing.isEmpty {
                let proceed = asanaConfirm(
                    title: "Sprint Passives už existuje",
                    text: "V projektu \(projectLabel) už pro \(AsanaConfig.sprintLabel(sprint)) "
                        + "existuje \(existing.count)× „Sprint Passives“.\n\nVytvořit další?")
                if !proceed { log.append("Zrušeno — duplicitní sprint."); running = false; return }
            }
        } catch {
            log.append("⚠︎ Kontrolu duplicit nešlo provést (\(error.localizedDescription)) — pokračuji.")
        }

        // Real run sets the full AL x SSGH v2 field set; debug sets only the
        // fields JH Tasks has (Dev Status, AL SPRINT, Estimate original).
        let fields: [String: Any]
        if debug {
            fields = [
                AsanaConfig.Passives.devStatusFieldGID: AsanaConfig.Passives.devStatusTodoGID,
                AsanaConfig.sprintFieldGID: sprint,
                AsanaConfig.Passives.debugEstimateOriginalFieldGID: settings.passivesEstimate,
            ]
        } else {
            fields = [
                AsanaConfig.Passives.devStatusFieldGID: AsanaConfig.Passives.devStatusTodoGID,
                AsanaConfig.Passives.projektFieldGID: [AsanaConfig.Passives.projektReoccurringGID],
                AsanaConfig.Passives.estimateFieldGID: settings.passivesEstimate,
                AsanaConfig.Passives.estimateUpdatedFieldGID: settings.passivesEstimateUpdated,
                AsanaConfig.sprintFieldGID: sprint,
            ]
        }

        let task = AsanaClient.NewTask(
            name: AsanaConfig.Passives.taskName,
            assigneeGID: debug ? AsanaConfig.janHanakGID : nil,
            projectGID: project,
            dueOn: nil,
            notes: AsanaConfig.Passives.description,
            customFields: fields
        )
        do {
            _ = try await AsanaClient.createTask(task)
            settings.recordPassivesCreated(debug: debug)
            log.append("✓ Sprint Passives → \(projectLabel) (\(AsanaConfig.sprintLabel(sprint)))")
            NotificationManager.shared.post(
                title: "HPA — Asana",
                body: "Sprint Passives vytvořen — \(debug ? "JH Tasks (debug)" : AsanaConfig.sprintLabel(sprint)).",
                kind: .success)
        } catch {
            log.append("✗ \(error.localizedDescription)")
            NotificationManager.shared.post(
                title: "HPA — Asana", body: "Sprint Passives selhal. Viz okno.", kind: .failure)
        }
        running = false
    }
}
