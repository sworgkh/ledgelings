namespace Ledgelings.Core.Tests;

public class TeaPartyTests
{
    /// <summary>Step the party <paramref name="seconds"/> in tenths, collecting what it asks for.</summary>
    static List<TeaParty.Event> Run(TeaParty party, double start, double seconds, Action<double, TeaParty.Event, TeaParty>? each = null)
    {
        var events = new List<TeaParty.Event>();
        var t = start;
        while (t < start + seconds - 1e-9)
        {
            t += 0.1;
            foreach (var e in party.Update(t)) { events.Add(e); each?.Invoke(t, e, party); }
        }
        return events;
    }

    [Fact]
    public void APartySeatsLaysTheTableTakesTurnsAndPacksAwayOnTime()
    {
        var party = new TeaParty(2, 5, 0, 60, 6);
        Assert.True(party.CurrentPhase == TeaParty.Phase.Seating && party.Scale(0) == 0 && party.IsOn);
        party.Seated(1);
        Assert.Equal(TeaParty.Phase.Laying, party.CurrentPhase);
        party.Update(1.2);
        Assert.True(Math.Abs(party.Scale(1.2) - 0.5) < 1e-9, "grows up out of the edge");
        // Each round takes 10 s to say; the party answers with the next after the sip.
        var tellers = new List<int>();
        var events = Run(party, 1.2, 80, (t, e, p) =>
        {
            if (e is not TeaParty.Event.Round round) return;
            tellers.Add(round.Teller);
            Assert.True(new HashSet<int> { round.Teller, round.Listener }.SetEquals(new[] { 2, 5 }));
            p.RoundDone(t + 10);          // said by then; its own clock catches up below
        });
        Assert.Equal(new[] { 2, 5, 2, 5 }, tellers.Take(4));      // they take turns telling, a first
        Assert.True(events[^1] is TeaParty.Event.Finished && party.IsOver);
        Assert.Equal(tellers.Count, party.Rounds);
        Assert.True(party.Rounds >= 3 && party.Rounds <= 4, $"one round every 16 s or so over a minute: {party.Rounds}");
    }

    [Fact]
    public void ARoundUnderWayIsLetFinishAfterTheTimeIsUp()
    {
        var party = new TeaParty(0, 1, 0, 5, 0);
        party.Seated(0);
        Assert.Equal(new TeaParty.Event[] { new TeaParty.Event.Round(0, 1) }, Run(party, 0, 2));
        Assert.True(Run(party, 2, 20).Count == 0 && party.CurrentPhase == TeaParty.Phase.Tea, "still telling at 22 s");
        party.RoundDone(22);
        Assert.Equal(new TeaParty.Event[] { new TeaParty.Event.Finished() }, Run(party, 22, 1));      // then straight to packing, no new round
    }

    [Fact]
    public void AStragglerStillGetsTheTableAfterTheSeatingCap()
    {
        var party = new TeaParty(0, 1, 0, 60, 1);
        Run(party, 0, 3.9);
        Assert.Equal(TeaParty.Phase.Seating, party.CurrentPhase);
        Run(party, 3.9, 0.2);
        Assert.Equal(TeaParty.Phase.Laying, party.CurrentPhase);
    }

    [Fact]
    public void PostponingARoundAsksForItAgainAndCountsNothing()
    {
        var party = new TeaParty(0, 1, 0, 60, 1);
        party.Seated(0);
        Assert.Single(Run(party, 0, 2));
        party.Postpone(2);
        Assert.True(party.Rounds == 0 && !party.InRound);
        Assert.Equal(new TeaParty.Event[] { new TeaParty.Event.Round(0, 1) }, Run(party, 2, 1.05));      // the same teller again
    }

    [Fact]
    public void BreakingUpPacksTheTableOrWithNoTableEndsAtOnce()
    {
        var laid = new TeaParty(0, 1, 0, 60, 1);
        laid.Seated(0);
        Run(laid, 0, 2);
        laid.End(2);
        Assert.True(laid.CurrentPhase == TeaParty.Phase.Packing && !laid.IsOn && !laid.InRound);
        Assert.True(Math.Abs(laid.Scale(2.25) - 0.5) < 1e-9);
        Assert.Equal(new TeaParty.Event[] { new TeaParty.Event.Finished() }, Run(laid, 2, 1));

        var seating = new TeaParty(0, 1, 0, 60, 1);
        seating.End(1);
        Assert.True(seating.IsOver, "no table yet, nothing to pack");
    }

    [Fact]
    public void SeatsAreEitherSideOfTheMiddleAndNeverRoundACorner()
    {
        var loop = new EdgeLoop(new Rect(10, 10, 780, 580));
        // On the floor, a middle at x = 300: the one facing right (+1) sits to the left of it.
        var middle = new Pt(300, 10);
        var left = TeaParty.Seat(loop, 0, middle, 1, 50);
        var right = TeaParty.Seat(loop, 0, middle, -1, 50);
        Assert.NotNull(left); Assert.NotNull(right);
        Assert.Equal(new Pt(250, 10), loop.Point(left!.Value));
        Assert.Equal(new Pt(350, 10), loop.Point(right!.Value));
        // Near the corner there is no room for the one behind.
        Assert.Null(TeaParty.Seat(loop, 0, new Pt(40, 10), 1, 50));
        // On the right wall, going up: the same rule along its own direction.
        var up = TeaParty.Seat(loop, 1, new Pt(790, 300), 1, 40);
        Assert.NotNull(up);
        Assert.Equal(new Pt(790, 260), loop.Point(up!.Value));
    }

    [Fact]
    public void TheChanceIsAShareOfBumps()
    {
        var rng = new Random(11);
        var yes = Enumerable.Range(0, 2000).Count(_ => TeaParty.Wanted(10, rng));
        Assert.True(yes > 150 && yes < 250, $"about one in ten: {yes}");
        Assert.DoesNotContain(Enumerable.Range(0, 200), _ => TeaParty.Wanted(0, rng));
        Assert.All(Enumerable.Range(0, 200), _ => Assert.True(TeaParty.Wanted(100, rng)));
    }

    [Fact]
    public void EveryBuiltInCharacterHasItsOwnStoriesAndAnswers()
    {
        // The same 27 as the complaints: every built-in character, in its own voice.
        Assert.True(Tea.Stories.Keys.ToHashSet().SetEquals(Complaints.Lines.Keys));
        Assert.True(Tea.Replies.Keys.ToHashSet().SetEquals(Complaints.Lines.Keys));
        foreach (var (name, stories) in Tea.Stories)
        {
            Assert.True(stories.Length == 4 && stories.Distinct().Count() == 4, name);
            Assert.True(stories.All(s => !s.Contains('{')), $"{name}: a story needs nothing filled in");
        }
        foreach (var (name, replies) in Tea.Replies) Assert.True(replies.Length == 3, name);
        var all = Tea.Stories.Values.SelectMany(s => s).ToList();
        Assert.True(all.Distinct().Count() == all.Count, "nobody tells someone else's story");
    }

    [Fact]
    public void AStoryIsNotToldTwiceAtOnePartyAndAnAnswerNamesTheTeller()
    {
        var rng = new Random(3);
        var told = new HashSet<string>();
        for (int i = 0; i < 4; i++) told.Add(Tea.Story("Blocky", told, rng));
        Assert.True(told.SetEquals(Tea.Stories["Blocky"]));
        Assert.Contains(Tea.Story("Blocky", told, rng), Tea.Stories["Blocky"]);      // all told: one again
        Assert.Contains(Tea.Story("Someone New", new HashSet<string>(), rng), Tea.AnyoneStories);
        var replies = Enumerable.Range(0, 30).Select(_ => Tea.Reply("Pip", "Zed", rng)).ToList();
        Assert.All(replies, r => Assert.DoesNotContain("{other}", r));
        Assert.Contains(replies, r => r.Contains("Zed"));
    }

    [Fact]
    public void ThePromptsCarryWhoTheyAreAndWhatWasSaidAtTheTable()
    {
        Assert.True(Tea.SystemPrompt.Contains("{speakerPersona}") && Tea.SystemPrompt.Contains("{speakerKind}"));
        Assert.True(Tea.StoryPrompt.Contains("{party}") && Tea.ReplyPrompt.Contains("{line}"));
        Assert.Contains("just been poured", Tea.Transcript(new List<ChatLog.Line>()));
        var lines = Enumerable.Range(1, 10).Select(i => new ChatLog.Line(i % 2 == 0 ? "Pip" : "Zed", $"line {i}")).ToList();
        var shown = Tea.Transcript(lines);
        Assert.True(!shown.Contains("line 2\n") && shown.StartsWith("Zed: line 3") && shown.EndsWith("Pip: line 10"), "the last eight");
    }
}
