import Testing
@testable import LedgelingsCore

@Suite struct BanterTests {
    @Test func rendersPlaceholdersAndLeavesUnknownOnesAlone() {
        let out = Banter.render("Hi {listener}, I am {speaker}. {nope}", ["speaker": "Blocky", "listener": "Pip"])
        #expect(out == "Hi Pip, I am Blocky. {nope}")
    }

    @Test func defaultPromptsUseOnlyKnownPlaceholders() {
        for template in [Banter.defaultSystemPrompt, Banter.defaultLinePrompt, Banter.defaultReplyPrompt] {
            let filled = Banter.render(template, Dictionary(uniqueKeysWithValues: Banter.placeholders.map { ($0, "x") }))
            #expect(!filled.contains("{"), Comment(rawValue: template))
        }
    }

    @Test func cleansWhatASmallModelTendsToSend() {
        #expect(Banter.cleanLine("\"Pip, you're a beige disappointment.\"", speaker: "Blocky") == "Pip, you're a beige disappointment.")
        #expect(Banter.cleanLine("Blocky: Get off my edge.\nSecond line", speaker: "Blocky") == "Get off my edge.")
        #expect(Banter.cleanLine("<think>hmm\nhmm</think>\n\n*Fine.*", speaker: "Blocky") == "Fine.")
        #expect(Banter.cleanLine("   \n  ", speaker: "Blocky") == "")
    }

    @Test func capsRunawayLines() {
        let long = String(repeating: "ha ", count: 100)
        let out = Banter.cleanLine(long, speaker: "Pip", maxLength: 30)
        #expect(out.count <= 31 && out.hasSuffix("…"))
    }
}

@Suite struct BubbleTimeTests {
    @Test func aTypicalLineStaysAboutTheBaseTime() {
        let eight = "one two three four five six seven eight"
        #expect(abs(Banter.showTime(eight, base: 14) - 14.2) < 0.01)
    }

    @Test func longerLinesStayLongerButNeverPastTwiceTheBase() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        #expect(Banter.showTime(long, base: 14) == 28)
        #expect(Banter.showTime("hi", base: 14) < Banter.showTime("hi there friend", base: 14))
    }

    @Test func theDefaultBaseIsFourteenSeconds() {
        #expect(Banter.defaultBubbleSeconds == 14)
    }
}
