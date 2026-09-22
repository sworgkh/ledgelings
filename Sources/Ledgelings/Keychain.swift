import Foundation
import Security

/// Secrets, such as an API key, kept in the user's login keychain rather than
/// in the preferences file, which any process could read.
///
/// One item per `account`, all under one `service` name so they are easy to
/// find in Keychain Access. Setting `nil` or an empty string removes the item.
/// Where a secret lives. The keychain in the app; a spy in tests.
protocol SecretStore: Sendable {
    func get(_ account: String) -> String?
    func set(_ value: String?, for account: String)
}

struct Keychain: SecretStore {
    var service = "Ledgelings"

    func get(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replace, never update: changing an item made by an earlier build of the
    /// app needs the user's permission, a fresh item made by this build does not.
    func set(_ value: String?, for account: String) {
        let query = base(account)
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
