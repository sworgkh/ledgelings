using Ledgelings.Core;
using T = Ledgelings.Core.Translate;

namespace Ledgelings;

/// <summary>
/// The calls the translator makes (SPEC §7.14), the Mac's <c>Translator.swift</c>: a translation, cut into parts
/// when it is long and with links, code and numbers kept out of reach; a guess at how a phrase goes on. Every
/// call is priced as Translation or Autocomplete, empty answers too. Answers are kept in a small cache in
/// memory, so backspacing and retyping cost nothing.
///
/// Nothing here cancels a call: a newer keystroke only means nobody waits for the older answer (the sheet
/// drops it), while the call itself runs to its end and is priced (AGENTS rule 1).
/// </summary>
public sealed class Translator
{
    public enum TroubleKind { NoModel, TimedOut, Network, Refused, Empty }

    public sealed record Trouble(TroubleKind Kind, string Why = "")
    {
        public string Line => Kind switch
        {
            TroubleKind.NoModel => L10n.Tr("Translating needs an OpenRouter key (Settings › Talk), or LM Studio as the brain."),
            TroubleKind.TimedOut => L10n.Tr("No answer in %d s: offline? Enter to try again", (int)T.TranslationTimeout),
            TroubleKind.Network => L10n.Tr("Could not reach the model: %@", Why),
            TroubleKind.Refused => L10n.Tr("The model refused: %@", Why),
            _ => L10n.Tr("The model sent nothing back. Enter to try again"),
        };
    }

    /// <summary>A finished translation: the words, how long it took, whether a link, code or number may have come
    /// back changed (the markers were lost and the text went again without them), and whether the cache answered.</summary>
    public sealed record Done(string Text, double Seconds, bool MarkersLost = false, bool Cached = false);

    private sealed class Failed : Exception
    {
        public Trouble Trouble { get; }
        public Failed(Trouble trouble) : base(trouble.Line) { Trouble = trouble; }
    }

    private readonly AppSettings settings;
    private readonly SpendLedger spend;
    private readonly T.Cache cache = new();

    /// <summary>Every call with its time, for <c>--translate</c>.</summary>
    public Action<string>? Trace { get; set; }
    /// <summary>A model to use instead of the chosen one, for <c>--translate --model</c>.</summary>
    public string? ModelOverride { get; set; }
    /// <summary>Replaces the network in tests: the system prompt and the text in, the answer out. Nothing is recorded.</summary>
    public Func<string, string, Task<ChatClient.Answer>>? Fake { get; set; }

    public Translator(AppSettings settings, SpendLedger spend)
    {
        this.settings = settings;
        this.spend = spend;
    }

    /// <summary>Reads the key again if the last read failed: the sheet opens, or the settings changed.</summary>
    public void Refresh()
    {
        if (Fake is null) settings.RetryOpenRouterKey();
    }

    /// <summary>The model that answers: OpenRouter with the chosen model when a key is saved, else LM Studio when
    /// it is the brain (free), else none.</summary>
    public ChatClient? Client(bool guessing = false)
    {
        var key = settings.OpenRouterKey.Trim();
        if (key.Length > 0)
        {
            var own = settings.TranslateAutocompleteModel.Trim();
            var model = ModelOverride ?? (guessing && own.Length > 0 ? own : settings.TranslateModel.Trim());
            return ChatClient.OpenRouter(key, model.Length == 0 ? T.DefaultModel : model);
        }
        if (settings.Brain == BrainKind.LmStudio && Uri.TryCreate(settings.TalkServer, UriKind.Absolute, out var server))
            return ChatClient.LmStudio(server, settings.TalkModel.Trim());
        return null;
    }

    public bool HasModel => Fake is not null || Client() is not null;

    // MARK: Translating

    /// <summary><paramref name="text"/> from <paramref name="source"/> into <paramref name="target"/>; a failure is a
    /// <see cref="Trouble"/> to show.</summary>
    public async Task<(Done? Done, Trouble? Trouble)> Translate(string text, T.Lang source, T.Lang target)
    {
        var started = DateTime.Now;
        var key = new T.CacheKey(text, source.Code, target.Code, Client()?.Model ?? "fake");
        if (cache.Get(key) is { } hit)
        {
            Trace?.Invoke($"translate cached {source.Code}→{target.Code}: {Head(hit)}");
            return (new Done(hit, 0, Cached: true), null);
        }
        var parts = T.Parts(text);
        var results = new string[parts.Count];
        var lost = false;
        try
        {
            // Three parts at a time, joined back in order.
            for (var batch = 0; batch < parts.Count; batch += T.PartsAtOnce)
            {
                var indices = Enumerable.Range(batch, Math.Min(T.PartsAtOnce, parts.Count - batch)).ToList();
                var answers = await Task.WhenAll(indices.Select(i => Part(parts[i], source, target)));
                for (var j = 0; j < indices.Count; j++)
                {
                    results[indices[j]] = answers[j].Words;
                    lost |= answers[j].Lost;
                }
            }
        }
        catch (Failed f) { return (null, f.Trouble); }
        var joined = string.Concat(results);
        if (joined.Trim().Length == 0) return (null, new Trouble(TroubleKind.Empty));
        if (!lost) cache.Put(key, joined);
        var seconds = (DateTime.Now - started).TotalSeconds;
        Trace?.Invoke($"translate {source.Code}→{target.Code} in {seconds:F2} s, {parts.Count} part{(parts.Count == 1 ? "" : "s")}: {Head(joined)}");
        return (new Done(joined, seconds, lost), null);
    }

    /// <summary>One part, its protected pieces put back; again without markers when the model lost one.</summary>
    private async Task<(string Words, bool Lost)> Part(string text, T.Lang source, T.Lang target)
    {
        var p = T.Protect(text);
        var marked = p.Pieces.Count > 0;
        var answer = await Ask(T.Instruction(source, target, marked), p.Text, Room(text), Spend.Purpose.Translation);
        var words = T.Cleaned(answer.Text, p.Text);
        if (!marked) return (words, false);
        if (T.Restore(words, p.Pieces) is { } restored) return (restored, false);
        Trace?.Invoke("markers lost: again without them");
        var again = await Ask(T.Instruction(source, target, false), text, Room(text), Spend.Purpose.Translation);
        return (T.Cleaned(again.Text, text), true);
    }

    /// <summary>Room for the answer: a translation is about as long as the text, Russian and Hebrew in tokens a
    /// little longer, plus some to spare.</summary>
    public static int Room(string text) => Math.Max(200, Math.Min(8_000, text.Length / 2 + 200));

    // MARK: Guessing

    /// <summary>The next few words after <paramref name="text"/>, or "" when there is no guess (or no model).</summary>
    public async Task<string> Guess(string text, T.Lang language)
    {
        if (!settings.TranslateAutocomplete || text.Trim().Length == 0) return "";
        try
        {
            var answer = await Ask(T.GuessInstruction(language), T.GuessPrompt(text), T.GuessTokens, Spend.Purpose.Autocomplete, guessing: true);
            return T.CleanedGuess(answer.Text, text);
        }
        catch (Failed) { return ""; }
    }

    // MARK: The call

    private async Task<ChatClient.Answer> Ask(string system, string user, int maxTokens, Spend.Purpose purpose, bool guessing = false)
    {
        if (Fake is { } fake) return await fake(system, user);
        if (Client(guessing) is not { } client) throw new Failed(new Trouble(TroubleKind.NoModel));
        var sent = DateTime.Now;
        var timeout = TimeSpan.FromSeconds(guessing ? T.GuessTimeout : T.TranslationTimeout);
        ChatClient.Answer answer;
        try { answer = await client.Ask(system, user, maxTokens, guessing ? 0.3 : 0, timeout); }
        catch (ChatClient.Failure e) when (e.Refusal is string why) { throw new Failed(new Trouble(TroubleKind.Refused, why)); }
        catch (ChatClient.Failure e) when ((DateTime.Now - sent) >= timeout - TimeSpan.FromMilliseconds(200)) { throw new Failed(new Trouble(TroubleKind.TimedOut, e.Message)); }
        catch (ChatClient.Failure e) { throw new Failed(new Trouble(TroubleKind.Network, e.Message)); }
        spend.Record(client.Kind, client.Model, answer.Usage ?? new Spend.Usage(0, 0, null), purpose);
        Trace?.Invoke($"{purpose.Raw()} {client.Model} answered in {(DateTime.Now - sent).TotalSeconds:F2} s, {answer.Usage?.PromptTokens ?? 0} in, {answer.Usage?.CompletionTokens ?? 0} out, {(answer.Usage?.Cost is double c ? Spend.Label(c) : "price unknown")}");
        return answer;
    }

    private static string Head(string text) => text.Length <= 80 ? text : text[..80];
}
