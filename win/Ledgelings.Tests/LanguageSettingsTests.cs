using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>The language setting: chosen from the system, remembered, and the shipped
/// prompts and lines following it while edited ones stay (the Mac's <c>LanguageSettingsTests</c>).</summary>
public class LanguageSettingsTests
{
    [Fact]
    public void TheDefaultIsTheSystemsLanguageAndAChoiceSurvivesARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.Equal(Languages.System, s.Language);
        s.Language = Language.Russian;
        Assert.Equal(Language.Russian, new AppSettings(store, secrets).Language);
        s.Language = Language.English;
        Assert.Equal(Language.English, new AppSettings(store, secrets).Language);
    }

    [Fact]
    public void ShippedTextFollowsTheLanguageAndEditedTextStays()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        store.Set("language", "en");
        var s = new AppSettings(store, secrets);
        Assert.True(s.Script == Script.BuiltInTextIn(Language.English) && s.SystemPrompt == Banter.SystemPromptIn(Language.English));
        s.LinePrompt = "my own line prompt {listener}";
        s.Language = Language.Russian;
        Assert.Equal(Script.BuiltInTextIn(Language.Russian), s.Script);
        Assert.Equal(Banter.SystemPromptIn(Language.Russian), s.SystemPrompt);
        Assert.Equal(Banter.ReplyPromptIn(Language.Russian), s.ReplyPrompt);
        Assert.Equal(Bonds.PlotPromptIn(Language.Russian), s.PlotPrompt);
        Assert.Equal("my own line prompt {listener}", s.LinePrompt);        // an edited prompt is the user's: it stays
        s.ResetPrompts();
        Assert.Equal(Banter.LinePromptIn(Language.Russian), s.LinePrompt);
        // Saved English text, read back by a Russian app, is Russian too.
        store.Set("script", Script.BuiltInTextIn(Language.English));
        Assert.Equal(Script.BuiltInTextIn(Language.Russian), new AppSettings(store, secrets).Script);
    }
}
