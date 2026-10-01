using System.Speech.Synthesis;
using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>What the app says while it runs, and who says it out loud, in Russian:
/// statuses and errors in Russian, and lines read by voices that can (the Mac's
/// <c>RuntimeLanguageTests</c>). Windows' voices are a pretend list, so the test does
/// not depend on which speech packs this PC has.</summary>
[Collection("windows voices")]
public sealed class RuntimeLanguageTests : IDisposable
{
    private static readonly Voice.SystemVoiceInfo David = new("Microsoft David Desktop", "en-US", VoiceGender.Male, VoiceAge.Adult);
    private static readonly Voice.SystemVoiceInfo Zira = new("Microsoft Zira Desktop", "en-US", VoiceGender.Female, VoiceAge.Adult);
    private static readonly Voice.SystemVoiceInfo Irina = new("Microsoft Irina Desktop", "ru-RU", VoiceGender.Female, VoiceAge.Adult);

    private readonly string dir = Path.Combine(Path.GetTempPath(), "ledgelings-runtime-language-" + Guid.NewGuid());
    private readonly IReadOnlyList<Voice.SystemVoiceInfo> installedBefore = Voice.Installed;
    private readonly string? defaultBefore = Voice.SapiDefault;
    private readonly AppSettings settings = new(new MemorySettingsStore(), new MemorySecretStore());

    public void Dispose()
    {
        Voice.Installed = installedBefore;
        Voice.SapiDefault = defaultBefore;
        try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private Voice MakeVoice() =>
        new(settings, new SpendLedger(Path.Combine(dir, "spend")), archive: Path.Combine(dir, "voices"), lineArchive: Path.Combine(dir, "line-voices"));

    private static void Pretend(string sapiDefault, params Voice.SystemVoiceInfo[] voices)
    {
        Voice.Installed = voices;
        Voice.SapiDefault = sapiDefault;
    }

    private static bool Cyrillic(string s) => s.Any(c => c is >= 'Ѐ' and <= 'ӿ');

    [Fact]
    public void WindowsVoicesAreTheAppsLanguageAndEnglishWithoutOne()
    {
        Pretend(David.Name, David, Zira, Irina);
        Assert.Equal(new[] { Irina.Name }, Languages.With(Language.Russian, () => Voice.SystemVoices.Select(v => v.Name).ToArray()));
        Assert.Equal(new[] { David.Name, Zira.Name }, Languages.With(Language.English, () => Voice.SystemVoices.Select(v => v.Name).ToArray()));
        // No Russian speech pack: the English voices read it, as before.
        Pretend(David.Name, David, Zira);
        Assert.Equal("en", Languages.With(Language.Russian, () => Voice.VoiceLanguage));
        Assert.Equal(new[] { David.Name, Zira.Name }, Languages.With(Language.Russian, () => Voice.SystemVoices.Select(v => v.Name).ToArray()));
    }

    [Fact]
    public void AnEnglishVoiceChosenByHandDoesNotReadRussian()
    {
        Pretend(David.Name, David, Zira, Irina);
        settings.VoiceEngine = VoiceEngine.System;
        settings.VoicePerCharacter = true;
        settings.SetVoice("Blocky", v => v.SystemVoice = David.Name);
        var voice = MakeVoice();
        string[] cast = { "Blocky", "Pip" };
        Assert.Equal(David.Name, Languages.With(Language.English, () => voice.SystemVoiceFor("Blocky", cast)));
        Assert.Equal(Irina.Name, Languages.With(Language.Russian, () => voice.SystemVoiceFor("Blocky", cast)));
        // One voice for everyone: an English one gives way to the Russian default.
        settings.VoicePerCharacter = false;
        settings.SystemVoice = David.Name;
        Assert.Null(Languages.With(Language.Russian, () => voice.SystemVoiceFor("Blocky", Array.Empty<string>())));
        Assert.Equal(Irina.Name, Languages.With(Language.Russian, () => Voice.DefaultVoice));
        // SAPI's own default already speaks Russian: it is left to speak.
        Pretend(Irina.Name, David, Irina);
        Assert.Null(Languages.With(Language.Russian, () => Voice.DefaultVoice));
        // And in English, an English default needs nothing.
        Pretend(David.Name, David, Irina);
        Assert.Null(Languages.With(Language.English, () => Voice.DefaultVoice));
    }

    [Fact]
    public void AnOnlineVoiceOfAnotherLanguageGivesWayToARussianOne()
    {
        settings.VoiceEngine = VoiceEngine.OpenRouter;
        settings.VoicePerCharacter = true;
        settings.SetVoice("Blocky", v => v.OpenRouterVoice = "en_paul");
        var voice = MakeVoice();
        string[] voices = { "en_paul", "en_jane", "ru_olga", "ru_ivan" };
        string[] cast = { "Blocky" };
        Assert.Equal("en_paul", Languages.With(Language.English, () => voice.OnlineVoice("Blocky", cast, voices)));
        Assert.StartsWith("ru_", Languages.With(Language.Russian, () => voice.OnlineVoice("Blocky", cast, voices)) ?? "");
        // Voices that say nothing of their language keep the one chosen.
        settings.SetVoice("Blocky", v => v.OpenRouterVoice = "alloy");
        Assert.Equal("alloy", Languages.With(Language.Russian, () => voice.OnlineVoice("Blocky", cast, new[] { "alloy", "echo" })));
    }

    [Fact]
    public void WhatIsGoingOnIsSaidInRussian()
    {
        Languages.With(Language.Russian, () =>
        {
            Assert.True(Cyrillic(AppSettings.NeedsModel));
            Assert.True(Cyrillic(AppSettings.BrainTitle(BrainKind.Script)) && Cyrillic(AppSettings.VoiceEngineTitle(VoiceEngine.System)));
            Assert.Equal("Встроенные реплики", AppSettings.BrainTitle(BrainKind.Script));
            Assert.True(Cyrillic(ChatClient.Failure.ServerDown("x").Message));
            Assert.True(Cyrillic(ChatClient.Failure.ServerDown(L10n.Tr("timed out")).Message.Split(':')[1]));
            Assert.True(Cyrillic(LaunchAtLogin.Status));
            Assert.True(Cyrillic(MakeVoice().Status));
            Assert.True(Cyrillic(new SpeechClient.SpeechModel("m", "m", 1, null, Array.Empty<string>()).PriceLabel));
        });
        Languages.With(Language.English, () => Assert.Equal("Built-in lines", AppSettings.BrainTitle(BrainKind.Script)));
    }
}
