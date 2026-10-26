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
    /// What a read found: the secret, nothing saved, or a read that failed
    /// (the permission dialog refused or closed), which is worth trying again.
    func read(_ account: String) -> SecretRead
}

enum SecretRead: Equatable {
    case found(String)
    case missing
    case failed(Int32)
}

extension SecretStore {
    func read(_ account: String) -> SecretRead { get(account).map(SecretRead.found) ?? .missing }
}

struct Keychain: SecretStore {
    var service = "Ledgelings"

    func get(_ account: String) -> String? {
        if case .found(let value) = read(account) { return value }
        return nil
    }

    func read(_ account: String) -> SecretRead {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return .failed(status) }
        return .found(value)
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
