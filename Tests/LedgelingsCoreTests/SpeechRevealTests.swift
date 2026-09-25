import Testing
@testable import LedgelingsCore

@Suite struct SpeechRevealTests {
    let line = "Nice edge you've got there."

    @Test func whileTheSoundIsOnItsWayTheBubbleCountsDots() {
        let waiting = SpeechReveal.waiting(since: 10)
        #expect(waiting.shown(line, at: 10).text == "...")
        #expect(waiting.shown(line, at: 10).share == 1.0 / 3)
        #expect(waiting.shown(line, at: 10.4).share == 2.0 / 3)
        #expect(waiting.shown(line, at: 10.7).share == 1)
        #expect(waiting.shown(line, at: 11.05).share == 1.0 / 3, "and round again")
    }

    @Test func aClipTypesTheLineEvenlyOverItsLength() {
        let timed = SpeechReveal.timed(start: 5, duration: 2)
        #expect(timed.shown(line, at: 4).share == 0)
        #expect(timed.shown(line, at: 6).share == 0.5)
        #expect(timed.shown(line, at: 9) == (line, 1))
        #expect(SpeechReveal.timed(start: 5, duration: 0).shown(line, at: 5).share == 1)
    }

    @Test func aReportingVoiceShowsWhatItHasSaid() {
        #expect(SpeechReveal.spoken(0.25).shown(line, at: 0) == (line, 0.25))
        #expect(SpeechReveal.spoken(3).shown(line, at: 0).share == 1)
        #expect(SpeechReveal.all.shown(line, at: 0) == (line, 1))
    }

    @Test func lettersAppearWholeAndTheLastOnlyAtTheEnd() {
        #expect(SpeechReveal.visible(0, of: 10) == 0)
        #expect(SpeechReveal.visible(0.55, of: 10) == 5)
        #expect(SpeechReveal.visible(0.999, of: 10) == 9)
        #expect(SpeechReveal.visible(1, of: 10) == 10)
    }
}
