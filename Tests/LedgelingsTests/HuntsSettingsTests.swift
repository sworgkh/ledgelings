import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The Chases tab's settings, the count on disk, and the colony counting and using it.
@MainActor
@Suite(.serialized) struct HuntsSettingsTests {
    let name = "ledgelings-hunts-settings-tests"

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.huntCountEnabled && s.huntTalkEnabled && s.huntWary)
        #expect(s.huntTalkChance == 25)
        #expect(s.huntWaryAfter == 20)
        s.huntCountEnabled = false; s.huntTalkEnabled = false; s.huntTalkChance = 60; s.huntWary = false; s.huntWaryAfter = 45
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!again.huntCountEnabled && !again.huntTalkEnabled && !again.huntWary)
        #expect(again.huntTalkChance == 60 && again.huntWaryAfter == 45)
        defaults.set(500.0, forKey: "huntTalkChance"); defaults.set(1, forKey: "huntWaryAfter")
        let clamped = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(clamped.huntTalkChance == 100 && clamped.huntWaryAfter == 5, "clamped on load")
    }

    @Test func theBookKeepsItsCountAcrossARelaunch() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-huntbook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = HuntBook(directory: dir)
        book.count("Blocky"); book.count("Blocky"); book.count("Zed")
        let relaunched = HuntBook(directory: dir)
        #expect(relaunched.numbers(of: "Blocky").today == 2 && relaunched.numbers(of: "Blocky").all == 2)
        #expect(relaunched.total.all == 3)
        relaunched.reset("Blocky")
        #expect(HuntBook(directory: dir).numbers(of: "Blocky").all == 0)
        #expect(HuntBook(directory: dir).numbers(of: "Zed").all == 1)
        relaunched.reset()
        #expect(HuntBook(directory: dir).book == Hunts.Book())
    }

    @Test func everyChaseAndPickUpIsCountedUnlessCountingIsOff() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.complainEnabled = false
        let me = w.colony.character(forCreature: 0).name
        w.colony.bothered(0); w.colony.bothered(0)
        #expect(w.colony.hunts.numbers(of: me).today == 2)
        w.settings.huntCountEnabled = false
        w.colony.applySettings()
        w.colony.bothered(0)
        #expect(w.colony.hunts.numbers(of: me).today == 2, "off counts nothing")
    }

    @Test func aRoundNumberIsSaidInTheCreaturesOwnWords() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.complainEnabled = false
        w.settings.huntTalkChance = 0          // only the milestone speaks
        w.settings.revengeEnabled = false      // ten in a row would grab the cursor instead
        w.colony.applySettings()
        for _ in 0..<9 { w.colony.bothered(0) }
        #expect(w.colony.bubbles[0] == nil)
        w.colony.bothered(0)
        let said = try #require(w.colony.bubbles[0]?.text)
        #expect(said.contains("10"), "the tenth hunt today: \(said)")
        // Talking about it off: counted, never said.
        w.colony.bubbles.removeAll()
        w.settings.huntTalkEnabled = false
        w.colony.applySettings()
        for _ in 0..<15 { w.colony.bothered(0) }
        #expect(w.colony.bubbles[0] == nil)
        #expect(w.colony.hunts.numbers(of: w.colony.character(forCreature: 0).name).today == 25)
    }

    @Test func theCountReachesThePromptsSituation() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.complainEnabled = false
        w.colony.bothered(0); w.colony.bothered(0); w.colony.bothered(0)
        let me = w.colony.character(forCreature: 0).name
        let sentence = Language.$override.withValue(.english) { w.colony.huntSentence([0, 1], always: true) }
        #expect(sentence.contains("\(me) 3 times"))
        w.settings.huntTalkChance = 0
        #expect(w.colony.huntSentence([0]) == "", "this moment does not bring it up")
        w.settings.huntTalkChance = 100
        #expect(!w.colony.huntSentence([0]).isEmpty)
        #expect(w.colony.huntLineInstead(0) != nil, "a built-in line about the count, now and then")
        w.settings.huntTalkEnabled = false
        #expect(w.colony.huntSentence([0], always: true) == "")
        #expect(w.colony.huntLineInstead(0) == nil)
    }

    @Test func aMuchHuntedCreatureKeepsItsDistanceOnlyWhenTheCursorIsAMenace() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.complainEnabled = false
        w.settings.huntTalkEnabled = false
        w.settings.huntWaryAfter = 5
        w.settings.cursorMood = .bad
        w.colony.applySettings()
        let calm = w.colony.creatures[0].config.fleeRadius
        for _ in 0..<5 { w.colony.bothered(0) }
        #expect(w.colony.creatures[0].config.fleeRadius > calm)
        w.settings.cursorMood = .good
        w.colony.applySettings()
        #expect(w.colony.creatures[0].config.fleeRadius == calm, "a playmate comes close")
        w.settings.cursorMood = .bad
        w.settings.huntWary = false
        w.colony.applySettings()
        #expect(w.colony.creatures[0].config.fleeRadius == calm)
    }
}
