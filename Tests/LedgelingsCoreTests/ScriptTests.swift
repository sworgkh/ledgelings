import Testing
@testable import LedgelingsCore

/// The built-in lines: a text file of conversations that needs no model.
@Suite struct ScriptTests {
    let sample = """
    # A comment, and a blank line between conversations.

    Nice edge you've got there, {listener}.
    It was nicer before you turned up.

    [flower]
    Here. I found a {flower} under the cursor.
    Is it... ticking?
    No. Probably.

    [night, flower]
    A {flower}, at this hour?
    Flowers don't sleep either.

    [night]
    Can't sleep.
    """

    @Test func parsesBlocksTagsAndComments() throws {
        let script = try Script.parse(sample)
        #expect(script.conversations.count == 4)
        #expect(script.conversations[0].tags.isEmpty)
        #expect(script.conversations[0].lines == ["Nice edge you've got there, {listener}.", "It was nicer before you turned up."])
        #expect(script.conversations[1].tags == ["flower"] && script.conversations[1].lines.count == 3)
        #expect(script.conversations[2].tags == ["night", "flower"])
        #expect(script.conversations[3].tags == ["night"] && script.conversations[3].lines == ["Can't sleep."])
    }

    @Test func refusesWhatItCannotUseAndSaysWhere() {
        func problem(_ text: String) -> Script.ParseError? {
            do { _ = try Script.parse(text); return nil } catch { return error }
        }
        #expect(problem("")?.message == "no conversations")
        #expect(problem("# only a comment\n\n")?.message == "no conversations")
        let unknown = problem("Hello.\nHi.\n\n[loud]\nWhat?")
        #expect(unknown?.line == 4 && unknown?.message.contains("loud") == true)
        let bare = problem("[night]\n\nHello.\nHi.")
        #expect(bare?.line == 1 && bare?.message.contains("needs at least one line") == true)
        let late = problem("Hello.\n[night]\nHi.")
        #expect(late?.line == 2 && late?.message.contains("first line") == true)
    }

    @Test func theTextFormComesBackTheSame() throws {
        let script = try Script.parse(sample)
        let again = try Script.parse(script.text())
        #expect(again == script)
    }

    @Test func picksTheMostSpecificConversationForTheMoment() throws {
        let script = try Script.parse(sample)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            #expect(script.pick(for: ["day"], avoiding: [], using: &rng) == 0, "by day, without a flower, only the untagged one fits")
            #expect(script.pick(for: ["day", "flower"], avoiding: [], using: &rng) == 1)
            #expect(script.pick(for: ["night", "flower"], avoiding: [], using: &rng) == 2)
            #expect(script.pick(for: ["night"], avoiding: [], using: &rng) == 3)
        }
        #expect(Script(conversations: []).pick(for: ["day"], avoiding: [], using: &rng) == nil)
    }

    @Test func avoidsRecentOnesUntilThereIsNothingElse() throws {
        let script = try Script.parse("One.\n\nTwo.\n\nThree.")
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            #expect(script.pick(for: ["day"], avoiding: [0, 1], using: &rng) == 2)
        }
        let picks = Set((0..<40).compactMap { _ in script.pick(for: ["day"], avoiding: [0, 1, 2], using: &rng) })
        #expect(picks == [0, 1, 2], "everyone recent: anyone will do")
    }

    @Test func fillsInWhoIsTalkingAndWhatWasGiven() {
        #expect(Script.fill("Hey {listener}, {speaker} here. Take this {flower}.", speaker: "Pip", listener: "Zed", flower: "tulip")
                == "Hey Zed, Pip here. Take this tulip.")
        #expect(Script.fill("A {flower} for you.", speaker: "Pip", listener: "Zed", flower: nil) == "A flower for you.")
    }

    @Test func theBuiltInScriptIsBigCleanAndCoversTheMoments() throws {
        let script = try Script.parse(Script.builtInText)
        #expect(script.conversations.count >= 60)
        #expect(script.conversations.filter { $0.tags == ["flower"] }.count >= 10)
        #expect(script.conversations.filter { $0.tags == ["night"] }.count >= 6)
        #expect(script.conversations.filter { $0.tags.isEmpty }.count >= 40)
        for c in script.conversations {
            #expect(c.lines.count >= 2 && c.lines.count <= 4, Comment(rawValue: c.lines.joined(separator: " / ")))
            for line in c.lines {
                #expect(line.count <= 120, Comment(rawValue: line))
                let filled = Script.fill(line, speaker: "x", listener: "y", flower: "z")
                #expect(!filled.contains("{"), Comment(rawValue: line))
            }
        }
    }

    @Test func theAgentPromptTeachesTheFormatAndNamesTheCast() {
        let prompt = Script.agentPrompt(cast: [Character(name: "Blocky", persona: "Grumpy."), Character(name: "Pip", persona: "Cheerful.")], count: 30)
        #expect(prompt.contains("30"))
        #expect(prompt.contains("Blocky") && prompt.contains("Grumpy.") && prompt.contains("Pip"))
        #expect(prompt.contains("{speaker}") && prompt.contains("{listener}") && prompt.contains("{flower}"))
        #expect(prompt.contains("[flower]") && prompt.contains("[night]"))
        #expect(prompt.contains("blank line"))
    }
}
