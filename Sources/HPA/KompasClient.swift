import Foundation

// Minimal client for the Kompas native REST API (/api/v1) — creates tasks and
// lists a project's tasks for the duplicate guard. Needs a write-scope API
// token (Kompas → Administrace → Nastavení → Integrace a import → API tokeny).
enum KompasClient {
    enum KompasError: LocalizedError {
        case noToken
        case http(Int, String)
        case decode
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "Chybí Kompas API token (Settings → Kompas — připojení)."
            case .http(let code, let msg):
                return "Kompas HTTP \(code): \(msg)"
            case .decode:
                return "Nečekaná odpověď Kompasu."
            case .transport(let m):
                return "Síťová chyba: \(m)"
            }
        }
    }

    static let keychainService = "com.hanak.hpa.kompas"
    static let keychainAccount = "kompas_token"

    // Prefer the Keychain (set via Settings); fall back to
    // ~/.config/hpa/kompas_token (chmod 600), same as the other integrations.
    static func loadToken() -> String? {
        if let t = Keychain.get(service: keychainService, account: keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        let path = ("~/.config/hpa/kompas_token" as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static var hasToken: Bool { loadToken() != nil }

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        Keychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines),
                     service: keychainService, account: keychainAccount)
    }

    static func clearToken() {
        Keychain.clear(service: keychainService, account: keychainAccount)
    }

    struct Stage {
        let id: String
        let name: String
        let enabled: Bool
    }

    // The project's columns. Doubles as the connection test — there is no
    // "who am I" endpoint, a token identifies a workspace, not a person.
    static func stages(project: String) async throws -> [Stage] {
        let obj = try await request("GET", "/api/v1/projects/\(project)/stages")
        guard let arr = obj["data"] as? [[String: Any]] else { throw KompasError.decode }
        return arr.compactMap { s in
            guard let id = s["id"] as? String, let name = s["name"] as? String else { return nil }
            return Stage(id: id, name: name, enabled: s["enabled"] as? Bool ?? true)
        }
    }

    // Verify the stored token against the three configured projects. Returns a
    // one-line summary on success.
    static func testConnection() async -> Result<String, Error> {
        do {
            var missing: [String] = []
            for (label, ref) in [("blockery", KompasConfig.blockersProject),
                                 ("passives", KompasConfig.passivesProject),
                                 ("debug", KompasConfig.debugProject)] {
                do { _ = try await stages(project: ref) }
                catch KompasError.http(let code, _) where code == 404 || code == 403 {
                    missing.append(label)
                }
            }
            return .success(missing.isEmpty
                ? "Token funguje, všechny tři projekty nalezeny."
                : "Token funguje, ale nedostupné projekty: \(missing.joined(separator: ", ")).")
        } catch {
            return .failure(error)
        }
    }

    // The stage new tasks should land in: the enabled column called "Todo",
    // else nil (Kompas then uses the project's first enabled column).
    static func todoStageID(project: String) async throws -> String? {
        try await stages(project: project)
            .first { $0.enabled && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "todo" }?
            .id
    }

    struct NewTask {
        let name: String
        let assignee: String?               // display name / e-mail / id; nil = none
        let project: String
        let stageID: String?                // nil = project's first column
        let sprintID: String?               // "YYYY-MM-1" / "YYYY-MM-2"
        let notes: String
        let estimateOriginal: Double?       // "Estimate (h)"
        let estimateUpdated: Double?        // "Estimate updated (h)"
    }

    // Create one task. Returns the new task's URL.
    @discardableResult
    static func createTask(_ t: NewTask) async throws -> String {
        var payload: [String: Any] = ["name": t.name, "notes": t.notes]
        if let a = t.assignee { payload["assignee"] = a }
        if let s = t.stageID { payload["stage"] = s }
        if let s = t.sprintID { payload["sprint"] = s }
        if let e = t.estimateOriginal { payload["estimate_original_h"] = e }
        if let e = t.estimateUpdated { payload["estimate_h"] = e }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let obj = try await request("POST", "/api/v1/projects/\(t.project)/tasks", body: body)
        guard let d = obj["data"] as? [String: Any], let id = d["id"] as? String else {
            throw KompasError.decode
        }
        return d["url"] as? String ?? "\(KompasConfig.base)/tasks/\(id)"
    }

    // Names of non-archived tasks in the project and sprint whose name starts
    // with `namePrefix`. Used to warn before creating duplicates.
    static func existingTasks(project: String, sprintID: String,
                              namePrefix: String) async throws -> [String] {
        var found: [String] = []
        var cursor: String? = nil
        repeat {
            var path = "/api/v1/projects/\(project)/tasks?limit=200"
            if let c = cursor { path += "&cursor=\(c)" }
            let obj = try await request("GET", path)
            for t in (obj["data"] as? [[String: Any]] ?? []) {
                guard let name = t["name"] as? String, name.hasPrefix(namePrefix),
                      (t["sprint"] as? String) == sprintID else { continue }
                found.append(name)
            }
            cursor = obj["next_cursor"] as? String
        } while cursor != nil
        return found
    }

    private static func request(_ method: String, _ path: String,
                                body: Data? = nil) async throws -> [String: Any] {
        guard let token = loadToken() else { throw KompasError.noToken }
        guard let url = URL(string: KompasConfig.base + path) else { throw KompasError.decode }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await dataTask(req)
        guard let http = resp as? HTTPURLResponse else { throw KompasError.decode }
        guard (200..<300).contains(http.statusCode) else {
            throw KompasError.http(http.statusCode, errorMessage(data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KompasError.decode
        }
        return obj
    }

    private static func errorMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = obj["error"] as? String {
            return msg
        }
        // An unauthenticated or unknown path redirects to the HTML login page.
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "?"
    }

    // URLSession async wrapper (works on the macOS 13 deployment target).
    private static func dataTask(_ req: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err { cont.resume(throwing: KompasError.transport(err.localizedDescription)); return }
                guard let data, let resp else { cont.resume(throwing: KompasError.decode); return }
                cont.resume(returning: (data, resp))
            }.resume()
        }
    }
}
