namespace Ledgelings.Core.Tests;

/// <summary>What the creatures' talking costs: one record per model call, summed by day, month and model.</summary>
public class SpendTests
{
    static readonly DateTimeOffset Noon = new(new DateTime(2026, 9, 20, 12, 0, 0, DateTimeKind.Local));

    static Spend.Record Record(double hoursAgo, string model = "google/gemini-2.5-flash-lite", double? cost = 0.0004, int prompt = 300, int completion = 40) =>
        new(Noon.AddSeconds(-hoursAgo * 3600), "OpenRouter", model, new Spend.Usage(prompt, completion, cost));

    [Fact]
    public void TodayThisMonthAndAllTimeAreSummedFromTheRecords()
    {
        var records = new[]
        {
            Record(1), Record(3, cost: 0.0006), Record(30, model: "anthropic/claude-haiku-4.5", cost: 0.002),
            Record(24 * 25, cost: 0.001), Record(24 * 400, cost: 0.5),
        };
        var s = Spend.Summarise(records, Noon);
        Assert.True(s.Today.Calls == 2 && Math.Abs(s.Today.Cost - 0.001) < 1e-9 && s.Today.PromptTokens == 600 && s.Today.CompletionTokens == 80);
        Assert.True(s.Month.Calls == 3 && Math.Abs(s.Month.Cost - 0.003) < 1e-9);
        Assert.True(s.AllTime.Calls == 5 && Math.Abs(s.AllTime.Cost - 0.504) < 1e-9);
        Assert.True(s.ByModel.Select(m => m.Model).SequenceEqual(new[] { "google/gemini-2.5-flash-lite", "anthropic/claude-haiku-4.5" }), "dearest model first");
        Assert.Equal(4, s.ByModel[0].Total.Calls);
    }

    [Fact]
    public void ACallWithoutAPriceIsCountedButFlagged()
    {
        var s = Spend.Summarise(new[] { Record(1, cost: null), Record(2) }, Noon);
        Assert.True(s.Today.Calls == 2 && s.Today.Unpriced == 1 && Math.Abs(s.Today.Cost - 0.0004) < 1e-9);
        Assert.Equal(new Spend.Total(), Spend.Summarise(Array.Empty<Spend.Record>(), Noon).AllTime);
    }

    [Fact]
    public void MoneyIsShownToTheCentOrToTheTenthOfACent()
    {
        Assert.Equal("$0.00", Spend.Label(0));
        Assert.Equal("<$0.001", Spend.Label(0.00004));
        Assert.Equal("$0.004", Spend.Label(0.0042));
        Assert.Equal("$0.037", Spend.Label(0.037));
        Assert.Equal("$1.50", Spend.Label(1.5));
        Assert.Equal("$12.35", Spend.Label(12.345));
    }

    [Fact]
    public void TheLedgerKeepsRecordsOnDiskInOrder()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-spend-" + Guid.NewGuid().ToString("N"));
        try
        {
            var ledger = new Spend.Ledger(dir);
            Assert.Empty(ledger.Records());
            ledger.Append(Record(2));
            ledger.Append(Record(1, cost: null));
            var back = ledger.Records();
            Assert.True(back.Count == 2 && back[0].Usage.Cost == 0.0004 && back[1].Usage.Cost == null);
            Assert.True(Math.Abs((back[0].Time - Record(2).Time).TotalSeconds) < 1);
            Assert.Equal("spend.jsonl", Path.GetFileName(ledger.File));
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }
}
