namespace Ledgelings.Core.Tests;

/// <summary>Conversations on disk: one JSON-lines file per day.</summary>
public class ChatLogTests
{
    static string Temp() => Path.Combine(Path.GetTempPath(), "ledgelings-chats-" + Guid.NewGuid().ToString("N"));

    static DateTimeOffset Local(int year, int month, int day, int hour, int minute = 0) =>
        new(new DateTime(year, month, day, hour, minute, 0, DateTimeKind.Local));

    static void Remove(string dir)
    {
        try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    static ChatLog.Exchange Exchange(DateTimeOffset time, string first = "Move, boulder.", string? reply = "Says the pebble.")
    {
        var lines = new List<ChatLog.Line> { new("Dot", first) };
        if (reply is not null) lines.Add(new("Blocky", reply));
        return new ChatLog.Exchange
        {
            Time = time,
            Situation = "It is day. Dot is on the bottom edge. Blocky is on the bottom edge.",
            Provider = "LM Studio",
            Model = "google/gemma-3-1b",
            Lines = lines,
        };
    }

    [Fact]
    public void AnExchangeMayCarryWhatItCostAndOldLinesStillRead()
    {
        var log = new ChatLog(Temp());
        try
        {
            var noon = Local(2026, 9, 20, 12);
            var priced = Exchange(noon);
            priced.Cost = 0.0007; priced.Tokens = 410;
            log.Append(priced);
            var old = "{\"time\":\"2026-09-20T13:00:00Z\",\"situation\":\"s\",\"provider\":\"LM Studio\",\"model\":\"m\",\"lines\":[]}";
            File.AppendAllText(log.File("2026-09-20"), old + "\n");
            var back = log.Exchanges("2026-09-20");
            Assert.Equal(2, back.Count);
            Assert.True(back[0].Cost == 0.0007 && back[0].Tokens == 410);
            Assert.True(back[1].Cost == null && back[1].Tokens == null);
        }
        finally { Remove(log.Directory); }
    }

    [Fact]
    public void ADayIsNamedByTheLocalCalendarDate()
    {
        var late = Local(2026, 9, 18, 23, 59);
        Assert.Equal("2026-09-18", ChatLog.Day(late));
    }

    [Fact]
    public void ExchangesAppendToTheDaysFileAndComeBackInOrder()
    {
        var log = new ChatLog(Temp());
        try
        {
            var noon = Local(2026, 9, 18, 12);
            log.Append(Exchange(noon));
            log.Append(Exchange(noon.AddSeconds(600), first: "Still here?", reply: null));
            var back = log.Exchanges("2026-09-18");
            Assert.Equal(2, back.Count);
            Assert.Equal(new[] { "Move, boulder.", "Says the pebble." }, back[0].Lines.Select(l => l.Text));
            Assert.True(back[1].Lines.Count == 1 && back[1].Time > back[0].Time);
            Assert.True(back[0].Model == "google/gemma-3-1b" && back[0].Provider == "LM Studio");
            Assert.True(File.Exists(Path.Combine(log.Directory, "2026-09-18.jsonl")));
        }
        finally { Remove(log.Directory); }
    }

    [Fact]
    public void DaysAreListedNewestFirstAndOnlyRealLogsCount()
    {
        var log = new ChatLog(Temp());
        try
        {
            log.Append(Exchange(Local(2026, 9, 1, 9)));
            log.Append(Exchange(Local(2026, 9, 18, 9)));
            log.Append(Exchange(Local(2026, 8, 30, 9)));
            File.WriteAllText(Path.Combine(log.Directory, "notes.txt"), "junk");
            Assert.Equal(new[] { "2026-09-18", "2026-09-01", "2026-08-30" }, log.Days());
        }
        finally { Remove(log.Directory); }
    }

    [Fact]
    public void ABrokenLineIsSkippedNotFatal()
    {
        var log = new ChatLog(Temp());
        try
        {
            var noon = Local(2026, 9, 18, 12);
            log.Append(Exchange(noon));
            var file = Path.Combine(log.Directory, "2026-09-18.jsonl");
            File.AppendAllText(file, "{not json\n");
            log.Append(Exchange(noon.AddSeconds(60)));
            Assert.Equal(2, log.Exchanges("2026-09-18").Count);
        }
        finally { Remove(log.Directory); }
    }

    [Fact]
    public void AnEmptyOrMissingFolderHasNoDays()
    {
        var log = new ChatLog(Temp());
        Assert.Empty(log.Days());
        Assert.Empty(log.Exchanges("2026-01-01"));
    }
}
