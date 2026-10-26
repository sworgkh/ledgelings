import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The OpenRouter key in the keychain: a read the keychain's dialog refused is
/// not "no key", and the Translate sheet or dictation, started by hand, reads it again.
@MainActor
@Suite(.serialized) struct OpenRouterKeyTests {
    let name = "ledgelings-openrouter-key-tests"

    /// Fails the first `failures` reads, as a refused or closed dialog does, then finds the key.
    final class Keys: SecretStore, @unchecked Sendable {
        var failures: Int
        var key: String?
        var reads = 0
        init(failures: Int, key: String?) { self.failures = failures; self.key = key }
        func get(_ account: String) -> String? { if case .found(let k) = read(account) { return k }; return nil }
        func set(_ value: String?, for account: String) { key = value }
        func read(_ account: String) -> SecretRead {
            reads += 1
            if failures > 0 { failures -= 1; return .failed(-25293) }
            return key.map(SecretRead.found) ?? .missing
        }
    }

    func settings(_ keys: Keys) -> AppSettings {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults, keychain: keys)
    }

    @Test func aRefusedReadIsTriedAgainWhenTheSheetOpens() throws {
        defer { UserDefaults(suiteName: name)!.removePersistentDomain(forName: name) }
        let keys = Keys(failures: 1, key: "sk-or-test")
        let s = settings(keys)
        #expect(s.openRouterKey == "", "the first read was refused")
        #expect(s.openRouterKey == "" && keys.reads == 1, "creatures talking on their own do not ask again")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let translator = Translator(settings: s, spend: SpendLedger(directory: scratch))
        translator.refresh()
        #expect(translator.client()?.model == Translate.defaultModel, "the sheet opening read it again and found it")
        #expect(translator.hasModel)
        #expect(s.openRouterKey == "sk-or-test" && keys.reads == 2)
        translator.refresh()
        #expect(keys.reads == 2, "a key read fine is not read again")
    }

    @Test func noKeySavedIsNotAskedAgain() {
        defer { UserDefaults(suiteName: name)!.removePersistentDomain(forName: name) }
        let keys = Keys(failures: 0, key: nil)
        let s = settings(keys)
        #expect(s.openRouterKey == "")
        s.retryOpenRouterKey()
        #expect(keys.reads == 1)
        s.openRouterKey = "sk-or-new"
        #expect(s.openRouterKey == "sk-or-new" && keys.key == "sk-or-new")
    }
}
