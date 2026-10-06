import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The cursor mood setting: a menace unless chosen otherwise, and remembered.
@MainActor
@Suite(.serialized) struct CursorMoodSettingsTests {
    let name = "ledgelings-cursor-mood-tests"

    @Test func theDefaultIsTheMenaceAndAChoiceSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.cursorMood == .bad, "nobody's colony changes its mind unasked")
        for mood in CursorMood.allCases {
            s.cursorMood = mood
            #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).cursorMood == mood)
        }
        defaults.set("grumpy", forKey: "cursorMood")
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).cursorMood == .bad, "an unknown value falls back")
    }
}
