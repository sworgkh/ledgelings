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
    public void TheCursorIsAMenaceByDefaultAndAChoiceIsRemembered()
    {
        var box = Fresh();
        Assert.Equal(CursorMood.Bad, box.Settings.CursorMood);
        foreach (var m in CursorMoods.All)
        {
            box.Settings.CursorMood = m;
            Assert.Equal(m, box.Again().CursorMood);
        }
        box.Store.Set("cursorMood", "grumpy");
        Assert.Equal(CursorMood.Bad, box.Again().CursorMood);      // an unknown value falls back
    }

    [Fact]
    public void ChasesAreCountedAndTalkedAboutByDefaultAndAChangeIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.HuntCountEnabled && s.HuntTalkEnabled && s.HuntWary);
        Assert.Equal(25, s.HuntTalkChance);
        Assert.Equal(20, s.HuntWaryAfter);
        s.HuntCountEnabled = false; s.HuntTalkEnabled = false; s.HuntTalkChance = 60; s.HuntWary = false; s.HuntWaryAfter = 45;
        var again = box.Again();
        Assert.False(again.HuntCountEnabled || again.HuntTalkEnabled || again.HuntWary);
        Assert.Equal(60, again.HuntTalkChance);
        Assert.Equal(45, again.HuntWaryAfter);
        box.Store.Set("huntTalkChance", 500.0);
        box.Store.Set("huntWaryAfter", 1);
        Assert.Equal(100, box.Again().HuntTalkChance);      // clamped on load
        Assert.Equal(5, box.Again().HuntWaryAfter);
    }

    [Fact]
    public void RevengeIsOnByDefaultAndAChangeIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.RevengeEnabled);
        Assert.Equal(10, s.RevengeAfter);
        Assert.Equal(120, s.RevengeWindowSeconds);
        Assert.Equal(0, s.RevengeHoldSeconds);      // until shaken off
        Assert.Equal(4, s.RevengeShakes);
        Assert.Equal(10, s.RevengeCooldownMinutes);
        Assert.Equal((15.0, 20.0, 2.0), (s.RevengeTauntSeconds, s.RevengeShakeStroke, s.RevengeShakeWindowSeconds));
        Assert.False(s.RevengePinsCursor);      // it rides along
        s.RevengeEnabled = false; s.RevengeAfter = 15; s.RevengeWindowSeconds = 300; s.RevengeHoldSeconds = 20; s.RevengeShakes = 9; s.RevengeCooldownMinutes = 45;
        var again = box.Again();
        Assert.False(again.RevengeEnabled);
        Assert.Equal((15, 300.0, 20.0, 9, 45.0), (again.RevengeAfter, again.RevengeWindowSeconds, again.RevengeHoldSeconds, again.RevengeShakes, again.RevengeCooldownMinutes));
        s.RevengeTauntSeconds = 30; s.RevengeShakeStroke = 40; s.RevengeShakeWindowSeconds = 1.5; s.RevengePinsCursor = true;
        again = box.Again();
        Assert.Equal((30.0, 40.0, 1.5, true), (again.RevengeTauntSeconds, again.RevengeShakeStroke, again.RevengeShakeWindowSeconds, again.RevengePinsCursor));
        box.Store.Set("revengeAfter", 1);
        box.Store.Set("revengeHoldSeconds", 999.0);
        box.Store.Set("revengeShakes", 0);
        box.Store.Set("revengeCooldownMinutes", 0.0);
        box.Store.Set("revengeWindowSeconds", 1.0);
        box.Store.Set("revengeShakeStroke", 500.0);
        box.Store.Set("revengeShakeWindowSeconds", 0.1);
        box.Store.Set("revengeTauntSeconds", -5.0);
        var clamped = box.Again();      // clamped on load
        Assert.Equal((60.0, 1.0, 0.0), (clamped.RevengeShakeStroke, clamped.RevengeShakeWindowSeconds, clamped.RevengeTauntSeconds));
        Assert.Equal((3, 30.0, 2, 1.0, 30.0), (clamped.RevengeAfter, clamped.RevengeHoldSeconds, clamped.RevengeShakes, clamped.RevengeCooldownMinutes, clamped.RevengeWindowSeconds));
    }

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
    public void FlowersArePlantedByDefaultAndTheGardenSurvivesARelaunch()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.PlantFlowers && s.GardenMinutes == 60 && s.GardenSize == 12);
        s.PlantFlowers = false; s.GardenMinutes = 90; s.GardenSize = 3;
        var again = box.Again();
        Assert.True(!again.PlantFlowers && again.GardenMinutes == 90 && again.GardenSize == 3);
        box.Store.Set("gardenMinutes", 0.0); box.Store.Set("gardenSize", 500);
        var repaired = box.Again();
        Assert.Equal(AppSettings.GardenMinutesMin, repaired.GardenMinutes);
        Assert.Equal(AppSettings.GardenSizeMax, repaired.GardenSize);
    }

    [Fact]
    public void TheActionsSheetStaysOpenAfterATileUnlessToldOtherwiseAndItIsRemembered()
    {
        var box = Fresh();
        Assert.True(box.Settings.ActionsStayOpen);
        box.Settings.ActionsStayOpen = false;
        Assert.False(box.Again().ActionsStayOpen);
    }

    [Fact]
    public void TheShortcutIsControlAltLAndAChangeIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.ShortcutEnabled && s.Shortcut == Shortcut.Standard && s.ReopenShowsActions);
        Assert.Equal(new Shortcut(0x4C, ShortcutModifiers.Control | ShortcutModifiers.Option), Shortcut.Standard);
        s.ShortcutEnabled = false;
        s.Shortcut = new Shortcut(0x20, ShortcutModifiers.Command | ShortcutModifiers.Shift);
        s.ReopenShowsActions = false;
        s.RecordingShortcut = true;
        var back = box.Again();
        Assert.True(!back.ShortcutEnabled && back.Shortcut == new Shortcut(0x20, ShortcutModifiers.Command | ShortcutModifiers.Shift) && !back.ReopenShowsActions);
        Assert.True(!back.RecordingShortcut && back.ShortcutProblem.Length == 0);
        // A saved key someone types (Shift alone, or nothing held), or no key at all, reads as the standard one.
        box.Store.Set("shortcutModifiers", (int)ShortcutModifiers.Shift);
        Assert.Equal(Shortcut.Standard, box.Again().Shortcut);
        box.Store.Set("shortcutModifiers", (int)ShortcutModifiers.Control);
        box.Store.Set("shortcutKeyCode", 900);
        Assert.Equal(Shortcut.Standard, box.Again().Shortcut);
    }

    [Fact]
    public void TheShortcutIsWrittenAsWindowsWritesIt()
    {
        Assert.Equal("Ctrl+Alt+L", ShortcutKeys.Label(Shortcut.Standard));
        Assert.Equal("Ctrl+Alt+Shift+Win+Space", ShortcutKeys.Label(new Shortcut(0x20, ShortcutModifiers.Command | ShortcutModifiers.Shift | ShortcutModifiers.Control | ShortcutModifiers.Option)));
        Assert.Equal("Ctrl+F12", ShortcutKeys.Label(new Shortcut(0x7B, ShortcutModifiers.Control)));
        Assert.Equal(0x0002u | 0x0001u, ShortcutKeys.Win32Modifiers(Shortcut.Standard.Modifiers));      // MOD_CONTROL | MOD_ALT
        Assert.Equal(ShortcutModifiers.Control | ShortcutModifiers.Shift,
            ShortcutKeys.From(System.Windows.Input.ModifierKeys.Control | System.Windows.Input.ModifierKeys.Shift));
    }

    /// <summary>Nobody else would hold this one, so the first to ask gets it and the second is told no.</summary>
    [Fact]
    public void AShortcutAlreadyTakenIsNotRegisteredAndIsFreeAgainOnceLetGo()
    {
        var rare = new Shortcut(0x7B, ShortcutModifiers.Command | ShortcutModifiers.Shift | ShortcutModifiers.Control | ShortcutModifiers.Option);
        uint modifiers = ShortcutKeys.Win32Modifiers(rare.Modifiers), key = (uint)rare.KeyCode;
        using (var first = new GlobalHotkey(modifiers, key, () => { }))
        {
            Assert.True(first.IsRegistered);
            using var second = new GlobalHotkey(modifiers, key, () => { });
            Assert.False(second.IsRegistered);
        }
        using var third = new GlobalHotkey(modifiers, key, () => { });
        Assert.True(third.IsRegistered);
    }

    [Fact]
    public void TeaPartiesAreOnNowAndThenAndTheirNumbersSurviveARelaunch()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.TeaPartiesEnabled && s.TeaPartyChance == 10 && s.TeaPartyMinutes == 3 && s.TeaSipSeconds == 6);
        s.TeaPartiesEnabled = false;
        s.TeaPartyChance = 25;
        s.TeaPartyMinutes = 5.5;
        s.TeaSipSeconds = 12;
        var back = box.Again();
        Assert.True(!back.TeaPartiesEnabled && back.TeaPartyChance == 25 && back.TeaPartyMinutes == 5.5 && back.TeaSipSeconds == 12);
        box.Store.Set("teaPartyChance", 500.0);
        box.Store.Set("teaPartyMinutes", 0.1);
        box.Store.Set("teaSipSeconds", -3.0);
        var clamped = box.Again();
        Assert.Equal(AppSettings.TeaChanceMax, clamped.TeaPartyChance);
        Assert.Equal(AppSettings.TeaMinutesMin, clamped.TeaPartyMinutes);
        Assert.Equal(AppSettings.TeaSipMin, clamped.TeaSipSeconds);
    }

    [Fact]
    public void TheyComplainAfterFourInARowCalmAfterTwentySecondsAndItIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.ComplainEnabled && s.ComplainAfter == 4 && s.ComplainCalmSeconds == 20);
        s.ComplainEnabled = false;
        s.ComplainAfter = 7;
        s.ComplainCalmSeconds = 45;
        var back = box.Again();
        Assert.True(!back.ComplainEnabled && back.ComplainAfter == 7 && back.ComplainCalmSeconds == 45);
        box.Store.Set("complainAfter", 99);
        box.Store.Set("complainCalmSeconds", 1.0);
        var clamped = box.Again();
        Assert.Equal(AppSettings.ComplainAfterMax, clamped.ComplainAfter);
        Assert.Equal(AppSettings.ComplainCalmMin, clamped.ComplainCalmSeconds);
    }

    [Fact]
    public void WithTheBuiltInLinesThereIsNoModelAndTheReasonSaysWhereToChooseOne()
    {
        var s = Fresh().Settings;
        Assert.False(s.HasModel, "a fresh install greys out what only a model can do");
        Assert.Equal(AppSettings.NeedsModel, s.BrainProblem);
        Assert.Contains("Settings › Talk", AppSettings.NeedsModel);
        Assert.True(ChatClient.Failure.NoModel(s.BrainProblem).Message == AppSettings.NeedsModel, "said as it is, not as a server refusal");
        s.Brain = BrainKind.LmStudio;
        Assert.True(s.HasModel);
        s.Brain = BrainKind.OpenRouter;
        Assert.True(s.HasModel && s.ChatClient() is null, "chosen but keyless: the features show, the key is what is missing");
    }

    [Fact]
    public void LineMemoryDefaultsToTwelveAndIsClampedOnLoad()
    {
        var box = Fresh();
        Assert.Equal(12, box.Settings.LineMemory);
        box.Settings.LineMemory = 0;
        Assert.Equal(0, box.Again().LineMemory);
        box.Store.Set("lineMemory", 500);
        Assert.Equal(AppSettings.LineMemoryMax, box.Again().LineMemory);
    }

    [Fact]
    public void RoomForEachLineDefaultsToSixHundredTokensReachesTheClientAndIsClampedOnLoad()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.Equal(600, s.LineTokens);
        s.LineTokens = 1500;
        Assert.Equal(1500, box.Again().LineTokens);
        s.Brain = BrainKind.LmStudio;
        Assert.Equal(1500, s.ChatClient()?.LineTokens);
        box.Store.Set("lineTokens", 10);
        Assert.Equal(AppSettings.LineTokensMin, box.Again().LineTokens);
        box.Store.Set("lineTokens", 99_999);
        Assert.Equal(AppSettings.LineTokensMax, box.Again().LineTokens);
    }

    [Fact]
    public void StoriesAreOnAfterAnHourForSixConversationsAndRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.PlotsEnabled && s.PlotAfterHours == 1 && s.PlotLength == 6 && s.PlotPrompt == Bonds.DefaultPlotPrompt);
        s.PlotsEnabled = false;
        s.PlotAfterHours = 24;
        s.PlotLength = 10;
        s.PlotPrompt = "Write {speaker} a plot.";
        var back = box.Again();
        Assert.True(!back.PlotsEnabled && back.PlotAfterHours == 24 && back.PlotLength == 10 && back.PlotPrompt == "Write {speaker} a plot.");
        back.ResetPlotPrompt();
        Assert.Equal(Bonds.DefaultPlotPrompt, back.PlotPrompt);
        box.Store.Set("plotAfterHours", 500.0);
        box.Store.Set("plotLength", 0);
        var clamped = box.Again();
        Assert.True(clamped.PlotAfterHours == AppSettings.PlotAfterMax && clamped.PlotLength == AppSettings.PlotLengthMin);
    }

    [Fact]
    public void TheyKnowTheTimeDateAndAllThreeFaithsHolidaysByDefaultAndItIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.KnowsTimeOfDay && s.KnowsDate && s.JewishHolidays && s.ChristianHolidays && s.MuslimHolidays);
        Assert.Equal(3, s.HolidayLookAhead);
        Assert.Equal(new Almanac.Awareness(true, true, Almanac.AllFaiths, 3), s.Awareness);
        s.KnowsTimeOfDay = false;
        s.KnowsDate = false;
        s.ChristianHolidays = false;
        s.MuslimHolidays = false;
        s.HolidayLookAhead = 7;
        var back = box.Again();
        Assert.True(!back.KnowsTimeOfDay && !back.KnowsDate && back.JewishHolidays && !back.ChristianHolidays && !back.MuslimHolidays);
        Assert.Equal(new Almanac.Awareness(false, false, new[] { Almanac.Faith.Jewish }, 7), back.Awareness);
        box.Store.Set("holidayLookAhead", 99);
        Assert.Equal(AppSettings.HolidayLookAheadMax, box.Again().HolidayLookAhead);
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

    [Fact]
    public void PaperPlanesAreOnEveryThreeMinutesByDefaultAndItIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.PlanesEnabled);
        Assert.Equal(3, s.PlaneMinutes);
        s.PlanesEnabled = false;
        s.PlaneMinutes = 10;
        var back = box.Again();
        Assert.True(!back.PlanesEnabled && back.PlaneMinutes == 10);
        box.Store.Set("planeMinutes", 0.0);
        Assert.Equal(AppSettings.PlaneMin, box.Again().PlaneMinutes);
        box.Store.Set("planeMinutes", 500.0);
        Assert.Equal(AppSettings.PlaneMax, box.Again().PlaneMinutes);
    }

    [Fact]
    public void RemindersArriveByPlaneTheLetterStaysAMinuteAndIsReadAloudAndItIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.True(s.RemindersEnabled && s.ReminderLetterSeconds == 60 && s.ReminderReadAloud);
        s.RemindersEnabled = false;
        s.ReminderLetterSeconds = 120;
        s.ReminderReadAloud = false;
        var back = box.Again();
        Assert.True(!back.RemindersEnabled && back.ReminderLetterSeconds == 120 && !back.ReminderReadAloud);
        box.Store.Set("reminderLetterSeconds", 1.0);
        Assert.Equal(AppSettings.ReminderLetterMin, box.Again().ReminderLetterSeconds);
    }

    [Fact]
    public void AddAReminderOpensThePaperNoteUnlessToldOtherwiseAndItIsRemembered()
    {
        var box = Fresh();
        Assert.True(box.Settings.ReminderPaperNote);
        box.Settings.ReminderPaperNote = false;
        Assert.False(box.Again().ReminderPaperNote);
    }

    [Fact]
    public void VoiceIsOffUntilAskedAndEveryVoiceSettingIsRemembered()
    {
        var box = Fresh();
        var s = box.Settings;
        Assert.False(s.VoiceEnabled);                                   // it must not start talking out loud unasked
        Assert.True(s.VoiceEngine == VoiceEngine.System && s.VoicePerCharacter);
        Assert.True(s.VoiceModel == AppSettings.DefaultVoiceModel && s.VoiceSpeed == 1 && s.VoicePitch == 1 && s.VoiceVolume == 0.8);
        Assert.True(s.KeepVoices);                                      // paid-for sounds are kept unless asked not to
        Assert.True(s.CartoonVoices);                                   // desktop pets, not newsreaders
        Assert.Empty(s.CharacterVoices);
        Assert.True(s.SpeedFollowsPitch);                               // clean sound by default
        Assert.True(s.CastByPersonality);                               // voices fit who they are by default
        Assert.Equal(0.35, s.VoiceTurnPause);                           // a natural beat between one line and the answer
        s.VoiceTurnPause = 0.8;
        Assert.Equal(0.8, box.Again().VoiceTurnPause);
        box.Store.Set("voiceTurnPause", 9.0);
        Assert.Equal(AppSettings.VoiceTurnPauseMax, box.Again().VoiceTurnPause);
        s.CastByPersonality = false;
        Assert.False(box.Again().CastByPersonality);
        s.SpeedFollowsPitch = false;
        Assert.False(box.Again().SpeedFollowsPitch);
        Assert.True(s.LocalVoiceUrl == "http://localhost:8880/v1" && s.LocalVoiceModel == "kokoro" && s.LocalVoice.Length == 0);
        s.LocalVoiceServer = "not a url";
        Assert.Null(s.LocalVoiceUrl);
        s.LocalVoiceServer = "http://127.0.0.1:9000";
        s.LocalVoice = "am_puck";
        Assert.Equal("http://127.0.0.1:9000/v1", box.Again().LocalVoiceUrl);
        Assert.Equal("am_puck", box.Again().LocalVoice);
        s.SetVoice("Pip", v => { v.Pitch = 1.5; v.OpenRouterVoice = "am_puck"; });
        Assert.Equal(new CharacterVoice { OpenRouterVoice = "am_puck", Pitch = 1.5 }, box.Again().CharacterVoices["Pip"]);
        s.SetVoice("Pip", v => v.FollowPitch = false);
        Assert.False(box.Again().CharacterVoices["Pip"].FollowPitch);
        s.SetVoice("Pip", v => { v.OpenRouterVoice = null; v.Pitch = null; v.FollowPitch = null; });
        Assert.False(s.CharacterVoices.ContainsKey("Pip"));            // all automatic again: nothing stored
        s.CartoonVoices = false;
        Assert.False(box.Again().CartoonVoices);
        s.KeepVoices = false;
        Assert.False(box.Again().KeepVoices);
        Assert.True(box.Again().ReuseLineVoices);                       // the built-in lines are made once unless asked not to
        s.ReuseLineVoices = false;
        Assert.False(box.Again().ReuseLineVoices);
        s.VoiceEnabled = true;
        s.VoiceEngine = VoiceEngine.OpenRouter;
        s.VoicePerCharacter = false;
        s.SystemVoice = "Microsoft Zira Desktop";
        s.VoiceModel = "deepgram/flux-tts:free";
        s.OpenRouterVoice = "flux-kit-en";
        s.VoiceSpeed = 1.5; s.VoicePitch = 0.75; s.VoiceVolume = 0.3;
        var back = box.Again();
        Assert.True(back.VoiceEnabled && back.VoiceEngine == VoiceEngine.OpenRouter && !back.VoicePerCharacter);
        Assert.Equal("openRouter", box.Store.Get<string>("voiceEngine"));     // the macOS app's word for it
        Assert.Equal("Microsoft Zira Desktop", back.SystemVoice);
        Assert.True(back.VoiceModel == "deepgram/flux-tts:free" && back.OpenRouterVoice == "flux-kit-en");
        Assert.True(back.VoiceSpeed == 1.5 && back.VoicePitch == 0.75 && back.VoiceVolume == 0.3);
        box.Store.Set("voiceSpeed", 9.0);
        Assert.Equal(AppSettings.VoiceSpeedMax, box.Again().VoiceSpeed);
    }
}
