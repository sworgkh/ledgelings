import Testing
@testable import LedgelingsCore

/// Every prompt has a Russian version that asks for a Russian answer and keeps
/// every placeholder, and the plot prompt keeps the labels its parser reads.
@Suite struct PromptsRussianTests {
    static func placeholders(_ text: String) -> Set<String> {
        Set(text.matches(of: /\{[A-Za-z]+\}/).map { String(text[$0.range]) })
    }

    static let pairs: [(String, Translated<String>)] = [
        ("system", Banter.systemPrompts), ("line", Banter.linePrompts), ("reply", Banter.replyPrompts),
        ("plot", Bonds.plotPrompts), ("plot system", Bonds.plotSystemPrompts),
        ("note", Letters.notePrompts), ("plane reply", Letters.replyPrompts), ("musing", Letters.musingPrompts),
        ("tea system", Tea.systemPrompts), ("tea story", Tea.storyPrompts), ("tea reply", Tea.replyPrompts),
        ("complaint", Complaints.prompts), ("reminder", Reminders.notePrompts),
    ]

    @Test func everyPromptHasARussianVersionWithTheSamePlaceholders() {
        for (name, prompt) in Self.pairs {
            let ru = prompt(.russian)
            #expect(ru != prompt(.english), "\(name) has no Russian")
            #expect(ru.contains(/[а-яё]/), "\(name)")
            #expect(Self.placeholders(ru) == Self.placeholders(prompt(.english)), "\(name)")
        }
    }

    @Test func thePlotPromptKeepsItsLabelsAndOpener() {
        let ru = Bonds.plotPrompts(.russian)
        #expect(ru.contains("BOND:") && ru.contains("PLOT:"))
        #expect(ru.hasPrefix("Не пиши их разговоры"), "small models need the opener first")
    }

    @Test func pastedPromptsFollowTheLanguage() {
        Language.$override.withValue(.russian) {
            #expect(Script.agentPrompt(cast: []).contains(/[а-яё]/))
            #expect(SpriteText.prompt(example: ["...."]).contains(/[а-яё]/))
        }
        Language.$override.withValue(.english) {
            #expect(!Script.agentPrompt(cast: []).contains(/[а-яё]/))
        }
    }
}
