using System.Text;
using System.Text.RegularExpressions;

namespace Ledgelings.Core;

/// <summary>One character's own voice settings, set by hand in Settings › Voice. Every
/// field left null is automatic: a voice handed out by <see cref="Voices.Assign(IEnumerable{string}, IReadOnlyList{string})"/>,
/// the global speed, the cartoon lift or small nudge for pitch.</summary>
public sealed record CharacterVoice
{
    /// <summary>A Windows voice name, for the built-in engine.</summary>
    public string? SystemVoice { get; set; }
    /// <summary>One of the speech model's voices, for OpenRouter. Ignored when the
    /// chosen model has no voice by that name.</summary>
    public string? OpenRouterVoice { get; set; }
    /// <summary>One of the local server's voices, for the Local server engine.</summary>
    public string? LocalVoice { get; set; }
    /// <summary>Times the global Speed.</summary>
    public double? Speed { get; set; }
    /// <summary>Times the global Pitch, instead of the automatic lift.</summary>
    public double? Pitch { get; set; }
    /// <summary>Speed follows pitch for this character; null follows the overall setting.</summary>
    public bool? FollowPitch { get; set; }

    public bool IsAutomatic => SystemVoice is null && OpenRouterVoice is null && LocalVoice is null
        && Speed is null && Pitch is null && FollowPitch is null;
}

/// <summary>
/// Who sounds like whom, and what of a line is worth saying out loud. No audio
/// here: the app's <c>Voice</c> does the speaking, this decides what and with which voice.
/// </summary>
public static partial class Voices
{
    /// <summary><see cref="Assign(IEnumerable{string}, IReadOnlyList{string})"/>, with some characters' voices chosen
    /// by hand (<paramref name="fixedVoices"/>, name to voice). They keep theirs; everyone else is handed voices
    /// from what is left of the pool, or from the whole pool when nothing is left.</summary>
    public static Dictionary<string, string> Assign(IEnumerable<string> names, IReadOnlyList<string> pool, IReadOnlyDictionary<string, string> fixedVoices)
    {
        var all = names.ToList();
        var everyone = all.ToHashSet();
        var chosen = fixedVoices.Where(kv => everyone.Contains(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value);
        var free = pool.Where(v => !chosen.ContainsValue(v)).ToList();
        var result = Assign(all.Where(n => !chosen.ContainsKey(n)), free.Count == 0 ? pool : free);
        foreach (var (name, voice) in chosen) result[name] = voice;
        return result;
    }

    /// <summary>
    /// Every character in <paramref name="names"/> gets a voice from <paramref name="pool"/>, and the same name
    /// gets the same voice every launch while the pool stays the same. Two
    /// characters share a voice only once the pool has run out.
    ///
    /// Each name starts from a spot picked by a hash of the name and takes the
    /// first voice nobody has yet, going round the pool. Names are handled in
    /// sorted order, so the answer does not depend on who happens to be first.
    /// </summary>
    public static Dictionary<string, string> Assign(IEnumerable<string> names, IReadOnlyList<string> pool)
    {
        var result = new Dictionary<string, string>();
        if (pool.Count == 0) return result;
        var taken = new HashSet<string>();
        foreach (var name in names.Distinct().OrderBy(n => n, StringComparer.Ordinal))
        {
            var start = (int)(StableHash(name) % (ulong)pool.Count);
            string? free = null;
            for (int k = 0; k < pool.Count; k++)
            {
                var v = pool[(start + k) % pool.Count];
                if (!taken.Contains(v)) { free = v; break; }
            }
            var voice = free ?? pool[start];
            taken.Add(voice);
            result[name] = voice;
        }
        return result;
    }

    /// <summary>A small nudge in 0.9...1.1 that is always the same for a name, so two
    /// characters sharing a voice still do not sound identical.</summary>
    public static double PitchNudge(string name) => 0.9 + 0.2 * (StableHash(name + "#pitch") % 1000) / 999.0;

    /// <summary>The voices in a Kokoro blend, weights dropped: <c>af_bella(2)+am_puck(1)</c>
    /// gives <c>af_bella</c>, <c>am_puck</c>. A plain voice gives itself.</summary>
    public static List<string> BlendParts(string voice) =>
        voice.Split('+', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('(', 2)[0].Trim())
            .Where(p => p.Length > 0)
            .ToList();

    /// <summary>True when <paramref name="voice"/> can be asked for from a server with <paramref name="voices"/>: one of
    /// them, or a blend of them. An empty list means it could not be checked.</summary>
    public static bool IsUsable(string voice, IReadOnlyCollection<string> voices)
    {
        var parts = BlendParts(voice);
        return parts.Count > 0 && (voices.Count == 0 || parts.All(voices.Contains));
    }

    /// <summary>A cartoon lift for a name: 1.15...1.6 times the voice's own pitch, always
    /// the same for a name, so every character squeaks at a height of its own.</summary>
    public static double CartoonPitch(string name) => 1.15 + 0.45 * (StableHash(name + "#cartoon") % 1000) / 999.0;

    /// <summary>Words in a voice's name that mean it is playful rather than a newsreader:
    /// MiniMax's <c>English_AnimeCharacter</c>, Voxtral's <c>en_paul_excited</c>, Kokoro's <c>am_santa</c>.</summary>
    internal static readonly string[] Playful = { "anime", "playful", "whimsical", "comedian", "jovial", "lovely", "upbeat",
        "excited", "cheerful", "happy", "santa", "boy", "girl", "radiant", "kind-hearted" };

    /// <summary>The playful voices of a list when there are at least two, else the list as it is.</summary>
    public static List<string> CartoonFirst(IReadOnlyList<string> voices)
    {
        var fun = voices.Where(v => { var l = v.ToLowerInvariant(); return Playful.Any(l.Contains); }).ToList();
        return fun.Count >= 2 ? fun : voices.ToList();
    }

    /// <summary>
    /// The speed to have a line spoken at, before it is played <paramref name="pitch"/> times
    /// faster (and so that much higher), like a tape.
    ///
    /// Asking for the full <c>speed / pitch</c> keeps the pace exactly, but a voice
    /// asked to speak very slowly stretches its vowels into a smear that sounds
    /// like an echo. With <paramref name="followPitch"/>, it is asked for <c>speed / √pitch</c>, half
    /// the slowdown in musical terms: at a 1.4× cartoon lift it speaks at 0.85×,
    /// which every voice renders cleanly, and the line ends up 1.18× quicker, as
    /// a higher voice naturally would.
    /// </summary>
    public static double AskedSpeed(double speed, double pitch, bool followPitch)
    {
        var lift = Math.Max(pitch, 0.01);
        return followPitch ? speed / Math.Sqrt(lift) : speed / lift;
    }

    /// <summary>FNV-1a over the UTF-8 bytes. .NET's own <c>GetHashCode</c> changes every launch.</summary>
    public static ulong StableHash(string text)
    {
        ulong hash = 0xcbf29ce484222325;
        foreach (var b in Encoding.UTF8.GetBytes(text)) hash = unchecked((hash ^ b) * 0x00000100000001b3);
        return hash;
    }

    /// <summary>The English voices of a speech model's list, when its names say which
    /// they are; otherwise the whole list. Providers mark language in the name:
    /// <c>flux-kit-en</c>, <c>en_paul_happy</c>, <c>gb_jane_sad</c>, <c>English_Comedian</c>,
    /// <c>en-US-Harper:MAI-Voice-2</c>, Kokoro's <c>af_bella</c> / <c>bm_george</c>.</summary>
    public static List<string> EnglishFirst(IReadOnlyList<string> voices)
    {
        // Orpheus names its voices like people, with no language mark; its
        // English ones are these eight, the rest French, German, Korean and so on.
        var orpheus = voices.Where(OrpheusEnglish.Contains).ToList();
        if (orpheus.Count >= 4) return orpheus;
        var english = voices.Where(IsEnglish).ToList();
        return english.Count == 0 ? voices.ToList() : english;
    }

    internal static readonly HashSet<string> OrpheusEnglish = new() { "tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe" };

    internal static bool IsEnglish(string voice)
    {
        var v = voice.ToLowerInvariant();
        if (v.EndsWith("-en", StringComparison.Ordinal) || v.StartsWith("en_", StringComparison.Ordinal) || v.StartsWith("gb_", StringComparison.Ordinal)
            || v.StartsWith("en-", StringComparison.Ordinal) || v.StartsWith("english_", StringComparison.Ordinal)) return true;
        // Kokoro: first letter is the language (a = American, b = British), second the sex.
        var parts = v.Split('_', 2);
        return parts.Length == 2 && parts[0] is "af" or "am" or "bf" or "bm";
    }

    /// <summary>The line as it should be heard: no emoji, no *stage directions*, no
    /// markdown marks, no runs of spaces. Empty when nothing sayable is left.</summary>
    public static string Speakable(string line)
    {
        var text = Regex.Replace(line, @"\*\*(.+?)\*\*", "$1");       // **bold** is said
        text = Regex.Replace(text, @"\*[^*]+\*", " ");                 // *sighs* is not
        var kept = new StringBuilder(text.Length);
        foreach (var rune in text.EnumerateRunes())
        {
            var v = rune.Value;
            if (IsEmoji(v) || v == 0xFE0F || v == 0x200D || "*_~`#".Contains((char)Math.Min(v, 0xFFFF))) continue;
            kept.Append(rune.ToString());
        }
        var words = kept.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return Regex.Replace(string.Join(" ", words), @" ([.,!?;:])", "$1");
    }
}
