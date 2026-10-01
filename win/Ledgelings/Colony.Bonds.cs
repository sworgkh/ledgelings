using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Living together: every pair on screen adds up time side by side, and a pair
/// that has shared the screen long enough gets a small story from the model,
/// which colours their next few conversations (<see cref="Core.Bonds"/>).</summary>
public sealed partial class Colony
{
    /// <summary>Time together is added to the bonds, and saved, this often, in seconds.</summary>
    private const double BondSaveEvery = 30;

    private BondBook? bondBook;
    /// <summary>Who has lived beside whom, how they get on, and the story between them;
    /// <c>bonds.json</c> beside the spend file.</summary>
    public BondBook Bonds => bondBook ??= new BondBook(Spend.Ledger.Directory);
    /// <summary>Pairs whose next plot is being written, by <see cref="Core.Bonds.Key"/>.</summary>
    private readonly HashSet<string> plotting = new();
    /// <summary>Time together not yet added to the bonds; they are saved every half minute, not every frame.</summary>
    private double togetherPending;

    /// <summary>Every frame: everyone on screen spent <paramref name="dt"/> more with everyone else.</summary>
    partial void LiveTogether(double dt)
    {
        togetherPending += dt;
        if (togetherPending < BondSaveEvery) return;
        var seconds = togetherPending;
        togetherPending = 0;
        var names = Enumerable.Range(0, creatures.Count).Select(i => CharacterFor(i).Name).ToList();
        Bonds.Change(book => book.LiveTogether(seconds, names));
    }

    /// <summary>What goes into creature <paramref name="i"/>'s prompt about <paramref name="j"/>. Empty when plots are off,
    /// or the two have no bond or story yet.</summary>
    private string Relationship(int i, int j)
    {
        if (!Settings.PlotsEnabled) return "";
        string a = CharacterFor(i).Name, b = CharacterFor(j).Name;
        return Core.Bonds.Context(Bonds.Bond(a, b), a, b);
    }

    /// <summary>The story running between two creatures, for the chat log: "part 2 of 6: …".</summary>
    private string? PlotLabel(int i, int j)
    {
        if (!Settings.PlotsEnabled || Bonds.Bond(CharacterFor(i).Name, CharacterFor(j).Name)?.Plot is not Core.Bonds.Plot plot) return null;
        return L10n.Tr("part %d of %d: %@", Math.Min(plot.Told + 1, plot.Length), plot.Length, plot.Text);
    }

    /// <summary>A conversation between <paramref name="a"/> and <paramref name="b"/> (names) ended: count it, and ask for
    /// their next story if they are due one.</summary>
    private void Talked(string a, string b, IReadOnlyList<ChatLog.Line> lines)
    {
        if (lines.Count == 0) return;
        Bonds.Change(book => book.Talked(a, b, lines));
        WritePlotIfDue(a, b);
    }

    /// <summary>One model call, in the background, for the pair's next story; ready for
    /// their next conversation. Recorded as <see cref="Core.Spend.Purpose.Plots"/> whatever comes back.
    /// <paramref name="now"/>: ask even if they have not lived together long enough (the Mac's <c>--plot</c>).</summary>
    public void WritePlotIfDue(string a, string b, bool now = false)
    {
        var key = Core.Bonds.Key(a, b);
        if (now) Bonds.Change(book => book.Update(a, b, bond => { bond.Plot = null; bond.LastAsked = null; }));
        if (!Settings.PlotsEnabled || Settings.Brain == BrainKind.Script || plotting.Contains(key)) return;
        if (!Bonds.Book.NeedsPlot(a, b, now ? 0 : Settings.PlotAfterHours * 3600, DateTimeOffset.Now)) return;
        if (Bonds.Bond(a, b) is not Core.Bonds.Bond bond || Settings.ChatClient() is not ChatClient service) return;
        var i = Enumerable.Range(0, creatures.Count).Cast<int?>().FirstOrDefault(k => CharacterFor(k!.Value).Name == a);
        var j = Enumerable.Range(0, creatures.Count).Cast<int?>().FirstOrDefault(k => CharacterFor(k!.Value).Name == b);
        if (i is not int ai || j is not int bj) return;
        var length = Settings.PlotLength;
        var values = Core.Bonds.PlotValues(bond, (a, KindOf(ai), CharacterFor(ai).Persona), (b, KindOf(bj), CharacterFor(bj).Persona), length);
        var prompt = Banter.Render(Settings.PlotPrompt, values);
        plotting.Add(key);
        Trace?.Invoke($"plot: asking for {key}");
        _ = WritePlot(service, a, b, key, prompt, length);
    }

    private async Task WritePlot(ChatClient service, string a, string b, string key, string prompt, int length)
    {
        double? cost = null;
        Core.Bonds.Written? written = null;
        try
        {
            // Room for a thinking model to think a little and still answer: at 160
            // tokens one spent them all thinking and sent nothing back.
            var answer = await service.Reply(Core.Bonds.PlotSystemPrompt, prompt, Core.Bonds.PlotMaxTokens, reasoning: "low");
            if (answer.Usage is Spend.Usage usage)
            {
                if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
                cost = usage.Cost;
                Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Plots);
            }
            written = Core.Bonds.Parse(answer.Text);
            if (written is null) Console.Error.WriteLine("Ledgelings plot: no PLOT line in " + System.Text.Json.JsonSerializer.Serialize(answer.Text));
        }
        catch (ChatClient.Failure e)
        {
            Console.Error.WriteLine("Ledgelings plot: " + e.Message);
        }
        plotting.Remove(key);
        var at = DateTimeOffset.Now;
        Bonds.Change(book =>
        {
            book.Asked(a, b, at, cost);
            if (written is not null) book.Begin(a, b, written, length, at);
        });
        if (written is not null)
        {
            TalkStatus = L10n.Tr("%@ and %@: %@", a, b, written.Plot);
            Trace?.Invoke($"plot: {key} · bond: {written.Bond ?? "-"} · plot: {written.Plot}");
        }
    }
}
