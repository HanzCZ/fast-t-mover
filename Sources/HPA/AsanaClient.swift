import Foundation

// Minimal Asana REST client for creating tasks with custom fields.
// Token is read from ~/.config/hpa/asana_token (chmod 600). A Keychain-backed
// entry UI can replace the file later; the file path stays as a fallback.
enum AsanaClient {
    static let base = "https://app.asana.com/api/1.0"

    enum AsanaError: LocalizedError {
        case noToken
        case http(Int, String)
        case decode
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "Chybí Asana token (~/.config/hpa/asana_token)."
            case .http(let code, let msg):
                return "Asana HTTP \(code): \(msg)"
            case .decode:
                return "Nečekaná odpověď Asany."
            case .transport(let m):
                return "Síťová chyba: \(m)"
            }
        }
    }

    static let keychainService = "com.hanak.hpa.asana"
    static let keychainAccount = "asana_token"

    // Prefer the Keychain (set via Settings); fall back to the legacy
    // ~/.config/hpa/asana_token file so existing setups keep working.
    static func loadToken() -> String? {
        if let t = Keychain.get(service: keychainService, account: keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        let path = ("~/.config/hpa/asana_token" as NSString).expandingTildeInPath
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

    // Verify the stored token. Returns "Name <email>" on success.
    static func testConnection() async -> Result<String, Error> {
        guard let token = loadToken() else { return .failure(AsanaError.noToken) }
        var req = URLRequest(url: URL(string: "\(base)/users/me?opt_fields=name,email")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await dataTask(req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failure(AsanaError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, errorMessage(data)))
            }
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let d = obj?["data"] as? [String: Any]
            let name = d?["name"] as? String ?? "?"
            let email = d?["email"] as? String ?? ""
            return .success(email.isEmpty ? name : "\(name) <\(email)>")
        } catch {
            return .failure(error)
        }
    }

    struct NewTask {
        let name: String
        let assigneeGID: String?            // nil = no assignee
        let projectGID: String
        let dueOn: String?                  // YYYY-MM-DD, or nil for no due date
        let notes: String
        // gid -> value: String (enum option), Double (number), [String] (multi_enum)
        let customFields: [String: Any]
    }

    // Create one task. Returns the new task's GID on success.
    static func createTask(_ t: NewTask) async throws -> String {
        guard let token = loadToken() else { throw AsanaError.noToken }
        var req = URLRequest(url: URL(string: "\(base)/tasks")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        var payload: [String: Any] = [
            "name": t.name,
            "projects": [t.projectGID],
            "notes": t.notes,
            "custom_fields": t.customFields,
        ]
        if let a = t.assigneeGID { payload["assignee"] = a }
        if let due = t.dueOn { payload["due_on"] = due }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

        let (data, resp) = try await dataTask(req)
        guard let http = resp as? HTTPURLResponse else { throw AsanaError.decode }
        guard (200..<300).contains(http.statusCode) else {
            throw AsanaError.http(http.statusCode, errorMessage(data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["data"] as? [String: Any],
              let gid = d["gid"] as? String else {
            throw AsanaError.decode
        }
        return gid
    }

    // Return the names of existing tasks whose name starts with `namePrefix`,
    // already in the given project AND tagged with the given AL SPRINT option.
    // Used to warn before creating duplicates. Pages through the project's tasks.
    static func existingTasks(projectGID: String, sprintOptionGID: String,
                              namePrefix: String) async throws -> [String] {
        guard let token = loadToken() else { throw AsanaError.noToken }
        var found: [String] = []
        var offset: String? = nil
        let fields = "name,custom_fields.gid,custom_fields.enum_value.gid"
        repeat {
            var urlStr = "\(base)/tasks?project=\(projectGID)&opt_fields=\(fields)&limit=100"
            if let o = offset { urlStr += "&offset=\(o)" }
            var req = URLRequest(url: URL(string: urlStr)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, resp) = try await dataTask(req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AsanaError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, errorMessage(data))
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AsanaError.decode
            }
            for t in (obj["data"] as? [[String: Any]] ?? []) {
                guard let name = t["name"] as? String,
                      name.hasPrefix(namePrefix) else { continue }
                let cfs = t["custom_fields"] as? [[String: Any]] ?? []
                let matches = cfs.contains { cf in
                    (cf["gid"] as? String) == AsanaConfig.sprintFieldGID
                        && ((cf["enum_value"] as? [String: Any])?["gid"] as? String) == sprintOptionGID
                }
                if matches { found.append(name) }
            }
            offset = (obj["next_page"] as? [String: Any])?["offset"] as? String
        } while offset != nil
        return found
    }

    // Delete a task (used by the self-test).
    static func deleteTask(_ gid: String) async throws {
        guard let token = loadToken() else { throw AsanaError.noToken }
        var req = URLRequest(url: URL(string: "\(base)/tasks/\(gid)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await dataTask(req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AsanaError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, errorMessage(data))
        }
    }

    private static func errorMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errs = obj["errors"] as? [[String: Any]],
           let msg = errs.first?["message"] as? String {
            return msg
        }
        return String(data: data, encoding: .utf8) ?? "?"
    }

    // URLSession async wrapper (works on the macOS 13 deployment target).
    private static func dataTask(_ req: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err { cont.resume(throwing: AsanaError.transport(err.localizedDescription)); return }
                guard let data, let resp else { cont.resume(throwing: AsanaError.decode); return }
                cont.resume(returning: (data, resp))
            }.resume()
        }
    }

    static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
