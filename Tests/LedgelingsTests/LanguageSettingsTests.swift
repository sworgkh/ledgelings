import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The language setting: chosen from the system, remembered, and the shipped
/// prompts and lines following it while edited ones stay.
@MainActor
@Suite(.serialized) struct LanguageSettingsTests {
    let name = "ledgelings-language-tests"

    func fresh() -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theDefaultIsTheSystemsLanguageAndAChoiceSurvivesARelaunch() {
        let defaults = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.language == Language.preferred())
        s.language = .russian
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).language == .russian)
        s.language = .english
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).language == .english)
    }

    @Test func shippedTextFollowsTheLanguageAndEditedTextStays() {
        let defaults = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("en", forKey: "language")
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.script == Script.builtInTexts(.english) && s.systemPrompt == Banter.systemPrompts(.english))
        s.linePrompt = "my own line prompt {listener}"
        s.language = .russian
        #expect(s.script == Script.builtInTexts(.russian))
        #expect(s.systemPrompt == Banter.systemPrompts(.russian))
        #expect(s.replyPrompt == Banter.replyPrompts(.russian))
        #expect(s.plotPrompt == Bonds.plotPrompts(.russian))
        #expect(s.linePrompt == "my own line prompt {listener}", "an edited prompt is the user's: it stays")
        s.resetPrompts()
        #expect(s.linePrompt == Banter.linePrompts(.russian))
        // Saved English text, read back by a Russian app, is Russian too.
        defaults.set(Script.builtInTexts(.english), forKey: "script")
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).script == Script.builtInTexts(.russian))
    }
}
