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

    @Test func starsAndUnderscoresBecomeItalicAndDoubleStarsBold() {
        typealias R = Banter.StyledRun
        #expect(Banter.styled("Ah, the bottom edge... *sighs* ...where pride settles.") == [
            R("Ah, the bottom edge... "), R("sighs", italic: true), R(" ...where pride settles."),
        ])
        #expect(Banter.styled("You almost knocked me off the *good* edge!") == [
            R("You almost knocked me off the "), R("good", italic: true), R(" edge!"),
        ])
        #expect(Banter.styled("This is **important**, _really_ important.") == [
            R("This is "), R("important", bold: true), R(", "), R("really", italic: true), R(" important."),
        ])
        #expect(Banter.styled("***loud***") == [R("loud", bold: true, italic: true)])
    }

    @Test func loneOrOddMarksStayAsTheyAre() {
        typealias R = Banter.StyledRun
        #expect(Banter.styled("2 * 3 = 6") == [R("2 * 3 = 6")])
        #expect(Banter.styled("*sigh without an end") == [R("*sigh without an end")])
        #expect(Banter.styled("snake_case_name here") == [R("snake_case_name here")])
        #expect(Banter.styled("a ** b") == [R("a ** b")])
        #expect(Banter.styled("") == [])
    }

    @Test func styledTextCollapsesTheDoubleSpacesModelsLeaveAfterAMark() {
        typealias R = Banter.StyledRun
        #expect(Banter.styled("*Sigh.*  The abyss, eh?") == [R("Sigh.", italic: true), R(" The abyss, eh?")])
        #expect(Banter.plain("*Sigh.*  The **abyss**, eh?") == "Sigh. The abyss, eh?")
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
