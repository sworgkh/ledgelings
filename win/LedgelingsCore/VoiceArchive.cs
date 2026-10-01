using System.Globalization;
using System.Text;

namespace Ledgelings.Core;

/// <summary>
/// Every line a speech model said, kept as a sound file beside the chats, with
/// an index of who said what in which voice. Two uses: the sounds are there to
/// reuse later, and a line that comes round again (the built-in lines repeat)
/// is played from here instead of being paid for twice.
///
/// Layout, under <see cref="Directory"/> (normally <c>%APPDATA%\Ledgelings\voices</c>):
/// <code>
///     voices.jsonl                          one Clip per line, oldest first
///     2026-09-25/221530-Blocky-3f9a1c2e.wav the sound, named by day, time, speaker, key
/// </code>
/// A clip is found again by its <c>Key</c>: the text, model, voice and speed, hashed.
/// The same words in another voice or at another speed are another clip.
/// </summary>
public sealed class VoiceArchive
{
    /// <summary>One kept sound. Properties in alphabetical order, as the Mac writes its keys.</summary>
    public sealed record Clip
    {
        /// <summary>Relative to the archive's folder, with forward slashes like the Mac's.</summary>
        public string File { get; set; } = "";
        public string Key { get; set; } = "";
        public string Model { get; set; } = "";
        public string Speaker { get; set; } = "";
        public double Speed { get; set; }
        public string Text { get; set; } = "";
        public DateTimeOffset Time { get; set; }
        public string Voice { get; set; } = "";
    }

    public string Directory { get; }
    public VoiceArchive(string directory) { Directory = directory; }

    public string Index => Path.Combine(Directory, "voices.jsonl");

    /// <summary>Speed is rounded to the slider's step, so 1.0 and 1.0000001 are one clip.</summary>
    public static string Key(string text, string model, string voice, double speed)
    {
        var hash = Voices.StableHash(string.Join("\u001F", text, model, voice, speed.ToString("F2", CultureInfo.InvariantCulture)));
        return hash.ToString("x16", CultureInfo.InvariantCulture);
    }

    /// <summary>The sound kept for these words in this voice, if its file is still there.</summary>
    public string? Find(string key, IReadOnlyList<Clip> clips)
    {
        var clip = clips.LastOrDefault(c => c.Key == key);
        if (clip is null) return null;
        var path = Path.Combine(Directory, clip.File.Replace('/', Path.DirectorySeparatorChar));
        return System.IO.File.Exists(path) ? path : null;
    }

    /// <summary>Write the sound and add it to the index. Returns what was indexed.
    /// <paramref name="zone"/> names the day and time in the file name; the user's own by default.</summary>
    public Clip Keep(byte[] audio, string speaker, string text, string model, string voice, double speed,
                     string extension = "wav", DateTimeOffset? at = null, TimeZoneInfo? zone = null)
    {
        var key = Key(text, model, voice, speed);
        var raw = at ?? DateTimeOffset.Now;
        // The index keeps whole seconds.
        var time = DateTimeOffset.FromUnixTimeSeconds(raw.ToUnixTimeSeconds());
        var local = TimeZoneInfo.ConvertTime(time, zone ?? TimeZoneInfo.Local);
        var day = local.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var name = local.ToString("HHmmss", CultureInfo.InvariantCulture) + "-" + Safe(speaker) + "-" + key[..8] + "." + extension;
        var folder = Path.Combine(Directory, day);
        System.IO.Directory.CreateDirectory(folder);
        System.IO.File.WriteAllBytes(Path.Combine(folder, name), audio);
        var clip = new Clip { Time = time, Speaker = speaker, Text = text, Model = model, Voice = voice, Speed = speed, File = day + "/" + name, Key = key };
        JsonLines.Append(Index, clip);
        return clip;
    }

    /// <summary>Every clip in the order it was kept. A damaged line is skipped.</summary>
    public List<Clip> Clips() => JsonLines.Read<Clip>(Index);

    /// <summary>Letters, digits, <c>-</c> and <c>_</c> only, so any name makes a safe file name.</summary>
    internal static string Safe(string name)
    {
        var kept = new StringBuilder();
        var count = 0;
        foreach (var rune in name.EnumerateRunes())
        {
            if (count == 24) break;
            kept.Append(IsAlphanumeric(rune) || rune.Value == '-' || rune.Value == '_' ? rune.ToString() : "_");
            count += 1;
        }
        return kept.Length == 0 ? "someone" : kept.ToString();
    }

    /// <summary>Swift's <c>CharacterSet.alphanumerics</c>: letters, marks and numbers of every kind.</summary>
    private static bool IsAlphanumeric(Rune rune) => Rune.GetUnicodeCategory(rune) switch
    {
        UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter
            or UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark
            or UnicodeCategory.DecimalDigitNumber or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber => true,
        _ => false,
    };
}
