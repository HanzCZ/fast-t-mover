import Foundation
import Combine

// Persistent store for OL/DL documents and the activity catalog.
// State lives in a single JSON file under Application Support; a singleton so
// the window can be closed and reopened without losing in-memory edits.
final class ListyStore: ObservableObject {
    static let shared = ListyStore()

    @Published var data: ListyData {
        didSet { save() }
    }

    private let fileURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HPA", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("listy.json")

        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ListyData.self, from: raw) {
            data = decoded
        } else {
            data = ListyData(months: ListySeed.months(),
                             catalog: ListySeed.catalog())
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? enc.encode(data) {
            try? raw.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Months & lifecycle

    // Months newest first (for the sidebar).
    var monthsDesc: [MonthEntry] {
        data.months.sorted { $0.ym > $1.ym }
    }

    var currentYM: Int? { data.months.map(\.ym).max() }

    func isCurrent(_ m: MonthEntry) -> Bool { m.ym == currentYM }

    // Which doc kinds are usable for a month, given its lifecycle position:
    //  - current month: only OL (you're ordering/planning)
    //  - past months:   DL is primary; OL stays reachable but greyed
    func isEnabled(_ kind: DocKind, for m: MonthEntry) -> Bool {
        if isCurrent(m) { return kind == .ol }
        return true
    }

    func isDimmed(_ kind: DocKind, for m: MonthEntry) -> Bool {
        !isCurrent(m) && kind == .ol
    }

    func defaultKind(for m: MonthEntry) -> DocKind {
        isCurrent(m) ? .ol : .dl
    }

    private func index(of id: UUID) -> Int? {
        data.months.firstIndex { $0.id == id }
    }

    func binding(forMonth id: UUID, kind: DocKind) -> [DocRow] {
        guard let i = index(of: id) else { return [] }
        return kind == .ol ? data.months[i].ol.rows : data.months[i].dl.rows
    }

    func setRows(_ rows: [DocRow], forMonth id: UUID, kind: DocKind) {
        guard let i = index(of: id) else { return }
        if kind == .ol { data.months[i].ol.rows = rows }
        else { data.months[i].dl.rows = rows }
    }

    func month(_ id: UUID) -> MonthEntry? {
        index(of: id).map { data.months[$0] }
    }

    // "Další měsíc": prepare the next month from the current one. The current
    // month's OL is copied into the new month's OL. The now-previous month's
    // DL is seeded from its OL (if empty) so the delivery list starts as a
    // draft you only need to adjust.
    @discardableResult
    func addNextMonth() -> UUID {
        guard let curYM = currentYM, let ci = data.months.firstIndex(where: { $0.ym == curYM }) else {
            // No months yet — start with the current calendar month, empty.
            let now = Calendar.current.dateComponents([.year, .month], from: Date())
            let fresh = MonthEntry(year: now.year ?? 2026, month: now.month ?? 1)
            data.months.append(fresh)
            return fresh.id
        }

        if data.months[ci].dl.rows.isEmpty {
            data.months[ci].dl.rows = data.months[ci].ol.rows.map { $0.duplicated() }
        }

        let cur = data.months[ci]
        let nxt = CzCal.next(year: cur.year, month: cur.month)
        var fresh = MonthEntry(year: nxt.year, month: nxt.month)
        fresh.ol.rows = cur.ol.rows.map { $0.duplicated() }
        data.months.append(fresh)
        return fresh.id
    }

    func deleteMonth(_ id: UUID) {
        data.months.removeAll { $0.id == id }
    }

    // MARK: - Catalog

    var catalogCategories: [String] {
        var seen = Set<String>(), out: [String] = []
        for e in data.catalog where !seen.contains(e.category) {
            seen.insert(e.category); out.append(e.category)
        }
        return out
    }

    func suggestions(matching text: String, limit: Int = 8) -> [CatalogEntry] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return data.catalog
            .filter { $0.item.lowercased().contains(q) }
            .prefix(limit)
            .map { $0 }
    }

    func catalogContains(_ item: String) -> Bool {
        let t = item.trimmingCharacters(in: .whitespaces).lowercased()
        return data.catalog.contains { $0.item.trimmingCharacters(in: .whitespaces).lowercased() == t }
    }

    func addToCatalog(item: String, category: String) {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !catalogContains(trimmed) else { return }
        let cat = category.trimmingCharacters(in: .whitespaces).isEmpty ? "Ostatní" : category
        data.catalog.append(CatalogEntry(category: cat, item: trimmed))
    }

    func removeFromCatalog(_ id: UUID) {
        data.catalog.removeAll { $0.id == id }
    }
}
