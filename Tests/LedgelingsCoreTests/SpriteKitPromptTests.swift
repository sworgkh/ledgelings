import Foundation
import Testing
@testable import LedgelingsCore

/// The sprite kit's prompts: one for an image model, built from the form, and
/// one for Refine with AI, whose answer fills the form back in.
@Suite struct SpriteKitPromptTests {
    static let form = SpriteKit.Form(kind: "a boxy moss sprite with a leaf on top", name: "Moss", colour: "#55AA33",
                                     cast: [Character(name: "Fern", persona: "tiny, fast, anxious")])

    @Test func theImagePromptAsksForAPictureAndShowsNoLetters() {
        for language in Language.allCases {
            let prompt = SpriteKit.imagePrompt(Self.form, language: language)
            #expect(prompt.contains("a boxy moss sprite with a leaf on top") && prompt.contains("#55aa33") && prompt.contains("moss"))
            for name in SpriteKit.attachmentNames { #expect(prompt.contains(name), "\(language): says which picture is \(name)") }
            for pose in SpriteText.poses { #expect(prompt.contains(pose)) }
            // Nothing a model could copy as text art: no grid of letters, no letter key, no example rows.
            #expect(!prompt.contains("oooo") && !prompt.contains("...") && !prompt.contains(". o b l s k x"))
            #expect(!prompt.contains("pose:") && !prompt.contains("character:"))
            #expect(!prompt.contains("{"), "\(language): every placeholder is filled")
        }
    }

    @Test func anEmptyFormLeavesTheChoiceToTheModel() {
        let prompt = SpriteKit.imagePrompt(SpriteKit.Form(), language: .english)
        #expect(prompt.contains(Language.$override.withValue(.english) { SpriteText.describePlaceholder }))
        #expect(prompt.contains("Choose a body colour") && !prompt.contains("Its name"))
    }

    @Test func aFormHasThreeCharactersAndASafeName() {
        #expect(SpriteKit.Form().cast.count == 3)
        #expect(SpriteKit.Form(cast: Array(repeating: Character(name: "a", persona: ""), count: 5)).cast.count == 3)
        #expect(SpriteKit.speciesName("Moss Ball!") == "moss-ball")
        #expect(SpriteKit.speciesName("  Ёж ") == nil)
        #expect(SpriteKit.speciesName("ChatGPT Image 3 Oct") == "chatgpt-image-3-oct")
        let saved = try! JSONDecoder().decode(SpriteKit.Form.self, from: JSONEncoder().encode(Self.form))
        #expect(saved == Self.form)
    }

    @Test func theRefinePromptCarriesTheIdeaAndTheRules() {
        let prompt = SpriteKit.refinePrompt(Self.form, language: .english)
        #expect(prompt.contains("a boxy moss sprite") && prompt.contains("Fern (tiny, fast, anxious)") && prompt.contains("#55aa33"))
        for word in ["square body", "outline", "square eyes", "no curves", "SOUNDS", "old or young", "he or she"] {
            #expect(prompt.contains(word), "\(word)")
        }
        #expect(SpriteKit.refinePrompt(SpriteKit.Form(), language: .english).contains("name: none"))
        #expect(SpriteKit.refinePrompt(Self.form, language: .russian).contains(/[а-яё]/))
    }

    @Test func aRefinedAnswerFillsTheForm() throws {
        let answer = """
            Sure! ```json
            {"name": "Mossy", "kind": "a boxy green moss block with a stepped leaf on top", "colour": "#4f9a3a",
             "characters": [{"name": "Fern", "persona": "A tiny anxious girl who talks fast."},
                            {"name": "Bark", "persona": "An old slow grumpy man."},
                            {"name": "Sprig", "persona": "A cheerful young boy."}]}
            ```
            """
        let out = try #require(SpriteKit.parseRefine(answer, over: SpriteKit.Form(kind: "moss")))
        #expect(out.name == "mossy" && out.colour == "#4f9a3a" && out.kind.hasPrefix("a boxy green moss block"))
        #expect(out.cast.map(\.name) == ["Fern", "Bark", "Sprig"] && out.cast[1].persona.contains("slow"))
    }

    @Test func aPartOrUnusableAnswerKeepsWhatWasThere() {
        let form = SpriteKit.Form(kind: "moss", name: "moss", colour: "#112233")
        let part = SpriteKit.parseRefine(#"{"kind": "a moss cube", "colour": "green"}"#, over: form)
        #expect(part?.kind == "a moss cube" && part?.colour == "#112233" && part?.name == "moss")
        #expect(SpriteKit.parseRefine("I cannot help with that.", over: form) == nil)
        #expect(SpriteKit.parseRefine("{}", over: form) == nil)
    }

    @Test func refiningIsItsOwnLineInTheCosts() {
        let usage = Spend.Usage(promptTokens: 400, completionTokens: 200, cost: 0.0003)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .creatureRefine),
                       Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .talk)]
        let s = Spend.summarise(records, now: Date())
        let line = s.byPurpose.first { $0.purpose == Spend.Purpose.creatureRefine.title }
        #expect(line?.total.calls == 1 && line?.total.cost == 0.0003)
        #expect(Spend.Purpose.creatureRefine.title == "Sprite kit: Refine with AI")
    }
}
