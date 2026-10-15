import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The Play tab's settings, and the colony playing: on its own when a game is
/// due, by hand from the Actions sheet, never with someone busy, and each pair
/// game a moment of their story.
@MainActor
@Suite(.serialized) struct PlaySettingsTests {
    let name = "ledgelings-play-settings-tests"

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.playEnabled && s.playTagEnabled && s.playRopeEnabled && s.playParachuteEnabled && s.playBasketballEnabled && s.playTalk)
        #expect(s.playEveryMinutes == 5 && s.playBondBoost == 100 && s.tagSeconds == 25)
        #expect(s.parachuteFallSpeed == 70 && s.ballBounce == 60 && s.basketballThrows == 3)
        #expect(s.enabledPlays == Set(Plays.Kind.allCases))
        s.playEnabled = false; s.playTagEnabled = false; s.playRopeEnabled = false; s.playParachuteEnabled = false
        s.playBasketballEnabled = false; s.playTalk = false
        s.playEveryMinutes = 12; s.playBondBoost = 250; s.tagSeconds = 60
        s.parachuteFallSpeed = 40; s.ballBounce = 80; s.basketballThrows = 7
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!again.playEnabled && !again.playTagEnabled && !again.playRopeEnabled && !again.playParachuteEnabled)
        #expect(!again.playBasketballEnabled && !again.playTalk && again.enabledPlays.isEmpty)
        #expect(again.playEveryMinutes == 12 && again.playBondBoost == 250 && again.tagSeconds == 60)
        #expect(again.parachuteFallSpeed == 40 && again.ballBounce == 80 && again.basketballThrows == 7)
        for (key, value) in [("playEveryMinutes", 0.0), ("playBondBoost", 999), ("tagSeconds", 1), ("parachuteFallSpeed", 5000), ("ballBounce", 100)] {
            defaults.set(value, forKey: key)
        }
        defaults.set(50, forKey: "basketballThrows")
        let clamped = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(clamped.playEveryMinutes == 1 && clamped.playBondBoost == 300 && clamped.tagSeconds == 10, "clamped on load")
        #expect(clamped.parachuteFallSpeed == 200 && clamped.ballBounce == 90 && clamped.basketballThrows == 10)
    }

    func world() throws -> ColonyTalkTests.World {
        let w = try ColonyTalkTests.World()
        w.colony.nextPlayAt = .infinity
        w.colony.playEveryWas = w.settings.playEveryMinutes
        return w
    }

    @Test func aGameOfTagTakesTurnsAndBecomesAMomentOfTheirStory() throws {
        let w = try world()
        defer { w.forget() }
        w.settings.tagSeconds = 10
        var lines: [String] = []
        w.colony.trace = { lines.append($0) }
        let started = w.colony.startPlay(.tag)
        #expect(started)
        let players = try #require(w.colony.play?.players)
        #expect(Set(players) == [0, 1] && w.colony.busy == [0, 1], "nothing else starts with them")
        #expect(w.colony.bubbles[players[0]] != nil, "whoever starts it says so")
        let second = w.colony.startPlay(.rope)
        #expect(!second, "one game at a time")
        var waited = 0.0
        while w.colony.play != nil, waited < 40 { w.step(0.1); waited += 0.1 }
        #expect(w.colony.play == nil && w.colony.busy.isEmpty)
        #expect(lines.contains { $0.contains("out of breath") }, "\(lines)")
        let a = w.colony.character(forCreature: 0).name, b = w.colony.character(forCreature: 1).name
        #expect(w.colony.bonds.bond(a, b)?.tally["play"] == 1)
        #expect(w.colony.bonds.bond(a, b)?.moments.last?.detail == "tag")
        #expect(w.history.days().flatMap { w.history.exchanges(on: $0) }.count >= 1, "the lines go to the chat log")
    }

    @Test func aRopeSwingAndAParachuteJumpComeBackDownOntoAnEdge() throws {
        let w = try world()
        defer { w.forget() }
        w.settings.creatureCount = 1
        w.colony.applySettings()
        for kind in [Plays.Kind.rope, .parachute] {
            var lines: [String] = []
            w.colony.trace = { lines.append($0) }
            var waited = 0.0
            while !w.colony.startPlay(kind), waited < 20 { w.step(0.5); waited += 0.5 }
            #expect(w.colony.play?.kind == kind)
            var flew = false
            waited = 0
            while w.colony.play != nil, waited < 40 {
                w.step(0.05); waited += 0.05
                if w.colony.creatures[0].isPlaying { flew = true }
                if kind == .rope, w.colony.play?.rope?.ropeIsOut == true { #expect(!w.colony.playProps().isEmpty, "the rope and its hook are drawn") }
            }
            #expect(flew && w.colony.play == nil, "\(kind): \(lines)")
            #expect(lines.contains { $0.contains("lands") }, "\(lines)")
            w.step(1.5)
            let c = w.colony.creatures[0]
            #expect(!c.isPlaying && !c.isJumping)
            #expect(hypot(c.position.x - c.world.point(at: c.spot).x, c.position.y - c.world.point(at: c.spot).y) < 0.5, "back on its edge")
        }
    }

    @Test func basketballPutsAHoopOnAWallAndThrowsTheBall() throws {
        let w = try world()
        defer { w.forget() }
        w.settings.creatureCount = 1
        w.settings.basketballThrows = 2
        w.colony.applySettings()
        var lines: [String] = []
        w.colony.trace = { lines.append($0) }
        let started = w.colony.startPlay(.basketball)
        #expect(started)
        var sawBall = false, waited = 0.0
        while w.colony.play != nil, waited < 60 {
            w.step(0.05); waited += 0.05
            if w.colony.play?.court?.ball != nil { sawBall = true }
        }
        #expect(sawBall && w.colony.play == nil)
        #expect(lines.filter { $0.hasSuffix("throws") }.count == 2, "\(lines)")
        #expect(lines.contains { $0.contains("basketball over") })
    }

    @Test func noGameWithSomeoneBusyAsleepOrWithPlayOff() throws {
        let w = try world()
        defer { w.forget() }
        w.colony.creatures[0].toggleNap(using: &w.colony.rng)
        w.colony.busy.insert(1)
        let rope = w.colony.startPlay(.rope), tag = w.colony.startPlay(.tag)
        #expect(!rope && !tag)
        w.colony.busy.removeAll()
        let tagWithASleeper = w.colony.startPlay(.tag)
        #expect(!tagWithASleeper, "tag needs two awake")
        // On its own, when due, and never with play off.
        w.colony.creatures[0].toggleNap(using: &w.colony.rng)
        w.settings.playEnabled = false
        w.colony.applySettings()
        w.colony.nextPlayAt = 0
        w.step(1)
        #expect(w.colony.play == nil)
        w.settings.playEnabled = true
        w.colony.applySettings()
        w.colony.nextPlayAt = 0
        w.step(0.2)
        #expect(w.colony.play != nil, "a game, due, starts on its own")
        w.settings.playEnabled = false
        w.colony.applySettings()
        #expect(w.colony.play == nil && w.colony.busy.isEmpty, "turned off, it stops at once")
    }

    @Test func theActivitiesPageHasARowForEveryGameAndTheSheetStaysLean() {
        #expect(ActionsTile.allCases.count == 8, "no game tiles on the sheet itself")
        var s = ActionsState()
        #expect(Plays.Kind.allCases.allSatisfy { $0.activityDetail(in: s) == nil && !$0.activityLine.isEmpty })
        s.playsOff = [.rope]
        #expect(Plays.Kind.rope.activityDetail(in: s) == "off in settings" && Plays.Kind.tag.activityDetail(in: s) == nil)
        s.playsOff = []; s.playing = true
        #expect(Plays.Kind.tag.activityDetail(in: s) == "one at a time")
        s.hiding = true
        #expect(Plays.Kind.tag.activityDetail(in: s) == "they are hiding")
        let keys = Plays.Kind.allCases.map(\.activityKey)
        #expect(Set(keys).count == 4 && Set(keys).isDisjoint(with: ActionsTile.allCases.map(\.key) + ["a"]), "its own keys")
        #expect(ActionsSwitch.play.title(in: ActionsState()) == "PLAY ON")
        #expect(ActionsSwitch.play.title(in: s) == "PLAY ON" && ActionsSwitch.play.said(in: s) == "They play now and then.")
    }

    @Test func theSheetOpensOnTheActivitiesPageAndGoesBack() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        let sheet = ActionsController(settings: settings, colony: { nil }, addReminder: {})
        sheet.show(page: .activities)
        #expect(sheet.isUp && sheet.page == .activities)
        sheet.show()
        #expect(sheet.page == .main, "the sheet itself, from the menu or the shortcut")
        sheet.toggle()
    }
}
