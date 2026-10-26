using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Productivity tools › Dictation: its settings, its place among the tools, and the microphone's picture.
/// The Mac's DictationSettingsTests.</summary>
public class DictationSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.DictationEnabled && s.DictationShortcutEnabled && !s.DictationHoldToTalk);
        Assert.Equal(Shortcut.Dictation, s.DictationShortcut);                                         // Ctrl+Alt+D
        Assert.Equal(new Shortcut(0x44, ShortcutModifiers.Control | ShortcutModifiers.Option), Shortcut.Dictation);
        Assert.True(s.DictationModel == Dictation.DefaultModel && s.DictationLanguage == Dictation.Spoken.Auto && s.DictationCleanUp);
        Assert.True(s.DictationMaxSeconds == 120 && !s.DictationPaste && s.DictationCreature && s.DictationHelper == "");

        s.DictationEnabled = false; s.DictationShortcutEnabled = false; s.DictationHoldToTalk = true;
        s.DictationShortcut = new Shortcut(0x44, ShortcutModifiers.Control | ShortcutModifiers.Shift);
        s.DictationModel = "openai/gpt-audio-mini"; s.DictationLanguage = Dictation.Spoken.Russian; s.DictationCleanUp = false;
        s.DictationMaxSeconds = 300; s.DictationPaste = true; s.DictationCreature = false; s.DictationHelper = "Zed";
        var again = new AppSettings(store, secrets);
        Assert.True(!again.DictationEnabled && !again.DictationShortcutEnabled && again.DictationHoldToTalk);
        Assert.Equal(new Shortcut(0x44, ShortcutModifiers.Control | ShortcutModifiers.Shift), again.DictationShortcut);
        Assert.True(again.DictationModel == "openai/gpt-audio-mini" && again.DictationLanguage == Dictation.Spoken.Russian && !again.DictationCleanUp);
        Assert.True(again.DictationMaxSeconds == 300 && again.DictationPaste && !again.DictationCreature && again.DictationHelper == "Zed");
        Assert.Equal("russian", store.Get<string>("dictationLanguage"));

        store.Set("dictationMaxSeconds", 5000); store.Set("dictationLanguage", "klingon"); store.Set("dictationModel", " ");
        var clamped = new AppSettings(store, secrets);
        Assert.Equal(600, clamped.DictationMaxSeconds);
        Assert.Equal(Dictation.Spoken.Auto, clamped.DictationLanguage);
        Assert.Equal(Dictation.DefaultModel, clamped.DictationModel);
    }

    [Fact]
    public void DictationIsATool() => Assert.Equal(SettingsGroup.Tools, SettingsPage.Dictation.Group());

    [Fact]
    public void TheMicrophoneIsAPictureTurnedToFaceOut()
    {
        var grid = Dictation.Microphone(5);
        using var right = Colony.Picture(grid);
        using var left = Colony.Picture(grid, mirrored: true);
        Assert.Equal(18, right.Width);
        Assert.Equal(14, right.Height);
        Assert.Equal(right.GetPixel(1, 0), left.GetPixel(16, 0));
        Assert.Equal(7, Colony.MicrophoneInks.Count);
    }
}
