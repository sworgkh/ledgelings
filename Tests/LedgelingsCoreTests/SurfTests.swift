import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// Surfing: the water, catching a wave, scoring, a wipe-out, and the end.
@Suite struct SurfTests {
    static let span: ClosedRange<CGFloat> = 25...1415

    func session(_ count: Int, waves: Int = 4, length: Double = 120, seed: UInt64 = 1) -> (Plays.Surf, SeededRNG) {
        var rng = SeededRNG(state: seed)
        let players = Array(0..<count)
        let halves = Dictionary(uniqueKeysWithValues: players.map { ($0, CGFloat(25)) })
        let at = Dictionary(uniqueKeysWithValues: players.map { ($0, CGFloat(200 + 150 * $0)) })
        let surf = Plays.Surf(players: players, halves: halves, at: at, floorY: 0, span: Self.span,
                              waveHeight: 125, depth: 55, waves: waves, length: length, using: &rng)
        return (surf, rng)
    }

    /// Played until over (or `limit` seconds), every event with its time.
    func play(_ surf: inout Plays.Surf, _ rng: inout SeededRNG, limit: Double = 600) -> [(Double, Plays.Surf.Event)] {
        var events: [(Double, Plays.Surf.Event)] = []
        var t = 0.0
        while !surf.isFinished, t < limit {
            t += 1.0 / 30
            events += surf.update(dt: 1.0 / 30, using: &rng).map { (t, $0) }
        }
        return events
    }

    @Test func theWaterComesInRisesUnderTheCrestAndGoesOut() {
        var (surf, rng) = session(1)
        #expect(surf.surface(at: 700) == 0, "dry before the tide comes in")
        var t = 0.0
        while surf.wave == nil, t < 20 { t += 1.0 / 30; _ = surf.update(dt: 1.0 / 30, using: &rng) }
        #expect(surf.tide == 1)
        while let w = surf.wave, abs(w.crest - 700) > 4 { _ = surf.update(dt: 1.0 / 30, using: &rng) }
        let crest = surf.wave!.crest
        #expect(abs(surf.surface(at: crest) - (55 + 125)) < 1, "the crest stands the wave's height over the calm water")
        #expect(surf.surface(at: crest + surf.way * surf.faceWidth * 1.01) == 55, "calm ahead of the face")
        #expect(surf.surface(at: crest - surf.way * surf.backWidth * 1.01) == 55, "calm behind its back")
        #expect(surf.slope(at: crest + surf.way * surf.faceWidth * 0.5) * Double(surf.way) < 0, "the face slopes down ahead of the crest")
        _ = play(&surf, &rng)
        #expect(surf.isFinished && surf.tide == 0)
        for r in surf.riders { #expect(r.y > 0 && r.y < 25 * 2 + 20, "set down on the floor") }
    }

    @Test func everyCountIsPlayedToTheEnd() {
        for count in [1, 2, 3, 5] {
            var (surf, rng) = session(count, waves: 3)
            let events = play(&surf, &rng).map(\.1)
            #expect(surf.isFinished, "\(count) surfers finish")
            #expect(events.first == .tideIn && events.last == .over)
            #expect(events.filter { if case .wave = $0 { true } else { false } }.count == 3)
            #expect(events.contains { if case .caught = $0 { true } else { false } }, "\(count): someone catches a wave")
            let won = events.compactMap { if case .won(let by) = $0 { by } else { nil } }
            #expect(won.count == 1)
            if count == 1 { #expect(won[0].isEmpty, "alone, nobody wins") } else {
                let best = surf.riders.map(\.score).max()!
                #expect(!won[0].isEmpty && won[0].allSatisfy { surf.scores[$0] == best })
            }
        }
    }

    @Test func itEndsAfterTheWavesOrWhenTimeIsUp() {
        var (byCount, rng) = session(2, waves: 2, length: 600)
        _ = play(&byCount, &rng)
        #expect(byCount.wavesRolled == 2)
        var (byTime, rng2) = session(2, waves: 20, length: 10)
        let events = play(&byTime, &rng2)
        #expect(byTime.isFinished && byTime.wavesRolled < 20, "time up stops new waves")
        let lastWave = events.last { if case .wave = $0.1 { true } else { false } }!.0
        #expect(lastWave <= Plays.Surf.tideTime + 10 + 0.1, "no wave starts once the time is up")
    }

    @Test func aRideScoresItsSecondsAndTricksAndOnlyKickingOutBanksIt() {
        for seed in UInt64(1)...12 {
            var (surf, rng) = session(3, waves: 4, seed: seed)
            let events = play(&surf, &rng).map(\.1)
            for r in surf.riders {
                let banked = events.compactMap { if case .kickOut(r.index, let p) = $0 { p } else { nil } }.reduce(0, +)
                #expect(r.score == banked, "the score is the rides kicked out of, nothing else")
            }
            let tricks = events.filter { if case .trick = $0 { true } else { false } }.count
            #expect(surf.riders.map(\.tricks).reduce(0, +) == tricks)
        }
        // A ride of about the wave's length scores ten a second, plus the tricks landed.
        var (surf, rng) = session(1, waves: 1)
        var rideStart: Double?, t = 0.0
        while !surf.isFinished {
            t += 1.0 / 30
            for e in surf.update(dt: 1.0 / 30, using: &rng) {
                if case .caught = e { rideStart = t }
                if case .kickOut(_, let p) = e, let s = rideStart {
                    let bonus = surf.riders[0].tricks == 0 ? 0 : p - Int((t - s) * 10)
                    #expect(abs(p - bonus - Int((t - s) * Plays.Surf.pointsPerSecond)) <= 1)
                }
            }
        }
    }

    @Test func aWipeOutSplashesLosesTheRideAndPaddlesBack() {
        var found = false
        for seed in UInt64(1)...60 where !found {
            var (surf, rng) = session(2, waves: 4, seed: seed)
            var t = 0.0, wiped: Int?, riding: [Int: Bool] = [:]
            while !surf.isFinished, t < 600 {
                t += 1.0 / 30
                for e in surf.update(dt: 1.0 / 30, using: &rng) {
                    switch e {
                    case .caught(let by): riding[by] = true
                    case .wipeout(let by, let at):
                        #expect(riding[by] == true, "only a rider wipes out")
                        #expect(abs(at.y - surf.surface(at: at.x)) < 1, "the splash is on the water")
                        #expect(surf.rider(by)?.onBoard == false)
                        riding[by] = false
                        wiped = by
                    case .kickOut(let by, _): #expect(riding[by] == true, "a wiped-out ride is never banked"); riding[by] = false
                    case .back(let by) where by == wiped:
                        #expect(surf.rider(by)?.onBoard == true, "back on its board")
                        found = true
                    default: break
                    }
                }
            }
        }
        #expect(found, "some seed wipes out and paddles back")
    }

    @Test func everyRiderStaysOnTheFloorItSurfs() {
        var (surf, rng) = session(5, waves: 3)
        while !surf.isFinished {
            _ = surf.update(dt: 1.0 / 30, using: &rng)
            for r in surf.riders { #expect(Self.span.contains(r.x)) }
        }
    }
}

/// Surfing in each character's voice, its boards, and what its lines cost.
@Suite struct SurfLinesTests {
    @Test func everyCharacterHasEverySurfLineInBothLanguages() {
        let names = BedsTests.shipped
        #expect(names.count == 39)
        for language in Language.allCases {
            let voices = Plays.surfVoiceSets(language)
            for name in names {
                guard let v = voices[name] else { Issue.record("\(name) has no surf lines in \(language)"); continue }
                for line in [v.start, v.wave, v.wipeout, v.trick, v.win, v.invite, v.yes, v.no] { #expect(!line.isEmpty, "\(name) \(language)") }
                #expect(v.invite.contains("{reader}") && v.yes.contains("{reader}") && v.no.contains("{reader}"), "\(name) \(language) speaks to the reader")
                #expect(Plays.startSets(language)[name]?["surf"] == v.start)
                for moment in [Plays.Moment.wave, .wipeout, .trick, .surfWin] {
                    #expect(Plays.cheerSets(language)[name]?[moment.rawValue]?.isEmpty == false, "\(name) \(moment) \(language)")
                }
            }
            #expect(Plays.startAnyone(language)["surf"] != nil && Plays.cheerAnyone(language)["wipeout"] != nil)
        }
        // Each in its own voice: no two characters share a line.
        let starts = BedsTests.shipped.compactMap { Plays.englishSurfVoices[$0]?.wipeout }
        #expect(Set(starts).count == starts.count)
        Language.$override.withValue(.english) {
            #expect(Plays.cheerLine(by: "Blocky", .wipeout).contains("Wet corners"), "Blocky grumbles about wet corners")
            #expect(Plays.cheerLine(by: "Unit 7", .trick).contains("%"), "Unit 7 in numbers")
            #expect(Plays.cheerLine(by: "Zed", .wave).contains("lying down"), "Zed sleepy")
            #expect(Plays.cheerLine(by: "Nobody Made", .surfWin) == Plays.englishSurfAnyone.win)
        }
        #expect(Plays.Moment.surfWin.asksTheModel && !Plays.Moment.wipeout.asksTheModel && !Plays.Moment.wave.asksTheModel)
    }

    @Test func anInvitationToSurfIsInTheSurfersOwnWords() {
        Language.$override.withValue(.english) {
            #expect(Deeds.inviteLine(by: "Blocky", to: "Pip", .game(.surf)) == "Pip. Water on the bottom edge. Surfing. Unless you're scared of wet corners.")
            #expect(Deeds.answerLine(by: "Pip", to: "Blocky", .game(.surf), yes: true) == "Surfing? Yes yes yes! Wheee, Blocky!")
            #expect(Deeds.answerLine(by: "Someone New", to: "Pip", .game(.surf), yes: false) == "Not today, Pip. I'll stay dry.")
            #expect(Deeds.inviteLine(by: "Blocky", to: "Pip", .game(.soccer)).contains("Soccer"), "other games keep their lines")
        }
        #expect(Deeds.invitable.contains(.surf))
        #expect(Deeds.parse("invite surfing") == .some(.invite(.game(.surf))) && Deeds.parse("invite серфинг") == .some(.invite(.game(.surf))))
    }

    @Test func everyCharacterPaddlesOutOnABoardOfItsOwn() {
        let boards = BedsTests.shipped.map { Plays.Surf.board(of: $0) }
        #expect(Set(boards).count == boards.count, "no two share a board")
        #expect(boards.allSatisfy { (0..<Plays.Surf.boardCount).contains($0) })
        #expect(Plays.Surf.board(of: "Someone New") == Plays.Surf.board(of: "Someone New"), "a made character keeps its board")
        #expect((0..<Plays.Surf.boardCount).contains(Plays.Surf.board(of: "Someone New")))
    }

    @Test func whatSurfingSaysIsCountedUnderItsOwnPurpose() {
        #expect(Plays.Kind.surf.spendPurpose == .surfing && Plays.Kind.soccer.spendPurpose == .ballGames && Plays.Kind.tag.spendPurpose == .plays)
        let usage = Spend.Usage(promptTokens: 150, completionTokens: 15, cost: 0.0004)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .surfing)]
        let s = Spend.summarise(records, now: Date())
        Language.$override.withValue(.english) {
            #expect(s.byPurpose.first { $0.purpose == "Surfing" }?.total.cost == 0.0004)
        }
    }
}
