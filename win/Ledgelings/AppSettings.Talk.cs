using System.ComponentModel;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Where the words come from. The built-in lines need nothing set up.</summary>
public enum BrainKind { Script, LmStudio, OpenRouter }

/// <summary>The talking half of the settings: which brain, its address and key, the lines, the cast and the prompts.</summary>
public sealed partial class AppSettings
{
    public const string DefaultTalkServer = "http://localhost:1234";
    public const string DefaultTalkModel = "google/gemma-3-1b";
    public const string DefaultOpenRouterModel = "anthropic/claude-haiku-4.5";
    /// <summary>Seconds a speech bubble stays up, for a line of typical length.</summary>
    public const double BubbleMin = 4, BubbleMax = 60;
    /// <summary>Minutes a gifted flower stays on a head before it wilts away.</summary>
    public const double FlowerMin = 0.5, FlowerMax = 30;
    /// <summary>Lines each character remembers saying, so it does not say them again soon.</summary>
    public const int LineMemoryMin = 0, LineMemoryMax = 40;
    /// <summary>Tokens a model may spend on one line, thinking included. 80 was too few:
    /// a thinking model spent them thinking and stopped mid-sentence.</summary>
    public const int LineTokensMin = 100, LineTokensMax = 4000;

    /// <summary>Beside anything greyed out for want of a model, in the same words everywhere.</summary>
    public const string NeedsModel = "Needs a model: the built-in lines have none. Choose LM Studio or OpenRouter as the Brain in Settings › Talk.";

    private bool talkEnabled;
    private bool followGiver;
    private BrainKind brain;
    private string script = "";
    private string talkServer = "", talkModel = "", openRouterModel = "", openRouterKey = "";
    private double bubbleSeconds, flowerMinutes;
    private int lineMemory, lineTokens;
    private Dictionary<string, List<Character>> casts = new();
    private string systemPrompt = "", linePrompt = "", replyPrompt = "";

    public static string BrainTitle(BrainKind kind) => kind switch
    {
        BrainKind.Script => "Built-in lines",
        BrainKind.LmStudio => Ledgelings.ChatClient.Title(Ledgelings.ChatClient.Provider.LmStudio),
        _ => Ledgelings.ChatClient.Title(Ledgelings.ChatClient.Provider.OpenRouter),
    };

    /// <summary>How the brain is written in the settings file: the same words the macOS app uses.</summary>
    private static string BrainKey(BrainKind kind) => kind switch { BrainKind.Script => "script", BrainKind.LmStudio => "lmStudio", _ => "openRouter" };

    private void LoadTalk()
    {
        talkEnabled = store.Get<bool?>("talkEnabled") ?? true;
        followGiver = store.Get<bool?>("followGiver") ?? true;
        // Before the built-in lines existed the brain was LM Studio; someone who
        // set up a model keeps it. Everyone else starts with lines that need no server.
        var setUpAModel = new[] { "talkServer", "talkModel", "openRouterModel" }.Any(k => store.Get<string>(k) is not null);
        brain = Enum.TryParse<BrainKind>(store.Get<string>("brainProvider"), true, out var b) ? b : setUpAModel ? BrainKind.LmStudio : BrainKind.Script;
        script = store.Get<string>("script") ?? Core.Script.BuiltInText;
        talkServer = store.Get<string>("talkServer") ?? DefaultTalkServer;
        talkModel = store.Get<string>("talkModel") ?? DefaultTalkModel;
        openRouterModel = store.Get<string>("openRouterModel") ?? DefaultOpenRouterModel;
        openRouterKey = secrets.Get(KeyAccount) ?? "";
        bubbleSeconds = Math.Clamp(store.Get<double?>("bubbleSeconds") ?? Banter.DefaultBubbleSeconds, BubbleMin, BubbleMax);
        flowerMinutes = Math.Clamp(store.Get<double?>("flowerMinutes") ?? 2, FlowerMin, FlowerMax);
        // Twelve: more than any one character's built-in letters, a few rounds of banter.
        lineMemory = Math.Clamp(store.Get<int?>("lineMemory") ?? 12, LineMemoryMin, LineMemoryMax);
        lineTokens = Math.Clamp(store.Get<int?>("lineTokens") ?? Ledgelings.ChatClient.DefaultLineTokens, LineTokensMin, LineTokensMax);
        casts = store.Get<Dictionary<string, List<Character>>>("casts") ?? new Dictionary<string, List<Character>>();
        systemPrompt = store.Get<string>("systemPrompt") ?? Banter.DefaultSystemPrompt;
        linePrompt = store.Get<string>("linePrompt") ?? Banter.DefaultLinePrompt;
        replyPrompt = store.Get<string>("replyPrompt") ?? Banter.DefaultReplyPrompt;
    }

    public bool TalkEnabled { get => talkEnabled; set => Put(ref talkEnabled, value, "talkEnabled"); }

    /// <summary>The one wearing a flower trails the one who gave it while the flower lasts.</summary>
    public bool FollowGiver { get => followGiver; set => Put(ref followGiver, value, "followGiver"); }

    /// <summary>Who answers, for banter and for anything else that wants words.</summary>
    public BrainKind Brain
    {
        get => brain;
        set
        {
            if (brain == value) return;
            brain = value;
            store.Set("brainProvider", BrainKey(value));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Brain)));
            Changed?.Invoke();
        }
    }

    /// <summary>The conversations said when the brain is the built-in lines, in <see cref="Script"/>'s text form.</summary>
    public string Script { get => script; set => Put(ref script, value, "script"); }

    public void ResetScript() => Script = Core.Script.BuiltInText;

    /// <summary>LM Studio's local server and the model loaded in it.</summary>
    public string TalkServer { get => talkServer; set => Put(ref talkServer, value, "talkServer"); }
    public string TalkModel { get => talkModel; set => Put(ref talkModel, value, "talkModel"); }
    public string OpenRouterModel { get => openRouterModel; set => Put(ref openRouterModel, value, "openRouterModel"); }

    /// <summary>Lives in the Credential Manager, never in the settings file. Empty means no key.
    /// Reading it never prompts on Windows, so unlike the Mac it is read at launch.</summary>
    public string OpenRouterKey
    {
        get => openRouterKey;
        set
        {
            if (openRouterKey == value) return;
            openRouterKey = value;
            secrets.Set(KeyAccount, value);
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(OpenRouterKey)));
            Changed?.Invoke();
        }
    }

    public double BubbleSeconds { get => bubbleSeconds; set => Put(ref bubbleSeconds, Math.Clamp(value, BubbleMin, BubbleMax), "bubbleSeconds"); }
    public double FlowerMinutes { get => flowerMinutes; set => Put(ref flowerMinutes, Math.Clamp(value, FlowerMin, FlowerMax), "flowerMinutes"); }

    /// <summary>How many of its own last lines a character avoids saying again; 0 lets it repeat freely.</summary>
    public int LineMemory { get => lineMemory; set => Put(ref lineMemory, Math.Clamp(value, LineMemoryMin, LineMemoryMax), "lineMemory"); }

    /// <summary>Room for each model-written line (<see cref="Ledgelings.ChatClient.Line"/>); only what is used is paid for.</summary>
    public int LineTokens { get => lineTokens; set => Put(ref lineTokens, Math.Clamp(value, LineTokensMin, LineTokensMax), "lineTokens"); }

    public string SystemPrompt { get => systemPrompt; set => Put(ref systemPrompt, value, "systemPrompt"); }
    public string LinePrompt { get => linePrompt; set => Put(ref linePrompt, value, "linePrompt"); }
    public string ReplyPrompt { get => replyPrompt; set => Put(ref replyPrompt, value, "replyPrompt"); }

    /// <summary>The cast of a species: the user's edit if there is one, else <paramref name="fallback"/> (the sheet's).</summary>
    public IReadOnlyList<Character> CastOf(string species, IReadOnlyList<Character> fallback) =>
        casts.TryGetValue(species, out var own) && own.Count > 0 ? own : fallback;

    public bool HasOwnCast(string species) => casts.ContainsKey(species);

    /// <summary>Who creature <paramref name="i"/> is: the k-th creature wearing its species takes the k-th
    /// character of that species' cast, wrapping round.</summary>
    public Character CharacterFor(int i, SpriteLibrary library)
    {
        var species = SpeciesFor(i);
        var cast = CastOf(species, library.Cast(species));
        if (cast.Count == 0) return new Character($"Ledgeling {i + 1}", "");
        var k = Enumerable.Range(0, i).Count(j => SpeciesFor(j) == species);
        return cast[k % cast.Count];
    }

    public void SetCast(string species, IEnumerable<Character> cast)
    {
        casts[species] = cast.ToList();
        SaveCasts();
    }

    public void ResetCast(string species)
    {
        if (casts.Remove(species)) SaveCasts();
    }

    private void SaveCasts()
    {
        store.Set("casts", casts);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Casts"));
        Changed?.Invoke();
    }

    public Uri? TalkServerUri =>
        Uri.TryCreate(talkServer.Trim(), UriKind.Absolute, out var uri) && !string.IsNullOrEmpty(uri.Host) && (uri.Scheme == "http" || uri.Scheme == "https") ? uri : null;

    /// <summary>The model any feature should ask, or null with <see cref="BrainProblem"/> saying what
    /// is missing. Null, too, with the built-in lines: there is no model to ask.</summary>
    public ChatClient? ChatClient()
    {
        ChatClient client;
        switch (brain)
        {
            case BrainKind.Script:
                return null;
            case BrainKind.LmStudio:
                if (TalkServerUri is not Uri url) return null;
                client = Ledgelings.ChatClient.LmStudio(url, talkModel.Trim());
                break;
            default:
                var key = openRouterKey.Trim();
                if (key.Length == 0) return null;
                client = Ledgelings.ChatClient.OpenRouter(key, openRouterModel.Trim());
                break;
        }
        client.LineTokens = lineTokens;
        return client;
    }

    /// <summary>A model is chosen as the brain: LM Studio or OpenRouter. Off with the
    /// built-in lines, which is how a fresh install starts; the features that
    /// only a model can do are greyed out then, saying so (<see cref="NeedsModel"/>).</summary>
    public bool HasModel => brain != BrainKind.Script;

    /// <summary>Why <see cref="ChatClient"/> came back empty, in words for the menu and the settings window.</summary>
    public string BrainProblem => brain switch
    {
        BrainKind.Script => NeedsModel,
        BrainKind.LmStudio => "LM Studio server address is not a URL",
        _ => "no OpenRouter API key; add one in Settings › Talk",
    };

    public void ResetPrompts()
    {
        SystemPrompt = Banter.DefaultSystemPrompt;
        LinePrompt = Banter.DefaultLinePrompt;
        ReplyPrompt = Banter.DefaultReplyPrompt;
    }
}
