namespace Ledgelings.Core.Tests;

/// <summary>Surfing (SPEC §7.10): the water, catching a wave, scoring, a wipe-out, and the end. The Mac's SurfTests; the
/// random numbers differ, so the assertions are about behaviour.</summary>
public class SurfTests
{
    private const double From = 25, To = 1415;

    private static (Plays.Surf Surf, Random Rng) Session(int count, int waves = 4, double length = 120, int seed = 1)
    {
        var rng = new Random(seed);
        var players = Enumerable.Range(0, count).ToList();
        var halves = players.ToDictionary(p => p, _ => 25.0);
        var at = players.ToDictionary(p => p, p => 200.0 + 150 * p);
        return (new Plays.Surf(players, halves, at, 0, From, To, 125, 55, waves, length, rng), rng);
    }

    /// <summary>Played until over (or <paramref name="limit"/> seconds), every event with its time.</summary>
    private static List<(double Time, Plays.Surf.Event Event)> Play(Plays.Surf surf, Random rng, double limit = 600)
    {
        var events = new List<(double, Plays.Surf.Event)>();
        var t = 0.0;
        while (!surf.IsFinished && t < limit)
        {
            t += 1.0 / 30;
            events.AddRange(surf.Update(1.0 / 30, rng).Select(e => (t, e)));
        }
        return events;
    }

    [Fact]
    public void TheWaterComesInRisesUnderTheCrestAndGoesOut()
    {
        var (surf, rng) = Session(1);
        Assert.Equal(0, surf.Surface(700));                                              // dry before the tide comes in
        var t = 0.0;
        while (surf.Wave is null && t < 20) { t += 1.0 / 30; surf.Update(1.0 / 30, rng); }
        Assert.Equal(1, surf.Tide);
        while (surf.Wave is { } w && Math.Abs(w.Crest - 700) > 4) surf.Update(1.0 / 30, rng);
        var crest = surf.Wave!.Crest;
        Assert.True(Math.Abs(surf.Surface(crest) - (55 + 125)) < 1, "the crest stands the wave's height over the calm water");
        Assert.Equal(55, surf.Surface(crest + surf.Way * surf.FaceWidth * 1.01));        // calm ahead of the face
        Assert.Equal(55, surf.Surface(crest - surf.Way * surf.BackWidth * 1.01));        // calm behind its back
        Assert.True(surf.Slope(crest + surf.Way * surf.FaceWidth * 0.5) * surf.Way < 0, "the face slopes down ahead of the crest");
        Play(surf, rng);
        Assert.True(surf.IsFinished && surf.Tide == 0);
        foreach (var r in surf.Riders) Assert.True(r.Y > 0 && r.Y < 25 * 2 + 20, "set down on the floor");
    }

    [Fact]
    public void EveryCountIsPlayedToTheEnd()
    {
        foreach (var count in new[] { 1, 2, 3, 5 })
        {
            var (surf, rng) = Session(count, waves: 3);
            var events = Play(surf, rng).Select(e => e.Event).ToList();
            Assert.True(surf.IsFinished, $"{count} surfers finish");
            Assert.True(events[0] is Plays.Surf.Event.TideIn && events[^1] is Plays.Surf.Event.Over);
            Assert.Equal(3, events.Count(e => e is Plays.Surf.Event.Wave));
            Assert.True(events.Any(e => e is Plays.Surf.Event.Caught), $"{count}: someone catches a wave");
            var won = events.OfType<Plays.Surf.Event.Won>().ToList();
            Assert.Single(won);
            if (count == 1) Assert.Empty(won[0].By);                                       // alone, nobody wins
            else
            {
                var best = surf.Riders.Max(r => r.Score);
                Assert.True(won[0].By.Count > 0 && won[0].By.All(i => surf.Scores[i] == best));
            }
        }
    }

    [Fact]
    public void ItEndsAfterTheWavesOrWhenTimeIsUp()
    {
        var (byCount, rng) = Session(2, waves: 2, length: 600);
        Play(byCount, rng);
        Assert.Equal(2, byCount.WavesRolled);
        var (byTime, rng2) = Session(2, waves: 20, length: 10);
        var events = Play(byTime, rng2);
        Assert.True(byTime.IsFinished && byTime.WavesRolled < 20, "time up stops new waves");
        var lastWave = events.Last(e => e.Event is Plays.Surf.Event.Wave).Time;
        Assert.True(lastWave <= Plays.Surf.TideTime + 10 + 0.1, "no wave starts once the time is up");
    }

    [Fact]
    public void ARideScoresItsSecondsAndTricksAndOnlyKickingOutBanksIt()
    {
        for (int seed = 1; seed <= 12; seed++)
        {
            var (surf, rng) = Session(3, waves: 4, seed: seed);
            var events = Play(surf, rng).Select(e => e.Event).ToList();
            foreach (var r in surf.Riders)
            {
                var banked = events.OfType<Plays.Surf.Event.KickOut>().Where(k => k.By == r.Index).Sum(k => k.Points);
                Assert.True(r.Score == banked, "the score is the rides kicked out of, nothing else");
            }
            Assert.Equal(events.Count(e => e is Plays.Surf.Event.Landed), surf.Riders.Sum(r => r.Tricks));
        }
        // A ride of about the wave's length scores ten a second, plus the tricks landed.
        var (one, rng1) = Session(1, waves: 1);
        double? rideStart = null;
        var t = 0.0;
        while (!one.IsFinished)
        {
            t += 1.0 / 30;
            foreach (var e in one.Update(1.0 / 30, rng1))
            {
                if (e is Plays.Surf.Event.Caught) rideStart = t;
                if (e is Plays.Surf.Event.KickOut k && rideStart is double s)
                {
                    var bonus = one.Riders[0].Tricks == 0 ? 0 : k.Points - (int)((t - s) * 10);
                    Assert.True(Math.Abs(k.Points - bonus - (int)((t - s) * Plays.Surf.PointsPerSecond)) <= 1);
                }
            }
        }
    }

    [Fact]
    public void AWipeOutSplashesLosesTheRideAndPaddlesBack()
    {
        var found = false;
        for (int seed = 1; seed <= 60 && !found; seed++)
        {
            var (surf, rng) = Session(2, waves: 4, seed: seed);
            var t = 0.0;
            int? wiped = null;
            var riding = new Dictionary<int, bool>();
            while (!surf.IsFinished && t < 600)
            {
                t += 1.0 / 30;
                foreach (var e in surf.Update(1.0 / 30, rng))
                {
                    switch (e)
                    {
                        case Plays.Surf.Event.Caught c: riding[c.By] = true; break;
                        case Plays.Surf.Event.Wipeout w:
                            Assert.True(riding.GetValueOrDefault(w.By), "only a rider wipes out");
                            Assert.True(Math.Abs(w.At.Y - surf.Surface(w.At.X)) < 1, "the splash is on the water");
                            Assert.False(surf.RiderOf(w.By)!.OnBoard);
                            riding[w.By] = false;
                            wiped = w.By;
                            break;
                        case Plays.Surf.Event.KickOut k:
                            Assert.True(riding.GetValueOrDefault(k.By), "a wiped-out ride is never banked");
                            riding[k.By] = false;
                            break;
                        case Plays.Surf.Event.Back b when b.By == wiped:
                            Assert.True(surf.RiderOf(b.By)!.OnBoard, "back on its board");
                            found = true;
                            break;
                    }
                }
            }
        }
        Assert.True(found, "some seed wipes out and paddles back");
    }

    [Fact]
    public void EveryRiderStaysOnTheFloorItSurfs()
    {
        var (surf, rng) = Session(5, waves: 3);
        while (!surf.IsFinished)
        {
            surf.Update(1.0 / 30, rng);
            foreach (var r in surf.Riders) Assert.InRange(r.X, From, To);
        }
    }

    [Fact]
    public void TheScoreboardPutsTheBestFirst()
    {
        var (surf, rng) = Session(3, waves: 3);
        Play(surf, rng);
        Languages.With(Language.English, () =>
        {
            var board = surf.Board(i => $"P{i}");
            Assert.StartsWith("SURF ", board);
            var scores = surf.Riders.Select(r => r.Score).OrderByDescending(x => x).ToList();
            Assert.EndsWith($" {scores[^1]}", board);
            Assert.Contains(" · ", board);
        });
        Languages.With(Language.Russian, () => Assert.StartsWith("СЕРФ ", surf.Board(i => $"P{i}")));
    }
}

/// <summary>Surfing in each character's voice, its boards, and what its lines cost. The Mac's SurfLinesTests.</summary>
public class SurfLinesTests
{
    private static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));

    [Fact]
    public void EveryCharacterHasEverySurfLineInBothLanguages()
    {
        var names = BedsTests.ShippedNames();
        Assert.Equal(39, names.Count);
        var swift = File.ReadAllText(Path.Combine(Root, "Sources/LedgelingsCore/Plays+SurfLines.swift"));
        var moments = new[] { Plays.Moment.Wave, Plays.Moment.Wipeout, Plays.Moment.Trick, Plays.Moment.SurfWin };
        foreach (var language in Languages.All)
        {
            var voices = Plays.SurfVoicesIn(language);
            foreach (var name in names)
            {
                Assert.True(voices.TryGetValue(name, out var v), $"{name} has no surf lines in {language}");
                var lines = new[] { v!.Start, v.Wave, v.Wipeout, v.Trick, v.Win, v.Invite, v.Yes, v.No };
                foreach (var line in lines)
                {
                    Assert.False(string.IsNullOrEmpty(line), $"{name} {language}");
                    if (language == Language.English) Assert.Contains("\"" + line + "\"", swift);       // word for word
                }
                Assert.True(v.Invite.Contains("{reader}") && v.Yes.Contains("{reader}") && v.No.Contains("{reader}"), $"{name} {language} speaks to the reader");
                Assert.Equal(v.Start, Plays.StartLinesIn(language)[name]["surf"]);
                foreach (var moment in moments)
                    Assert.False(string.IsNullOrEmpty(Plays.CheerLinesIn(language)[name].GetValueOrDefault(moment.Raw())), $"{name} {moment} {language}");
            }
            Assert.True(Plays.StartAnyoneIn(language).ContainsKey("surf") && Plays.CheerAnyoneIn(language).ContainsKey("wipeout"));
        }
        // Each in its own voice: no two characters share a line.
        var wipeouts = names.Select(n => Plays.EnglishSurfVoices[n].Wipeout).ToList();
        Assert.Equal(wipeouts.Count, wipeouts.Distinct().Count());
        // The Russian is ru.json's, the Mac's words.
        Assert.Equal("Мокрые углы. Все четыре. Терпеть не могу мокрые углы.", Plays.SurfVoicesIn(Language.Russian)["Blocky"].Wipeout);
        Assert.Equal("Прилив пришёл. Все на доски!", Plays.SurfAnyoneIn(Language.Russian).Start);
        Languages.With(Language.English, () =>
        {
            Assert.Contains("Wet corners", Plays.CheerLine("Blocky", Plays.Moment.Wipeout));          // Blocky grumbles about wet corners
            Assert.Contains("%", Plays.CheerLine("Unit 7", Plays.Moment.Trick));                      // Unit 7 in numbers
            Assert.Contains("lying down", Plays.CheerLine("Zed", Plays.Moment.Wave));                 // Zed sleepy
            Assert.Equal(Plays.EnglishSurfAnyone.Win, Plays.CheerLine("Nobody Made", Plays.Moment.SurfWin));
            Assert.Equal(Plays.EnglishSurfAnyone.Start, Plays.StartLine("Nobody Made", Plays.Kind.Surf, ""));
        });
        Assert.True(Plays.Moment.SurfWin.AsksTheModel() && !Plays.Moment.Wipeout.AsksTheModel() && !Plays.Moment.Wave.AsksTheModel());
    }

    [Fact]
    public void AnInvitationToSurfIsInTheSurfersOwnWords()
    {
        var surf = Deeds.Offer.Game(Plays.Kind.Surf);
        Languages.With(Language.English, () =>
        {
            Assert.Equal("Pip. Water on the bottom edge. Surfing. Unless you're scared of wet corners.", Deeds.InviteLine("Blocky", "Pip", surf));
            Assert.Equal("Surfing? Yes yes yes! Wheee, Blocky!", Deeds.AnswerLine("Pip", "Blocky", surf, yes: true));
            Assert.Equal("Not today, Pip. I'll stay dry.", Deeds.AnswerLine("Someone New", "Pip", surf, yes: false));
            Assert.Contains("Soccer", Deeds.InviteLine("Blocky", "Pip", Deeds.Offer.Game(Plays.Kind.Soccer)));      // other games keep their lines
            Assert.Equal("Surfing", surf.Word);
        });
        Languages.With(Language.Russian, () =>
            Assert.Equal("Pip. Вода на нижнем краю. Серфинг. Если не боишься мокрых углов.", Deeds.InviteLine("Blocky", "Pip", surf)));
        Assert.Contains(Plays.Kind.Surf, Deeds.Invitable);
        var invite = Deeds.Deed.Invite(surf);
        Assert.Equal((true, invite), Deeds.Parse("invite surfing"));
        Assert.Equal((true, invite), Deeds.Parse("invite серфинг"));
        Assert.Equal((true, invite), Deeds.Parse("invite surf"));
    }

    [Fact]
    public void EveryCharacterPaddlesOutOnABoardOfItsOwn()
    {
        var boards = BedsTests.ShippedNames().Select(Plays.Surf.Board).ToList();
        Assert.Equal(boards.Count, boards.Distinct().Count());                              // no two share a board
        Assert.All(boards, b => Assert.InRange(b, 0, Plays.Surf.BoardCount - 1));
        Assert.Equal(7, Plays.Surf.Board("Blocky"));
        // A made character keeps its board, by the Mac's own hash.
        Assert.Equal(7, Plays.Surf.Board("Someone New"));
        Assert.Equal(42, Plays.Surf.Board("Ёжик"));
    }

    [Fact]
    public void WhatSurfingSaysIsCountedUnderItsOwnPurpose()
    {
        Assert.True(Plays.Kind.Surf.SpendPurpose() == Spend.Purpose.Surfing && Plays.Kind.Soccer.SpendPurpose() == Spend.Purpose.BallGames
                    && Plays.Kind.Tag.SpendPurpose() == Spend.Purpose.Plays);
        Assert.Equal("surfing", Spend.Purpose.Surfing.Raw());
        var records = new[] { new Spend.Record(DateTimeOffset.Now, "OpenRouter", "m", new Spend.Usage(150, 15, 0.0004), Spend.Purpose.Surfing) };
        var s = Spend.Summarise(records, DateTimeOffset.Now);
        Languages.With(Language.English, () => Assert.Equal(0.0004, s.ByPurpose.First(p => p.Purpose == "Surfing").Total.Cost));
        Languages.With(Language.Russian, () => Assert.Equal("Серфинг", Spend.Purpose.Surfing.Title()));
    }

    [Fact]
    public void SurfingIsATeamGameWithItsOwnPage()
    {
        Assert.Equal(Plays.Kind.Surf, Plays.AllKinds[^1]);
        Assert.True(Plays.Kind.Surf.IsTeamGame() && !Plays.Kind.Surf.CanSolo() && !Plays.Kind.Surf.CanPair());
        Assert.Equal(Plays.Kind.Surf, Plays.FromRaw("surf"));
        Assert.Equal(SettingsGroup.Games, SettingsPage.Surfing.Group());
        Assert.Equal(SettingsPage.Surfing, SettingsPages.Named("surfing"));
        Languages.With(Language.English, () => Assert.Equal("surfing on a wave along the bottom edge", Plays.Kind.Surf.Title()));
        Languages.With(Language.Russian, () => Assert.Equal("Серфинг", SettingsPage.Surfing.Title()));
    }
}
