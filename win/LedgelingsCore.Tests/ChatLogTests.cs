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
    [Fact]
    public void VoiceChargesLiveInASideFileTheDayListIgnores()
    {
        var log = new ChatLog(Temp());
        try
        {
            var now = DateTimeOffset.FromUnixTimeSeconds(DateTimeOffset.Now.ToUnixTimeSeconds());      // the file keeps whole seconds
            log.Append(new ChatLog.Exchange { Time = now, Provider = "Built-in lines", Lines = new() { new("Blocky", "Hi.") } });
            var charge = new ChatLog.VoiceCharge(now, "Blocky", "Hi.", "hexgrad/kokoro-82m", 0.00003);
            log.AppendVoice(charge);
            Assert.Equal(new[] { charge }, log.VoiceCharges(ChatLog.Day(now)));
            Assert.True(log.Days().SequenceEqual(new[] { ChatLog.Day(now) }), "the .voice.jsonl file is not a day of its own");
            Assert.Single(log.Exchanges(ChatLog.Day(now)));
        }
        finally { Remove(log.Directory); }
    }

    [Fact]
    public void EachVoiceChargeGoesToTheLatestConversationWithThatLine()
    {
        var t0 = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        ChatLog.Exchange Talk(double at, params (string Who, string Text)[] lines) =>
            new() { Time = t0.AddSeconds(at), Lines = lines.Select(l => new ChatLog.Line(l.Who, l.Text)).ToList() };
        var exchanges = new[]
        {
            Talk(0, ("Blocky", "*sighs* Nice edge."), ("Pip", "Thanks!")),
            Talk(600, ("Blocky", "*sighs* Nice edge."), ("Pip", "Again?")),        // the script repeats itself
        };
        ChatLog.VoiceCharge Said(double at, string who, string text, double? cost, bool kept = false) =>
            new(t0.AddSeconds(at), who, text, "m", cost, kept);
        var totals = ChatLog.VoiceTotals(new[]
        {
            Said(1, "Blocky", "Nice edge.", 0.002),       // words as spoken: no stage direction
            Said(5, "Pip", "Thanks!", null),
            Said(601, "Blocky", "Nice edge.", 0, kept: true),
            Said(605, "Pip", "Again?", 0.001),
            Said(700, "Zed", "Nobody wrote this down.", 0.5),
        }, exchanges);
        Assert.True(totals[0].Lines == 2 && totals[0].Cost == 0.002 && totals[0].Unpriced == 1 && totals[0].Kept == 0);
        Assert.True(totals[1].Lines == 1 && totals[1].Cost == 0.001 && totals[1].Kept == 1);
        Assert.True(totals.Count == 2, "a line with no conversation is left out");
    }

    [Fact]
    public void AModelConversationWrittenDownAfterItsLinesStillGetsThem()
    {
        var t0 = DateTimeOffset.FromUnixTimeSeconds(2_000_000);
        var x = new ChatLog.Exchange { Time = t0.AddSeconds(20), Lines = new() { new("Dot", "Hm.") } };
        var totals = ChatLog.VoiceTotals(new[] { new ChatLog.VoiceCharge(t0, "Dot", "Hm.", "m", 0.01) }, new[] { x });
        Assert.Equal(0.01, totals[0].Cost);
    }

    [Fact]
    public void TimesAreWrittenAndReadTheMacsWayWhateverTheUsersCulture()
    {
        var log = new ChatLog(Temp());
        var before = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("th-TH");      // a Buddhist-era calendar
            var noon = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
            log.Append(Exchange(noon));
            var day = ChatLog.Day(noon);
            Assert.Contains("\"time\":\"2026-09-20T12:00:00Z\"", File.ReadAllText(log.File(day)));
            File.AppendAllText(log.File(day), "{\"time\":\"2026-09-20T13:00:00Z\",\"situation\":\"\",\"provider\":\"\",\"model\":\"\",\"lines\":[]}\n");
            var back = log.Exchanges(day);
            Assert.True(back.Count == 2 && back[0].Time == noon && back[1].Time == noon.AddHours(1), "a Mac-written time reads too");
        }
        finally { System.Globalization.CultureInfo.CurrentCulture = before; Remove(log.Directory); }
    }

    [Fact]
    public void ALineWithADamagedTimeIsSkippedNotFatal()
    {
        var log = new ChatLog(Temp());
        try
        {
            var noon = Local(2026, 9, 18, 12);
            log.Append(Exchange(noon));
            File.AppendAllText(log.File("2026-09-18"), "{\"time\":\"yesterday-ish\",\"situation\":\"\",\"provider\":\"\",\"model\":\"\",\"lines\":[]}\n");
            log.Append(Exchange(noon.AddSeconds(60)));
            Assert.Equal(2, log.Exchanges("2026-09-18").Count);
        }
        finally { Remove(log.Directory); }
    }
}
