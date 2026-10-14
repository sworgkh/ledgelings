using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The bonds half of the settings: whether pairs who live together get stories, when, for how long, and the prompt that writes them.</summary>
public sealed partial class AppSettings
{
    /// <summary>Hours a pair must share the screen before the model writes them a story.</summary>
    public const double PlotAfterMin = 0.25, PlotAfterMax = 72;
    /// <summary>Conversations one story lasts.</summary>
    public const int PlotLengthMin = 2, PlotLengthMax = 20;

    private bool plotsEnabled;
    private double plotAfterHours;
    private int plotLength;
    private string plotPrompt = "";
    /// <summary>Words a pair's storyline (their story so far) is kept to.</summary>
    public const int StoryWordsMin = 30, StoryWordsMax = 200;
    /// <summary>Moments since the last story the prompt lists one by one.</summary>
    public const int StoryMomentsMin = 2, StoryMomentsMax = 20;
    private bool storylinesEnabled;
    private int storyWords;
    private int storyMoments;

    private void LoadBonds()
    {
        plotsEnabled = store.Get<bool?>("plotsEnabled") ?? true;
        // An hour: a colony that runs all day gets its first stories the same morning.
        plotAfterHours = Math.Clamp(store.Get<double?>("plotAfterHours") ?? 1, PlotAfterMin, PlotAfterMax);
        plotLength = Math.Clamp(store.Get<int?>("plotLength") ?? 6, PlotLengthMin, PlotLengthMax);
        // A saved copy of a shipped prompt from before storylines is the shipped one now.
        var saved = store.Get<string>("plotPrompt");
        plotPrompt = saved is not null && !Bonds.EarlierPlotPrompts.Contains(saved) ? saved : Bonds.PlotPromptIn(language);
        storylinesEnabled = store.Get<bool?>("storylinesEnabled") ?? true;
        // 80 words: a few weeks of a friendship in about 110 tokens.
        storyWords = Math.Clamp(store.Get<int?>("storyWords") ?? Bonds.StoryWords, StoryWordsMin, StoryWordsMax);
        storyMoments = Math.Clamp(store.Get<int?>("storyMoments") ?? Bonds.StoryMoments, StoryMomentsMin, StoryMomentsMax);
    }

    /// <summary>Pairs who have lived together a while get a small story, written by the
    /// model, that colours their next few conversations.</summary>
    public bool PlotsEnabled { get => plotsEnabled; set => Put(ref plotsEnabled, value, "plotsEnabled"); }
    public double PlotAfterHours { get => plotAfterHours; set => Put(ref plotAfterHours, Math.Clamp(value, PlotAfterMin, PlotAfterMax), "plotAfterHours"); }
    public int PlotLength { get => plotLength; set => Put(ref plotLength, Math.Clamp(value, PlotLengthMin, PlotLengthMax), "plotLength"); }
    public string PlotPrompt { get => plotPrompt; set => Put(ref plotPrompt, value, "plotPrompt"); }

    /// <summary>Each new story grows from the pair's whole shared history: a short
    /// chronicle rewritten with every story, plus what they lived through since.</summary>
    public bool StorylinesEnabled { get => storylinesEnabled; set => Put(ref storylinesEnabled, value, "storylinesEnabled"); }
    public int StoryWords { get => storyWords; set => Put(ref storyWords, Math.Clamp(value, StoryWordsMin, StoryWordsMax), "storyWords"); }
    public int StoryMoments { get => storyMoments; set => Put(ref storyMoments, Math.Clamp(value, StoryMomentsMin, StoryMomentsMax), "storyMoments"); }

    /// <summary>How much history a new story is told with; null when storylines are off.</summary>
    public Bonds.Telling? StoryTelling => storylinesEnabled ? new Bonds.Telling(storyWords, storyMoments) : null;

    public void ResetPlotPrompt() => PlotPrompt = Bonds.PlotPromptIn(language);
}
