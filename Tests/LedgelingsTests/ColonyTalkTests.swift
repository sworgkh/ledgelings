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

    @Test func theSituationCarriesTheUsersClockDateAndHolidays() throws {
        let w = try World()
        defer { w.forget() }
        // 26 September 2026, 22:40 on this Mac's clock: the first evening of Sukkot.
        let sukkot = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 22, minute: 40))!
        w.colony.now = { sukkot }
        w.settings.script = "Hi.\nHo.\n"
        w.colony.talkNow(from: 0)
        let said = try #require(w.history.exchanges(on: ChatLog.day(of: Date())).last)
        #expect(said.situation.hasPrefix("For the person at this computer it is Saturday, 26 September 2026, late evening (22:40). Today is day 1 of Sukkot, a Jewish holiday."))
        #expect(said.situation.contains("On the edge it is "))
        #expect((0..<40).contains { _ in w.colony.holidayForLines() == "Sukkot" }, "a holiday line now and then")

        w.settings.knowsTimeOfDay = false
        w.settings.knowsDate = false
        w.settings.jewishHolidays = false
        #expect(w.colony.almanac.isEmpty)
        #expect(!(0..<40).contains { _ in w.colony.holidayForLines() != nil })
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

    @Test func aPairStaysFaceToFaceUntilTheLastBubbleIsGone() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "Hi there.\nHello back to you, friend.\n"
        w.colony.talkNow(from: 0)
        #expect(w.colony.creatures[0].isChatting && w.colony.creatures[1].isChatting)
        w.step(Banter.showTime("Hi there.", base: w.settings.bubbleSeconds) * 0.6 + 0.1)
        #expect(w.colony.bubbles[1] != nil, "the answer is up")
        w.step(2)
        #expect(w.colony.busy.isEmpty, "the last line is out")
        #expect(w.colony.bubbles[1] != nil, "but still on screen")
        #expect(w.colony.creatures[0].isChatting && w.colony.creatures[1].isChatting, "so nobody walks off mid-sentence")
        w.step(Banter.showTime("Hello back to you, friend.", base: w.settings.bubbleSeconds))
        #expect(w.colony.bubbles.isEmpty)
        #expect(!w.colony.creatures[0].isChatting && !w.colony.creatures[1].isChatting, "then both walk on")
        #expect(w.colony.chats.isEmpty)
    }

    @Test func aSlowConversationOutlastsTheChatsSafetyLimit() throws {
        let w = try World()
        defer { w.forget() }
        w.colony.hold(0, and: 1)
        w.colony.busy.formUnion([0, 1])            // a model thinking, a voice speaking: longer than 30 s
        w.step(40)
        #expect(w.colony.creatures[0].isChatting && w.colony.creatures[1].isChatting)
        w.colony.busy.subtract([0, 1])
        w.colony.endChat(0, 1, after: 1.2)
        w.step(1.5)
        #expect(!w.colony.creatures[0].isChatting && !w.colony.creatures[1].isChatting)
    }

    @Test func aPairThatNeverSaysItIsDoneStillWalksOnOnceQuiet() throws {
        let w = try World()
        defer { w.forget() }
        w.colony.hold(0, and: 1)
        w.colony.busy.formUnion([0, 1])
        w.step(40)
        w.colony.busy.subtract([0, 1])             // nobody calls endChat
        w.step(Colony.chatGrace + 0.5)
        #expect(!w.colony.creatures[0].isChatting && !w.colony.creatures[1].isChatting)
        #expect(w.colony.chats.isEmpty)
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

    @Test func outLoudTheNextLineWaitsForTheOneBeforeToBeSaid() throws {
        let world = try World()
        defer { world.forget() }
        let c = world.colony
        c.voicedLines.insert(41)
        var next = 0
        c.whenSaid(41) { next += 1 }
        c.heard(.started(duration: 1.5), bubble: 41, of: 0)
        c.heard(.progress(0.5), bubble: 41, of: 0)
        #expect(next == 0, "still being said")
        c.heard(.done, bubble: 41, of: 0)
        #expect(next == 1)
        c.heard(.done, bubble: 41, of: 0)
        #expect(next == 1, "once only")
        c.whenSaid(99) { next += 1 }
        #expect(next == 2, "a line not being voiced does not hold anyone up")
    }

    @Test func aVoicedLineThatNeverHearsBackStillEndsItsTurn() throws {
        let world = try World()
        defer { world.forget() }
        let c = world.colony
        c.bubbles[0] = Colony.Bubble(text: "Hello?", until: c.elapsed + 1, reveal: .waiting(since: c.elapsed), serial: 7)
        c.voicedLines.insert(7)
        var next = false
        c.whenSaid(7) { next = true }
        world.step(2)
        #expect(next && c.bubbles[0] == nil)
    }

    @Test func aDroppedLineAlsoLetsTheNextOneGo() throws {
        let world = try World()
        defer { world.forget() }
        let c = world.colony
        c.voicedLines.insert(3)
        var next = false
        c.whenSaid(3) { next = true }
        c.heard(.dropped, bubble: 3, of: 1)       // its bubble is long gone: still counts
        #expect(next)
    }

    @Test func outLoudOnlyOneConversationTalksAtATime() throws {
        let world = try World()
        defer { world.forget() }
        let c = world.colony
        // No voice attached: nothing is out loud, so a second pair may talk.
        c.voicedDialogues = 1
        #expect(!c.voiceIsTaken)
        c.voice = Voice(settings: world.settings, spend: SpendLedger(directory: world.dir.appendingPathComponent("s")),
                        archive: world.dir.appendingPathComponent("voices"))
        world.settings.voiceEnabled = true
        #expect(c.voiceIsTaken)
        #expect(!c.talk(from: 0, to: 1), "the second pair only bumps")
        c.voicedDialogues = 0
        world.settings.voiceEnabled = false
        #expect(!c.voiceIsTaken)
    }

    @Test func aPairsBondAndStoryReachTheirPromptsOnlyWhileStoriesAreOn() throws {
        let w = try World()
        defer { w.forget() }
        let a = w.colony.character(forCreature: 0).name, b = w.colony.character(forCreature: 1).name
        #expect(w.colony.relationship(of: 0, with: 1) == "", "strangers")
        w.step(Colony.bondSaveEvery + 0.5)
        #expect((w.colony.bonds.bond(a, b)?.together ?? 0) >= Colony.bondSaveEvery, "time on screen together is counted")
        w.colony.bonds.change { $0.begin(a, b, Bonds.Written(bond: "Rivals.", plot: "A feud."), length: 3, at: Date()) }
        #expect(w.colony.relationship(of: 0, with: 1).contains("You and \(b) have shared"))
        #expect(w.colony.relationship(of: 1, with: 0).contains("(part 1 of 3): A feud."))
        #expect(w.colony.plotLabel(0, 1) == "part 1 of 3: A feud.")
        w.settings.plotsEnabled = false
        #expect(w.colony.relationship(of: 0, with: 1) == "" && w.colony.plotLabel(0, 1) == nil)
    }

    @Test func theBuiltInLinesNeverAskForAStory() throws {
        let w = try World()
        defer { w.forget() }
        let a = w.colony.character(forCreature: 0).name, b = w.colony.character(forCreature: 1).name
        w.colony.bonds.change { $0.liveTogether(1e6, names: [a, b]) }
        w.colony.talked(a, b, lines: [ChatLog.Line(speaker: a, text: "Hi.")])
        #expect(w.colony.plotting.isEmpty, "no model, no call")
        #expect(w.colony.bonds.bond(a, b)?.talks == 1)
    }

    // MARK: Reminders

    @Test func aDueReminderIsThrownOpensAsALetterAndIsMarkedSent() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.talkEnabled = true
        w.settings.reminderLetterSeconds = 10
        w.colony.userIdleSeconds = { 0 }
        let due = Date().addingTimeInterval(-5)
        w.colony.reminders.add("Call mom", at: due, repeats: .once)
        w.step(1.2)
        let mail = try #require(w.colony.delivery)
        #expect(mail.reminder.text == "Call mom")
        #expect(w.colony.reminders.book.reminders[0].isFinished, "marked sent as soon as it is taken, so it is never sent twice")
        #expect(run(w, upTo: 15) { if case .open = w.colony.delivery?.phase { true } else { false } })
        let open = try #require(w.colony.delivery)
        let writer = try #require(open.thrower.map { w.colony.character(forCreature: $0).name })
        #expect(open.writer == writer)
        #expect(open.note?.lowercased().contains("call mom") == true, "the note names the reminder")
        let letter = try #require(w.colony.reminderSnapshot()?.letter)
        #expect(letter.text == "Call mom" && letter.signature == "— \(writer)")
        let logged = try #require(w.history.exchanges(on: ChatLog.day(of: Date())).last)
        #expect(logged.situation.contains("\"Call mom\"") && logged.lines.map(\.speaker) == [writer])

        // A click folds it away; it flies off and is gone.
        w.colony.closeLetter()
        let gone = run(w, upTo: 8) { w.colony.delivery == nil }
        #expect(gone, "still \(String(describing: w.colony.delivery?.phase)) at \(String(describing: w.colony.delivery?.plane.position)) trail \(w.colony.delivery?.plane.trail.count ?? -1)")
    }

    @Test func theLetterWaitsWhileNobodyIsAtTheComputerThenFoldsItselfAway() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.reminderLetterSeconds = 10
        var idle = 600.0
        w.colony.userIdleSeconds = { idle }
        w.colony.deliverNow(Reminders.Reminder(text: "Stretch", time: Date()))
        #expect(run(w, upTo: 15) { if case .open = w.colony.delivery?.phase { true } else { false } })
        w.step(30)
        guard case .open = w.colony.delivery?.phase else { Issue.record("closed while nobody was there"); return }
        idle = 0
        w.step(10.5)
        #expect(run(w, upTo: 8) { w.colony.delivery == nil })
    }

    @Test func remindersOffDeliverNothingUntilTurnedBackOn() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.remindersEnabled = false
        w.colony.reminders.add("Water", at: Date().addingTimeInterval(-60), repeats: .once)
        w.step(3)
        #expect(w.colony.delivery == nil && !w.colony.reminders.book.reminders[0].isFinished)
        w.settings.remindersEnabled = true
        w.step(1.2)
        #expect(w.colony.delivery?.reminder.text == "Water", "late, but delivered")
    }
}
