namespace Ledgelings.Tests;

/// <summary>The ledger as the app uses it: records land on disk, the summary refreshes, local calls are free.</summary>
public class SpendLedgerTests
{
    [Fact]
    public void RecordingUpdatesTheSummaryAndLocalCallsCostNothing()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-spend-" + Guid.NewGuid());
        try
        {
            var ledger = new SpendLedger(dir);
            Assert.Equal(0, ledger.Summary.AllTime.Calls);
            ledger.Record(ChatClient.Provider.OpenRouter, "m", new Spend.Usage(10, 5, 0.001));
            ledger.Record(ChatClient.Provider.LmStudio, "local", new Spend.Usage(10, 5, null));
            Assert.True(ledger.Summary.AllTime.Calls == 2 && ledger.Summary.AllTime.Unpriced == 0);
            Assert.True(Math.Abs(ledger.Summary.AllTime.Cost - 0.001) < 1e-9, "LM Studio is free, so its call is priced at zero");
            Assert.Equal(new[] { "m", "local" }, ledger.Summary.ByModel.Select(e => e.Model));
            Assert.True(new SpendLedger(dir).Summary.AllTime.Calls == 2, "read back from disk on the next launch");
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
