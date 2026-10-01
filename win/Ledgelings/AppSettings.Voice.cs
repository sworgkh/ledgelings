using System.ComponentModel;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Who reads the lines out loud: Windows' own voices, a speech model on OpenRouter, or a local speech server.</summary>
public enum VoiceEngine { System, OpenRouter, Local }

/// <summary>Voice: whether the lines are read out loud, by which engine, and how each character sounds.</summary>
public sealed partial class AppSettings
{
    /// <summary>Kokoro-FastAPI's own address and model name; any server speaking
    /// OpenAI's <c>/v1/audio/speech</c> will do.</summary>
    public const string DefaultLocalVoiceServer = "http://localhost:8880";
    public const string DefaultLocalVoiceModel = "kokoro";
    /// <summary>Kokoro: dozens of English voices for about $0.00003 a line. The free
    /// speech models have daily limits the creatures would run into.</summary>
    public const string DefaultVoiceModel = "hexgrad/kokoro-82m";
    public const double VoiceSpeedMin = 0.5, VoiceSpeedMax = 2.0;
    public const double VoicePitchMin = 0.5, VoicePitchMax = 2.0;
    public const double VoiceVolumeMin = 0, VoiceVolumeMax = 1;
    /// <summary>With voice on, how long after one line ends the next begins.</summary>
    public const double VoiceTurnPauseMin = 0, VoiceTurnPauseMax = 2.0;

    private bool voiceEnabled, voicePerCharacter, cartoonVoices, castByPersonality, speedFollowsPitch, keepVoices, reuseLineVoices;
    private VoiceEngine voiceEngine;
    private string systemVoice = "", voiceModel = "", openRouterVoice = "", localVoiceServer = "", localVoiceModel = "", localVoice = "";
    private double voiceSpeed, voicePitch, voiceVolume, voiceTurnPause;
    private Dictionary<string, CharacterVoice> characterVoices = new();

    public static string VoiceEngineTitle(VoiceEngine engine) => engine switch
    {
        VoiceEngine.System => L10n.Tr("Built-in voices"),
        VoiceEngine.OpenRouter => Ledgelings.ChatClient.Title(Ledgelings.ChatClient.Provider.OpenRouter),
        _ => L10n.Tr("Local server"),
    };

    /// <summary>How the engine is written in the settings file: the macOS app's words.</summary>
    private static string VoiceEngineKey(VoiceEngine engine) => engine switch { VoiceEngine.System => "system", VoiceEngine.OpenRouter => "openRouter", _ => "local" };

    private void LoadVoice()
    {
        // Off by default: a desktop pet that starts talking out loud unasked is a surprise.
        voiceEnabled = store.Get<bool?>("voiceEnabled") ?? false;
        voiceEngine = Enum.TryParse<VoiceEngine>(store.Get<string>("voiceEngine"), true, out var e) ? e : VoiceEngine.System;
        voicePerCharacter = store.Get<bool?>("voicePerCharacter") ?? true;
        systemVoice = store.Get<string>("systemVoice") ?? "";
        voiceModel = store.Get<string>("voiceModel") ?? DefaultVoiceModel;
        openRouterVoice = store.Get<string>("openRouterVoice") ?? "";
        localVoiceServer = store.Get<string>("localVoiceServer") ?? DefaultLocalVoiceServer;
        localVoiceModel = store.Get<string>("localVoiceModel") ?? DefaultLocalVoiceModel;
        localVoice = store.Get<string>("localVoice") ?? "";
        voiceSpeed = Math.Clamp(store.Get<double?>("voiceSpeed") ?? 1, VoiceSpeedMin, VoiceSpeedMax);
        voicePitch = Math.Clamp(store.Get<double?>("voicePitch") ?? 1, VoicePitchMin, VoicePitchMax);
        voiceVolume = Math.Clamp(store.Get<double?>("voiceVolume") ?? 0.8, VoiceVolumeMin, VoiceVolumeMax);
        characterVoices = store.Get<Dictionary<string, CharacterVoice>>("characterVoices") ?? new Dictionary<string, CharacterVoice>();
        // Paid-for sounds are kept unless asked not to; the built-in lines are made once.
        keepVoices = store.Get<bool?>("keepVoices") ?? true;
        reuseLineVoices = store.Get<bool?>("reuseLineVoices") ?? true;
        // Clean sound by default, voices that fit who they are, a natural beat between a line and its answer.
        speedFollowsPitch = store.Get<bool?>("speedFollowsPitch") ?? true;
        castByPersonality = store.Get<bool?>("castByPersonality") ?? true;
        voiceTurnPause = Math.Clamp(store.Get<double?>("voiceTurnPause") ?? 0.35, VoiceTurnPauseMin, VoiceTurnPauseMax);
        // Desktop pets, not newsreaders.
        cartoonVoices = store.Get<bool?>("cartoonVoices") ?? true;
    }

    public bool VoiceEnabled { get => voiceEnabled; set => Put(ref voiceEnabled, value, "voiceEnabled"); }

    public VoiceEngine VoiceEngine
    {
        get => voiceEngine;
        set
        {
            if (voiceEngine == value) return;
            voiceEngine = value;
            store.Set("voiceEngine", VoiceEngineKey(value));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(VoiceEngine)));
            Changed?.Invoke();
        }
    }

    /// <summary>Every character gets a voice of its own; off, everyone uses the one chosen below.</summary>
    public bool VoicePerCharacter { get => voicePerCharacter; set => Put(ref voicePerCharacter, value, "voicePerCharacter"); }
    /// <summary>A voice name from Windows' list; empty means the system default.</summary>
    public string SystemVoice { get => systemVoice; set => Put(ref systemVoice, value, "systemVoice"); }
    public string VoiceModel { get => voiceModel; set => Put(ref voiceModel, value, "voiceModel"); }
    /// <summary>One of the model's voices; empty means its first.</summary>
    public string OpenRouterVoice { get => openRouterVoice; set => Put(ref openRouterVoice, value, "openRouterVoice"); }
    /// <summary>A speech server on this PC: its address (without <c>/v1</c>), model and voice (empty = its first).</summary>
    public string LocalVoiceServer { get => localVoiceServer; set => Put(ref localVoiceServer, value, "localVoiceServer"); }
    public string LocalVoiceModel { get => localVoiceModel; set => Put(ref localVoiceModel, value, "localVoiceModel"); }
    public string LocalVoice { get => localVoice; set => Put(ref localVoice, value, "localVoice"); }
    /// <summary>1 is normal speed, for every engine.</summary>
    public double VoiceSpeed { get => voiceSpeed; set => Put(ref voiceSpeed, Math.Clamp(value, VoiceSpeedMin, VoiceSpeedMax), "voiceSpeed"); }
    /// <summary>Squeakier and sillier: each character's pitch lifted by its own amount, and
    /// the playful voices (AnimeCharacter, en_paul_excited) first.</summary>
    public bool CartoonVoices { get => cartoonVoices; set => Put(ref cartoonVoices, value, "cartoonVoices"); }
    /// <summary>1 is the voice's own pitch. Every engine: the clips are shifted as they play.</summary>
    public double VoicePitch { get => voicePitch; set => Put(ref voicePitch, Math.Clamp(value, VoicePitchMin, VoicePitchMax), "voicePitch"); }
    public double VoiceVolume { get => voiceVolume; set => Put(ref voiceVolume, Math.Clamp(value, VoiceVolumeMin, VoiceVolumeMax), "voiceVolume"); }
    /// <summary>With voice on, how long after one line ends the next begins. Replaces the
    /// silent-bubble timing, which knows nothing of how long a line takes to say.</summary>
    public double VoiceTurnPause { get => voiceTurnPause; set => Put(ref voiceTurnPause, Math.Clamp(value, VoiceTurnPauseMin, VoiceTurnPauseMax), "voiceTurnPause"); }
    /// <summary>Automatic voices fit each character's description and species (old,
    /// tiny, cheerful, robot, ghost…), pitch and speed included. Off: handed
    /// out by name, only different from each other.</summary>
    public bool CastByPersonality { get => castByPersonality; set => Put(ref castByPersonality, value, "castByPersonality"); }
    /// <summary>Raising the pitch also quickens the talk a little (by √pitch), so no voice
    /// is ever asked to drawl, which is what smears into an echo. Off: the pace
    /// is kept exactly, at the cost of some smear on big lifts.</summary>
    public bool SpeedFollowsPitch { get => speedFollowsPitch; set => Put(ref speedFollowsPitch, value, "speedFollowsPitch"); }
    /// <summary>Every line a speech model says is kept as a sound file beside the chats.</summary>
    public bool KeepVoices { get => keepVoices; set => Put(ref keepVoices, value, "keepVoices"); }
    /// <summary>The built-in lines' sounds (OpenRouter or the local server) are kept once
    /// made and played from disk after that, instead of being made every time.</summary>
    public bool ReuseLineVoices { get => reuseLineVoices; set => Put(ref reuseLineVoices, value, "reuseLineVoices"); }

    /// <summary>Each character's own voice, speed and pitch, by name; absent means automatic.</summary>
    public IReadOnlyDictionary<string, CharacterVoice> CharacterVoices => characterVoices;

    /// <summary>One character's own settings, or all-automatic ones.</summary>
    public CharacterVoice VoiceOf(string name) => characterVoices.TryGetValue(name, out var v) ? v with { } : new CharacterVoice();

    /// <summary>Change one character's voice settings; all automatic again forgets them.</summary>
    public void SetVoice(string name, Action<CharacterVoice> change)
    {
        var own = VoiceOf(name);
        change(own);
        if (own.IsAutomatic) { if (!characterVoices.Remove(name)) return; }
        else if (characterVoices.TryGetValue(name, out var before) && before == own) return;
        else characterVoices[name] = own;
        store.Set("characterVoices", characterVoices);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CharacterVoices)));
        Changed?.Invoke();
    }

    /// <summary>The local speech server's <c>/v1</c> root, or null when the address is not a URL.</summary>
    public string? LocalVoiceUrl =>
        Uri.TryCreate(localVoiceServer.Trim(), UriKind.Absolute, out var uri) && !string.IsNullOrEmpty(uri.Host)
            ? uri.ToString().TrimEnd('/') + "/v1" : null;
}
