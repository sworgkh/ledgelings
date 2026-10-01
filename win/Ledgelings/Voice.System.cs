using System.Globalization;
using System.Security;
using System.Speech.Synthesis;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// Windows' own voices, through SAPI (<c>System.Speech</c>). The Mac speaks its voices
/// live and they report each word; here every line is rendered to a WAV first and
/// played through the same player as a downloaded clip, so all three engines sound,
/// pitch and time their bubbles the same way.
/// </summary>
public sealed partial class Voice
{
    /// <summary>One installed Windows voice: its name (what the settings keep, and what
    /// SAPI selects by), its language, and the sex and age it reports.</summary>
    public sealed record SystemVoiceInfo(string Name, string Culture, VoiceGender Gender, VoiceAge Age);

    private static IReadOnlyList<SystemVoiceInfo>? installed;
    private static string? sapiDefault;

    /// <summary>Every enabled SAPI voice on this PC; none when speech is not available. Tests set a pretend list.</summary>
    public static IReadOnlyList<SystemVoiceInfo> Installed
    {
        get
        {
            if (installed is not null) return installed;
            try
            {
                using var synth = new SpeechSynthesizer();
                installed = synth.GetInstalledVoices().Where(v => v.Enabled)
                    .Select(v => new SystemVoiceInfo(v.VoiceInfo.Name, v.VoiceInfo.Culture?.Name ?? "", v.VoiceInfo.Gender, v.VoiceInfo.Age))
                    .ToList();
                sapiDefault = synth.Voice?.Name;
            }
            catch (Exception e) when (e is PlatformNotSupportedException or InvalidOperationException or TypeInitializationException)
            {
                installed = Array.Empty<SystemVoiceInfo>();
            }
            return installed;
        }
        set => installed = value;
    }

    /// <summary>The voice SAPI speaks with when asked for none (Settings › Time &amp; language › Speech);
    /// null when speech is not available. Tests set it with <see cref="Installed"/>.</summary>
    public static string? SapiDefault
    {
        get { _ = Installed; return sapiDefault; }
        set => sapiDefault = value;
    }

    /// <summary>Windows' voices in the app's language (English when there are none), for choosing one.</summary>
    public static IReadOnlyList<SystemVoiceInfo> SystemVoices
    {
        get
        {
            var language = VoiceLanguage;
            return Installed.Where(v => v.Culture.StartsWith(language, StringComparison.OrdinalIgnoreCase))
                .OrderBy(v => v.Name, StringComparer.Ordinal).ThenBy(v => v.Culture, StringComparer.Ordinal).ToList();
        }
    }

    /// <summary>The language code Windows' voices are taken in: the app's, when this PC has a
    /// voice for it (Microsoft Irina Desktop for Russian, once Windows' Russian speech pack is
    /// installed), else English.</summary>
    public static string VoiceLanguage
    {
        get
        {
            var code = Languages.Current.Code();
            return Installed.Any(v => v.Culture.StartsWith(code, StringComparison.OrdinalIgnoreCase)) ? code : "en";
        }
    }

    /// <summary>The region whose voice wins when two share a name: the user's own for English,
    /// the language's home otherwise (RU for Russian).</summary>
    public static string VoiceRegion
    {
        get
        {
            var language = VoiceLanguage;
            if (language == "en") return RegionInfo.CurrentRegion.TwoLetterISORegionName;
            return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == language
                ? RegionInfo.CurrentRegion.TwoLetterISORegionName : language.ToUpperInvariant();
        }
    }

    /// <summary>True for an installed Windows voice in <paramref name="language"/> (a <see cref="VoiceLanguage"/>);
    /// false for an empty or unknown one.</summary>
    public static bool Speaks(string? voice, string language) =>
        !string.IsNullOrEmpty(voice)
        && Installed.FirstOrDefault(v => v.Name == voice)?.Culture.StartsWith(language, StringComparison.OrdinalIgnoreCase) == true;

    /// <summary>The voice for a line with none chosen: null, SAPI's own, when that speaks the app's
    /// language; else Windows' voice for the language (Irina on an English Windows with the Russian pack).</summary>
    public static string? DefaultVoice
    {
        get
        {
            var language = VoiceLanguage;
            if (SapiDefault is null || Speaks(SapiDefault, language)) return null;
            var pool = CharacterPool;
            return (pool.FirstOrDefault(v => v.Culture.EndsWith(VoiceRegion, StringComparison.OrdinalIgnoreCase)) ?? pool.FirstOrDefault())?.Name;
        }
    }

    /// <summary>The voices handed out one per character: each name once, the language's own region first.
    /// Windows has no character or novelty voices (the Mac's Grandpa, Zarvox), so Cartoon voices
    /// changes the pitch here, not the pool.</summary>
    public static IReadOnlyList<SystemVoiceInfo> CharacterPool
    {
        get
        {
            var region = VoiceRegion;
            var byName = new Dictionary<string, SystemVoiceInfo>();
            foreach (var voice in SystemVoices)
            {
                if (byName.TryGetValue(voice.Name, out var kept)
                    && (kept.Culture.EndsWith(region, StringComparison.OrdinalIgnoreCase) || !voice.Culture.EndsWith(region, StringComparison.OrdinalIgnoreCase))) continue;
                byName[voice.Name] = voice;
            }
            return byName.Values.OrderBy(v => v.Name, StringComparer.Ordinal).ToList();
        }
    }

    /// <summary>The Windows voices handed out one per character.</summary>
    public IReadOnlyList<SystemVoiceInfo> SystemPool => CharacterPool;

    /// <summary>A Windows voice's tags: from its name, and the sex and age SAPI reports.</summary>
    public static HashSet<Casting.Tag> TagsOf(SystemVoiceInfo voice)
    {
        var tags = Casting.TagsOfVoice(voice.Name, voice.Name);
        if (voice.Gender == VoiceGender.Female) tags.Add(Casting.Tag.Female);
        else if (voice.Gender == VoiceGender.Male) tags.Add(Casting.Tag.Male);
        if (voice.Age == VoiceAge.Senior) tags.Add(Casting.Tag.Old);
        else if (voice.Age is VoiceAge.Child or VoiceAge.Teen) tags.Add(Casting.Tag.Young);
        return tags;
    }

    /// <summary>
    /// A Windows voice. With speed following pitch (the default), the line is rendered
    /// at the asked speed and natural pitch, then played <c>pitch</c> times faster like a
    /// tape, as the Mac does for its voices. Without, SAPI is asked for the pitch itself
    /// (SSML prosody) and the clip plays as rendered. The bubble types over the clip's length.
    /// </summary>
    private bool SpeakHere(string line, string name, IReadOnlyList<string> cast, Action<Cue>? cue)
    {
        var voice = SystemVoiceFor(name, cast) ?? DefaultVoice;
        var pitch = Pitch(name);
        var follow = FollowsPitch(name);
        var asked = follow ? Voices.AskedSpeed(Speed(name), pitch, followPitch: true) : Speed(name);
        double? sapiPitch = follow ? null : Math.Clamp(pitch, 0.5, 2);
        var culture = Installed.FirstOrDefault(v => v.Name == voice)?.Culture;
        var rendered = Task.Run(() => Render(line, voice, asked, sapiPitch, culture));
        Enqueue(async cancel =>
        {
            var audio = await rendered;
            if (audio.Length == 0 || cancel.IsCancellationRequested) return false;
            Status = $"{name}: {voice ?? L10n.Tr("system voice")}";
            await Play(audio, follow ? pitch : 1, Estimate(line, Speed(name)), duration => Tell(cue, new Cue.Started(duration)), cancel);
            return true;
        }, cue);
        return true;
    }

    /// <summary>The line as a WAV, not played. <paramref name="speed"/> is a multiplier; SAPI's rate
    /// runs from −10 to 10, a third as fast to three times as fast.</summary>
    private static byte[] Render(string line, string? voice, double speed, double? pitch, string? culture)
    {
        using var synth = new SpeechSynthesizer();
        if (voice is not null)
        {
            try { synth.SelectVoice(voice); }
            catch (ArgumentException) { }      // uninstalled since it was chosen: the default speaks
        }
        synth.Rate = (int)Math.Clamp(Math.Round(10 * Math.Log(Math.Max(speed, 0.01)) / Math.Log(3)), -10, 10);
        using var stream = new MemoryStream();
        synth.SetOutputToWaveStream(stream);
        if (pitch is double p && Math.Abs(p - 1) > 0.005)
        {
            var percent = Math.Round((p - 1) * 100).ToString("+0;-0", CultureInfo.InvariantCulture);
            var lang = string.IsNullOrEmpty(culture) ? synth.Voice.Culture?.Name ?? "en-US" : culture;
            synth.SpeakSsml($"<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"{lang}\">"
                            + $"<prosody pitch=\"{percent}%\">{SecurityElement.Escape(line)}</prosody></speak>");
        }
        else synth.Speak(line);
        synth.SetOutputToNull();
        return stream.ToArray();
    }
}
