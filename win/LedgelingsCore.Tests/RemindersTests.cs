namespace Ledgelings.Core.Tests;

public class RemindersTests
{
    /// <summary>Jerusalem time: a real calendar with a weekend, fixed so the tests do not depend on this computer.</summary>
    private static readonly TimeZoneInfo calendar = TimeZoneInfo.FindSystemTimeZoneById("Asia/Jerusalem");

    private static DateTimeOffset At(int day, int hour, int minute = 0, int month = 9) =>
        Reminders.Instant(new DateTime(2026, month, day, hour, minute, 0), calendar);

    [Fact]
    public void AOneOffIsDueFromItsTimeAndFinishedOnceSent()
    {
        var r = new Reminders.Reminder("Call mom", At(26, 14, 30));
        Assert.False(r.IsDue(At(26, 14, 29)));
        Assert.True(r.IsDue(At(26, 14, 30)));
        Assert.True(r.IsDue(At(28, 9)), "missed while the computer was off: still delivered, late");
        r.MarkSent(At(26, 14, 31), calendar);
        Assert.True(r.IsFinished && !r.IsDue(At(30, 9)));
    }

    [Fact]
    public void ADailyReminderSkipsTheMorningsItMissedAndKeepsItsTime()
    {
        var r = new Reminders.Reminder("Stretch", At(20, 9), Reminders.Repeat.Daily);
        // Off for a week: one letter now, the next tomorrow at nine.
        r.MarkSent(At(26, 11), calendar);
        Assert.False(r.IsFinished);
        Assert.Equal(At(27, 9), r.Time);
        Assert.True(!r.IsDue(At(26, 23)) && r.IsDue(At(27, 9)));
    }

    [Fact]
    public void WeekdaysSkipTheWeekendAndWeeklyKeepsItsDay()
    {
        // 25 September 2026 is a Friday.
        var weekdays = new Reminders.Reminder("Stand-up", At(25, 10), Reminders.Repeat.Weekdays);
        weekdays.MarkSent(At(25, 10), calendar);
        Assert.Equal(At(28, 10), weekdays.Time);      // Friday → Monday
        var weekly = new Reminders.Reminder("Bins", At(25, 19), Reminders.Repeat.Weekly);
        weekly.MarkSent(At(25, 19, 1), calendar);
        Assert.Equal(At(2, 19, month: 10), weekly.Time);
    }

    [Fact]
    public void TheBookListsWaitingOnesFirstAndGivesTheDueOnesOldestFirst()
    {
        var book = new Reminders.Book();
        book.Add(new("later", At(27, 9)));
        book.Add(new("second", At(26, 10)));
        book.Add(new("first", At(26, 8)));
        book.Add(new("done", At(25, 8), sentAt: At(25, 8)));
        Assert.Equal(new[] { "first", "second" }, book.Due(At(26, 12)).Select(r => r.Text));
        Assert.Equal(new[] { "first", "second", "later", "done" }, book.Sorted.Select(r => r.Text));
        Assert.Equal("first", book.Upcoming?.Text);
        book.MarkSent(book.Reminders[2].Id, At(26, 12));
        book.ClearFinished();
        Assert.Equal(new[] { "later", "second" }, book.Reminders.Select(r => r.Text));
    }

    [Fact]
    public void TheBookSurvivesARelaunch()
    {
        var dir = Path.Combine(Path.GetTempPath(), "reminders-" + Guid.NewGuid());
        try
        {
            var store = new Reminders.Store(dir);
            Assert.Empty(store.Load().Reminders);
            var book = new Reminders.Book();
            book.Add(new("Water the plant", At(26, 18), Reminders.Repeat.Weekly));
            store.Save(book);
            Assert.True(new Reminders.Store(dir).Load().SameAs(book));
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    /// <summary>The Mac's file reads here, and ours reads there: sorted keys, capital ids, dates in UTC.</summary>
    [Fact]
    public void TheFileIsTheMacsFormat()
    {
        var dir = Path.Combine(Path.GetTempPath(), "reminders-" + Guid.NewGuid());
        try
        {
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "reminders.json"), """
                {
                  "reminders" : [
                    {
                      "id" : "6C4E2A57-0B6B-4C0B-9D0E-3B0E3E0B6A11",
                      "repeats" : "weekdays",
                      "sentAt" : "2026-09-25T07:00:00Z",
                      "text" : "Stand-up",
                      "time" : "2026-09-28T07:00:00Z"
                    }
                  ]
                }
                """);
            var store = new Reminders.Store(dir);
            var r = Assert.Single(store.Load().Reminders);
            Assert.Equal(Guid.Parse("6C4E2A57-0B6B-4C0B-9D0E-3B0E3E0B6A11"), r.Id);
            Assert.Equal(Reminders.Repeat.Weekdays, r.Repeats);
            Assert.Equal(At(28, 10), r.Time);
            Assert.Equal(At(25, 10), r.SentAt);
            store.Save(store.Load());
            var written = File.ReadAllText(store.File);
            Assert.Contains("\"id\": \"6C4E2A57-0B6B-4C0B-9D0E-3B0E3E0B6A11\"", written);
            Assert.Contains("\"time\": \"2026-09-28T07:00:00Z\"", written);
            Assert.Contains("\"repeats\": \"weekdays\"", written);
            Assert.True(written.IndexOf("\"id\"") < written.IndexOf("\"repeats\"") && written.IndexOf("\"text\"") < written.IndexOf("\"time\""), "sorted keys");
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void EveryBuiltInCharacterWritesTheReminderInItsOwnWords()
    {
        var everyone = Banter.DefaultCharacters.Select(c => c.Name).Concat(Letters.Voices.Keys).ToHashSet();
        var rng = new Random();
        foreach (var name in everyone)
        {
            Assert.True(Reminders.Notes.TryGetValue(name, out var lines) && lines.Count >= 2, $"{name} has its own reminder notes");
            Assert.True(lines!.All(l => l.Contains("{reminder}")), $"{name} names the reminder");
            Assert.Contains("stretch", Reminders.Note(name, "Stretch", rng).ToLowerInvariant());
        }
        Assert.Contains("Stretch", Reminders.Note("Somebody New", "Stretch", rng));
    }

    [Fact]
    public void MidSentenceTheReminderStartsSmallUnlessItShouts()
    {
        Assert.Equal("Well, call mom!", Reminders.Fill("Well, {reminder}!", "Call mom"));
        Assert.Equal("It's time for stretching.", Reminders.Fill("It's time for {reminder}.", "Stretching"));
        Assert.Equal("Well, NASA call!", Reminders.Fill("Well, {reminder}!", "NASA call"));
        Assert.Equal("Call mom! Now.", Reminders.Fill("{reminder}! Now.", "Call mom"));
    }

    [Fact]
    public void ThePaperIsDrawnInBlockysRules()
    {
        var rows = Reminders.Paper(40, 24);
        Assert.True(rows.Length == 24 && rows.All(r => r.Length == 40));
        Assert.True(rows[0][0] == Reminders.Ink.Rim && rows[0][39] == Reminders.Ink.Rim && rows[23][0] == Reminders.Ink.Rim, "a dark rim all round");
        Assert.True(rows[1][5] == Reminders.Ink.Light && rows[5][1] == Reminders.Ink.Light, "a light line top-left");
        Assert.True(rows[22][5] == Reminders.Ink.Shade && rows[5][38] == Reminders.Ink.Shade, "a shade line bottom-right");
        Assert.Null(rows[23][39]);      // the bottom-right corner is folded down
        Assert.Contains(rows.SelectMany(r => r), i => i == Reminders.Ink.DeepShade);      // and the flap shows
        Assert.Equal(Reminders.Ink.Crease, rows[12][10]);      // the creases of an unfolded plane
    }

    [Fact]
    public void TheNoteStepsTheClockAlongItsLines()
    {
        var c = calendar;
        Assert.Equal(At(26, 14, 15), Reminders.Step(At(26, 14, 7), 15, c));
        Assert.Equal(At(26, 14, 0), Reminders.Step(At(26, 14, 7), -15, c));
        Assert.Equal(At(26, 14, 30), Reminders.Step(At(26, 14, 15), 15, c));
        Assert.Equal(At(26, 14, 0), Reminders.Step(At(26, 14, 15), -15, c));
        Assert.Equal(At(27, 0, 0), Reminders.Step(At(26, 23, 50), 15, c));      // past midnight: the next day
        Assert.Equal(At(25, 23, 45), Reminders.Step(At(26, 0, 0), -15, c));
        Assert.Equal(At(26, 14, 15), Reminders.Step(At(26, 14, 15).AddSeconds(20), -15, c));      // seconds past a line: back to that line
    }

    [Fact]
    public void TheDayAndTheClockAreNamedApart()
    {
        var c = calendar;
        var now = At(26, 12);
        Assert.Equal("Today", Reminders.Day(At(26, 18), now, c));
        Assert.Equal("Tomorrow", Reminders.Day(At(27, 9), now, c));
        Assert.Equal("Sat 3 Oct", Reminders.Day(At(3, 9, month: 10), now, c));
        Assert.Equal("09:05", Reminders.Clock(At(27, 9, 5), c));
        Assert.Equal("Tomorrow 09:05", Reminders.When(At(27, 9, 5), now, c));
    }
}
