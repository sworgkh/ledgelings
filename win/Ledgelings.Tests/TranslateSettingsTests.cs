using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;
using T = Ledgelings.Core.Translate;

namespace Ledgelings.Tests;

/// <summary>Tools › Translate and Tools › Tools screen: their settings, the failed key read tried again, the translator
/// pricing every call, and the Actions sheet's wrench. The Mac's TranslateSettingsTests, ToolsScreenTests and
/// OpenRouterKeyTests.</summary>
public class TranslateSettingsTests
{
    [Fact]
    public void TheTranslatorsDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.TranslateEnabled && s.TranslateShortcutEnabled && s.TranslateClipShortcutEnabled);
        Assert.Equal(new Shortcut(0x54, ShortcutModifiers.Control | ShortcutModifiers.Option), s.TranslateShortcut);                              // Ctrl+Alt+T
        Assert.Equal(new Shortcut(0x54, ShortcutModifiers.Control | ShortcutModifiers.Option | ShortcutModifiers.Shift), s.TranslateClipShortcut); // Ctrl+Alt+Shift+T
        Assert.Equal(T.ClipMode.Sheet, s.TranslateClipMode);
        Assert.Equal(new[] { "en", "ru", "he" }, s.TranslateLanguages);
        Assert.Equal("en", s.TranslateTargets["he"]);
        Assert.True(s.TranslateModel == T.DefaultModel && s.TranslateAutocomplete && s.TranslateAutocompleteModel == "");
        Assert.True(s.TranslateDelayMs == 400 && s.TranslateLiveLimit == 5_000 && s.TranslatePickerButton && s.TranslateKeepInHistory);
        Assert.True(s.TranslateHelperEnabled && s.TranslateHelper == "");

        s.TranslateEnabled = false; s.TranslateClipMode = T.ClipMode.Quietly; s.TranslateLanguages = new() { "he", "en" };
        s.TranslateTargets = new() { ["en"] = "he" }; s.TranslateModel = "openai/gpt-4.1-nano"; s.TranslateDelayMs = 900;
        s.TranslateLiveLimit = 12_000; s.TranslatePickerButton = false; s.TranslateHelper = "Zed";
        var again = new AppSettings(store, secrets);
        Assert.False(again.TranslateEnabled);
        Assert.Equal(T.ClipMode.Quietly, again.TranslateClipMode);
        Assert.Equal("quietly", store.Get<string>("translateClipMode"));
        Assert.Equal(new[] { "en", "he" }, again.TranslateLanguages);
        Assert.Equal("he", again.TranslateTargets["en"]);
        Assert.True(again.TranslateModel == "openai/gpt-4.1-nano" && again.TranslateDelayMs == 900 && again.TranslateLiveLimit == 12_000);
        Assert.True(!again.TranslatePickerButton && again.TranslateHelper == "Zed");

        store.Set("translateDelayMs", 99_999); store.Set("translateLiveLimit", 3); store.Set("translateLanguages", new List<string> { "en" });
        store.Set("translateTargets", new Dictionary<string, string> { ["en"] = "en", ["xx"] = "ru" }); store.Set("translateModel", " ");
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.TranslateDelayMs == 1_500 && clamped.TranslateLiveLimit == 1_000);
        Assert.Equal(new[] { "en", "ru", "he" }, clamped.TranslateLanguages);
        Assert.Equal("ru", clamped.TranslateTargets["en"]);
        Assert.False(clamped.TranslateTargets.ContainsKey("xx"));
        Assert.Equal(T.DefaultModel, clamped.TranslateModel);
    }

    [Fact]
    public void TheToolsScreensDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.ToolsScreenEnabled && s.ToolsScreenShortcutEnabled);
        Assert.Equal(new Shortcut(0x4B, ShortcutModifiers.Control | ShortcutModifiers.Option), s.ToolsScreenShortcut);   // Ctrl+Alt+K
        Assert.Equal(Tools.DefaultShown, s.ToolsScreenTools);
        s.ToolsScreenEnabled = false;
        s.ToolsScreenTools = new() { "reminder", "translate" };
        var again = new AppSettings(store, secrets);
        Assert.False(again.ToolsScreenEnabled);
        Assert.Equal(new[] { "reminder", "translate" }, again.ToolsScreenTools);
        // A Mac's screenshot tiles and a doubled one are dropped on load.
        store.Set("toolsScreenTools", new List<string> { "screenshot", "translate", "translate", "dictation" });
        Assert.Equal(new[] { "translate", "dictation" }, new AppSettings(store, secrets).ToolsScreenTools);
    }

    /// <summary>Fails the first reads, as the Credential Manager does before it is there, then finds the key.</summary>
    private sealed class FlakySecrets : ISecretStore
    {
        public int Failures;
        public string? Key;
        public int Reads;
        public string? Get(string account) => Read(account) is SecretRead.Found f ? f.Value : null;
        public void Set(string account, string? value) => Key = value;
        public SecretRead Read(string account)
        {
            Reads++;
            if (Failures > 0) { Failures--; return new SecretRead.Failed(1312); }
            return Key is null ? new SecretRead.Missing() : new SecretRead.Found(Key);
        }
    }

    [Fact]
    public void AFailedKeyReadIsTriedAgainWhenTheSheetOpens()
    {
        var secrets = new FlakySecrets { Failures = 1, Key = "sk-or-test" };
        var s = new AppSettings(new MemorySettingsStore(), secrets);
        Assert.Equal("", s.OpenRouterKey);
        var reads = secrets.Reads;
        var translator = new Translator(s, new SpendLedger(Path.Combine(Path.GetTempPath(), "ledgelings-key-" + Guid.NewGuid())));
        translator.Refresh();
        Assert.Equal("sk-or-test", s.OpenRouterKey);
        Assert.Equal(T.DefaultModel, translator.Client()?.Model);
        translator.Refresh();
        Assert.Equal(reads + 1, secrets.Reads);      // a key read fine is not read again

        var none = new FlakySecrets();
        var empty = new AppSettings(new MemorySettingsStore(), none);
        var before = none.Reads;
        empty.RetryOpenRouterKey();
        Assert.Equal(before, none.Reads);             // none saved is not asked again
    }

    [Fact]
    public async Task TheCacheAnswersRetypingAndAnEmptyAnswerIsATrouble()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-translate-" + Guid.NewGuid());
        var spend = new SpendLedger(dir);
        var s = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var translator = new Translator(s, spend) { Fake = (_, text) => Task.FromResult(new ChatClient.Answer(text == "Hello there" ? "Привет" : "", null)) };
        var (done, trouble) = await translator.Translate("Hello there", T.English, T.Russian);
        Assert.Equal("Привет", done?.Text);
        Assert.Null(trouble);
        var (cached, _) = await translator.Translate("Hello there", T.English, T.Russian);
        Assert.True(cached?.Cached);
        var (_, empty) = await translator.Translate("Good night", T.English, T.Russian);
        Assert.Equal(Translator.TroubleKind.Empty, empty?.Kind);
        Assert.False(new Translator(s, spend).HasModel);      // no key, no LM Studio: the sheet says so
    }

    [Fact]
    public void TheWrenchNamesItsKey()
    {
        Assert.Contains("(K)", Languages.With(Language.English, () => ActionsLinks.ToolsTooltip("")));
        Assert.Contains("K · Ctrl+Alt+K", Languages.With(Language.English, () => ActionsLinks.ToolsTooltip("Ctrl+Alt+K")));
        Assert.DoesNotContain(ActionsLink.Tools, ActionsLinks.Footer);
    }
}
