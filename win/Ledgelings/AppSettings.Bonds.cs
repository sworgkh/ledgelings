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

    private void LoadBonds()
    {
        plotsEnabled = store.Get<bool?>("plotsEnabled") ?? true;
        // An hour: a colony that runs all day gets its first stories the same morning.
        plotAfterHours = Math.Clamp(store.Get<double?>("plotAfterHours") ?? 1, PlotAfterMin, PlotAfterMax);
        plotLength = Math.Clamp(store.Get<int?>("plotLength") ?? 6, PlotLengthMin, PlotLengthMax);
        plotPrompt = store.Get<string>("plotPrompt") ?? Bonds.PlotPromptIn(language);
    }

    /// <summary>Pairs who have lived together a while get a small story, written by the
    /// model, that colours their next few conversations.</summary>
    public bool PlotsEnabled { get => plotsEnabled; set => Put(ref plotsEnabled, value, "plotsEnabled"); }
    public double PlotAfterHours { get => plotAfterHours; set => Put(ref plotAfterHours, Math.Clamp(value, PlotAfterMin, PlotAfterMax), "plotAfterHours"); }
    public int PlotLength { get => plotLength; set => Put(ref plotLength, Math.Clamp(value, PlotLengthMin, PlotLengthMax), "plotLength"); }
    public string PlotPrompt { get => plotPrompt; set => Put(ref plotPrompt, value, "plotPrompt"); }

    public void ResetPlotPrompt() => PlotPrompt = Bonds.PlotPromptIn(language);
}
