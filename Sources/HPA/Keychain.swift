import Foundation
import Security

// Minimal login-keychain wrapper for generic-password secrets, keyed by
// service + account. Works for ad-hoc-signed apps (no special entitlement);
// the first access after a rebuild may prompt once to allow access.
enum Keychain {
    private static func baseQuery(_ service: String, _ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        SecItemDelete(baseQuery(service, account) as CFDictionary)
        var add = baseQuery(service, account)
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(service: String, account: String) -> String? {
        var query = baseQuery(service, account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    @discardableResult
    static func clear(service: String, account: String) -> Bool {
        SecItemDelete(baseQuery(service, account) as CFDictionary) == errSecSuccess
    }
}
