import Foundation
import Testing
@testable import LedgelingsCore

/// Deeds: the tag taken off a line, read leniently, checked against what was
/// offered and against the owner's limits, and the built-in lines.
@Suite struct DeedsTests {

    @Test func theTagComesOffTheLineWhereverItIs() {
        let own = Deeds.split("Soccer? Bottom edge, now.\nDO: invite soccer")
        #expect(own.text == "Soccer? Bottom edge, now." && own.deed == .invite(.game(.soccer)))
        let inline = Deeds.split("Fine. Soccer. DO: accept")
        #expect(inline.text == "Fine. Soccer." && inline.deed == .accept)
        let bracketed = Deeds.split("Tea? [DO: invite tea]")
        #expect(bracketed.text == "Tea?" && bracketed.deed == .invite(.tea))
        let starred = Deeds.split("**DO:** decline\nNo.")
        #expect(starred.deed == .decline)
        let noted = Deeds.split("You owe me a sunflower.\nNOTE: Boo owes Blocky a sunflower\nDO: none")
        #expect(noted.text == "You owe me a sunflower." && noted.note == "Boo owes Blocky a sunflower" && noted.deed == nil && noted.unknown == nil)
        let plain = Deeds.split("Just a line, nothing to do.")
        #expect(plain == Deeds.Tagged(text: "Just a line, nothing to do."))
        // An ordinary word that happens to end in "do" is not a tag.
        #expect(Deeds.split("Who do: you think you are?").deed == nil)
    }

    @Test func aThinkingModelsTagIsReadAfterItsThinking() {
        let t = Deeds.split("<think>maybe DO: flower?</think>Here, a daisy. DO: flower")
        #expect(t.deed == .flower && t.text.hasSuffix("Here, a daisy."))
    }

    @Test func theDeedIsReadLeniently() {
        #expect(Deeds.parse("play tag") == .some(.invite(.game(.tag))))
        #expect(Deeds.parse("invite to a game of baseball") == .some(.invite(.game(.baseball))))
        #expect(Deeds.parse("Soccer") == .some(.invite(.game(.soccer))))
        #expect(Deeds.parse("футбол") == .some(.invite(.game(.soccer))))
        #expect(Deeds.parse("yes") == .some(.accept) && Deeds.parse("нет") == .some(.decline))
        #expect(Deeds.parse("visit Unit 7") == .some(.visit("Unit 7")))
        #expect(Deeds.parse("go to sleep") == .some(.sleep) && Deeds.parse("go") == nil, "go needs somewhere")
        #expect(Deeds.parse("sleep") == .some(.sleep) && Deeds.parse("nap") == .some(.sleep))
        #expect(Deeds.parse("none") == .some(nil) && Deeds.parse("") == .some(nil))
        #expect(Deeds.parse("dance") == nil, "not a deed")
        #expect(Deeds.parse("invite rope") == nil, "the rope is played alone")
        let unknown = Deeds.split("Let's dance! DO: dance")
        #expect(unknown.deed == nil && unknown.unknown == "dance" && unknown.text == "Let's dance!")
    }

    @Test func onlyWhatWasOfferedIsDone() {
        var o = Deeds.Options()
        o.games = [.soccer]
        o.flower = true
        o.visit = ["Boo"]
        #expect(Deeds.check(.invite(.game(.soccer)), o) == nil)
        #expect(Deeds.check(.invite(.game(.basketball)), o) == .notOffered)
        #expect(Deeds.check(.invite(.tea), o) == .notOffered)
        #expect(Deeds.check(.visit("boo"), o) == nil && Deeds.check(.visit("Zed"), o) == .notOffered)
        #expect(Deeds.check(.accept, o) == .nothingToAnswer)
        o.answering = Deeds.Invitation(from: "Zed", to: "Pip", offer: .tea, at: 0, byLetter: false)
        #expect(Deeds.check(.decline, o) == nil)
        #expect(o.tags == ["invite soccer", "flower", "visit Boo"])
    }

    @Test func thePromptOffersOnlyWhatIsPossible() {
        var o = Deeds.Options()
        #expect(Deeds.prompt(o).isEmpty)
        o.games = [.tag, .soccer]; o.tea = true
        let menu = Deeds.prompt(o)
        #expect(menu.contains("invite tag | invite soccer | invite tea | none"))
        o.answering = Deeds.Invitation(from: "Boo", to: "Blocky", offer: .game(.soccer), at: 0, byLetter: true)
        let answer = Deeds.prompt(o, notes: true, listener: "Boo")
        #expect(answer.hasPrefix("Boo has invited you to a game of soccer.") && answer.contains("DO: accept or DO: decline"))
        #expect(answer.contains("NOTE:") && answer.contains("about Boo"))
        let russian = Language.$override.withValue(.russian) { Deeds.prompt(o) }
        #expect(russian.contains("DO: accept") && russian.contains("зовёт тебя"), "tags stay in Latin letters")
    }

    @Test func theLimitsHoldAndTheLoopGuardStaysWhenTheyAreOff() {
        var ledger = Deeds.Ledger()
        let limits = Deeds.Limits(gap: 240, perHour: 2, pairGap: 1200)
        #expect(ledger.refusal("flower", "A", "B", at: 0, limits) == nil)
        ledger.record("flower", "A", "B", at: 0)
        #expect(ledger.refusal("flower", "B", "A", at: 10, limits) == .loopGuard)
        #expect(ledger.refusal("tea", "C", "D", at: 100, limits) == .tooSoon)
        #expect(ledger.refusal("flower", "A", "B", at: 300, limits) == .pairTooSoon)
        #expect(ledger.refusal("tea", "A", "B", at: 300, limits) == nil)
        ledger.record("tea", "C", "D", at: 300)
        #expect(ledger.refusal("letter", "E", "F", at: 3000, limits) == .tooMany)
        #expect(ledger.refusal("letter", "E", "F", at: 3700, limits) == nil, "an hour later")
        #expect(ledger.refusal("accept", "C", "D", at: 301, limits) == nil, "an answer is never held back")
        let off = Deeds.Limits(gap: 0, perHour: 0, pairGap: 0)
        #expect(ledger.refusal("tea", "C", "D", at: 310, off) == .loopGuard)
        #expect(ledger.refusal("tea", "C", "D", at: 300 + Deeds.loopGuard, off) == nil)
    }

    @Test func builtInLinesInviteAndAnswerInEachVoice() {
        #expect(Deeds.inviteLine(by: "Unit 7", to: "Blocky", .game(.soccer)) == "Blocky. Proposal: Soccer. My odds of winning: 61%. Accept?")
        #expect(Deeds.answerLine(by: "Blocky", to: "Unit 7", .game(.soccer), yes: true) == "Fine. Soccer. But on a respectable edge, Unit 7.")
        #expect(Deeds.inviteLine(by: "Someone New", to: "Pip", .tea) == "Pip! Tea together? You and me, right now.")
        let russian = Language.$override.withValue(.russian) { Deeds.answerLine(by: "Zed", to: "Pip", .game(.tag), yes: false) }
        #expect(russian.hasPrefix("...нет..."))
        // Every built-in character has its lines in both languages, with the one spoken to in each.
        #expect(Set(Deeds.englishVoices.keys) == Set(Letters.englishVoices.keys))
        #expect(Set(Deeds.russianVoices.keys) == Set(Deeds.englishVoices.keys))
        for v in Array(Deeds.englishVoices.values) + Array(Deeds.russianVoices.values) {
            #expect(v.invite.contains("{game}") && v.invite.contains("{reader}") && v.yes.contains("{reader}") && v.no.contains("{reader}"), "\(v.invite)")
        }
    }

    @Test func builtInAnswersFollowTheChanceAndTheFriendship() {
        var rng = SeededRNG(state: 7)
        let strangers = (0..<2000).filter { _ in Deeds.builtInYes(closeness: 0, chance: 60, using: &rng) }.count
        let friends = (0..<2000).filter { _ in Deeds.builtInYes(closeness: 1, chance: 60, using: &rng) }.count
        #expect((800...1000).contains(strangers) && (1400...1600).contains(friends))
        #expect(!(0..<200).contains { _ in Deeds.builtInYes(closeness: 1, chance: 0, using: &rng) })
        var o = Deeds.Options(); o.games = [.soccer, .tag]
        #expect(Deeds.builtInOffer(o, rematch: .tag, using: &rng) == .game(.tag), "a rematch first")
        #expect(Deeds.builtInOffer(Deeds.Options(), using: &rng) == nil)
    }
}
