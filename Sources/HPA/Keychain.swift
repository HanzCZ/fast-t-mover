import Foundation
import Security

// Minimal login-keychain wrapper for a single generic-password secret.
// Works for ad-hoc-signed apps (no special entitlement needed); the first
// access after a rebuild may prompt once to allow access.
enum Keychain {
    static let service = "com.hanak.hpa.asana"
    static let account = "asana_token"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func set(_ value: String) -> Bool {
        SecItemDelete(baseQuery() as CFDictionary)
        var add = baseQuery()
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    @discardableResult
    static func clear() -> Bool {
        SecItemDelete(baseQuery() as CFDictionary) == errSecSuccess
    }
}
