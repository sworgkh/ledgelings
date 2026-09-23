using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>Settings against a memory store and a memory secret store: nothing touches the
/// user's settings file or the Credential Manager. Each test starts from an empty store.</summary>
public class SettingsTests
{
    /// <summary>A throwaway store pair and the settings on top of them, empty at the start of each test.</summary>
    private sealed class Sandbox
    {
        public readonly MemorySettingsStore Store = new();
        public readonly MemorySecretStore Secrets = new();
        public readonly AppSettings Settings;
        public Sandbox() { Settings = new AppSettings(Store, Secrets); }
        /// <summary>A second launch over the same stores.</summary>
        public AppSettings Again() => new(Store, Secrets);
    }

    private static Sandbox Fresh() => new();

    [Fact]
    public void FollowingTheGiverIsOnByDefaultAndRemembered()
    {
        var box = Fresh();
        Assert.True(box.Settings.FollowGiver);
        box.Settings.FollowGiver = false;
        Assert.False(box.Again().FollowGiver);
    }

    [Fact]
    public void SpeciesThatNoLongerExistAreDroppedAndBlockyFillsAnEmptyList()
    {
        var s = Fresh().Settings;
        s.Species = new List<string> { "cat", "rabbit", "frog" };
        s.KeepSpecies(new[] { "blocky", "cat", "frog" });
        Assert.Equal(new[] { "cat", "frog" }, s.Species);
        s.KeepSpecies(new[] { "blocky" });
        Assert.Equal(new[] { "blocky" }, s.Species);
    }

    [Fact]
    public void CreaturesCycleThroughTheSpeciesInUseAndBlockyIsTheFallback()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.Equal(new[] { "blocky" }, s.Species);
        s.Species = new List<string> { "pip", "blocky" };
        Assert.True(s.SpeciesFor(0) == "pip" && s.SpeciesFor(1) == "blocky" && s.SpeciesFor(2) == "pip");
        Assert.Equal(new[] { "pip", "blocky" }, box.Again().Species);
        s.Species = new List<string>();
        Assert.Equal("blocky", s.SpeciesFor(0));
    }

    [Fact]
    public void AFreshInstallTalksFromTheBuiltInLinesAndAnOldOneKeepsLMStudio()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.Equal(BrainKind.Script, s.Brain);       // no model to set up: it talks out of the box
        Assert.Null(s.ChatClient());
        Assert.Equal(Script.BuiltInText, s.Script);
        box.Store.Set("talkModel", "google/gemma-3-4b");
        Assert.Equal(BrainKind.LmStudio, box.Again().Brain);   // someone who set up LM Studio before the lines existed keeps it
        box.Store.Set("brainProvider", "openRouter");
        Assert.Equal(BrainKind.OpenRouter, box.Again().Brain);
    }

    [Fact]
    public void TheLinesAreRememberedAndResetBringsTheBuiltInOnesBack()
    {
        var box = Fresh();
        var s = box.Settings;
        s.Script = "Hello.\nHi.";
        Assert.Equal("Hello.\nHi.", box.Again().Script);
        s.ResetScript();
        Assert.Equal(Script.BuiltInText, s.Script);
    }

    [Fact]
    public void TheBrainIsLMStudioWhenChosen()
    {
        var box = Fresh();
        var s = box.Settings;
        s.Brain = BrainKind.LmStudio;
        Assert.Equal("lmStudio", box.Store.Get<string>("brainProvider"));      // the same word the macOS app writes
        Assert.Equal(AppSettings.DefaultOpenRouterModel, s.OpenRouterModel);
        Assert.Equal("", s.OpenRouterKey);
        var client = s.ChatClient();
        Assert.NotNull(client);
        Assert.Equal(ChatClient.Provider.LmStudio, client.Kind);
        Assert.Equal("http://localhost:1234/v1", client.BaseUrl);
        Assert.Equal(AppSettings.DefaultTalkModel, client.Model);
    }

    [Fact]
    public void ChoosingOpenRouterBuildsAClientWithTheKeyAndModel()
    {
        var box = Fresh();
        var s = box.Settings;
        s.Brain = BrainKind.OpenRouter;
        s.OpenRouterKey = "sk-or-abc";
        s.OpenRouterModel = "openai/gpt-4o-mini";
        var client = s.ChatClient();
        Assert.NotNull(client);
        Assert.Equal(ChatClient.Provider.OpenRouter, client.Kind);
        Assert.Equal("sk-or-abc", client.ApiKey);
        Assert.Equal("openai/gpt-4o-mini", client.Model);
        Assert.Equal(ChatClient.OpenRouterUrl, client.BaseUrl);
        Assert.Equal("openRouter", box.Store.Get<string>("brainProvider"));
        Assert.False(box.Store.Has("openRouterKey"), "the key never lands in the settings file");
        s.OpenRouterKey = "";
    }

    [Fact]
    public void TheKeyComesBackFromTheKeychainOnTheNextLaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        new AppSettings(store, secrets).OpenRouterKey = "sk-or-kept";
        Assert.Equal("sk-or-kept", new AppSettings(new MemorySettingsStore(), secrets).OpenRouterKey);
    }

    [Fact]
    public void OpenRouterWithoutAKeyGivesNoClient()
    {
        var s = Fresh().Settings;
        s.Brain = BrainKind.OpenRouter;
        Assert.Null(s.ChatClient());
    }

    [Fact]
    public void CreaturesSpreadAcrossTheSizeRangeInHalfSteps()
    {
        var s = Fresh().Settings;
        s.MinSize = 1; s.MaxSize = 4;
        Assert.Equal(1, s.SizeForShare(0));
        Assert.Equal(4, s.SizeForShare(1));
        Assert.Equal(2.5, s.SizeForShare(0.5));
        Assert.Equal(2, s.SizeForShare(0.4));          // 2.2 snaps to the nearest half
    }

    [Fact]
    public void EqualMinAndMaxMakesEveryoneTheSameSize()
    {
        var s = Fresh().Settings;
        s.MinSize = 3; s.MaxSize = 3;
        Assert.Equal(new HashSet<double> { 3 }, new[] { 0, 0.3, 0.9, 1 }.Select(s.SizeForShare).ToHashSet());
    }

    [Fact]
    public void DraggingOneSliderPastTheOtherTakesItAlong()
    {
        var s = Fresh().Settings;
        s.MinSize = 2; s.MaxSize = 3;
        s.MinSize = 4.5;
        Assert.Equal(4.5, s.MaxSize);
        s.MaxSize = 1.5;
        Assert.Equal(1.5, s.MinSize);
    }

    [Fact]
    public void SizesAreSavedAndASwappedPairIsRepairedOnLoad()
    {
        var box = Fresh();
        var s = box.Settings;
        s.MinSize = 2.5; s.MaxSize = 4;
        var again = box.Again();
        Assert.True(again.MinSize == 2.5 && again.MaxSize == 4);

        box.Store.Set("minSize", 5.0); box.Store.Set("maxSize", 1.0);
        var repaired = box.Again();
        Assert.True(repaired.MinSize == 1 && repaired.MaxSize == 5);
    }

    [Fact]
    public void AFlowerIsWornForTwoMinutesByDefaultAndTheTimeIsClampedOnLoad()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.Equal(2, s.FlowerMinutes);
        s.FlowerMinutes = 10;
        Assert.Equal(10, box.Again().FlowerMinutes);
        box.Store.Set("flowerMinutes", 0.0);
        Assert.Equal(AppSettings.FlowerMin, box.Again().FlowerMinutes);
    }

    [Fact]
    public void BubbleTimeDefaultsToFourteenSecondsAndIsClampedOnLoad()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.Equal(14, s.BubbleSeconds);
        s.BubbleSeconds = 30;
        Assert.Equal(30, box.Again().BubbleSeconds);
        box.Store.Set("bubbleSeconds", 1.0);
        Assert.Equal(AppSettings.BubbleMin, box.Again().BubbleSeconds);
    }
}
