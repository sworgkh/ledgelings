import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The Relationships tab's settings, and the colony acting on what is said: a
/// built-in invitation answered yes starts the game with both, a no is
/// remembered, a deed nobody offered is ignored, and what a prompt carries.
@MainActor
@Suite(.serialized) struct RelationshipsSettingsTests {
    let name = "ledgelings-relationships-settings-tests"

    @Test func theDefaultsAndAChangeSurviveARelaunchAndAreClamped() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.deedsEnabled && s.deedGames && s.deedTea && s.deedFlower && s.deedLetter && s.deedVisit && s.deedFollow && s.deedSleep)
        #expect(s.deedGapMinutes == 4 && s.deedsPerHour == 8 && s.deedPairGapMinutes == 20 && s.inviteOpenMinutes == 10)
        #expect(s.deedWaitMinutes == 3 && s.builtInInviteShare == 20 && s.builtInAcceptChance == 65 && s.followSeconds == 30)
        #expect(s.memoryEnabled && s.memoryTokens == 600 && s.memoryFacts == 5 && s.memoryDays == 60 && s.memoryNotes)
        #expect(s.diaryEnabled && s.diaryEveryHours == 8 && s.diaryPairsPerNight == 8 && s.dayContextEnabled && s.dayContextItems == 4)
        #expect(s.seedDays == 14 && s.seedLines == 40)
        #expect(s.deedLimits == Deeds.Limits(gap: 240, perHour: 8, pairGap: 1200))
        s.deedsEnabled = false; s.deedGames = false; s.deedTea = false; s.deedFlower = false; s.deedLetter = false
        s.deedVisit = false; s.deedFollow = false; s.deedSleep = false
        s.deedGapMinutes = 0; s.deedsPerHour = 0; s.deedPairGapMinutes = 0; s.inviteOpenMinutes = 2; s.deedWaitMinutes = 1
        s.builtInInviteShare = 100; s.builtInAcceptChance = 0; s.followSeconds = 90
        s.memoryEnabled = false; s.memoryTokens = 0; s.memoryFacts = 0; s.memoryDays = 7; s.memoryNotes = false
        s.diaryEnabled = false; s.diaryEveryHours = 24; s.diaryPairsPerNight = 0; s.dayContextEnabled = false; s.dayContextItems = 10
        s.seedDays = 3; s.seedLines = 100
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!again.deedsEnabled && !again.deedGames && !again.deedTea && !again.deedFlower && !again.deedLetter)
        #expect(!again.deedVisit && !again.deedFollow && !again.deedSleep)
        #expect(again.deedGapMinutes == 0 && again.deedsPerHour == 0 && again.deedPairGapMinutes == 0 && again.inviteOpenMinutes == 2)
        #expect(again.deedWaitMinutes == 1 && again.builtInInviteShare == 100 && again.builtInAcceptChance == 0 && again.followSeconds == 90)
        #expect(!again.memoryEnabled && again.memoryTokens == 0 && again.memoryFacts == 0 && again.memoryDays == 7 && !again.memoryNotes)
        #expect(!again.diaryEnabled && again.diaryEveryHours == 24 && again.diaryPairsPerNight == 0 && !again.dayContextEnabled && again.dayContextItems == 10)
        #expect(again.seedDays == 3 && again.seedLines == 100)
        for (key, value) in [("deedGapMinutes", -5.0), ("deedPairGapMinutes", 9999), ("inviteOpenMinutes", 0), ("deedWaitMinutes", 99),
                             ("builtInInviteShare", 250), ("followSeconds", 1), ("diaryEveryHours", 0)] { defaults.set(value, forKey: key) }
        for (key, value) in [("deedsPerHour", 500), ("memoryTokens", 5000), ("memoryFacts", -1), ("memoryDays", 1000),
                             ("diaryPairsPerNight", 99), ("dayContextItems", 50), ("seedDays", 0), ("seedLines", 1)] { defaults.set(value, forKey: key) }
        let clamped = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(clamped.deedGapMinutes == 0 && clamped.deedPairGapMinutes == 240 && clamped.inviteOpenMinutes == 1 && clamped.deedWaitMinutes == 15)
        #expect(clamped.builtInInviteShare == 100 && clamped.followSeconds == 5 && clamped.diaryEveryHours == 1)
        #expect(clamped.deedsPerHour == 120 && clamped.memoryTokens == 2000 && clamped.memoryFacts == 0 && clamped.memoryDays == 365)
        #expect(clamped.diaryPairsPerNight == 50 && clamped.dayContextItems == 10 && clamped.seedDays == 1 && clamped.seedLines == 5)
    }

    @Test func theOldDefaultMovesToTheNewOnceAndAChosenValueStays() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(150, forKey: "memoryTokens")
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).memoryTokens == 600)
        // Chosen by hand after the move, 150 stays.
        AppSettings(defaults: defaults, keychain: Keychain(service: name)).memoryTokens = 150
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).memoryTokens == 150)
        // Any other saved value was the owner's choice and is never moved.
        defaults.removePersistentDomain(forName: name)
        defaults.set(300, forKey: "memoryTokens")
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).memoryTokens == 300)
    }

    @Test func theTabIsNamedForScripts() {
        #expect(SettingsTab.named("relationships") == .relationships)
    }

    /// Two creatures talking from the built-in lines, with a bonds file of their own.
    final class World {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-relationships-\(UUID().uuidString)")
        let defaults: UserDefaults
        let settings: AppSettings
        let colony: Colony
        var traced: [String] = []
        @MainActor init(_ suite: String) throws {
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            settings = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
            settings.creatureCount = 2
            settings.brain = .script
            settings.dayMinutes = 30; settings.nightMinutes = 30
            settings.planesEnabled = false
            colony = try Colony(settings: settings, history: ChatHistory(directory: dir.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: dir.appendingPathComponent("spend")),
                                bonds: BondBook(directory: dir),
                                stage: Display(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 1))
            colony.meetings = Meetings(gap: -1e6)
            colony.nextPlayAt = .infinity
            colony.trace = { [unowned self] in self.traced.append($0) }
        }
        @MainActor func step(_ seconds: Double) {
            var left = seconds
            while left > 0 { colony.advance(dt: min(left, 0.05), cursor: CGPoint(x: -500, y: -500), shift: true); left -= 0.05 }
        }
        func forget(_ suite: String) {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test func aBuiltInInvitationAnsweredYesStartsTheGameWithBoth() throws {
        let w = try World(name)
        defer { w.forget(name) }
        w.colony.forcedOffer = .game(.tag)
        w.colony.forcedAnswer = true
        w.colony.talkNow(from: 0)
        #expect(w.traced.contains { $0.hasPrefix("deed") && $0.contains("asks") && $0.contains(": tag") })
        #expect(w.traced.contains { $0.contains("accepts tag") })
        // They finish talking, then the game starts as soon as both are free.
        for _ in 0..<600 where w.colony.play == nil { w.step(0.1) }
        let play = try #require(w.colony.play, "the game never started: \(w.traced.filter { $0.hasPrefix("deed") })")
        #expect(play.kind == .tag && Set(play.players) == [0, 1] && play.askedBy == w.colony.name(0))
        #expect(w.colony.forcedOffer == nil, "a forced invitation is used once")
    }

    @Test func aNoIsRememberedAndAnUnofferedDeedIsIgnored() throws {
        let w = try World(name)
        defer { w.forget(name) }
        w.colony.forcedOffer = .game(.basketball)
        w.colony.forcedAnswer = false
        w.colony.talkNow(from: 0)
        let a = w.colony.name(0), b = w.colony.name(1)
        #expect(w.traced.contains { $0.contains("declines basketball") })
        #expect(w.colony.bonds.bond(a, b)?.facts.first?.text.contains("said no to") == true)
        w.step(20)
        #expect(w.colony.play == nil && w.colony.agreed.isEmpty)
        // At night no game is offered: an invitation to one is not taken.
        var night = Deeds.Options()
        night.flower = true
        w.colony.took(Deeds.Tagged(text: "", deed: .invite(.game(.soccer))), by: 0, to: 1, options: night, byLetter: false)
        #expect(w.traced.last == "deed refused: \(a) invite soccer: not offered" && w.colony.invitations.isEmpty)
        w.colony.took(Deeds.Tagged(text: "", note: "Boo owes Blocky a sunflower"), by: 0, to: 1, options: night, byLetter: false)
        #expect(w.colony.bonds.bond(a, b)?.facts.last?.text == "Boo owes Blocky a sunflower")
    }

    @Test func aPromptCarriesThePairsMemoryAndTheDeedsOnOffer() throws {
        let w = try World(name)
        defer { w.forget(name) }
        let a = w.colony.name(0), b = w.colony.name(1)
        w.colony.bonds.change { $0.remember(a, b, "they share the cache at six", source: "note", keep: 5) }
        let options = w.colony.deedOptions(0, with: 1, letter: false)
        #expect(options.games.contains(.tag) && options.flower && !options.sleep, "a day's deeds")
        let side = w.colony.side(of: 0, with: 1, options)
        #expect(side.contains("You remember: they share the cache at six") && side.contains("DO: and one of these"))
        w.settings.memoryEnabled = false
        w.settings.deedsEnabled = false
        #expect(w.colony.side(of: 0, with: 1, w.colony.deedOptions(0, with: 1, letter: false)).isEmpty)
    }
}
