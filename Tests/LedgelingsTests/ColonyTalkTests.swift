import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// A colony on a virtual display, stepped by hand, talking from the built-in lines.
@MainActor
@Suite(.serialized) struct ColonyTalkTests {
    @MainActor final class World {
        static let suite = "ledgelings-colony-tests"
        let dir: URL
        let defaults: UserDefaults
        let settings: AppSettings
        let history: ChatHistory
        let colony: Colony
        init() throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-colony-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: Self.suite)!
            defaults.removePersistentDomain(forName: Self.suite)
            settings = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
            settings.creatureCount = 2
            settings.brain = .script
            history = ChatHistory(directory: dir.appendingPathComponent("chats"))
            colony = try Colony(settings: settings, history: history,
                                library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: dir.appendingPathComponent("spend")),
                                stage: Display(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1))
            // Nobody bumps by accident: a random meeting would start a second
            // conversation, or restart the quiet before a plane, mid-test.
            colony.meetings = Meetings(gap: -1e6)
        }
        func step(_ seconds: Double) {
            var left = seconds
            while left > 0 { colony.advance(dt: min(left, 0.05), cursor: CGPoint(x: -500, y: -500), shift: true); left -= 0.05 }
        }
        /// Called from a `defer` at the top of each test, like `SettingsTests.Sandbox`.
        func forget() {
            defaults.synchronize()
            defaults.removePersistentDomain(forName: Self.suite)
            defaults.synchronize()
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test func aScriptedConversationPlaysOutLineByLineAndIsLogged() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "Hey {listener}, {speaker} here.\nHello {listener}.\nStill here.\n"
        w.colony.talkNow(from: 0)
        #expect(w.colony.bubbles[0]?.text == "Hey \(w.colony.character(forCreature: 1).name), \(w.colony.character(forCreature: 0).name) here.")
        #expect(w.colony.bubbles[1] == nil, "the answer waits a moment")
        #expect(w.colony.busy == [0, 1])
        w.step(Banter.showTime("Hey x, y here.", base: w.settings.bubbleSeconds) * 0.6 + 0.1)
        #expect(w.colony.bubbles[1]?.text == "Hello \(w.colony.character(forCreature: 0).name).")
        w.step(Banter.showTime("Hello x.", base: w.settings.bubbleSeconds) * 0.6 + 0.1)
        #expect(w.colony.bubbles[0]?.text == "Still here.")
        w.step(2)
        #expect(w.colony.busy.isEmpty, "free again once the last line is out")
        let logged = w.history.exchanges(on: ChatLog.day(of: Date()))
        #expect(logged.count == 1 && logged.first?.lines.count == 3)
        #expect(logged.first?.provider == AppSettings.Brain.script.title && logged.first?.cost == nil)
    }

    @Test func aBrokenScriptSaysSoInTheStatusInsteadOfTalking() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "[loud]\nHello."
        w.colony.talkNow(from: 0)
        #expect(w.colony.bubbles.isEmpty)
        #expect(w.colony.talkStatus.contains("line 1"))
        #expect(w.colony.busy.isEmpty)
    }

    @Test func aFlowerMeetingPicksAFlowerLine() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "Plain.\nPlain back.\n\n[flower]\nA {flower} for you.\nThanks."
        w.colony.talkNow(from: 0)
        #expect(w.colony.bubbles[0]?.text == "Plain.")
        w.step(3)
        w.colony.releaseChat(); w.colony.busy.removeAll(); w.colony.bubbles.removeAll()
        #expect(w.colony.talk(from: 1, to: 0, because: "gift", flower: "tulip"))
        #expect(w.colony.bubbles[1]?.text == "A tulip for you.")
    }
}

/// Paper planes in the same offscreen colony: thrown, carried, caught, read.
/// In the same serialized suite, since they share its settings domain.
extension ColonyTalkTests {
    /// A world where nobody ever bumps, so nothing interrupts the post.
    func quietWorld() throws -> World {
        let w = try World()
        w.colony.meetings = Meetings(gap: -1e6)
        return w
    }

    /// Step until `done`, at most `seconds`; true when it happened.
    func run(_ w: World, upTo seconds: Double, until done: () -> Bool) -> Bool {
        var left = seconds
        while left > 0 { if done() { return true }; w.step(0.05); left -= 0.05 }
        return done()
    }

    @Test func aPlaneFliesToTheOtherOneWhoReadsItAndThinksAloud() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.sendPlane(), "\(w.colony.talkStatus)")
        let mail = try #require(w.colony.airmail)
        let (from, to) = (mail.plane.from, mail.plane.to)
        #expect(from != to)
        #expect(w.colony.planeSnapshot()?.opacity == 1)
        #expect(!w.colony.sendPlane(), "one at a time")

        #expect(run(w, upTo: 30) { w.colony.letters[to] == true }, "caught")
        let a = w.colony.character(forCreature: from).name, b = w.colony.character(forCreature: to).name
        let read = try #require(w.colony.bubbles[to]?.text)
        #expect(read.hasPrefix("*reads* \"") && read.hasSuffix("— \(a)"))
        #expect(w.colony.busy.contains(to) && w.colony.creatures[to].isChatting, "it stops to read")
        #expect(w.colony.planeSnapshot()?.opacity == 0, "the plane is now the letter")

        #expect(run(w, upTo: 40) { w.colony.bubbles[to].map { !$0.text.hasPrefix("*reads*") } ?? false }, "then thinks aloud")
        #expect(run(w, upTo: 40) { w.colony.airmail == nil })
        #expect(w.colony.letters.isEmpty && !w.colony.busy.contains(to))

        let logged = w.history.exchanges(on: ChatLog.day(of: Date()))
        #expect(logged.last?.situation == "\(a) sent \(b) a paper plane.")
        #expect(logged.last?.lines.map(\.speaker) == [a, b])
    }

    @Test func aPlaneGoesByItselfEveryIntervalWhateverTheBumps() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.planeMinutes = 0.5
        w.colony.post.stir(at: w.colony.elapsed)
        w.step(20)
        #expect(w.colony.airmail == nil)
        w.colony.bumped(Meetings.Bump(a: 0, b: 1, count: 1, gift: false))     // a meeting does not put it off
        w.colony.releaseChat(); w.colony.busy.removeAll()
        w.step(11)
        #expect(w.colony.airmail != nil || w.colony.isNight)
    }

    @Test func turnedOffNoPlaneEverGoes() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.planesEnabled = false
        w.settings.planeMinutes = 0.5
        w.step(45)
        #expect(w.colony.airmail == nil)
    }

    @Test func aPlaneToASleeperIsDroppedAndFades() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.sendPlane())
        let to = try #require(w.colony.airmail).plane.to
        w.colony.creatures[to].toggleNap(using: &w.colony.rng)
        #expect(run(w, upTo: 40) { w.colony.airmail == nil })
        #expect(w.colony.letters.isEmpty && w.colony.bubbles[to] == nil)
    }
}

extension ColonyTalkTests {
    @Test func whatTheModelWroteIsReadAndThenThought() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.sendPlane())
        let to = try #require(w.colony.airmail).plane.to
        w.colony.airmail?.note = "Note from the model."
        w.colony.airmail?.musing = "Thought from the model."
        #expect(run(w, upTo: 30) { w.colony.letters[to] == true })
        #expect(w.colony.bubbles[to]?.text.contains("Note from the model.") == true)
        #expect(run(w, upTo: 30) { w.colony.bubbles[to]?.text == "Thought from the model." })
    }
}

extension ColonyTalkTests {
    /// Every bubble the overlay is actually drawing, by its text.
    func drawnBubbles(_ w: World) -> [String] {
        func texts(_ layer: CALayer) -> [String] {
            let own = (layer as? CATextLayer).flatMap { ($0.string as? NSAttributedString)?.string }.map { [$0] } ?? []
            return own + (layer.sublayers ?? []).filter { !$0.isHidden }.flatMap(texts)
        }
        return texts(w.colony.overlays[0].root)
    }

    @Test func theThoughtReplacesTheReadingOnScreenNotJustInTheColony() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.sendPlane())
        let to = try #require(w.colony.airmail).plane.to
        w.colony.airmail?.note = "Note from the model."
        w.colony.airmail?.musing = "Thought from the model."
        #expect(run(w, upTo: 30) { w.colony.bubbles[to]?.text == "Thought from the model." })
        w.step(0.1)
        #expect(drawnBubbles(w).contains("Thought from the model."), "\(drawnBubbles(w))")
        #expect(!drawnBubbles(w).contains { $0.contains("Note from the model.") }, "\(drawnBubbles(w))")
    }
}

extension ColonyTalkTests {
    @Test func theOneAPlaneIsFlyingToKeepsOutOfConversations() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.sendPlane())
        let to = try #require(w.colony.airmail).plane.to
        #expect(w.colony.parties()[to].canTalk == false, "no bumping into talks on the way")
        w.colony.talkNow(from: to == 0 ? 1 : 0)
        #expect(w.colony.talkStatus.contains("nobody free") || !w.colony.busy.contains(to))
    }
}

extension ColonyTalkTests {
    @Test func theCatcherWritesBackOnceAndTheAnswerIsNotAnswered() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.sendPlane())
        let first = try #require(w.colony.airmail)
        let (a, b) = (first.plane.from, first.plane.to)
        #expect(!first.isReply)
        #expect(run(w, upTo: 60) { w.colony.airmail?.isReply == true }, "an answer goes up")
        let answer = try #require(w.colony.airmail)
        #expect(answer.plane.from == b && answer.plane.to == a, "back to the one who wrote")
        #expect(run(w, upTo: 60) { w.colony.letters[a] == true }, "the first writer catches it")
        #expect(w.colony.bubbles[a]?.text.hasSuffix("— \(w.colony.character(forCreature: b).name)") == true)
        #expect(run(w, upTo: 60) { w.colony.airmail == nil })
        w.step(3)
        #expect(w.colony.airmail == nil && w.colony.replyDue == nil, "nobody answers an answer")
        let logged = w.history.exchanges(on: ChatLog.day(of: Date()))
        #expect(logged.suffix(2).map(\.situation) == [
            "\(w.colony.character(forCreature: a).name) sent \(w.colony.character(forCreature: b).name) a paper plane.",
            "\(w.colony.character(forCreature: b).name) wrote back to \(w.colony.character(forCreature: a).name) by paper plane.",
        ])
    }

    @Test func aFlowerWearerNeverBumps() throws {
        let w = try World()
        defer { w.forget() }
        w.step(1)
        #expect(w.colony.parties()[1].canTalk)
        w.colony.gifts.give("poppy", from: 0, to: 1, at: w.colony.elapsed)
        w.colony.gifts.update(at: w.colony.elapsed + 1, wearFor: 600)
        #expect(w.colony.gifts.hat(of: 1) == "poppy")
        #expect(!w.colony.parties()[1].canTalk, "wearing a flower, it walks past everyone")
        #expect(w.colony.parties()[0].canTalk, "the giver still meets others")
    }
}
