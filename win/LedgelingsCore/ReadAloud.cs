using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Ledgelings.Core;

/// <summary>
/// Read aloud (SPEC §7.16), the Mac's <c>ReadAloud.swift</c>: text in, audio out. Pasted or typed text is cut
/// into parts at paragraph and sentence ends, each part's language told by its letters, and each part read by a
/// speech model (or Windows' own voices) in a preset's voice and pace. The parts play as they arrive; the whole
/// reading can be saved as one sound file or put on the clipboard as one.
///
/// Everything here is plain logic: the parts, the presets, the voice that fits a language, the price before
/// sending, the buttons' pictures and words. The sound itself is made and played by the app.
/// </summary>
public static partial class ReadAloud
{
    // Engines

    /// <summary>Who reads: a speech model on OpenRouter, Windows' own voices, or a speech server on this computer.</summary>
    public enum Engine { OpenRouter, System, Local }

    /// <summary>The name saved: the Mac's <c>openRouter</c>, <c>system</c>, <c>local</c>.</summary>
    public static string Code(this Engine engine) => engine switch
    {
        Engine.OpenRouter => "openRouter",
        Engine.System => "system",
        _ => "local",
    };

    public static Engine? EngineNamed(string? code) => Enum.GetValues<Engine>().Cast<Engine?>().FirstOrDefault(e => e!.Value.Code() == code);

    public static string Title(this Engine engine) => engine switch
    {
        Engine.OpenRouter => L10n.Tr("OpenRouter speech model"),
        Engine.System => L10n.Tr("Windows' own voices"),
        _ => L10n.Tr("Local speech server"),
    };

    /// <summary>A paid call, priced on Settings › Costs; the others are free.</summary>
    public static bool IsPaid(this Engine engine) => engine == Engine.OpenRouter;

    /// <summary>Gemini 3.8 Flash Lite TTS: one voice list for every language (Hebrew too), a natural read, about a
    /// cent per thousand characters. The Mac measured it against Kokoro (English only) and MAI Voice 2.1 Flash (no Hebrew).</summary>
    public const string DefaultModel = "google/gemini-3.8-flash-lite-tts";

    // Presets

    public const double SpeedMin = 0.5, SpeedMax = 2.0;
    public const double PauseMin = 0, PauseMax = 3.0;
    public const double DefaultPause = 0.6;

    /// <summary>A ready-made way of reading: who reads (the engine, the model, a voice), as whom (a character, or a
    /// narrator), how fast, and how long it rests at the end of a paragraph. Saved in the settings as the Mac saves
    /// it (the fields <c>id, name, engine, model, voice, character, speed, pause, language</c>); the owner adds,
    /// renames and deletes their own.</summary>
    [JsonConverter(typeof(PresetJson))]
    public sealed record Preset
    {
        public Guid Id { get; init; } = Guid.NewGuid();
        public string Name { get; init; } = "";
        public Engine Engine { get; init; } = Engine.OpenRouter;
        /// <summary>The OpenRouter model; empty: <see cref="DefaultModel"/>.</summary>
        public string Model { get; init; } = "";
        /// <summary>One of the model's voices, or a Windows voice's name; empty: chosen for the character (cast
        /// from its persona) or the narrator's first.</summary>
        public string Voice { get; init; } = "";
        /// <summary>A character's name, from any species' cast; empty: a narrator.</summary>
        public string Character { get; init; } = "";
        /// <summary>1 is the voice's own pace.</summary>
        public double Speed { get; init; } = 1;
        /// <summary>Seconds of quiet at the end of each paragraph.</summary>
        public double Pause { get; init; } = DefaultPause;
        /// <summary>"en", "ru" or "he" to read everything as that language; empty: told per part.</summary>
        public string Language { get; init; } = "";

        /// <summary>The numbers inside their ranges, a known language or none, a name.</summary>
        public Preset Clamped()
        {
            var name = Name.Trim();
            return this with
            {
                Speed = Math.Round(Math.Clamp(Speed, SpeedMin, SpeedMax) * 20, MidpointRounding.AwayFromZero) / 20,
                Pause = Math.Round(Math.Clamp(Pause, PauseMin, PauseMax) * 10, MidpointRounding.AwayFromZero) / 10,
                Language = Translate.Language(Language) is null ? "" : Language,
                Name = name.Length == 0 ? L10n.Tr("Preset") : name,
                Model = Model.Trim(' ', '\t'),
            };
        }

        /// <summary>The model this preset asks.</summary>
        public string ModelOrDefault => Model.Length == 0 ? DefaultModel : Model;

        /// <summary>Its name in the app's language: a shipped preset's name is translated, the owner's own is shown as written.</summary>
        public string Title => L10n.Tr(Name);

        /// <summary>The language it forces, if any.</summary>
        public Translate.Lang? ForcedLanguage => Translate.Language(Language);
    }

    /// <summary>The Mac's JSON for a preset, read leniently: a missing or unknown field takes its default, numbers
    /// are clamped. Anything but an object is not a preset, and the whole list falls back to the shipped ones.</summary>
    public sealed class PresetJson : JsonConverter<Preset>
    {
        public override Preset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            var e = doc.RootElement;
            if (e.ValueKind != JsonValueKind.Object) throw new JsonException("a preset is an object");
            string? Str(string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
            double? Num(string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d) && double.IsFinite(d) ? d : null;
            return new Preset
            {
                Id = Guid.TryParse(Str("id"), out var id) ? id : Guid.NewGuid(),
                Name = Str("name") ?? "",
                Engine = EngineNamed(Str("engine")) ?? Engine.OpenRouter,
                Model = Str("model") ?? "",
                Voice = Str("voice") ?? "",
                Character = Str("character") ?? "",
                Speed = Num("speed") ?? 1,
                Pause = Num("pause") ?? DefaultPause,
                Language = Str("language") ?? "",
            }.Clamped();
        }

        public override void Write(Utf8JsonWriter writer, Preset value, JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            writer.WriteString("id", IdString(value.Id));
            writer.WriteString("name", value.Name);
            writer.WriteString("engine", value.Engine.Code());
            writer.WriteString("model", value.Model);
            writer.WriteString("voice", value.Voice);
            writer.WriteString("character", value.Character);
            writer.WriteNumber("speed", value.Speed);
            writer.WriteNumber("pause", value.Pause);
            writer.WriteString("language", value.Language);
            writer.WriteEndObject();
        }
    }

    /// <summary>A preset's id as the Mac writes a UUID: upper case, with dashes.</summary>
    public static string IdString(Guid id) => id.ToString("D").ToUpperInvariant();

    /// <summary>The shipped presets, with fixed ids so the default survives a relaunch (the Mac's). Editable like any other.</summary>
    public static readonly IReadOnlyList<Preset> DefaultPresets = new[]
    {
        new Preset { Id = Guid.Parse("6E61722D-0000-4000-8000-000000000001"), Name = "Narrator", Voice = "Charon", Speed = 1, Pause = 0.6 },
        new Preset { Id = Guid.Parse("6E61722D-0000-4000-8000-000000000002"), Name = "Quick skim", Voice = "Puck", Speed = 1.6, Pause = 0.2 },
        new Preset { Id = Guid.Parse("6E61722D-0000-4000-8000-000000000003"), Name = "Bedtime", Character = "Zed", Speed = 0.8, Pause = 1.2 },
        new Preset { Id = Guid.Parse("6E61722D-0000-4000-8000-000000000004"), Name = "Robot", Character = "Unit 7", Speed = 1.1, Pause = 0.4 },
        new Preset { Id = Guid.Parse("6E61722D-0000-4000-8000-000000000005"), Name = "Russian", Voice = "Kore", Speed = 1, Pause = 0.6, Language = "ru" },
    };

    /// <summary>The default of the defaults: the narrator.</summary>
    public static Guid DefaultPresetId => DefaultPresets[0].Id;

    /// <summary>At most this many presets, so each keeps a number key on the sheet.</summary>
    public const int MostPresets = 9;

    /// <summary>Presets as saved: each id once, at most <see cref="MostPresets"/>, the shipped ones when none are left.</summary>
    public static IReadOnlyList<Preset> Cleaned(IEnumerable<Preset> presets)
    {
        var seen = new HashSet<Guid>();
        var kept = presets.Select(p => p.Clamped()).Where(p => seen.Add(p.Id)).Take(MostPresets).ToList();
        return kept.Count == 0 ? DefaultPresets.ToList() : kept;
    }

    /// <summary>A name not yet taken: "My preset", "My preset 2"…</summary>
    public static string FreeName(string wanted, IEnumerable<Preset> presets)
    {
        var taken = presets.Select(p => p.Name.ToLowerInvariant()).ToHashSet();
        if (!taken.Contains(wanted.ToLowerInvariant())) return wanted;
        var n = 2;
        while (taken.Contains($"{wanted} {n}".ToLowerInvariant())) n++;
        return $"{wanted} {n}";
    }

    /// <summary>The preset with the reader and pace chosen on the sheet: another reader than the preset's gets a
    /// voice cast for that reader, not the preset's own.</summary>
    public static Preset Chosen(Preset preset, string reader, double speed)
    {
        var p = preset.Character == reader ? preset : preset with { Character = reader, Voice = "" };
        return p with { Speed = speed };
    }

    /// <summary>Ctrl+R: the next reader, the narrator ("") first, then every character there is.</summary>
    public static string NextReader(IReadOnlyList<string> readers, string current)
    {
        var all = readers.Count == 0 ? new[] { "" } : readers;
        var at = all.ToList().IndexOf(current);
        return all[(at + 1) % all.Count];
    }

    /// <summary>A preset chip's tag: "Bedtime: Zed, 0.8× (Ctrl+3)".</summary>
    public static string Tag(Preset preset, int number)
    {
        var who = preset.Character.Length == 0 ? (preset.Voice.Length == 0 ? L10n.Tr("a narrator") : preset.Voice) : preset.Character;
        return L10n.Tr("%@: %@, %@ (%@)", preset.Title, who, SpeedLabel(preset.Speed), "Ctrl+" + number.ToString(CultureInfo.InvariantCulture));
    }

    // Parts

    /// <summary>One piece of the text, read in one call: its words, the language its letters say, and whether a
    /// paragraph ends with it (a rest follows).</summary>
    public sealed record Part(string Text, Translate.Lang? Language, bool ParagraphEnd);

    /// <summary>The first part is short, so the first sound comes quickly; the rest are longer, so there are fewer calls.</summary>
    public const int FirstPartSize = 240, PartSize = 900;
    /// <summary>Parts asked for ahead of the one playing.</summary>
    public const int PartsAhead = 2;

    private static readonly char[] NewLines = { '\n', '\r', '\u2028', '\u2029', '\u0085', '\v', '\f' };

    /// <summary>The text in parts: a paragraph is a line with words on it; a paragraph longer than a part is cut
    /// after a sentence, else after a comma, else after a word. <paramref name="forced"/> reads every part as that language.</summary>
    public static IReadOnlyList<Part> Parts(string text, int first = FirstPartSize, int size = PartSize, Translate.Lang? forced = null)
    {
        var paragraphs = text.Split(NewLines).Select(Voices.Speakable).Where(p => p.Length > 0);
        var parts = new List<Part>();
        Translate.Lang? language = null;
        foreach (var paragraph in paragraphs)
        {
            var rest = paragraph;
            while (rest.Length > 0)
            {
                var limit = parts.Count == 0 ? first : size;
                var piece = rest.Length <= limit ? rest : rest[..Cut(rest, limit)];
                rest = rest[piece.Length..].TrimStart(' ');
                var words = piece.Trim(' ', '\t');
                if (words.Length == 0) continue;
                // A part with no letters of its own (a number, a link) keeps the language before it.
                if (Translate.Detect(Translate.Protect(words).Text) is { } told) language = told;
                parts.Add(new Part(words, forced ?? language, rest.Length == 0));
            }
        }
        return parts;
    }

    /// <summary>Where to cut <paramref name="text"/> to at most <paramref name="limit"/> characters: after the last
    /// sentence end, else comma or dash, else at a space; never before a third of the room.</summary>
    internal static int Cut(string text, int limit)
    {
        var length = Math.Min(limit, text.Length);
        if (length < 3) return length;
        var floor = Math.Min(Math.Max(1, limit / 3), length - 1);
        bool Ends(int i) => i + 1 == text.Length || text[i + 1] == ' ';
        foreach (var marks in new[] { ".!?…", ",;:—–" })
            for (var i = length - 1; i >= floor; i--)
                if (marks.Contains(text[i]) && Ends(i)) return i + 1;
        var space = text.LastIndexOf(' ', length - 1, length - floor);
        return space >= 0 ? space : length;
    }

    // What is never sent

    public enum Refusal
    {
        /// <summary>Nothing but spaces and new lines.</summary>
        Empty,
        /// <summary>A protected snippet, or a copy of its words: they stay on this computer.</summary>
        Protected,
        /// <summary>Longer than <see cref="HardCap"/>.</summary>
        TooLong,
    }

    public static string Line(this Refusal refusal) => refusal switch
    {
        Refusal.Empty => L10n.Tr("Nothing to read: paste or type some text"),
        Refusal.Protected => L10n.Tr("That is a protected snippet; it stays on this computer"),
        _ => L10n.Tr("Too long: at most %@ characters at a time", Translate.Grouped(HardCap)),
    };

    public const int HardCap = 50_000;
    /// <summary>Above this many characters a paid reading waits for Enter, showing its price first.</summary>
    public const int LongLimitMin = 500, LongLimitMax = 20_000, DefaultLongLimit = 3_000;

    /// <summary>The one check before anything is read: the sheet, the picker's button and the shortcut all ask it.
    /// Null when it may be read.</summary>
    public static Refusal? RefusalOf(string text, Clipboard.SnippetBook snippets)
    {
        if (text.Trim().Length == 0) return Refusal.Empty;
        if (snippets.SecretMatching(text) is not null) return Refusal.Protected;
        if (text.Length > HardCap) return Refusal.TooLong;
        if (Parts(text).Count == 0) return Refusal.Empty;
        return null;
    }

    public static Refusal? RefusalOf(Clipboard.Clip clip, Clipboard.SnippetBook snippets)
    {
        if (clip.Kind is not (Clipboard.Kind.Text or Clipboard.Kind.Rich)) return Refusal.Empty;
        if (snippets.MaskFor(clip) is not null) return Refusal.Protected;
        return RefusalOf(clip.Text, snippets);
    }

    public static Refusal? RefusalOf(Clipboard.Snippet snippet, Clipboard.SnippetBook snippets) =>
        snippet.Protected ? Refusal.Protected : RefusalOf(snippet.Text, snippets);

    // The price before sending

    /// <summary>About how many seconds a text takes to say at 1×: 15 characters a second.</summary>
    public static double Seconds(int characters, double speed = 1) => characters / 15.0 / Math.Max(speed, 0.1);

    /// <summary>About what reading <paramref name="characters"/> costs, from the model's list prices per token. A
    /// model that charges for its sound (Gemini: 25 audio tokens a second) pays for the seconds too; one that
    /// charges per character pays for the characters alone. Null when the price is not known.</summary>
    public static double? Estimate(int characters, double? promptPerToken, double? completionPerToken)
    {
        if (promptPerToken is not double prompt) return null;
        var completion = completionPerToken ?? 0;
        if (completion > 0)
        {
            var input = characters / 4.0 + 30;
            var output = Seconds(characters) * 25;
            return input * prompt + output * completion;
        }
        return characters * prompt;
    }

    // Voices that speak a language

    /// <summary>The voices of a model's list that speak <paramref name="language"/>. A list whose names carry no
    /// language mark (Gemini's <c>Kore</c>, <c>Puck</c>) speaks them all; a list that marks its languages (Kokoro's
    /// <c>af_bella</c>, MAI's <c>ru-RU-Lev:…</c>) speaks only the marked ones, and may speak none: then Windows'
    /// own voice reads that part.</summary>
    public static IReadOnlyList<string> VoicesSpeaking(IReadOnlyList<string> voices, Translate.Lang language)
    {
        if (!voices.Any(v => Mark(v) is not null)) return voices.ToList();
        return voices.Where(v => Mark(v) == language.Code).ToList();
    }

    private static readonly Regex RegionMark = new(@"^[a-z]{2}-[a-z]{2}-", RegexOptions.Compiled);
    private static readonly Regex KokoroMark = new(@"^[abefhijpz][fm]_", RegexOptions.Compiled);
    private static readonly Regex NamedMark = new(@"^(spanish|french|german|italian|japanese|korean|chinese|portuguese|arabic|hindi)_", RegexOptions.Compiled);

    /// <summary>The language a voice's name says it speaks, as a code; null when it says none.</summary>
    internal static string? Mark(string voice)
    {
        var v = voice.ToLowerInvariant();
        if (Voices.IsRussian(v)) return "ru";
        if (v.StartsWith("he-", StringComparison.Ordinal) || v.StartsWith("he_", StringComparison.Ordinal) || v.StartsWith("hebrew", StringComparison.Ordinal)
            || v.StartsWith("iw-", StringComparison.Ordinal) || v.EndsWith("-he", StringComparison.Ordinal)) return "he";
        if (Voices.OrpheusEnglish.Contains(v)) return "en";
        if (Voices.IsEnglish(voice)) return "en";
        // Another language by its mark: es-MX-…, Kokoro's ef_dora (Spanish), jf_alpha, zf_xiaobei.
        if (RegionMark.IsMatch(v)) return v[..2];
        if (KokoroMark.IsMatch(v)) return "xx";
        if (NamedMark.IsMatch(v)) return "xx";
        return null;
    }

    // Saving

    public enum Format { M4a, Wav }

    /// <summary>The name saved, and the file's extension: <c>m4a</c>, <c>wav</c>.</summary>
    public static string Code(this Format format) => format == Format.M4a ? "m4a" : "wav";

    public static Format? FormatNamed(string? code) => code switch { "m4a" => Format.M4a, "wav" => Format.Wav, _ => null };

    public static string Title(this Format format) => format == Format.M4a ? L10n.Tr("M4A (small, plays everywhere)") : L10n.Tr("WAV (big, exact)");

    private const string Unsafe = "/\\:*?\"<>|";

    /// <summary>"Read aloud 2026-11-01 14.32.05 – The first words.wav": the time it was made and the text's start.</summary>
    public static string FileName(string text, DateTime date, Format format)
    {
        // Marks a file name cannot hold become spaces before the words are counted.
        var plain = new string(text.Select(c => Unsafe.Contains(c) || char.IsControl(c) ? ' ' : c).ToArray());
        var words = string.Join(" ", Voices.Speakable(plain).Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(6));
        var safe = words.Length <= 48 ? words : words[..48];
        var start = safe.Length == 0 ? "" : " – " + safe;
        return L10n.Tr("Read aloud") + " " + date.ToString("yyyy-MM-dd HH.mm.ss", CultureInfo.InvariantCulture) + start + "." + format.Code();
    }

    // Words for the sheet

    /// <summary>"1:05": minutes and seconds.</summary>
    public static string Clock(double seconds)
    {
        var s = Math.Max(0, (int)Math.Floor(seconds));
        return $"{s / 60}:{s % 60:00}";
    }

    /// <summary>The creature reading's bubble: a dot running along three, never said.</summary>
    public static string ReadingDots(double since) => new[] { "•··", "·•·", "··•", "·•·" }[(int)(since * 4) % 4];

    /// <summary>How far a creature reading bobs, in points: a slow nod over the page.</summary>
    public static double ReadingBob(double since)
    {
        var phase = since % 0.9 / 0.9;
        return phase < 0.5 ? 2 : 0;
    }

    /// <summary>The pace a step on the sheet goes to: 0.1 a step, inside the range.</summary>
    public static double Step(double speed, int steps)
    {
        var next = Math.Round((speed + steps * 0.1) * 10, MidpointRounding.AwayFromZero) / 10;
        return Math.Clamp(next, SpeedMin, SpeedMax);
    }

    /// <summary>"1.6×".</summary>
    public static string SpeedLabel(double speed) =>
        (Math.Round(speed * 100, MidpointRounding.AwayFromZero) / 100).ToString("0.##", CultureInfo.InvariantCulture) + "×";

    // The buttons

    /// <summary>Every button Read aloud draws: a pixel picture of what it does (11×11, <c>#</c> ink, <c>.</c> paper)
    /// and, on hover, its name and the key that does the same.</summary>
    public enum Button
    {
        /// <summary>The sheet: read or go on, pause, stop, save the sound, copy it, slower, faster, the next reader.</summary>
        Play, Pause, Stop, Save, Copy, Slower, Faster, Reader,
        /// <summary>The clipboard picker's row: read it aloud.</summary>
        ReadRow,
    }

    public static IReadOnlyList<Button> Buttons { get; } = Enum.GetValues<Button>();

    /// <summary>The key, as Windows writes it.</summary>
    public static string Key(this Button button) => button switch
    {
        Button.Play or Button.Pause => "Enter",
        Button.Stop => "Ctrl+.",
        Button.Save => "Ctrl+S",
        // Ctrl+C alone copies the selected words in the text box.
        Button.Copy => "Ctrl+Shift+C",
        Button.Slower => "Ctrl+-",
        Button.Faster => "Ctrl+=",
        _ => "Ctrl+R",
    };

    /// <summary>What it does and its key.</summary>
    public static string Tooltip(this Button button) => button switch
    {
        Button.Play => L10n.Tr("Read it aloud (%@)", button.Key()),
        Button.Pause => L10n.Tr("Pause (%@)", button.Key()),
        Button.Stop => L10n.Tr("Stop reading (%@)", button.Key()),
        Button.Save => L10n.Tr("Save the sound as a file (%@)", button.Key()),
        Button.Copy => L10n.Tr("Copy the sound file (%@)", button.Key()),
        Button.Slower => L10n.Tr("Slower (%@)", button.Key()),
        Button.Faster => L10n.Tr("Faster (%@)", button.Key()),
        Button.Reader => L10n.Tr("The next reader (%@)", button.Key()),
        _ => L10n.Tr("Read aloud (%@)", button.Key()),
    };

    public static IReadOnlyList<string> Icon(this Button button) => button switch
    {
        Button.Play => new[] { "..#........", "..##.......", "..###......", "..####.....", "..#####....", "..######...", "..#####....", "..####.....", "..###......", "..##.......", "..#........" },
        Button.Pause => new[] { "...........", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..........." },
        Button.Stop => new[] { "...........", "...........", ".#######...", ".#######...", ".#######...", ".#######...", ".#######...", ".#######...", ".#######...", "...........", "..........." },
        // A floppy disk: the shutter on top, the label below.
        Button.Save => new[] { "#########..", "#.#####.##.", "#.#####..#.", "#.#####..#.", "#........#.", "#.######.#.", "#.#....#.#.", "#.#....#.#.", "#.#....#.#.", "##########.", "..........." },
        // A page with a note on it, a second page behind.
        Button.Copy => new[] { "######.....", "#....#.....", "#.#######..", "#.#.....#..", "#.#...###..", "###...#.#..", "..#...#.#..", "..#.###.#..", "..#.###.#..", "..#######..", "..........." },
        // One step forward, then two: slower and faster.
        Button.Slower => new[] { "...........", "...........", "...#.......", "...##......", "...#.#.....", "...#..#....", "...#.#.....", "...##......", "...#.......", "...........", "###########" },
        Button.Faster => new[] { "...........", "...........", ".#....#....", ".##...##...", ".#.#..#.#..", ".#..#.#..#.", ".#.#..#.#..", ".##...##...", ".#....#....", "...........", "###########" },
        // A creature, square with square eyes, as the readers are drawn.
        Button.Reader => new[] { ".#########.", ".#.......#.", ".#....#.##.", ".#....#.##.", ".#.......#.", ".#.......#.", ".#.......#.", ".#########.", "..##...##..", "...........", "..........." },
        _ => Speaker,
    };

    /// <summary>A loudspeaker with its sound going out: the tool's own picture.</summary>
    public static readonly IReadOnlyList<string> Speaker = new[]
    {
        "....#......", "...##....#.", "..#.#..#..#", "###.#...#.#", "#...#.#.#.#", "#...#.#.#.#", "#...#.#.#.#",
        "###.#...#.#", "..#.#..#..#", "...##....#.", "....#......",
    };
}
