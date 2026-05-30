import Foundation

// Fixed parameters for Jan Hanák's monthly SSGH invoice (introspected from
// invoice 2026-0005). Amount lives in Settings; the period (month/year) is the
// only per-invoice variable; the contract date is hardcoded for now.
enum FakturoidConfig {
    static let base = "https://app.fakturoid.cz/api/v3"
    static let slug = "janhanak"
    static let userAgent = "HPA (honzales@gmail.com)"
    static let subjectID = 28395359                       // SŠ gastronomická a hotelová
    static let clientName = "Střední škola gastronomická a hotelová s.r.o."
    static let contractDate = "01.01.2026"                // hardcoded for now
    static let dueDays = 30
    static let defaultAmount: Double = 92000

    static func lineText(month: Int, year: Int) -> String {
        "na základě uzavřené Rámcové smlouvy o poskytování služeb ze dne \(contractDate) "
        + "Vám fakturujeme služby za období: \(CzCal.monthName(month)) \(year)"
    }
}

enum FakturoidClient {
    static let kcService = "com.hanak.hpa.fakturoid"

    struct Invoice {
        let id: Int
        let number: String
        let status: String
        let htmlURL: String   // admin URL in the Fakturoid app

        init(_ d: [String: Any]) {
            id = d["id"] as? Int ?? 0
            number = d["number"] as? String ?? ""
            status = d["status"] as? String ?? ""
            htmlURL = d["html_url"] as? String
                ?? "https://app.fakturoid.cz/\(FakturoidConfig.slug)/invoices/\(d["id"] as? Int ?? 0)"
        }
    }

    enum FErr: LocalizedError {
        case noCreds, http(Int, String), decode, pdfTimeout
        var errorDescription: String? {
            switch self {
            case .noCreds: return "Chybí Fakturoid přihlášení (client ID/secret)."
            case .http(let c, let m): return "Fakturoid HTTP \(c): \(m)"
            case .decode: return "Nečekaná odpověď Fakturoidu."
            case .pdfTimeout: return "PDF se nepodařilo vygenerovat včas."
            }
        }
    }

    // MARK: - Credentials (Keychain, with ~/.config/hpa/fakturoid.json fallback)

    static func loadCreds() -> (id: String, secret: String)? {
        if let id = Keychain.get(service: kcService, account: "client_id"),
           let sec = Keychain.get(service: kcService, account: "client_secret"),
           !id.isEmpty, !sec.isEmpty {
            return (id, sec)
        }
        let path = ("~/.config/hpa/fakturoid.json" as NSString).expandingTildeInPath
        if let data = FileManager.default.contents(atPath: path),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = obj["client_id"] as? String, let sec = obj["client_secret"] as? String,
           !id.isEmpty, !sec.isEmpty {
            return (id, sec)
        }
        return nil
    }

    static var hasCreds: Bool { loadCreds() != nil }

    static func saveCreds(id: String, secret: String) {
        Keychain.set(id.trimmingCharacters(in: .whitespacesAndNewlines),
                     service: kcService, account: "client_id")
        Keychain.set(secret.trimmingCharacters(in: .whitespacesAndNewlines),
                     service: kcService, account: "client_secret")
        cachedToken = nil
    }

    static func clearCreds() {
        Keychain.clear(service: kcService, account: "client_id")
        Keychain.clear(service: kcService, account: "client_secret")
        cachedToken = nil
    }

    // MARK: - Token (cached in memory)

    private static var cachedToken: String?
    private static var tokenExpiry = Date.distantPast

    static func token() async throws -> String {
        if let t = cachedToken, Date() < tokenExpiry { return t }
        guard let c = loadCreds() else { throw FErr.noCreds }
        var req = URLRequest(url: URL(string: "\(FakturoidConfig.base)/oauth/token")!)
        req.httpMethod = "POST"
        let basic = Data("\(c.id):\(c.secret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(FakturoidConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["grant_type": "client_credentials"])

        let (data, resp) = try await dataTask(req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tok = obj["access_token"] as? String else {
            throw FErr.http((resp as? HTTPURLResponse)?.statusCode ?? -1, msg(data))
        }
        cachedToken = tok
        let ttl = (obj["expires_in"] as? Double) ?? 3600
        tokenExpiry = Date().addingTimeInterval(ttl - 60)
        return tok
    }

    // MARK: - Operations

    // Account name (used by Settings "Test connection").
    static func testConnection() async throws -> String {
        let t = try await token()
        let (data, resp) = try await authed("GET", "\(FakturoidConfig.base)/user.json", token: t)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw FErr.http((resp as? HTTPURLResponse)?.statusCode ?? -1, msg(data))
        }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let accounts = obj?["accounts"] as? [[String: Any]]
        let name = accounts?.first?["name"] as? String ?? (obj?["full_name"] as? String ?? FakturoidConfig.slug)
        return name
    }

    // The monthly invoice is issued on the last day of the period and assigned
    // to the school — find it by those two facts (idempotent).
    static func findInvoice(year: Int, month: Int) async throws -> Invoice? {
        let target = lastDay(year: year, month: month)
        let t = try await token()
        for page in 1...12 {
            let url = "\(FakturoidConfig.base)/accounts/\(FakturoidConfig.slug)/invoices.json?page=\(page)"
            let (data, resp) = try await authed("GET", url, token: t)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw FErr.http((resp as? HTTPURLResponse)?.statusCode ?? -1, msg(data))
            }
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !arr.isEmpty else { break }
            for inv in arr where (inv["subject_id"] as? Int) == FakturoidConfig.subjectID
                && (inv["issued_on"] as? String) == target {
                return Invoice(inv)
            }
            // Newest-first: once a page ends older than the target, stop.
            if let oldest = arr.last?["issued_on"] as? String, oldest < target { break }
        }
        return nil
    }

    static func createInvoice(year: Int, month: Int, amount: Double) async throws -> Invoice {
        let t = try await token()
        let day = lastDay(year: year, month: month)
        let payload: [String: Any] = [
            "subject_id": FakturoidConfig.subjectID,
            "issued_on": day,
            "taxable_fulfillment_due": day,
            "due": FakturoidConfig.dueDays,
            "currency": "CZK",
            "payment_method": "bank",
            "lines": [[
                "name": FakturoidConfig.lineText(month: month, year: year),
                "quantity": 1,
                "unit_price": amount,
                "vat_rate": 0,
            ]],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let url = "\(FakturoidConfig.base)/accounts/\(FakturoidConfig.slug)/invoices.json"
        let (data, resp) = try await authed("POST", url, token: t, body: body)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let inv = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FErr.http((resp as? HTTPURLResponse)?.statusCode ?? -1, msg(data))
        }
        return Invoice(inv)
    }

    // Download the invoice PDF to ~/Downloads and return the file URL.
    @discardableResult
    static func downloadPDF(_ inv: Invoice) async throws -> URL {
        let t = try await token()
        let url = "\(FakturoidConfig.base)/accounts/\(FakturoidConfig.slug)/invoices/\(inv.id)/download.pdf"
        for _ in 0..<6 {
            let (data, resp) = try await authed("GET", url, token: t, accept: "application/pdf")
            guard let http = resp as? HTTPURLResponse else { throw FErr.decode }
            if http.statusCode == 200 {
                let safe = inv.number.replacingOccurrences(of: "/", with: "-")
                let out = FileManager.default
                    .urls(for: .downloadsDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("faktura_\(safe.isEmpty ? String(inv.id) : safe).pdf")
                try data.write(to: out)
                return out
            } else if http.statusCode == 204 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            } else {
                throw FErr.http(http.statusCode, msg(data))
            }
        }
        throw FErr.pdfTimeout
    }

    // MARK: - Helpers

    static func lastDay(year: Int, month: Int) -> String {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        let cal = Calendar(identifier: .gregorian)
        if let date = cal.date(from: comps),
           let range = cal.range(of: .day, in: .month, for: date) {
            return String(format: "%04d-%02d-%02d", year, month, range.count)
        }
        return String(format: "%04d-%02d-28", year, month)
    }

    private static func authed(_ method: String, _ url: String, token: String,
                               body: Data? = nil, accept: String = "application/json")
        async throws -> (Data, URLResponse) {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue(FakturoidConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await dataTask(req)
    }

    private static func msg(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errs = obj["errors"] { return "\(errs)" }
            if let m = obj["error_description"] as? String { return m }
        }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "?"
    }

    private static func dataTask(_ req: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err { cont.resume(throwing: err); return }
                guard let data, let resp else { cont.resume(throwing: FErr.decode); return }
                cont.resume(returning: (data, resp))
            }.resume()
        }
    }
}
