import SwiftUI
import AppKit

struct FakturoidView: View {
    @AppStorage("fakturoidAmount") private var amount: Double = FakturoidConfig.defaultAmount
    @State private var year: Int
    @State private var month: Int
    @State private var invoice: FakturoidClient.Invoice?
    @State private var busy = false
    @State private var log: [String] = []

    init() {
        // Default to the previous month (the period you'd normally invoice).
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month], from: Date())
        var y = c.year ?? 2026, m = c.month ?? 1
        if m == 1 { m = 12; y -= 1 } else { m -= 1 }
        _year = State(initialValue: y)
        _month = State(initialValue: m)
    }

    private var periodLabel: String { "\(CzCal.monthName(month)) \(year)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 520)
        // Re-evaluate which invoice exists whenever the period changes.
        .onChange(of: year) { _ in invoice = nil }
        .onChange(of: month) { _ in invoice = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fakturace → Fakturoid").font(.title2).bold()
            Text("Měsíční faktura pro \(FakturoidConfig.clientName). Vystaví se na poslední den "
                 + "vybraného období; pokud už pro období existuje, jen se načte.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Text("Období").frame(width: 90, alignment: .leading)
                Picker("", selection: $month) {
                    ForEach(1...12, id: \.self) { m in Text(CzCal.monthName(m)).tag(m) }
                }.labelsHidden().frame(width: 130)
                Picker("", selection: $year) {
                    ForEach(2025...2028, id: \.self) { y in Text(String(y)).tag(y) }
                }.labelsHidden().frame(width: 90)
            }
            HStack {
                Text("Částka").frame(width: 90, alignment: .leading)
                TextField("", value: $amount, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                    .multilineTextAlignment(.trailing)
                Text("CZK").foregroundStyle(.secondary)
            }
            HStack {
                Text("Vystaveno").frame(width: 90, alignment: .leading)
                Text(FakturoidClient.lastDay(year: year, month: month)
                     + "  ·  splatnost \(FakturoidConfig.dueDays) dní").foregroundStyle(.secondary)
            }

            if !FakturoidClient.hasCreds {
                Label("Chybí Fakturoid přihlášení — vlož client ID/secret v Settings.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Text položky").font(.caption).foregroundStyle(.secondary)
            Text(FakturoidConfig.lineText(month: month, year: year))
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let inv = invoice {
                HStack(spacing: 12) {
                    Label("Faktura \(inv.number) — \(inv.status)", systemImage: "doc.text.fill")
                        .foregroundStyle(.green)
                    if let url = URL(string: inv.htmlURL) {
                        Link(destination: url) {
                            Label("Otevřít ve Fakturoidu", systemImage: "arrow.up.right.square")
                        }
                        .font(.callout)
                    }
                }
            }

            if !log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(log, id: \.self) { Text($0).font(.caption.monospaced()) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(height: 100).background(Color(nsColor: .textBackgroundColor))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Text("Klient: ").foregroundColor(.secondary)
                + Text("SŠ gastronomická a hotelová").bold()
            Spacer()
            if busy { ProgressView().controlSize(.small).padding(.trailing, 6) }
            Button { Task { await findOrCreate() } } label: {
                Label("Najít / vytvořit fakturu", systemImage: "doc.badge.plus")
            }
            .controlSize(.large)
            .disabled(busy || !FakturoidClient.hasCreds)

            Button { Task { await download() } } label: {
                Label("Stáhnout PDF", systemImage: "arrow.down.doc")
            }
            .controlSize(.large).keyboardShortcut(.defaultAction)
            .disabled(busy || invoice == nil)
        }
        .padding(16)
    }

    @MainActor
    private func findOrCreate() async {
        busy = true; defer { busy = false }
        log = ["• Hledám fakturu pro \(periodLabel)…"]
        do {
            if let found = try await FakturoidClient.findInvoice(year: year, month: month) {
                invoice = found
                log.append("✓ Nalezena \(found.number) (\(found.status)) — nevytvářím novou.")
                return
            }
            log.append("• Pro \(periodLabel) faktura neexistuje.")
            let ok = asanaConfirm(
                title: "Vytvořit fakturu?",
                text: "Pro \(periodLabel) vytvořit fakturu pro \(FakturoidConfig.clientName) "
                    + "na \(formatHours(amount)) CZK (vystaveno \(FakturoidClient.lastDay(year: year, month: month)))?")
            guard ok else { log.append("Zrušeno."); return }
            let created = try await FakturoidClient.createInvoice(year: year, month: month, amount: amount)
            invoice = created
            log.append("✓ Vytvořena \(created.number) (\(created.status)).")
            NotificationManager.shared.post(title: "HPA — Fakturoid",
                body: "Vytvořena faktura \(created.number) pro \(periodLabel).", kind: .success)
        } catch {
            log.append("✗ \(error.localizedDescription)")
            NotificationManager.shared.post(title: "HPA — Fakturoid",
                body: "Chyba: \(error.localizedDescription)", kind: .failure)
        }
    }

    @MainActor
    private func download() async {
        guard let inv = invoice else { return }
        busy = true; defer { busy = false }
        log.append("• Stahuji PDF \(inv.number)…")
        do {
            let url = try await FakturoidClient.downloadPDF(inv)
            log.append("✓ Uloženo: \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            log.append("✗ \(error.localizedDescription)")
        }
    }
}
