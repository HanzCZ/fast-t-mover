import Foundation

// Document kind: Objednávkový list (order) vs Dodávkový list (delivery).
enum DocKind: String, Codable, CaseIterable, Hashable {
    case ol
    case dl

    var shortPrefix: String { self == .ol ? "OL" : "DL" }
    var czTitle: String { self == .ol ? "Objednávkový list" : "Dodávkový list" }
    var czShort: String { self == .ol ? "OL" : "DL" }
}

// A single row of a document. The body is an ordered list of rows so we can
// faithfully reproduce the freeform layout: bold section headers, line items
// with hours, standalone bold items, and blank separator rows.
enum RowKind: String, Codable, Hashable {
    case section   // bold header spanning the row, no hours
    case item      // description + hours
    case spacer    // blank separator
}

struct DocRow: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: RowKind
    var text: String = ""
    var hours: Double? = nil
    var bold: Bool = false

    static func section(_ t: String) -> DocRow { DocRow(kind: .section, text: t, bold: true) }
    static func item(_ t: String, _ h: Double, bold: Bool = false) -> DocRow {
        DocRow(kind: .item, text: t, hours: h, bold: bold)
    }
    static func spacer() -> DocRow { DocRow(kind: .spacer) }

    // Fresh copy with a new id (so copied rows stay independent across months).
    func duplicated() -> DocRow {
        DocRow(id: UUID(), kind: kind, text: text, hours: hours, bold: bold)
    }
}

struct MonthDoc: Codable, Hashable {
    var rows: [DocRow] = []

    var totalHours: Double {
        rows.reduce(0) { $0 + (($1.kind == .item ? $1.hours : nil) ?? 0) }
    }
}

struct MonthEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var year: Int
    var month: Int            // 1...12
    var ol: MonthDoc = MonthDoc()
    var dl: MonthDoc = MonthDoc()

    var ym: Int { year * 100 + month }

    func doc(_ kind: DocKind) -> MonthDoc { kind == .ol ? ol : dl }

    var czLabel: String { "\(CzCal.monthName(month)) \(year)" }
}

struct CatalogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: String
    var item: String
}

struct ListyData: Codable {
    var months: [MonthEntry] = []
    var catalog: [CatalogEntry] = []
    var personName: String = "Jan Hanák"
    var ico: String = "05884217"
    var place: String = "V Praze"
}

enum CzCal {
    static let months = ["", "leden", "únor", "březen", "duben", "květen",
                         "červen", "červenec", "srpen", "září", "říjen",
                         "listopad", "prosinec"]

    static func monthName(_ m: Int) -> String {
        (1...12).contains(m) ? months[m] : "\(m)"
    }

    // Advance one month with year rollover.
    static func next(year: Int, month: Int) -> (year: Int, month: Int) {
        month == 12 ? (year + 1, 1) : (year, month + 1)
    }
}

// Format hours without a trailing ".0" (whole numbers are the common case).
func formatHours(_ h: Double?) -> String {
    guard let h else { return "" }
    if h == h.rounded() { return String(Int(h)) }
    return String(format: "%g", h)
}
