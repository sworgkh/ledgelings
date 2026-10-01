using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Who sounds how: the pitch, speed and voice of each character, and casting by the brain model.</summary>
public sealed partial class Voice
{
    /// <summary>How high <paramref name="name"/> speaks: the Pitch slider, times the character's own pitch
    /// if set by hand, else a cartoon lift, or a small nudge with a voice each.</summary>
    public double Pitch(string name) => settings.VoicePitch * OwnPitch(name);

    /// <summary>The character's own share of <see cref="Pitch"/>, before the global slider.</summary>
    public double OwnPitch(string name)
    {
        if (settings.VoiceOf(name).Pitch is double set) return set;
        if (settings.CastByPersonality)
        {
            // The personality sets the pitch; a cartoon sits higher overall; a small
            // nudge keeps two alike characters apart.
            var nudge = 1 + (Voices.PitchNudge(name) - 1) / 2;
            return (settings.CartoonVoices ? 1.3 : 1) * TraitsOf(name).Pitch * nudge;
        }
        return settings.CartoonVoices ? Voices.CartoonPitch(name)
            : settings.VoicePerCharacter ? Voices.PitchNudge(name) : 1;
    }

    /// <summary>How <paramref name="name"/> should sound, from its description; neutral with casting off.</summary>
    public Casting.Traits TraitsOf(string name)
    {
        if (!settings.CastByPersonality || Describe(name) is not { } who) return Casting.Traits.Neutral;
        return Casting.TraitsOf(who.Persona, who.Kind);
    }

    /// <summary>The character's own share of <see cref="Speed"/>, before the global slider.</summary>
    public double OwnSpeed(string name) => settings.VoiceOf(name).Speed ?? TraitsOf(name).Speed;

    /// <summary>Whether <paramref name="name"/>'s speed follows its pitch: its own choice, else the overall one.</summary>
    public bool FollowsPitch(string name) => settings.VoiceOf(name).FollowPitch ?? settings.SpeedFollowsPitch;

    /// <summary>How fast <paramref name="name"/> speaks: the Speed slider times its own.</summary>
    public double Speed(string name) => settings.VoiceSpeed * OwnSpeed(name);

    /// <summary>The Windows voice <paramref name="name"/> speaks with; null is the system default.
    /// <paramref name="automatic"/>: what it would get with no voice of its own chosen.</summary>
    public string? SystemVoiceFor(string name, IReadOnlyList<string> cast, bool automatic = false)
    {
        if (!automatic && settings.VoiceOf(name).SystemVoice is string own) return own;
        if (!settings.VoicePerCharacter) return settings.SystemVoice.Length == 0 ? null : settings.SystemVoice;
        var voices = SystemPool;
        var pool = voices.Select(v => v.Name).ToList();
        var fixedVoices = Fixed(v => v.SystemVoice);
        if (automatic) fixedVoices.Remove(name);
        var everyone = cast.Append(name).ToList();
        if (!settings.CastByPersonality) return Voices.Assign(everyone, pool, fixedVoices).GetValueOrDefault(name);
        var tags = new Dictionary<string, HashSet<Casting.Tag>>();
        foreach (var v in voices) tags.TryAdd(v.Name, TagsOf(v));
        return Casting.Assign(everyone, CastTraits(everyone), pool, tags, fixedVoices).GetValueOrDefault(name);
    }

    /// <summary>The voice <paramref name="name"/> speaks with on OpenRouter or the local server, from that
    /// model's <paramref name="voices"/>; null lets the model choose.</summary>
    public string? OnlineVoice(string name, IReadOnlyList<string> cast, IReadOnlyList<string> voices, bool automatic = false)
    {
        var local = settings.VoiceEngine == VoiceEngine.Local;
        string? Mine(CharacterVoice v) => local ? v.LocalVoice : v.OpenRouterVoice;
        var chosen = local ? settings.LocalVoice : settings.OpenRouterVoice;
        // A local server (Kokoro) also takes blends of its voices; OpenRouter does not.
        string? Usable(string? v) => v is null ? null
            : local ? (Voices.IsUsable(v, voices) ? v : null)
            : (voices.Count == 0 || voices.Contains(v) ? v : null);
        if (!automatic && Usable(Mine(settings.VoiceOf(name))) is string own) return own;
        if (!settings.VoicePerCharacter) return chosen.Length == 0 ? voices.FirstOrDefault() : chosen;
        var english = Voices.EnglishFirst(voices);
        var fixedVoices = Fixed(v => Usable(Mine(v)));
        if (automatic) fixedVoices.Remove(name);
        var everyone = cast.Append(name).ToList();
        if (!settings.CastByPersonality)
        {
            var pool = settings.CartoonVoices ? Voices.CartoonFirst(english) : english;
            return Voices.Assign(everyone, pool, fixedVoices).GetValueOrDefault(name);
        }
        var tags = new Dictionary<string, HashSet<Casting.Tag>>();
        foreach (var v in english) tags.TryAdd(v, Casting.TagsOfVoice(v));
        return Casting.Assign(everyone, CastTraits(everyone), english, tags, fixedVoices).GetValueOrDefault(name);
    }

    /// <summary>The hand-picked voices of every character with one, as <paramref name="pick"/> reads them.</summary>
    private Dictionary<string, string> Fixed(Func<CharacterVoice, string?> pick)
    {
        var found = new Dictionary<string, string>();
        foreach (var (who, v) in settings.CharacterVoices) if (pick(v) is string voice) found[who] = voice;
        return found;
    }

    private Dictionary<string, Casting.Traits> CastTraits(IEnumerable<string> names)
    {
        var traits = new Dictionary<string, Casting.Traits>();
        foreach (var n in names) traits.TryAdd(n, TraitsOf(n));
        return traits;
    }

    /// <summary>What <paramref name="name"/> would sound like with no voice of its own chosen, in words, for the Voice tab.</summary>
    public string AutomaticVoice(string name) => settings.VoiceEngine switch
    {
        VoiceEngine.System => SystemVoiceFor(name, Cast(), automatic: true) ?? "system default",
        VoiceEngine.OpenRouter => OnlineVoice(name, Cast(), ModelVoices, automatic: true) ?? "the model's own",
        _ => OnlineVoice(name, Cast(), LocalVoices, automatic: true) ?? "the server's own",
    };

    // MARK: Casting by the brain model

    /// <summary>Ask the brain model which voice, pitch and speed fit <paramref name="name"/>, and keep its
    /// answer as the character's own, as if picked by hand. Returns the model's
    /// reason. Needs a model brain (LM Studio or OpenRouter); the call is priced
    /// into the spend file like any other.</summary>
    public async Task<string> CastWithModel(string name)
    {
        if (settings.ChatClient() is not ChatClient client) throw ChatClient.Failure.NoModel(settings.BrainProblem);
        var who = Describe(name) ?? ("", "");
        // Choices for the engine in use, by the id the model sees, with what is known of each.
        static string Hints(IEnumerable<Casting.Tag> tags) => string.Join(", ", tags.Select(t => t.Raw()).OrderBy(t => t, StringComparer.Ordinal));
        List<(string Id, string Hints, string Value)> choices;
        switch (settings.VoiceEngine)
        {
            case VoiceEngine.System:
                choices = SystemPool.Select(v => (v.Name, Hints(TagsOf(v)), v.Name)).ToList();
                break;
            case VoiceEngine.OpenRouter:
            {
                var all = ModelVoices.Count == 0 ? await VoicesOf(settings.VoiceModel) : ModelVoices;
                choices = Voices.EnglishFirst(all).Select(v => (v, Hints(Casting.TagsOfVoice(v)), v)).ToList();
                break;
            }
            default:
            {
                var all = LocalVoices.Count == 0 ? await LoadLocalVoices() : LocalVoices;
                choices = Voices.EnglishFirst(all).Select(v => (v, Hints(Casting.TagsOfVoice(v)), v)).ToList();
                break;
            }
        }
        if (choices.Count == 0) throw ChatClient.Failure.BadReply("no voices to choose from");
        var prompt = Casting.ModelPrompt(name, who.Persona, who.Kind, choices.Select(c => (c.Id, c.Hints)), settings.CartoonVoices);
        // Room for a thinking model to reason before it answers; the answer itself is short.
        var answer = await client.Reply(Casting.ModelSystem, prompt, maxTokens: 2000, temperature: 0.3);
        if (answer.Usage is Spend.Usage usage) spend.Record(client.Kind, client.Model, usage, Spend.Purpose.Casting);
        var pick = Casting.ParsePick(answer.Text);
        var at = pick is null ? -1 : choices.FindIndex(c => string.Equals(c.Id, pick.Voice, StringComparison.OrdinalIgnoreCase));
        if (pick is null || at < 0) throw ChatClient.Failure.BadReply(ChatClient.Head(answer.Text, 120));
        var chosen = choices[at];
        var engine = settings.VoiceEngine;
        settings.SetVoice(name, v =>
        {
            switch (engine)
            {
                case VoiceEngine.System: v.SystemVoice = chosen.Value; break;
                case VoiceEngine.OpenRouter: v.OpenRouterVoice = chosen.Value; break;
                default: v.LocalVoice = chosen.Value; break;
            }
            if (pick.Pitch is double p) v.Pitch = Math.Clamp(p, AppSettings.VoicePitchMin, AppSettings.VoicePitchMax);
            if (pick.Speed is double s) v.Speed = Math.Clamp(s, AppSettings.VoiceSpeedMin, AppSettings.VoiceSpeedMax);
        });
        return chosen.Id + (pick.Why is string why ? ": " + why : "");
    }
}
