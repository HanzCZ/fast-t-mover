import SwiftUI
import AppKit

// Shared confirmation alert (used by the Kompas generators and Fakturoid).
@MainActor
func confirmCreate(title: String, text: String) -> Bool {
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
final class KompasUIState: ObservableObject {
    static let shared = KompasUIState()
    enum Mode: String, CaseIterable { case blockers, passives }
    @Published var mode: Mode = .blockers
    private init() {}
}

// Root Kompas window: shared mode switch between the two generators.
struct KompasView: View {
    @ObservedObject private var ui = KompasUIState.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $ui.mode) {
                Text("Helpdesk blockery").tag(KompasUIState.Mode.blockers)
                Text("Sprint Passives").tag(KompasUIState.Mode.passives)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Divider()

            switch ui.mode {
            case .blockers: KompasBlockersView()
            case .passives: KompasPassivesView()
            }
        }
        .frame(minWidth: 600, minHeight: 560)
    }
}

struct KompasPassivesView: View {
    @ObservedObject var settings = KompasTaskSettings.shared
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
            Text("Sprint Passives → Kompas").font(.title2).bold()
            Text("Založí jeden task „Sprint Passives“ do projektu AL x SSGH v2 pro vybraný sprint "
                 + "s pevnými parametry (sloupec Todo, bez assignee a termínu).")
                .font(.callout).foregroundStyle(.secondary)
            Link(destination: KompasConfig.webURL) {
                Label("kompas.ssgh.cz", systemImage: "arrow.up.right.square")
            }
            .font(.callout)

            HStack {
                Text("Sprint").frame(width: 130, alignment: .leading)
                Picker("", selection: $settings.sprintID) {
                    ForEach(KompasConfig.sprintOptions()) { o in Text(o.label).tag(o.id) }
                }
                .labelsHidden().frame(maxWidth: 240)
            }
            infoRow("Sloupec", "Todo")
            infoRow("Assignee / Due", "— žádné —")

            if !KompasClient.hasToken {
                Label("Chybí Kompas API token (Settings → Kompas — připojení).",
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
                Text(KompasConfig.Passives.description)
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
                + Text(KompasConfig.sprintLabel(settings.sprintID)).bold()
            Spacer()
            if running { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button { Task { await create(debug: true) } } label: {
                Label("Debug run", systemImage: "ladybug")
            }
            .controlSize(.large).tint(.orange)
            .disabled(running || !KompasClient.hasToken)
            .help("Založí Sprint Passives do JH Tasks (na tebe) — bezpečný test.")

            Button { Task { await create(debug: false) } } label: {
                Label("Vytvořit Sprint Passives", systemImage: "paperplane.fill")
            }
            .controlSize(.large).keyboardShortcut(.defaultAction)
            .disabled(running || !KompasClient.hasToken)
        }
        .padding(16)
    }

    @MainActor
    private func create(debug: Bool) async {
        running = true
        defer { running = false }
        let sprint = settings.sprintID
        let sprintLabel = KompasConfig.sprintLabel(sprint)
        let project = debug ? KompasConfig.debugProject : KompasConfig.passivesProject
        let projectLabel = debug ? "JH Tasks (debug)" : "AL x SSGH v2"

        log = ["• Kontroluji existující Sprint Passives v \(sprintLabel)…"]
        do {
            let existing = try await KompasClient.existingTasks(
                project: project, sprintID: sprint,
                namePrefix: KompasConfig.Passives.taskName)
            if !existing.isEmpty {
                let proceed = confirmCreate(
                    title: "Sprint Passives už existuje",
                    text: "V projektu \(projectLabel) už pro \(sprintLabel) "
                        + "existuje \(existing.count)× „Sprint Passives“.\n\nVytvořit další?")
                if !proceed { log.append("Zrušeno — duplicitní sprint."); return }
            }
        } catch {
            log.append("⚠︎ Kontrolu duplicit nešlo provést (\(error.localizedDescription)) — pokračuji.")
        }

        let task = KompasClient.NewTask(
            name: KompasConfig.Passives.taskName,
            assignee: debug ? KompasConfig.debugAssignee : nil,
            project: project,
            stageID: try? await KompasClient.todoStageID(project: project),
            sprintID: sprint,
            notes: KompasConfig.Passives.description,
            estimateOriginal: settings.passivesEstimate,
            estimateUpdated: settings.passivesEstimateUpdated
        )
        do {
            try await KompasClient.createTask(task)
            settings.recordPassivesCreated(debug: debug)
            log.append("✓ Sprint Passives → \(projectLabel) (\(sprintLabel))")
            NotificationManager.shared.post(
                title: "HPA — Kompas",
                body: "Sprint Passives vytvořen — \(debug ? "JH Tasks (debug)" : sprintLabel).",
                kind: .success)
        } catch {
            log.append("✗ \(error.localizedDescription)")
            NotificationManager.shared.post(
                title: "HPA — Kompas", body: "Sprint Passives selhal. Viz okno.", kind: .failure)
        }
    }
}
