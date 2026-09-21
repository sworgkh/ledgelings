using System.ComponentModel;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The talking half of the settings: which brain, its address and key, the cast and the prompts.</summary>
public sealed partial class AppSettings
{
    public const string DefaultTalkServer = "http://localhost:1234";
    public const string DefaultTalkModel = "google/gemma-3-1b";
    public const string DefaultOpenRouterModel = "anthropic/claude-haiku-4.5";
    /// <summary>Seconds a speech bubble stays up, for a line of typical length.</summary>
    public const double BubbleMin = 4, BubbleMax = 60;
    /// <summary>Minutes a gifted flower stays on a head before it wilts away.</summary>
    public const double FlowerMin = 0.5, FlowerMax = 30;

    private bool talkEnabled;
    private ChatClient.Provider brainProvider;
    private string talkServer = "", talkModel = "", openRouterModel = "", openRouterKey = "";
    private double bubbleSeconds, flowerMinutes;
    private Dictionary<string, List<Character>> casts = new();
    private string systemPrompt = "", linePrompt = "", replyPrompt = "";

    private void LoadTalk()
    {
        talkEnabled = store.Get<bool?>("talkEnabled") ?? true;
        brainProvider = Enum.TryParse<Ledgelings.ChatClient.Provider>(store.Get<string>("brainProvider"), true, out var p) ? p : Ledgelings.ChatClient.Provider.LmStudio;
        talkServer = store.Get<string>("talkServer") ?? DefaultTalkServer;
        talkModel = store.Get<string>("talkModel") ?? DefaultTalkModel;
        openRouterModel = store.Get<string>("openRouterModel") ?? DefaultOpenRouterModel;
        openRouterKey = secrets.Get(KeyAccount) ?? "";
        bubbleSeconds = Math.Clamp(store.Get<double?>("bubbleSeconds") ?? Banter.DefaultBubbleSeconds, BubbleMin, BubbleMax);
        flowerMinutes = Math.Clamp(store.Get<double?>("flowerMinutes") ?? 2, FlowerMin, FlowerMax);
        casts = store.Get<Dictionary<string, List<Character>>>("casts") ?? new Dictionary<string, List<Character>>();
        systemPrompt = store.Get<string>("systemPrompt") ?? Banter.DefaultSystemPrompt;
        linePrompt = store.Get<string>("linePrompt") ?? Banter.DefaultLinePrompt;
        replyPrompt = store.Get<string>("replyPrompt") ?? Banter.DefaultReplyPrompt;
    }

    public bool TalkEnabled { get => talkEnabled; set => Put(ref talkEnabled, value, "talkEnabled"); }

    /// <summary>Which model answers, for banter and for anything else that wants words.</summary>
    public ChatClient.Provider BrainProvider
    {
        get => brainProvider;
        set { if (Put(ref brainProvider, value, "brainProvider")) store.Set("brainProvider", value.ToString()); }
    }

    /// <summary>LM Studio's local server and the model loaded in it.</summary>
    public string TalkServer { get => talkServer; set => Put(ref talkServer, value, "talkServer"); }
    public string TalkModel { get => talkModel; set => Put(ref talkModel, value, "talkModel"); }
    public string OpenRouterModel { get => openRouterModel; set => Put(ref openRouterModel, value, "openRouterModel"); }

    /// <summary>Lives in the Credential Manager, never in the settings file. Empty means no key.</summary>
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

    public string SystemPrompt { get => systemPrompt; set => Put(ref systemPrompt, value, "systemPrompt"); }
    public string LinePrompt { get => linePrompt; set => Put(ref linePrompt, value, "linePrompt"); }
    public string ReplyPrompt { get => replyPrompt; set => Put(ref replyPrompt, value, "replyPrompt"); }

    /// <summary>The cast of a species: the user's edit if there is one, else <paramref name="fallback"/> (the sheet's).</summary>
    public IReadOnlyList<Character> CastOf(string species, IReadOnlyList<Character> fallback) =>
        casts.TryGetValue(species, out var own) && own.Count > 0 ? own : fallback;

    public bool HasOwnCast(string species) => casts.ContainsKey(species);

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

    /// <summary>The model any feature should ask, or null with <see cref="BrainProblem"/> saying what is missing.</summary>
    public ChatClient? ChatClient()
    {
        switch (brainProvider)
        {
            case Ledgelings.ChatClient.Provider.LmStudio:
                return TalkServerUri is Uri url ? Ledgelings.ChatClient.LmStudio(url, talkModel.Trim()) : null;
            default:
                var key = openRouterKey.Trim();
                return key.Length == 0 ? null : Ledgelings.ChatClient.OpenRouter(key, openRouterModel.Trim());
        }
    }

    /// <summary>Why <see cref="ChatClient"/> came back empty, in words for the menu and the settings window.</summary>
    public string BrainProblem => brainProvider == Ledgelings.ChatClient.Provider.LmStudio
        ? "LM Studio server address is not a URL"
        : "no OpenRouter API key; add one in Settings › Talk";

    public void ResetPrompts()
    {
        SystemPrompt = Banter.DefaultSystemPrompt;
        LinePrompt = Banter.DefaultLinePrompt;
        ReplyPrompt = Banter.DefaultReplyPrompt;
    }
}
