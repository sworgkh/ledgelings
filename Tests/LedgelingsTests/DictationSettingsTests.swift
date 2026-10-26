import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Productivity tools › Dictation: its settings, its place among the tools, and
/// the creature who holds the microphone.
@MainActor
@Suite(.serialized) struct DictationSettingsTests {
    let name = "ledgelings-dictation-settings-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        func get(_ account: String) -> String? { nil }
        func set(_ value: String?, for account: String) {}
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.dictationEnabled && s.dictationShortcutEnabled && s.dictationShortcut == .dictation && !s.dictationHoldToTalk)
        #expect(s.dictationModel == Dictation.defaultModel && s.dictationLanguage == .auto && s.dictationCleanUp)
        #expect(s.dictationMaxSeconds == 120 && !s.dictationPaste && s.dictationCreature && s.dictationHelper.isEmpty)
        #expect(Shortcut.dictation == Shortcut(keyCode: 2, modifiers: [.control, .option]), "⌃⌥D")

        s.dictationEnabled = false; s.dictationShortcutEnabled = false
        s.dictationShortcut = Shortcut(keyCode: 2, modifiers: [.command, .option])
        s.dictationHoldToTalk = true; s.dictationModel = "openai/gpt-audio-mini"; s.dictationLanguage = .russian
        s.dictationCleanUp = false; s.dictationMaxSeconds = 300; s.dictationPaste = true
        s.dictationCreature = false; s.dictationHelper = "Zed"
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.dictationEnabled && !again.dictationShortcutEnabled && again.dictationShortcut == Shortcut(keyCode: 2, modifiers: [.command, .option]))
        #expect(again.dictationHoldToTalk && again.dictationModel == "openai/gpt-audio-mini" && again.dictationLanguage == .russian)
        #expect(!again.dictationCleanUp && again.dictationMaxSeconds == 300 && again.dictationPaste)
        #expect(!again.dictationCreature && again.dictationHelper == "Zed")

        defaults.set(5000, forKey: "dictationMaxSeconds"); defaults.set("klingon", forKey: "dictationLanguage"); defaults.set(" ", forKey: "dictationModel")
        defaults.set(Shortcut.Modifiers.shift.rawValue, forKey: "dictationShortcutModifiers")
        let clamped = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(clamped.dictationMaxSeconds == 600, "clamped on load")
        #expect(clamped.dictationLanguage == .auto && clamped.dictationModel == Dictation.defaultModel)
        #expect(clamped.dictationShortcut == .dictation, "a shortcut with no Command, Control or Option is the standard one")
        defaults.set(1, forKey: "dictationMaxSeconds")
        #expect(AppSettings(defaults: defaults, keychain: Secrets()).dictationMaxSeconds == 10)
    }

    @Test func dictationIsTheFourthTool() {
        #expect(SettingsGroup.tools.pages == [.reminders, .clipboard, .screenshots, .dictation])
        #expect(SettingsPage.dictation.title == tr("Dictation"))
    }

    @Test func theMicrophoneIsAPictureTurnedToFaceOut() {
        let image = Colony.picture(Dictation.microphone(bars: 5))
        #expect(image?.width == 18 && image?.height == 14)
        #expect(Set(Colony.microphoneInks.keys) == Set([.outline, .body, .light, .shade, .grille, .lit, .unlit]))
    }
}
