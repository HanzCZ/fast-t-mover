import SwiftUI
import AppKit

// A4 in points (72 dpi).
private let pageSize = CGSize(width: 595, height: 842)
private let hairline: CGFloat = 0.75
private let hoursColWidth: CGFloat = 70

// Faithful reproduction of the bordered OL/DL table from the source workbook.
struct ListPDFView: View {
    let kind: DocKind
    let month: MonthEntry
    let data: ListyData

    private var doc: MonthDoc { month.doc(kind) }
    private var title: String {
        "\(kind.czTitle): \(month.czLabel) – \(data.personName), IČO: \(data.ico)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 13, weight: .bold))

            table

            Text("\(data.place) \(data.personName)")
                .font(.system(size: 11))

            Spacer(minLength: 0)
        }
        .padding(48)
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }

    private var table: some View {
        VStack(spacing: 0) {
            ForEach(doc.rows) { row in
                rowView(row)
                    .overlay(alignment: .bottom) { hLine }
            }
            totalRow
        }
        .overlay { Rectangle().strokeBorder(.black, lineWidth: hairline) }
    }

    @ViewBuilder
    private func rowView(_ row: DocRow) -> some View {
        switch row.kind {
        case .section:
            HStack(spacing: 0) {
                Text(row.text)
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                vLine
                Color.clear.frame(width: hoursColWidth)
            }
        case .item:
            HStack(spacing: 0) {
                Text(row.text)
                    .font(.system(size: 11, weight: row.bold ? .bold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                vLine
                Text(formatHours(row.hours))
                    .font(.system(size: 11, weight: row.bold ? .bold : .regular))
                    .frame(width: hoursColWidth, alignment: .trailing)
                    .padding(.horizontal, 6).padding(.vertical, 3)
            }
        case .spacer:
            HStack(spacing: 0) {
                Color.clear.frame(maxWidth: .infinity)
                vLine
                Color.clear.frame(width: hoursColWidth)
            }
            .frame(height: 16)
        }
    }

    private var totalRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(formatHours(doc.totalHours)).font(.system(size: 11, weight: .bold))
                Text("hodin").font(.system(size: 11))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
    }

    private var hLine: some View { Rectangle().fill(.black).frame(height: hairline) }
    private var vLine: some View { Rectangle().fill(.black).frame(width: hairline) }
}

enum ListyPDF {
    static func filename(kind: DocKind, month: MonthEntry) -> String {
        "\(kind.shortPrefix)_\(String(format: "%02d", month.month))_\(month.year)_JH_priloha.pdf"
    }

    // Render the document to a vector PDF and write it to `url`.
    @MainActor
    static func write(kind: DocKind, month: MonthEntry, data: ListyData, to url: URL) -> Bool {
        let view = ListPDFView(kind: kind, month: month, data: data)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(pageSize)
        var ok = false
        renderer.render { _, ctx in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            ctx(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok
    }

    // Ask where to save (prefilled with the required name), then write + reveal.
    @MainActor
    static func export(kind: DocKind, month: MonthEntry, data: ListyData) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename(kind: kind, month: month)
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if write(kind: kind, month: month, data: data, to: url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSSound.beep()
        }
    }
}
