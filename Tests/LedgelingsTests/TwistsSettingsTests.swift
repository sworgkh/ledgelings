import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The Plot twists page's settings, and the colony acting on a change of the
/// gang: a newcomer's first meeting, a departure in the friends' memory, the
/// news in a prompt and in the built-in lines.
@MainActor
@Suite(.serialized) struct TwistsSettingsTests {
    let name = "ledgelings-twists-settings-tests"

    @Test func theDefaultsAndAChangeSurviveARelaunchAndAreClamped() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.twistsEnabled && s.twistDays == 3 && s.twistChance == 35 && s.twistDepartures)
        s.twistsEnabled = false; s.twistDays = 10; s.twistChance = 80; s.twistDepartures = false
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!again.twistsEnabled && again.twistDays == 10 && again.twistChance == 80 && !again.twistDepartures)
        defaults.set(99, forKey: "twistDays"); defaults.set(0.0, forKey: "twistChance")
        let clamped = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(clamped.twistDays == 14 && clamped.twistChance == 5)
        defaults.set(0, forKey: "twistDays"); defaults.set(500.0, forKey: "twistChance")
        let low = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(low.twistDays == 1 && low.twistChance == 100)
    }

    @Test func thePageIsNamedForScriptsAndIndexed() {
        #expect(SettingsPage.named("twists") == .twists && SettingsPage.twists.group == .talkAndFriends)
        let keys = Set(SettingsIndex.sections.filter { $0.page == .twists }.flatMap(\.keys))
        #expect(keys == ["twistsEnabled", "twistDays", "twistChance", "twistDepartures"])
    }

    /// Three creatures talking from the built-in lines, with a bonds file of their own.
    @Test func aNewcomerMeetsEveryoneAndALeaverIsMissed() throws {
        let w = try RelationshipsSettingsTests.World(name)
        defer { w.forget(name) }
        w.settings.creatureCount = 3
        w.colony.applySettings()
        let a = w.colony.name(0), b = w.colony.name(1), c = w.colony.name(2)
        let now = Date()
        // The first look: everyone known, nothing is news.
        w.colony.observeGang(now: now - 600)
        #expect(w.colony.freshNews.isEmpty)
        w.colony.bonds.change { $0.liveTogether(3600, names: [a, b, c]) }
        // c leaves for good: the count comes down, and two minutes pass.
        w.settings.creatureCount = 2
        w.colony.applySettings()
        w.colony.observeGang(now: now - 400)
        w.colony.observeGang(now: now - 200)
        #expect(w.traced.contains("twist left \(c)"))
        #expect(w.colony.bonds.bond(a, c)?.facts.last?.text == "\(c) left the gang")
        #expect(w.colony.bonds.bond(b, c)?.facts.last?.source == "gang")
        // A newcomer made by hand: the next talk between a and b brings it up.
        w.colony.fakeTwist(.joined, "Newbie")
        w.colony.forceNews = true
        let heard = w.colony.relationship(of: 0, with: 1)
        #expect(heard.contains("News in the gang:") && heard.contains("Newbie is new to the gang: arrived today."))
        #expect(heard.contains("\(c) has left the gang"))
        // From the built-in lines it is a line of each one's own about it.
        w.colony.talkNow(from: 0)
        #expect(w.traced.contains { $0.hasPrefix("twist built in: \(a) on") })
        // Off, nothing is said of it.
        w.settings.twistsEnabled = false
        w.colony.newsRolls = [:]
        #expect(!w.colony.relationship(of: 0, with: 1).contains("News in the gang"))
    }

    @Test func aNewcomersFirstTalkIsAFirstMeeting() throws {
        let w = try RelationshipsSettingsTests.World(name)
        defer { w.forget(name) }
        let a = w.colony.name(0), b = w.colony.name(1)
        w.colony.observeGang(now: Date() - 600)
        w.colony.fakeTwist(.joined, b)
        w.colony.talked(a, b, lines: [ChatLog.Line(speaker: a, text: "Who are you?")])
        let bond = try #require(w.colony.bonds.bond(a, b))
        #expect(bond.tally["meet"] == 1 && bond.moments.first?.kind == .meet && bond.moments.first?.who == b)
        #expect(bond.facts.contains { $0.text == "\(a) and \(b) first met when \(b) was new to the gang" || $0.text == "\(b) and \(a) first met when \(b) was new to the gang" })
        // The second talk is just a talk.
        w.colony.talked(a, b, lines: [ChatLog.Line(speaker: b, text: "Still me.")])
        #expect(w.colony.bonds.bond(a, b)?.tally["meet"] == 1)
        #expect(w.colony.memoryDump().contains { $0.contains("first met when \(b) was new") })
    }

    @Test func oldFriendsNeverHaveAFirstMeeting() throws {
        let w = try RelationshipsSettingsTests.World(name)
        defer { w.forget(name) }
        let a = w.colony.name(0), b = w.colony.name(1)
        w.colony.observeGang(now: Date() - 600)
        w.colony.talked(a, b, lines: [ChatLog.Line(speaker: a, text: "Morning.")])
        w.colony.fakeTwist(.joined, b)
        w.colony.talked(a, b, lines: [ChatLog.Line(speaker: b, text: "Morning again.")])
        #expect(w.colony.bonds.bond(a, b)?.tally["meet"] == nil && w.colony.bonds.bond(a, b)?.tally["talk"] == 2)
    }
}
