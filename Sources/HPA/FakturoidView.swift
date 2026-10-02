import SwiftUI
import AppKit

struct FakturoidView: View {
    @AppStorage("fakturoidAmount") private var amount: Double = FakturoidConfig.defaultAmount
    // Optional flat fee added on top of `amount` (not a separate invoice line —
    // gets folded into the single line's unit_price). Persists across runs so
    // the typical recurring paušál survives app restarts; user can zero it
    // out anytime via the "Vynulovat" button.
    @AppStorage("fakturoidPausal") private var pausal: Double = 0
    // One-off extra work (vícepráce) billed as its own invoice line. Deliberately not persisted
    // (unlike paušál) so it never sneaks onto next month's invoice.
    @State private var bonus: Double = 0
    @State private var year: Int
    @State private var month: Int
    @State private var invoice: FakturoidClient.Invoice?
    @State private var busy = false
    @State private var log: [String] = []

    // Total that actually gets sent to Fakturoid / shown in the confirm dialog.
    private var totalAmount: Double { amount + pausal + bonus }

    init() {
        // Default to the previous month (the period you'd normally invoice).
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month], from: Date())
        var y = c.year ?? 2026, m = c.month ?? 1
        if m == 1 { m = 12; y -= 1 } else { m -= 1 }
        // One-time: a stored amount equal to an earlier default moves to the
        // current one (the field persists whatever was last shown).
        let d = UserDefaults.standard
        if !d.bool(forKey: "fakturoidAmount92720") {
            if let stored = d.object(forKey: "fakturoidAmount") as? Double,
               FakturoidConfig.supersededAmounts.contains(stored) {
                d.removeObject(forKey: "fakturoidAmount")
            }
            d.set(true, forKey: "fakturoidAmount92720")
        }
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
                Text("Paušál").frame(width: 90, alignment: .leading)
                TextField("0", value: $pausal, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                    .multilineTextAlignment(.trailing)
                Text("CZK").foregroundStyle(.secondary)
                Button("Claude max (2670)") { pausal = 2670 }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Claude pro (530)") { pausal = 530 }
                    .buttonStyle(.bordered).controlSize(.small)
                if pausal != 0 {
                    Button("Vynulovat") { pausal = 0 }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            HStack {
                Text("Vícepráce").frame(width: 90, alignment: .leading)
                TextField("0", value: $bonus, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                    .multilineTextAlignment(.trailing)
                Text("CZK").foregroundStyle(.secondary)
                Button("\(formatHours(FakturoidConfig.defaultBonus)) Kč") {
                    bonus = FakturoidConfig.defaultBonus
                }
                .buttonStyle(.bordered).controlSize(.small)
                if bonus != 0 {
                    Button("Vynulovat") { bonus = 0 }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            HStack {
                Text("Celkem").frame(width: 90, alignment: .leading)
                Text(formatHours(totalAmount)).bold()
                Text("CZK").foregroundStyle(.secondary)
                if pausal != 0 || bonus != 0 {
                    Text("(\(breakdown))")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

    // "92720 + paušál 2670 + vícepráce 30000" — shown next to the total and in the
    // confirm dialog whenever anything is added on top of the base amount.
    private var breakdown: String {
        var parts = [formatHours(amount)]
        if pausal != 0 { parts.append("paušál \(formatHours(pausal))") }
        if bonus != 0 { parts.append("vícepráce \(formatHours(bonus))") }
        return parts.joined(separator: " + ")
    }

    private func lineBox(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bonus != 0 ? "Text položek" : "Text položky")
                .font(.caption).foregroundStyle(.secondary)
            lineBox(FakturoidConfig.lineText(month: month, year: year, pausal: pausal))
            if bonus != 0 {
                lineBox("\(FakturoidConfig.bonusLineText(month: month, year: year)) — \(formatHours(bonus)) CZK")
            }

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
            .controlSize(.large)
            .disabled(busy || invoice == nil)

            Button { Task { await emailFakturaDL() } } label: {
                Label("Poslat fakturu + DL", systemImage: "envelope")
            }
            .controlSize(.large).keyboardShortcut(.defaultAction)
            .disabled(busy || invoice == nil)
        }
        .padding(16)
    }

    @MainActor
    private func emailFakturaDL() async {
        busy = true; defer { busy = false }
        log.append("• Připravuji e-mail (faktura + DL) pro \(periodLabel)…")
        do {
            try await InvoiceMail.composeFakturaAndDL(year: year, month: month)
            log.append("✓ Otevřen draft v Mailu.")
        } catch {
            log.append("✗ \(error.localizedDescription)")
            InvoiceMail.alert(error)
        }
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
            let pausalNote = pausal != 0 || bonus != 0 ? " (\(breakdown))" : ""
            let ok = confirmCreate(
                title: "Vytvořit fakturu?",
                text: "Pro \(periodLabel) vytvořit fakturu pro \(FakturoidConfig.clientName) "
                    + "na \(formatHours(totalAmount)) CZK\(pausalNote) "
                    + "(vystaveno \(FakturoidClient.lastDay(year: year, month: month)))?")
            guard ok else { log.append("Zrušeno."); return }
            let created = try await FakturoidClient.createInvoice(year: year, month: month, amount: amount + pausal, pausal: pausal, bonus: bonus)
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
