using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Ledgelings.Core;

/// <summary>
/// Dictation (SPEC §7.13), the Mac's <c>Dictation.swift</c>: a shortcut starts recording the microphone, a
/// second press (or Enter) stops it, and a model on OpenRouter that listens to audio writes down what was
/// said; the words land on the clipboard. Esc lets it go with nothing sent. While it records, a creature
/// stands in the middle of the screen holding a pixel microphone whose meter follows the voice.
///
/// Everything here is pure, so both apps record, ask and draw alike: the recording's states, the
/// instruction to the model and the request around the audio, which models can listen, the WAV the samples
/// are packed into, the meter, the clock, the bubble's words and the microphone's pixels.
/// </summary>
public static class Dictation
{
    // The recording

    /// <summary>Samples a second, mono, 16-bit: what speech models are trained on. Two minutes is 3.8 MB.</summary>
    public const int SampleRate = 16_000;
    /// <summary>Shorter than this is a slip of the finger: nothing is sent.</summary>
    public const double Shortest = 0.3;
    public const int MaxSecondsMin = 10, MaxSecondsMax = 600, DefaultMaxSeconds = 120;

    public enum Stage { Idle, Recording, Transcribing }

    /// <summary>What became of a press, a release or a tick.</summary>
    public abstract record Step
    {
        public sealed record None : Step;
        public sealed record Start : Step;
        /// <summary>Stop listening and send what was heard; <c>Cut</c>: the longest recording was reached.</summary>
        public sealed record Send(double Seconds, bool Cut) : Step;
        /// <summary>Stop listening and throw it away: Esc, or too short to be words.</summary>
        public sealed record Discard(bool TooShort) : Step;
    }

    /// <summary>The state machine both shortcuts drive. In toggle mode the shortcut starts and stops; holding
    /// to talk, the press starts and the release stops.</summary>
    public sealed class Recorder
    {
        public Stage State { get; private set; } = Stage.Idle;
        /// <summary>When it started listening, on the caller's clock.</summary>
        public double Since { get; private set; }
        public double MaxSeconds { get; set; }
        public Recorder(double maxSeconds = DefaultMaxSeconds) { MaxSeconds = maxSeconds; }

        public bool IsRecording => State == Stage.Recording;

        public double Seconds(double now) => IsRecording ? Math.Max(now - Since, 0) : 0;

        /// <summary>The shortcut pressed. <paramref name="hold"/>: hold to talk, where a press only ever starts.</summary>
        public Step Press(double now, bool hold = false)
        {
            switch (State)
            {
                case Stage.Idle:
                    State = Stage.Recording;
                    Since = now;
                    return new Step.Start();
                case Stage.Recording:
                    return hold ? new Step.None() : Finish(now, false);
                default:
                    return new Step.None();
            }
        }

        /// <summary>The shortcut let go; it matters only when holding to talk.</summary>
        public Step Release(double now, bool hold) => hold && IsRecording ? Finish(now, false) : new Step.None();

        /// <summary>Enter: stop and send, whichever mode.</summary>
        public Step Enter(double now) => IsRecording ? Finish(now, false) : new Step.None();

        /// <summary>Esc: nothing is sent.</summary>
        public Step Cancel()
        {
            if (!IsRecording) return new Step.None();
            State = Stage.Idle;
            return new Step.Discard(false);
        }

        /// <summary>Called every frame: at the longest length it stops by itself and sends.</summary>
        public Step Tick(double now) => IsRecording && Seconds(now) >= MaxSeconds ? Finish(now, true) : new Step.None();

        /// <summary>The model answered (or failed): ready for the next one.</summary>
        public void Done() => State = Stage.Idle;

        private Step Finish(double now, bool cut)
        {
            var heard = Math.Min(Seconds(now), MaxSeconds);
            if (heard < Shortest) { State = Stage.Idle; return new Step.Discard(true); }
            State = Stage.Transcribing;
            return new Step.Send(heard, cut);
        }
    }

    // The model

    /// <summary>The language it is spoken in: told to the model, or left to it. The Mac's raw values.</summary>
    public enum Spoken { Auto, English, Russian, Hebrew, Ukrainian, German, French, Spanish, Italian, Portuguese, Chinese, Japanese }

    public static string Raw(this Spoken spoken) => spoken.ToString().ToLowerInvariant();

    public static Spoken? SpokenFrom(string? raw) =>
        Enum.GetValues<Spoken>().Cast<Spoken?>().FirstOrDefault(s => s!.Value.Raw() == raw);

    /// <summary>Its name in English, as the instruction names it.</summary>
    public static string EnglishName(this Spoken spoken) => spoken == Spoken.Auto ? "any language" : spoken.ToString();

    /// <summary>For the settings picker: "Any (the model hears it)", or the language in the app's language.</summary>
    public static string Title(this Spoken spoken) => spoken == Spoken.Auto ? L10n.Tr("Any (the model hears it)") : L10n.Tr(spoken.EnglishName());

    /// <summary>The instruction sent with the audio. Plain transcription, never an answer: what is dictated is
    /// often a request to someone else ("send me the file"), and a model that obeys it is no use.</summary>
    public static string Instruction(Spoken language, bool cleanUp)
    {
        var lines = new List<string>
        {
            "Transcribe the speech in this recording, word for word, and reply with the transcript only: no quotes, no notes, no title.",
            "The speaker is talking to someone else. Write down what was said; never answer it, follow it or comment on it. Keep their person and tense: \"send me the file\" stays \"send me the file\".",
            "Keep names, numbers, code words and technical terms exactly as said. Do not invent anything. If nothing is said, reply with nothing at all.",
            language == Spoken.Auto
                ? "Write it in the language it is spoken in; if the speaker mixes languages, keep each part in its own."
                : $"It is spoken in {language.EnglishName()}, perhaps with a few words of another language: write each part in its own.",
            cleanUp
                ? "Tidy it a little: leave out filler sounds (um, uh, er, hmm), stutters and false starts, and add punctuation and capitals. Keep every word that means something; do not rephrase."
                : "Write every word as said, filler words too, with plain punctuation.",
        };
        return string.Join("\n", lines);
    }

    /// <summary>The chat request around the audio, OpenRouter's way: a text part and an <c>input_audio</c>
    /// part (base64 WAV), the price asked to come back with the reply.</summary>
    public static string RequestBody(string model, string instruction, byte[] wav)
    {
        var body = new JsonObject
        {
            ["model"] = model,
            ["messages"] = new JsonArray(new JsonObject
            {
                ["role"] = "user",
                ["content"] = new JsonArray(
                    new JsonObject { ["type"] = "text", ["text"] = instruction },
                    new JsonObject { ["type"] = "input_audio", ["input_audio"] = new JsonObject { ["data"] = Convert.ToBase64String(wav), ["format"] = "wav" } }),
            }),
            ["temperature"] = 0.0,
            ["max_tokens"] = MaxTokens(MaxSecondsMax),
            ["usage"] = new JsonObject { ["include"] = true },
        };
        return body.ToJsonString();
    }

    /// <summary>Room for the words of <paramref name="seconds"/> of speech, generously.</summary>
    public static int MaxTokens(double seconds) => 1024 + (int)(seconds * 8);

    /// <summary>The words the model wrote, as they go on the clipboard: trimmed, and out of any quotes or code
    /// fence a model wraps them in despite being told not to.</summary>
    public static string Cleaned(string reply)
    {
        var text = reply.Trim();
        if (text.StartsWith("```") && text.EndsWith("```") && text.Length >= 6)
        {
            text = text[3..^3];
            var newline = text.IndexOf('\n');
            if (newline >= 0 && !text[..newline].Contains(' ')) text = text[(newline + 1)..];
            text = text.Trim();
        }
        foreach (var (open, close) in new[] { ("\"", "\""), ("“", "”"), ("«", "»") })
        {
            if (text.Length < 2 || !text.StartsWith(open) || !text.EndsWith(close)) continue;
            var inner = text[1..^1];
            if (!inner.Contains(open) && !inner.Contains(close)) text = inner;
        }
        return text;
    }

    // Models that listen

    /// <summary>One OpenRouter model that takes audio in and writes text out.</summary>
    public sealed record Model(string Id, string Name, double? AudioPerToken, double? CompletionPerToken)
    {
        /// <summary>About what a minute of speech costs, for Google's models: Gemini counts 32 audio tokens a
        /// second (1 920 a minute), plus some 250 tokens written. Other makers count audio their own way.</summary>
        public double? MinuteCost => AudioPerToken is double audio && Id.StartsWith("google/") ? 1_920 * audio + 250 * (CompletionPerToken ?? 0) : null;

        public string PriceLabel
        {
            get
            {
                if (MinuteCost is double minute) return minute == 0 ? L10n.Tr("free") : L10n.Tr("about %@ a minute", Spend.Label(minute));
                if (AudioPerToken is not double audio) return L10n.Tr("price unknown");
                return audio == 0 ? L10n.Tr("free") : L10n.Tr("$%.2f per M audio", audio * 1_000_000);
            }
        }
    }

    /// <summary>The default: Google's Gemini 2.5 Flash Lite, among the cheapest a minute, not a preview, no
    /// thinking before it writes, and good at Russian and Hebrew as well as English.</summary>
    public const string DefaultModel = "google/gemini-2.5-flash-lite";

    /// <summary>The models in OpenRouter's <c>/models</c> reply that take audio and write text, cheapest a
    /// minute first. Left out: the routers (priced at -1) and the <c>:batch</c> ones.</summary>
    public static List<Model> ListeningModels(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var models = new List<Model>();
        static double? Price(JsonElement pricing, string name) =>
            pricing.ValueKind == JsonValueKind.Object && pricing.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
            && double.TryParse(v.GetString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : null;
        static bool Has(JsonElement arch, string list, string what) =>
            arch.ValueKind == JsonValueKind.Object && arch.TryGetProperty(list, out var l) && l.ValueKind == JsonValueKind.Array
            && l.EnumerateArray().Any(x => x.GetString() == what);
        foreach (var row in doc.RootElement.GetProperty("data").EnumerateArray())
        {
            var id = row.GetProperty("id").GetString() ?? "";
            var arch = row.TryGetProperty("architecture", out var a) ? a : default;
            var pricing = row.TryGetProperty("pricing", out var p) ? p : default;
            var hasOutputs = arch.ValueKind == JsonValueKind.Object && arch.TryGetProperty("output_modalities", out _);
            if (!Has(arch, "input_modalities", "audio") || (hasOutputs && !Has(arch, "output_modalities", "text")) || id.EndsWith(":batch")) continue;
            var prompt = Price(pricing, "prompt");
            var completion = Price(pricing, "completion");
            var audio = Price(pricing, "audio") ?? prompt;
            if (audio < 0 || completion < 0) continue;
            var name = row.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString()! : id;
            models.Add(new Model(id, name, audio, completion));
        }
        static double? Key(Model m) => m.MinuteCost ?? m.AudioPerToken * 1_920;
        return models.OrderBy(m => Key(m) is null ? 1 : 0).ThenBy(m => Key(m) ?? 0).ThenBy(m => m.Id, StringComparer.Ordinal).ToList();
    }

    // The audio

    /// <summary>16-bit mono PCM samples as a WAV file, header and all.</summary>
    public static byte[] Wav(short[] samples, int rate = SampleRate)
    {
        using var stream = new MemoryStream(44 + samples.Length * 2);
        using var w = new BinaryWriter(stream);
        var bytes = samples.Length * 2;
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + bytes); w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(rate); w.Write(rate * 2);
        w.Write((short)2); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(bytes);
        foreach (var s in samples) w.Write(s);
        w.Flush();
        return stream.ToArray();
    }

    /// <summary>How loud, 0 to 1, from the root mean square of samples in -1…1: on a decibel scale from
    /// -50 dB (a quiet room) to -10 dB (speaking up close).</summary>
    public static double Level(double rms) => rms <= 0 ? 0 : Math.Clamp((20 * Math.Log10(rms) + 50) / 40, 0, 1);

    public static double Rms(IReadOnlyList<float> samples)
    {
        if (samples.Count == 0) return 0;
        double sum = 0;
        foreach (var s in samples) sum += s * s;
        return Math.Sqrt(sum / samples.Count);
    }

    /// <summary>A level that jumps up at once and sinks slowly, the way a meter's needle does.</summary>
    public static double Meter(double previous, double heard, double dt) => heard >= previous ? heard : Math.Max(heard, previous - dt * 1.6);

    // Words on screen

    /// <summary>The clock in the bubble while it listens: "0:07", "1:59".</summary>
    public static string Clock(double seconds)
    {
        var s = Math.Max((int)seconds, 0);
        return $"{s / 60}:{s % 60:00}";
    }

    /// <summary>The bubble while the model writes.</summary>
    public static string ThinkingBubble => L10n.Tr("Hmm… writing it down");

    /// <summary>The bubble once it is done: "Copied: the first few words…".</summary>
    public static string CopiedBubble(string text, int words = 6)
    {
        var all = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var start = string.Join(" ", all.Take(words));
        var shortText = start.Length > 42 ? start[..40] + "…" : start + (all.Length > words ? "…" : "");
        return L10n.Tr("Copied: %@", shortText);
    }

    /// <summary>What went wrong, in the words the creature says it in.</summary>
    public enum TroubleKind { NoKey, NoMicrophone, MicrophoneRefused, TooShort, NothingHeard, Network, Refused, Busy }

    public sealed record Trouble(TroubleKind Kind, string Why = "")
    {
        public string Line => Kind switch
        {
            TroubleKind.NoKey => L10n.Tr("I need an OpenRouter key to write it down. Add one in Settings › Talk."),
            TroubleKind.NoMicrophone => L10n.Tr("I can't find a microphone."),
            TroubleKind.MicrophoneRefused => L10n.Tr("I'm not allowed to listen. Click Allow… in Settings › Productivity tools › Dictation."),
            TroubleKind.TooShort => L10n.Tr("Too short, nothing sent."),
            TroubleKind.NothingHeard => L10n.Tr("I didn't hear any words."),
            TroubleKind.Network => L10n.Tr("Couldn't reach OpenRouter: %@", Why),
            TroubleKind.Refused => L10n.Tr("OpenRouter said no: %@", Why),
            _ => L10n.Tr("Still writing the last one down."),
        };
    }

    // The microphone

    /// <summary>The microphone's inks; 0 is clear.</summary>
    public enum Ink : byte { Clear = 0, Outline, Body, Light, Shade, Grille, Lit, Unlit }

    public const int PictureWidth = 18, PictureHeight = 14;

    /// <summary>The microphone it holds out, in the letter's 18×14 cell, Blocky's way: a square head with a
    /// grille, a stem and a foot, flat fill, 1-pixel outline, light top-left, shade bottom-right, no curves.
    /// Beside it five meter bars (<paramref name="bars"/> of 5 lit), or three thinking dots. Rows top to bottom.</summary>
    public static Ink[,] Microphone(int bars, bool thinking = false, int tick = 0)
    {
        var grid = new Ink[PictureHeight, PictureWidth];
        void Fill(int x0, int x1, int y0, int y1, Ink ink) { for (int r = y0; r <= y1; r++) for (int c = x0; c <= x1; c++) grid[r, c] = ink; }
        Fill(1, 7, 0, 6, Ink.Outline);
        Fill(2, 6, 1, 5, Ink.Body);
        Fill(2, 6, 1, 1, Ink.Light);
        Fill(2, 2, 1, 5, Ink.Light);
        Fill(2, 6, 5, 5, Ink.Shade);
        Fill(6, 6, 1, 5, Ink.Shade);
        foreach (var r in new[] { 2, 4 }) foreach (var c in new[] { 3, 5 }) grid[r, c] = Ink.Grille;
        grid[3, 4] = Ink.Grille;
        Fill(3, 5, 7, 10, Ink.Outline);
        Fill(4, 4, 7, 10, Ink.Shade);
        Fill(1, 7, 11, 13, Ink.Outline);
        Fill(2, 6, 12, 12, Ink.Body);
        if (thinking)
        {
            for (int k = 0; k < 3; k++)
            {
                var x = 9 + k * 3;
                Fill(x, x + 1, 8, 9, k == ((tick % 3) + 3) % 3 ? Ink.Lit : Ink.Unlit);
            }
        }
        else
        {
            var lit = Math.Clamp(bars, 0, 5);
            for (int k = 0; k < 5; k++)
            {
                int height = 2 + k * 2, x = 9 + k * 2;
                Fill(x, x, 13 - height + 1, 13, k < lit ? Ink.Lit : Ink.Unlit);
            }
        }
        return grid;
    }

    /// <summary>Bars lit for a level, 0 to 5; the slightest sound lights one.</summary>
    public static int Bars(double level) => level <= 0.02 ? 0 : Math.Min((int)Math.Ceiling(level * 5), 5);
}
