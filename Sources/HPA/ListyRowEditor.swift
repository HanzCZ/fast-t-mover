import SwiftUI

struct RowEditor: View {
    @ObservedObject var store: ListyStore
    @Binding var row: DocRow
    let category: String

    private var hoursText: Binding<String> {
        Binding(
            get: { formatHours(row.hours) },
            set: { new in
                let cleaned = new.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                row.hours = cleaned.isEmpty ? 0 : (Double(cleaned) ?? row.hours)
            }
        )
    }

    var body: some View {
        switch row.kind {
        case .section:
            HStack(spacing: 6) {
                Image(systemName: "rectangle.fill").foregroundStyle(.secondary).font(.caption)
                TextField("Název sekce", text: $row.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.bold())
            }
            .padding(.vertical, 2)

        case .item:
            HStack(spacing: 6) {
                catalogMenu
                TextField("Popis položky", text: $row.text)
                    .textFieldStyle(.roundedBorder)
                saveToCatalogButton
                boldButton
                TextField("0", text: hoursText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                Text("h").foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

        case .spacer:
            HStack {
                Text("— prázdný oddělovací řádek —")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var catalogMenu: some View {
        Menu {
            let sugg = store.suggestions(matching: row.text)
            if !sugg.isEmpty {
                ForEach(sugg) { e in
                    Button(e.item) { row.text = e.item }
                }
            } else {
                ForEach(store.catalogCategories, id: \.self) { cat in
                    Section(cat) {
                        ForEach(store.data.catalog.filter { $0.category == cat }) { e in
                            Button(e.item) { row.text = e.item }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "text.badge.plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Vybrat z katalogu / našeptat")
    }

    @ViewBuilder
    private var saveToCatalogButton: some View {
        let trimmed = row.text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !store.catalogContains(trimmed) {
            Button {
                store.addToCatalog(item: trimmed, category: category)
            } label: {
                Image(systemName: "plus.circle").foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help("Uložit do katalogu (\(category.isEmpty ? "Ostatní" : category))")
        }
    }

    private var boldButton: some View {
        Button { row.bold.toggle() } label: {
            Image(systemName: "bold")
                .foregroundStyle(row.bold ? Color.accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        .help("Tučně")
    }
}

struct CatalogSheet: View {
    @ObservedObject var store: ListyStore
    @Environment(\.dismiss) private var dismiss

    @State private var newItem = ""
    @State private var newCategory = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Katalog položek").font(.title3).bold()
                Spacer()
                Button("Hotovo") { dismiss() }
            }
            .padding()
            Divider()

            List {
                ForEach(store.catalogCategories, id: \.self) { cat in
                    Section(cat) {
                        ForEach(store.data.catalog.filter { $0.category == cat }) { e in
                            HStack {
                                Text(e.item)
                                Spacer()
                                Button {
                                    store.removeFromCatalog(e.id)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Nová položka", text: $newItem)
                    .textFieldStyle(.roundedBorder)
                Menu(newCategory.isEmpty ? "Kategorie" : newCategory) {
                    ForEach(store.catalogCategories, id: \.self) { cat in
                        Button(cat) { newCategory = cat }
                    }
                }
                .frame(width: 180)
                Button("Přidat") {
                    store.addToCatalog(item: newItem, category: newCategory)
                    newItem = ""
                }
                .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 640, height: 560)
    }
}
