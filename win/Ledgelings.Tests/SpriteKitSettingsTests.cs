using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>The sprite kit's form is kept like any setting, and Refine with AI is there only with an
/// OpenRouter key, priced as its own feature even when its answer is no use. The Mac's SpriteKitSettingsTests.</summary>
public class SpriteKitSettingsTests
{
    [Fact]
    public void TheFormStartsEmptyAndSurvivesARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.Equal(new SpriteKit.Form(), s.SpriteKitForm);
        Assert.Equal(3, s.SpriteKitForm.Cast.Count);
        s.SpriteKitForm = s.SpriteKitForm with
        {
            Kind = "a boxy moss sprite", Colour = "#55aa33",
            Cast = new[] { new Character("", ""), new Character("Bark", "old, slow, grumpy") },
        };
        var again = new AppSettings(store, secrets);
        Assert.Equal("a boxy moss sprite", again.SpriteKitForm.Kind);
        Assert.Equal("#55aa33", again.SpriteKitForm.Colour);
        Assert.Equal("Bark", again.SpriteKitForm.Cast[1].Name);
        store.Set("spriteKitForm", new SpriteKit.Form { Colour = "greenish" });
        Assert.Equal("", new AppSettings(store, secrets).SpriteKitForm.Colour);
    }

    [Fact]
    public void RefineIsOnlyThereWithAnOpenRouterKey()
    {
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore()) { Brain = BrainKind.Script };
        s.OpenRouterKey = "sk-or-test";
        Assert.False(s.OpenRouterConnected);
        Assert.Null(s.RefineClient());
        s.VoiceEngine = VoiceEngine.OpenRouter;
        Assert.True(s.OpenRouterConnected);
        s.VoiceEngine = VoiceEngine.System;
        s.Brain = BrainKind.LmStudio;
        Assert.False(s.OpenRouterConnected);
        s.Brain = BrainKind.OpenRouter;
        s.OpenRouterModel = "some/model";
        Assert.Equal("some/model", s.RefineClient()!.Model);
        s.OpenRouterKey = "";
        Assert.Null(s.RefineClient());
    }

    [Fact]
    public void AnAnswerFillsTheFormAndIsPricedEvenWhenItIsNoUse()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-refine-" + Guid.NewGuid());
        try
        {
            var spend = new SpendLedger(dir);
            var usage = new Spend.Usage(420, 180, 0.0004);
            var good = new ChatClient.Answer("""{"name": "mossy", "kind": "a boxy moss block", "colour": "#4f9a3a", "characters": [{"name": "Fern", "persona": "tiny, fast, anxious, she"}]}""", usage);
            var form = SpriteKitRefine.Finish(good, ChatClient.Provider.OpenRouter, "m", new SpriteKit.Form { Kind = "moss" }, spend);
            Assert.True(form.Name == "mossy" && form.Kind == "a boxy moss block" && form.Cast[0].Name == "Fern");
            Assert.Throws<ChatClient.Failure>(() =>
                SpriteKitRefine.Finish(new ChatClient.Answer("Sorry, I can only draw.", usage), ChatClient.Provider.OpenRouter, "m", new SpriteKit.Form(), spend));
            var line = spend.Summary.ByPurpose.First(p => p.Purpose == Spend.Purpose.CreatureRefine.Title());
            Assert.Equal(2, line.Total.Calls);
            Assert.True(Math.Abs(line.Total.Cost - 0.0008) < 1e-12);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }
}
