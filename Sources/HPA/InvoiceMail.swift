import Foundation
import AppKit

// Compose the monthly "faktura + DL" e-mail (to EFAD): downloads the Fakturoid
// invoice PDF for the period and generates the matching DL PDF, then opens a
// draft with both attached. Used from both the DL tab and the Fakturoid window.
enum InvoiceMail {
    static let recipient = "efad@ssgh.cz"

    enum MErr: LocalizedError {
        case noDL(Int, Int), noInvoice(Int, Int), pdfFail
        var errorDescription: String? {
            switch self {
            case .noDL(let m, let y):
                return "DL pro období \(String(format: "%02d", m)) \(y) v listech neexistuje."
            case .noInvoice(let m, let y):
                return "Faktura pro období \(String(format: "%02d", m)) \(y) ve Fakturoidu neexistuje — vytvoř ji nejdřív."
            case .pdfFail:
                return "Nepodařilo se vygenerovat DL PDF."
            }
        }
    }

    @MainActor
    static func composeFakturaAndDL(year: Int, month: Int) async throws {
        let store = ListyStore.shared
        guard let entry = store.data.months.first(where: { $0.year == year && $0.month == month }) else {
            throw MErr.noDL(month, year)
        }
        let dlURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(ListyPDF.filename(kind: .dl, month: entry))
        guard ListyPDF.write(kind: .dl, month: entry, data: store.data, to: dlURL) else {
            throw MErr.pdfFail
        }
        guard let inv = try await FakturoidClient.findInvoice(year: year, month: month) else {
            throw MErr.noInvoice(month, year)
        }
        let invURL = try await FakturoidClient.downloadPDF(inv)

        let mm = String(format: "%02d", month)
        let subject = "Jan Hanák - SSGH - objednávka \(mm) \(year)"
        let body = "Dobrý den, \n"
            + "posílám fakturu za odpracované hodiny a výpis odpracovaných hodin v příloze za \(mm) \(year).\n\n"
            + "S pozdravem,\nJan Hanák"
        Emailer.composeDraft(to: recipient, subject: subject, body: body,
                             attachments: [invURL, dlURL])
    }

    // Shared error alert.
    @MainActor
    static func alert(_ error: Error) {
        let a = NSAlert()
        a.messageText = "Nelze připravit e-mail"
        a.informativeText = error.localizedDescription
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
