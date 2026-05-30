import SwiftUI
import AppKit

struct ListyView: View {
    @ObservedObject var store = ListyStore.shared
    @State private var selectedMonthID: UUID?
    @State private var showCatalog = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            if selectedMonthID == nil {
                selectedMonthID = store.monthsDesc.first?.id
            }
        }
        .sheet(isPresented: $showCatalog) { CatalogSheet(store: store) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedMonthID) {
                ForEach(store.monthsDesc) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.czLabel).font(.body)
                            Text(store.isCurrent(m) ? "aktuální" : "minulý")
                                .font(.caption2)
                                .foregroundStyle(store.isCurrent(m) ? Color.accentColor : .secondary)
                        }
                        Spacer()
                    }
                    .tag(m.id)
                    .contextMenu {
                        Button("Smazat měsíc", role: .destructive) {
                            store.deleteMonth(m.id)
                            if selectedMonthID == m.id { selectedMonthID = store.monthsDesc.first?.id }
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 8) {
                Button {
                    let id = store.addNextMonth()
                    selectedMonthID = id
                } label: {
                    Label("Další měsíc", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    showCatalog = true
                } label: {
                    Label("Katalog položek", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedMonthID, store.month(id) != nil {
            MonthEditorView(store: store, monthID: id)
                .id(id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                Text("Vyber měsíc nebo vytvoř další.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MonthEditorView: View {
    @ObservedObject var store: ListyStore
    let monthID: UUID
    @State private var kind: DocKind = .ol
    @AppStorage("listyTargetHours") private var targetHours: Double = 128

    private var month: MonthEntry { store.month(monthID) ?? MonthEntry(year: 0, month: 0) }

    // Current rows (value snapshot) and mutation helpers. We deliberately do
    // NOT use a Binding<[DocRow]> with ForEach element bindings: deleting a row
    // there makes SwiftUI read a now-out-of-range index binding and crash.
    private var rowsArray: [DocRow] { store.binding(forMonth: monthID, kind: kind) }

    private func setRows(_ arr: [DocRow]) {
        store.setRows(arr, forMonth: monthID, kind: kind)
    }

    private func append(_ row: DocRow) {
        var arr = rowsArray; arr.append(row); setRows(arr)
    }

    private func deleteRow(_ id: UUID) {
        var arr = rowsArray; arr.removeAll { $0.id == id }; setRows(arr)
    }

    // Safe by-id binding: reads/writes the matching row, no-ops if it's gone.
    private func rowBinding(_ id: UUID) -> Binding<DocRow> {
        Binding(
            get: { rowsArray.first { $0.id == id } ?? DocRow(kind: .spacer) },
            set: { newVal in
                var arr = rowsArray
                if let i = arr.firstIndex(where: { $0.id == id }) {
                    arr[i] = newVal
                    setRows(arr)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .onAppear { kind = store.defaultKind(for: month) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(month.czLabel).font(.title2).bold()
                Text(store.isCurrent(month) ? "aktuální" : "minulý")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(store.isCurrent(month) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
            }

            Picker("", selection: $kind) {
                ForEach(DocKind.allCases, id: \.self) { k in
                    Text(k == .ol ? "Objednávkový (OL)" : "Dodávkový (DL)")
                        .tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)

            if !store.isEnabled(kind, for: month) {
                banner(icon: "lock.fill",
                       text: "DL bude dostupný, až vytvoříš další měsíc — teď jsi v aktuálním měsíci, takže plánuješ jen OL.",
                       tint: .secondary)
            } else if store.isDimmed(kind, for: month) {
                banner(icon: "exclamationmark.triangle.fill",
                       text: "Tenhle OL už asi nepotřebuješ — měsíc je uzavřený, primární je teď DL. Stáhnout ale můžeš.",
                       tint: .orange)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var editor: some View {
        if store.isEnabled(kind, for: month) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { append(.item("", 0)) } label: {
                        Label("Položka", systemImage: "plus")
                    }
                    Button { append(.section("")) } label: {
                        Label("Sekce", systemImage: "plus")
                    }
                    Button { append(.spacer()) } label: {
                        Label("Mezera", systemImage: "plus")
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                List {
                    ForEach(rowsArray) { row in
                        RowEditor(store: store, row: rowBinding(row.id),
                                  category: nearestCategory(before: row.id))
                            .listRowSeparator(.hidden)
                            .contextMenu {
                                Button("Smazat řádek", role: .destructive) {
                                    deleteRow(row.id)
                                }
                            }
                    }
                    .onMove { from, to in
                        var arr = rowsArray
                        arr.move(fromOffsets: from, toOffset: to)
                        setRows(arr)
                    }
                    .onDelete { idx in
                        var arr = rowsArray
                        arr.remove(atOffsets: idx)
                        setRows(arr)
                    }
                }
                .listStyle(.plain)
            }
            .opacity(store.isDimmed(kind, for: month) ? 0.55 : 1)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                Text("DL pro aktuální měsíc je zamčený.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        let total = month.doc(kind).totalHours
        let off = total != targetHours
        return HStack {
            Text("Celkem: ").foregroundColor(.secondary)
                + Text(formatHours(total)).bold().foregroundColor(off ? .red : .primary)
                + Text(" / \(formatHours(targetHours)) hodin").foregroundColor(.secondary)
            if off {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
            Spacer()
            if kind == .ol {
                Button { emailOL() } label: {
                    Label("Poslat OL e-mailem", systemImage: "envelope")
                }
                .controlSize(.large)
                .disabled(!store.isEnabled(kind, for: month))
            }
            Button {
                guard let m = store.month(monthID) else { return }
                ListyPDF.export(kind: kind, month: m, data: store.data)
            } label: {
                Label("Stáhnout \(kind.czShort) PDF", systemImage: "arrow.down.doc")
            }
            .controlSize(.large)
            .disabled(!store.isEnabled(kind, for: month))
        }
        .padding(16)
    }

    // Generate the OL PDF and open a Mail draft (to Adam Motloch) with it
    // attached. Period in subject/body is numeric "MM YYYY".
    private func emailOL() {
        guard let m = store.month(monthID) else { return }
        let mm = String(format: "%02d", m.month)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ListyPDF.filename(kind: .ol, month: m))
        guard ListyPDF.write(kind: .ol, month: m, data: store.data, to: url) else {
            NSSound.beep(); return
        }
        let subject = "Jan Hanák - SSGH - Objednávka \(mm) \(m.year)"
        let body = "Dobrý den, \n"
            + "posílám objednávkový list na měsíc \(mm) \(m.year)\n\n"
            + "S pozdravem,\nJan Hanák"
        Emailer.composeDraft(to: "adam.motloch@ssgh.cz",
                             subject: subject, body: body, attachment: url)
    }

    private func banner(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Category for "save to catalog" = the nearest section header above a row.
    private func nearestCategory(before id: UUID) -> String {
        let all = rowsArray
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "" }
        for j in stride(from: i, through: 0, by: -1) where all[j].kind == .section {
            return all[j].text
        }
        return ""
    }
}
