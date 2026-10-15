import LedgelingsCore

/// Settings › Sprites › Refine with AI: the form's short idea becomes a whole
/// creature (a kind line in the toy's style, a colour, three characters who
/// sound like someone), from OpenRouter with the Talk tab's model.
@MainActor
enum SpriteKitRefine {
    /// The form, refined. The call is priced into the spend file as its own
    /// feature even when its answer cannot be used: it was paid for.
    static func refine(_ form: SpriteKit.Form, client: ChatClient, spend: SpendLedger) async throws -> SpriteKit.Form {
        // Room for a thinking model to think a little; the answer itself is a few hundred tokens.
        let answer = try await client.reply(system: SpriteKit.refineSystems(), user: SpriteKit.refinePrompt(form),
                                            maxTokens: 3000, temperature: 0.8, reasoning: "low")
        spend.record(provider: client.provider, model: client.model,
                     usage: answer.usage ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil), purpose: .creatureRefine)
        guard let refined = SpriteKit.parseRefine(answer.text, over: form) else {
            throw ChatClient.Failure.badReply(String(answer.text.prefix(120)))
        }
        return refined
    }
}
