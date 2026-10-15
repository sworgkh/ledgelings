using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Settings › Sprites › Refine with AI: the form's short idea becomes a whole creature
/// (a kind line in the toy's style, a colour, three characters who sound like someone), from
/// OpenRouter with the Talk tab's model. The Mac's <c>SpriteKitRefine</c>.</summary>
public static class SpriteKitRefine
{
    public static async Task<SpriteKit.Form> Refine(SpriteKit.Form form, ChatClient client, SpendLedger spend)
    {
        // Room for a thinking model to think a little; the answer itself is a few hundred tokens.
        var answer = await client.Reply(SpriteKit.RefineSystem, SpriteKit.RefinePrompt(form), maxTokens: 3000, temperature: 0.8, reasoning: "low");
        return Finish(answer, client.Kind, client.Model, form, spend);
    }

    /// <summary>The answer priced into the spend file as its own feature, even when it cannot be
    /// used (it was paid for), then laid over the form.</summary>
    public static SpriteKit.Form Finish(ChatClient.Answer answer, ChatClient.Provider provider, string model, SpriteKit.Form form, SpendLedger spend)
    {
        spend.Record(provider, model, answer.Usage ?? new Spend.Usage(0, 0, null), Spend.Purpose.CreatureRefine);
        return SpriteKit.ParseRefine(answer.Text, form) ?? throw ChatClient.Failure.BadReply(ChatClient.Head(answer.Text, 120));
    }
}
