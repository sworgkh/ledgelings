import Foundation
import Testing
@testable import Ledgelings

/// Touches the real login keychain, under a throwaway account name that is removed at the end.
@Suite struct KeychainTests {
    @Test func aSecretRoundTripsAndDisappearsWhenCleared() throws {
        let account = "test-\(UUID().uuidString)"
        let keychain = Keychain(service: "Ledgelings.tests")
        defer { keychain.set(nil, for: account) }

        #expect(keychain.get(account) == nil)
        keychain.set("sk-or-first", for: account)
        #expect(keychain.get(account) == "sk-or-first")
        keychain.set("sk-or-second", for: account)
        #expect(keychain.get(account) == "sk-or-second")
        keychain.set("", for: account)
        #expect(keychain.get(account) == nil)
    }
}
