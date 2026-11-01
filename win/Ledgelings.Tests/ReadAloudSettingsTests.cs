using System.Speech.Synthesis;
using System.Text.Json.Nodes;
using Ledgelings.Native;
using R = Ledgelings.Core.ReadAloud;

namespace Ledgelings.Tests;

/// <summary>Tools › Read aloud: its settings, the Tools screen's new tile, the sound pieces and the file, the voice a
/// part is read in. The Mac's ReadAloudSettingsTests; Windows' voices are a pretend list, so the test does not depend
/// on which speech packs this PC has.</summary>
[Collection("windows voices")]
public sealed class ReadAloudSettingsTests : IDisposable
{
    private static readonly Voice.SystemVoiceInfo David = new("Microsoft David Desktop", "en-US", VoiceGender.Male, VoiceAge.Adult);
    private static readonly Voice.SystemVoiceInfo Zira = new("Microsoft Zira Desktop", "en-US", VoiceGender.Female, VoiceAge.Adult);
    private static readonly Voice.SystemVoiceInfo Irina = new("Microsoft Irina Desktop", "ru-RU", VoiceGender.Female, VoiceAge.Adult);

    private readonly string dir = Path.Combine(Path.GetTempPath(), "ledgelings-read-aloud-" + Guid.NewGuid());
    private readonly IReadOnlyList<Voice.SystemVoiceInfo> installedBefore = Voice.Installed;
    private readonly string? defaultBefore = Voice.SapiDefault;

    public void Dispose()
    {
        Voice.Installed = installedBefore;
        Voice.SapiDefault = defaultBefore;
        try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private ReadAloudPlayer Player(AppSettings settings)
    {
        var spend = new SpendLedger(Path.Combine(dir, "spend"));
        return new ReadAloudPlayer(settings, spend, new Voice(settings, spend, archive: Path.Combine(dir, "voices"), lineArchive: Path.Combine(dir, "line-voices")));
    }

    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.ReadAloudEnabled && s.ReadAloudShortcutEnabled);
        // Ctrl+Alt+Shift+R: Ctrl+Alt+R is Add a Reminder on Windows.
        Assert.Equal(new Shortcut(0x52, ShortcutModifiers.Control | ShortcutModifiers.Option | ShortcutModifiers.Shift), s.ReadAloudShortcut);
        Assert.True(s.ReadAloudFromClipboard && s.ReadAloudStartAtOnce && s.ReadAloudKeepReading && s.ReadAloudPickerButton);
        Assert.True(s.ReadAloudHelperEnabled && s.ReadAloudHelper == "");
        Assert.Equal(R.DefaultPresets, s.ReadAloudPresets);
        Assert.Equal("Narrator", s.ReadAloudDefault.Name);
        Assert.Equal("~/Desktop", s.ReadAloudFolder);
        Assert.Equal(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), s.ReadAloudFolderPath);
        Assert.True(s.ReadAloudFormat == R.Format.M4a && s.ReadAloudLongLimit == 3_000);

        s.ReadAloudEnabled = false; s.ReadAloudShortcutEnabled = false;
        s.ReadAloudShortcut = new Shortcut(0x52, ShortcutModifiers.Command | ShortcutModifiers.Option);
        s.ReadAloudFromClipboard = false; s.ReadAloudStartAtOnce = false; s.ReadAloudKeepReading = false; s.ReadAloudPickerButton = false;
        s.ReadAloudHelperEnabled = false; s.ReadAloudHelper = "Zed";
        var mine = new R.Preset { Name = "Slow Mossy", Engine = R.Engine.System, Character = "Mossy", Speed = 0.7, Pause = 2, Language = "he", Voice = "Microsoft Asaf Desktop" };
        s.ReadAloudPresets = new[] { R.DefaultPresets[2], mine };
        s.ReadAloudDefaultPreset = R.IdString(mine.Id);
        s.ReadAloudFolder = "~/Music/Readings"; s.ReadAloudFormat = R.Format.Wav; s.ReadAloudLongLimit = 8_000;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.ReadAloudEnabled && !again.ReadAloudShortcutEnabled);
        Assert.Equal(new Shortcut(0x52, ShortcutModifiers.Command | ShortcutModifiers.Option), again.ReadAloudShortcut);
        Assert.True(!again.ReadAloudFromClipboard && !again.ReadAloudStartAtOnce && !again.ReadAloudKeepReading && !again.ReadAloudPickerButton);
        Assert.True(!again.ReadAloudHelperEnabled && again.ReadAloudHelper == "Zed");
        Assert.Equal(new[] { R.DefaultPresets[2], mine }, again.ReadAloudPresets);        // added, renamed and deleted presets are kept
        Assert.Equal(mine, again.ReadAloudDefault);
        Assert.True(again.ReadAloudFolder == "~/Music/Readings" && again.ReadAloudFormat == R.Format.Wav && again.ReadAloudLongLimit == 8_000);
        Assert.Equal("wav", store.Get<string>("readAloudFormat"));
        // The Mac's id and field names in the file.
        Assert.Equal(R.IdString(mine.Id), store.Get<string>("readAloudDefaultPreset"));
        Assert.Equal("system", store.Get<JsonArray>("readAloudPresets")![1]!["engine"]!.GetValue<string>());
    }

    [Fact]
    public void NonsenseIsClampedOnLoad()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        store.Set("readAloudLongLimit", 10); store.Set("readAloudFormat", "ogg"); store.Set("readAloudFolder", "  ");
        store.Set("readAloudPresets", JsonNode.Parse("""[{"name":"Loud","speed":40}]"""));
        store.Set("readAloudDefaultPreset", "not-an-id");
        var s = new AppSettings(store, secrets);
        Assert.True(s.ReadAloudLongLimit == 500 && s.ReadAloudFormat == R.Format.M4a && s.ReadAloudFolder == "~/Desktop");
        Assert.True(s.ReadAloudPresets.Count == 1 && s.ReadAloudPresets[0].Speed == 2);
        Assert.Equal("Loud", s.ReadAloudDefault.Name);                                        // an unknown default is the first
        store.Set("readAloudPresets", new JsonArray());
        Assert.Equal(R.DefaultPresets, new AppSettings(store, secrets).ReadAloudPresets);    // never none
        store.Set("readAloudPresets", JsonNode.Parse("[42, \"x\"]"));
        Assert.Equal(R.DefaultPresets, new AppSettings(store, secrets).ReadAloudPresets);    // not presets at all: the shipped ones
        store.Set("readAloudLongLimit", 999_999);
        Assert.Equal(20_000, new AppSettings(store, secrets).ReadAloudLongLimit);
        // Deleting the default moves it to the first.
        var t = new AppSettings(new MemorySettingsStore(), secrets);
        t.ReadAloudDefaultPreset = R.IdString(R.DefaultPresets[3].Id);
        t.ReadAloudPresets = R.DefaultPresets.Where(p => p.Id != R.DefaultPresets[3].Id).ToList();
        Assert.Equal(R.DefaultPresets[0].Id, t.ReadAloudDefault.Id);
    }

    [Fact]
    public void AToolsScreenArrangedBeforeGetsTheNewTileOnceAndItCanBeSwitchedOff()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        store.Set("toolsScreenTools", new List<string> { "translate", "dictation", "reminder" });     // as 0.62 left it: no toolsScreenKnown
        var s = new AppSettings(store, secrets);
        Assert.Equal(new[] { "translate", "dictation", "reminder", "readAloud" }, s.ToolsScreenTools);
        Assert.Equal(Tools.DefaultShown, store.Get<List<string>>("toolsScreenKnown"));
        s.ToolsScreenTools = new() { "translate", "dictation", "reminder" };
        Assert.Equal(new[] { "translate", "dictation", "reminder" }, new AppSettings(store, secrets).ToolsScreenTools);   // off stays off
        Assert.Equal(SettingsPage.ReadAloud, SettingsGroup.Tools.Pages()[^1]);
    }

    [Fact]
    public void TheSaveFolderIsTheDesktopOrUnderTheUsersFolder()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        Assert.Equal(desktop, AppSettings.FolderPath("~/Desktop"));
        Assert.Equal(Path.Combine(home, "Music", "Readings"), AppSettings.FolderPath("~/Music/Readings"));
        Assert.Equal(@"D:\Readings", AppSettings.FolderPath(@"D:\Readings"));
        Assert.Equal("~/Desktop", AppSettings.FolderSaved(desktop));
        Assert.Equal("~/Music/Readings", AppSettings.FolderSaved(Path.Combine(home, "Music", "Readings")));
    }

    // Sound

    [Fact]
    public void SoundPiecesAreJoinedAndWrittenAsOneWav()
    {
        var pcm = new byte[16_000];      // half a second at 16 kHz, 16-bit mono
        for (var i = 0; i < pcm.Length / 2; i++) BitConverter.GetBytes((short)(Math.Sin(i / 20.0) * 12_000)).CopyTo(pcm, i * 2);
        var tone = ReadAloudTape.Decode(SpeechClient.Wav(pcm, 16_000, 1));
        Assert.NotNull(tone);                                                         // a WAV reply is read
        Assert.True(tone!.Rate == ReadAloudTape.Rate && tone.Channels == 1);
        Assert.True(Math.Abs(tone.Frames - ReadAloudTape.Rate * 0.5) < 50, "16 kHz becomes 24 kHz, the length kept");
        Assert.Null(ReadAloudTape.Decode(new byte[] { 0xFF, 0xFB, 0x90, 0x00 }));     // an MP3 is not joined
        var stereo = ReadAloudTape.Mono(new WaveTape.Pcm(24_000, 2, new short[] { 100, 300, -50, 50 }));
        Assert.Equal(new short[] { 200, 0 }, stereo.Samples);
        var rest = ReadAloudTape.Silence(0.5);
        Assert.Equal(ReadAloudTape.Rate / 2, rest.Frames);
        var joined = ReadAloudTape.Join(new[] { tone, rest, tone });
        Assert.Equal(tone.Frames * 2 + rest.Frames, joined.Frames);

        var settings = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var player = Player(settings);
        Directory.CreateDirectory(dir);
        Assert.Throws<InvalidOperationException>(() => player.Write(Path.Combine(dir, "none.wav")));
        player.Load(new[] { tone, rest, tone });
        Assert.True(player.HasSound && player.IsComplete);
        var file = Path.Combine(dir, R.FileName("Hello there", new DateTime(2026, 11, 1, 14, 32, 5), ReadAloudPlayer.SavedFormat));
        Assert.EndsWith(".wav", file);                                                // M4A or not, Windows writes WAV
        player.Write(file);
        var back = WaveTape.Read(File.ReadAllBytes(file));
        Assert.NotNull(back);
        Assert.True(back!.Rate == 24_000 && back.Channels == 1 && Math.Abs(back.Duration - 1.5) < 0.01, $"{back.Duration} s");
    }

    // Who reads

    [Fact]
    public void ThePartsVoiceIsThePresetsTheCharactersOrTheFirst()
    {
        var secrets = new MemorySecretStore();
        var settings = new AppSettings(new MemorySettingsStore(), secrets) { OpenRouterKey = "sk-test" };
        var player = Player(settings);
        player.Describe = name => name == "Mortimer" ? ("Old and philosophical. Speaks slowly.", "a boxy creature") : null;
        var pool = new[] { "am_adam", "af_bella", "am_michael" };
        var narrator = R.DefaultPresets[0] with { Voice = "af_bella" };
        Assert.Equal("af_bella", player.OnlineVoice(player.PlanFor(narrator), pool, pool));                  // the preset's own voice
        narrator = narrator with { Voice = "Charon" };
        Assert.Equal("am_adam", player.OnlineVoice(player.PlanFor(narrator), pool, pool));                   // not among them: the first
        Assert.Equal("Charon", player.OnlineVoice(player.PlanFor(narrator), Array.Empty<string>(), Array.Empty<string>()));   // no list to check: sent as chosen
        var old = new R.Preset { Name = "Old", Character = "Mortimer" };
        var cast = player.OnlineVoice(player.PlanFor(old), pool, pool);
        Assert.True(cast is "am_adam" or "am_michael", "an old man's voice for an old man: " + cast);
        settings.VoiceModel = R.DefaultModel;
        settings.SetVoice("Mortimer", v => v.OpenRouterVoice = "af_bella");
        Assert.Equal("af_bella", player.OnlineVoice(player.PlanFor(old), pool, pool));                      // his own voice from the Voice page, same model
    }

    [Fact]
    public void NoKeyMeansWindowsReadsItFree()
    {
        var settings = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var player = Player(settings);
        var plan = player.PlanFor(R.DefaultPresets[0]);
        Assert.True(plan.Engine == R.Engine.System && plan.Note is not null && !plan.Engine.IsPaid());
        Assert.Null(player.Estimate("Hello there.", R.DefaultPresets[0]));                                   // free: no price to show
        settings.OpenRouterKey = "sk-test";
        Assert.Equal(R.Engine.OpenRouter, player.PlanFor(R.DefaultPresets[0]).Engine);
        Assert.NotNull(player.Estimate("Hello there.", R.DefaultPresets[0]));                                // Gemini's own price before the list is loaded
    }

    [Fact]
    public void WindowsVoiceSpeaksThePartsLanguageOrThePartIsSkipped()
    {
        Voice.Installed = new[] { David, Zira, Irina };
        Voice.SapiDefault = Zira.Name;
        var settings = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
        var narrator = R.DefaultPresets[0];
        Assert.Equal(Zira, ReadAloudPlayer.WindowsVoice(Translate.English, narrator, settings, _ => null));      // SAPI's own, when it speaks it
        Assert.Equal(Irina, ReadAloudPlayer.WindowsVoice(Translate.Russian, narrator, settings, _ => null));
        Assert.Null(ReadAloudPlayer.WindowsVoice(Translate.Hebrew, narrator, settings, _ => null));             // no Hebrew pack: skipped
        var own = narrator with { Engine = R.Engine.System, Voice = David.Name };
        Assert.Equal(David, ReadAloudPlayer.WindowsVoice(Translate.English, own, settings, _ => null));
        Assert.Equal(Irina, ReadAloudPlayer.WindowsVoice(Translate.Russian, own, settings, _ => null));         // David reads no Russian
        settings.SetVoice("Mortimer", v => v.SystemVoice = David.Name);
        Assert.Equal(David, ReadAloudPlayer.WindowsVoice(Translate.English, new R.Preset { Character = "Mortimer" }, settings, _ => null));
        var bob = ReadAloudPlayer.WindowsVoice(Translate.English, new R.Preset { Character = "Bob" }, settings, _ => ("A grumpy old man.", "a boxy robot"));
        Assert.Equal(David, bob);                                                                                // cast from his persona: a man's voice
    }
}
