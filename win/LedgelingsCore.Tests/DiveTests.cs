namespace Ledgelings.Core.Tests;

/// <summary>Scuba diving's water, divers and sea life, the lines every character says on a dive, and
/// Stop activity's key and its button (SPEC §7.19). The Mac's DiveTests.</summary>
public class DiveTests
{
    private static readonly Rect Screen = new(0, 0, 1200, 800);

    private static (Dive Dive, Random Rng) Make(double share = 1.0 / 3, double seconds = 30, int divers = 3)
    {
        var rng = new Random(7);
        var d = new Dive(new[] { Screen }, share, seconds, 2.5,
                         Enumerable.Range(0, divers).Select(i => (i, new Pt(200 + i * 300, 27), 27.0)).ToList(), 12, rng);
        return (d, rng);
    }

    [Fact]
    public void TheWaterRisesToTheSetShareOfTheScreenAndDrainsAway()
    {
        foreach (var share in new[] { 0.2, 1.0 / 3, 0.5 })
        {
            var (d, rng) = Make(share, seconds: 5);
            Assert.Equal(0, d.Water(0).Height);
            var events = new List<Dive.Event>();
            for (var i = 0; i < (int)(Dive.RiseSeconds / 0.05) + 2; i++) events.AddRange(d.Update(0.05, rng));
            Assert.Equal(Dive.Phase.On, d.CurrentPhase);
            Assert.Contains(new Dive.Event(Dive.EventKind.Filled), events);
            Assert.True(Math.Abs(d.Water(0).Height - Screen.Height * share) < 0.01, $"a {share} share of 800 points");
            while (!d.IsOver && d.Time < 60) events.AddRange(d.Update(0.05, rng));
            Assert.True(d.IsOver && d.Water(0).Height == 0);
            Assert.Contains(new Dive.Event(Dive.EventKind.Drained), events);
        }
    }

    [Fact]
    public void EveryDiverJumpsInWithASplashSwimsUnderAndComesUpForAir()
    {
        var (d, rng) = Make(seconds: 60);
        var events = new List<Dive.Event>();
        while (d.Time < 50) events.AddRange(d.Update(0.05, rng));
        Assert.Equal(3, events.Count(e => e.Kind == Dive.EventKind.Splash));                                    // one splash a diver
        Assert.Equal(new[] { 0, 1, 2 }, events.Where(e => e.Kind == Dive.EventKind.Surfaced).Select(e => e.Diver).Distinct().Order()); // each comes up for air
        foreach (var diver in d.Divers.Where(v => v.IsUnder))
            Assert.True(d.Water(0).Contains(diver.Position), "under the surface");
        Assert.Contains(events, e => e.Kind == Dive.EventKind.Sees);
    }

    [Fact]
    public void TheSeaLifeIsAllThereAndKeepsToTheWater()
    {
        var (d, rng) = Make(seconds: 60);
        Assert.Equal(Dive.AllLives.ToHashSet(), d.Critters.Select(c => c.Kind).ToHashSet());   // three fish, a jellyfish, a crab, a turtle and an octopus
        Assert.Equal(12, d.Critters.Count(c => c.Kind.IsFish()));
        Assert.NotEmpty(d.Weeds);
        while (d.Time < 40) d.Update(0.05, rng);
        var water = d.Water(0);
        foreach (var c in d.Critters) Assert.True(water.InsetBy(-1, -1).Contains(c.Position), $"{c.Kind} at {c.Position}");
        var crab = d.Critters.First(c => c.Kind == Dive.Life.Crab);
        Assert.True(Math.Abs(crab.Position.Y - Dive.Life.Crab.HalfSize().Height * 2.5) < 0.5, "the crab walks the floor");
    }

    [Fact]
    public void FishScatterFromADiverWhoComesNear()
    {
        var (d, rng) = Make(seconds: 60, divers: 1);
        while (d.CurrentPhase != Dive.Phase.On) d.Update(0.05, rng);
        while (d.Divers[0].State == Dive.DiverState.Gearing) d.Update(0.05, rng);
        while (d.Divers[0].State != Dive.DiverState.Swimming) d.Update(0.05, rng);
        // Put the diver right beside a fish.
        var fish = d.Critters.First(c => c.Kind.IsFish());
        var diver = d.Divers[0];
        diver.Position = new Pt(fish.Position.X - 20, fish.Position.Y);
        diver.Target = diver.Position;
        var before = fish.Position.DistanceTo(diver.Position);
        var events = new List<Dive.Event>();
        for (var i = 0; i < 10; i++) events.AddRange(d.Update(0.05, rng));
        var after = fish.Position.DistanceTo(diver.Position);
        Assert.True(fish.Scared > 0 && after > before, $"it darts away: {before} → {after}");
        Assert.Contains(new Dive.Event(Dive.EventKind.Scattered, 0), events);
    }

    [Fact]
    public void DrainingEarlyBringsEveryoneDown()
    {
        var (d, rng) = Make(seconds: 600);
        while (d.Time < 10) d.Update(0.05, rng);
        d.Drain();
        Assert.Equal(Dive.Phase.Draining, d.CurrentPhase);
        while (!d.IsOver) d.Update(0.05, rng);
        foreach (var diver in d.Divers) Assert.True(diver.Position.Y <= Screen.MinY + diver.Half + 1, "on the floor");
    }

    // Words

    private static readonly string[] Cast =
    {
        "Blocky", "Pip", "Mortimer", "Zed", "Dot", "Ruth", "Whiskers", "Mittens", "Sir Pounce", "Hopper", "Mossy", "Croak",
        "Boo", "Wisp", "Sheet", "Morel", "Puff", "Cap", "Unit 7", "Sprocket", "Glitch", "Goop", "Puddle", "Blorp",
        "Spike", "Wedge", "Delta", "Prickles", "Saguaro", "Tumble", "Click", "Scarab", "Crumb", "Shard", "Quartz", "Prism",
        "Sprout", "Fern", "Bud",
    };
    private static readonly string[] LineKinds = { "in", "see", "fish", "octopus", "air", "out" };

    [Fact]
    public void EveryCharacterHasItsOwnLinesInEveryLanguage()
    {
        var russian = Shared.In(Language.Russian)!;
        var tables = new (string Language, IReadOnlyDictionary<string, IReadOnlyDictionary<string, IReadOnlyList<string>>> Table,
                          IReadOnlyDictionary<string, IReadOnlyList<string>> Anyone)[]
        {
            ("en", Dive.EnglishLines, Dive.EnglishAnyone),
            ("ru", russian.DiveLines.ToDictionary(p => p.Key, p => (IReadOnlyDictionary<string, IReadOnlyList<string>>)p.Value.ToDictionary(q => q.Key, q => (IReadOnlyList<string>)q.Value)),
             russian.DiveAnyone.ToDictionary(p => p.Key, p => (IReadOnlyList<string>)p.Value)),
        };
        foreach (var (language, table, anyone) in tables)
        {
            Assert.Equal(Cast.Order(), table.Keys.Order());                                            // every built-in character
            foreach (var (name, lines) in table.Append(new("anyone", anyone)))
            {
                foreach (var kind in LineKinds)
                    Assert.True(lines.TryGetValue(kind, out var l) && l.Count > 0, $"{language} {name} has no {kind} line");
                foreach (var line in lines["see"]) Assert.True(line.Split("{what}").Length == 2, $"{language} {name}: {line}");
            }
        }
        Languages.With(Language.English, () =>
        {
            var rng = new Random(3);
            var line = Dive.Line("Unit 7", "see", Dive.Life.Turtle, rng);
            Assert.Contains("a turtle", line);
            Assert.DoesNotContain("{what}", line);
            Assert.NotEmpty(Dive.Line("Someone New", "in", null, rng));                              // a character the user made says anyone's line
        });
        Assert.Equal("Hmph. A turtle. Down here.", Dive.Fill("Hmph. {what}. Down here.", "a turtle"));
        Assert.Equal("Look, a turtle!", Dive.Fill("Look, {what}!", "a turtle"));
        Languages.With(Language.Russian, () =>
        {
            var rng = new Random(3);
            Assert.Contains("черепаха", Dive.Line("Unit 7", "see", Dive.Life.Turtle, rng).ToLowerInvariant());
        });
    }

    [Fact]
    public void ADiveLandsInThePairsStory() => Languages.With(Language.English, () =>
    {
        var book = new Bonds.Book();
        book.Note("Blocky", "Pip", new Bonds.Moment(DateTimeOffset.Now, Bonds.MomentKind.Dive, "Blocky",
                                                    Dive.Memory(new[] { Dive.Life.Turtle, Dive.Life.FishB, Dive.Life.FishA })));
        var moment = book.Bond("Blocky", "Pip")!.Moments[^1];
        Assert.Equal("Blocky and Pip went diving together and saw a school of fish, a turtle", Bonds.Describe(moment, new[] { "Blocky", "Pip" }));
        Assert.Equal(1, book.Bond("Blocky", "Pip")!.Tally["dive"]);
    });

    // Stop activity's key and its button

    [Fact]
    public void StopActivityIsCtrlAltQAndTheOldEscMovesOverToIt()
    {
        var ctrlAlt = ShortcutModifiers.Control | ShortcutModifiers.Option;
        Assert.Equal(new Shortcut(0x51, ctrlAlt), Shortcut.StopActivity);
        Assert.Equal(Shortcut.StopActivity, Shortcut.StopActivitySaved(null, null));                          // nothing saved
        Assert.Equal(Shortcut.StopActivity, Shortcut.StopActivitySaved(0x1B, (int)ctrlAlt));                   // the old default
        Assert.Equal(new Shortcut(0x1B, ctrlAlt | ShortcutModifiers.Shift), Shortcut.StopActivitySaved(0x1B, (int)(ctrlAlt | ShortcutModifiers.Shift)));
        var own = new[] { Shortcut.Standard, Shortcut.ClipHistory, Shortcut.ClipSnippets, Shortcut.Dictation, Shortcut.Translate,
                          Shortcut.TranslateClip, Shortcut.ReadAloud, Shortcut.Tools };
        Assert.DoesNotContain(Shortcut.StopActivity, own);                                                     // free among the app's own
        Assert.Equal("Ctrl + Alt + Q", Shortcut.StopActivity.Spoken("Q"));
        Assert.Equal("Ctrl + Alt + Shift + Win + S", new Shortcut(0x53, ctrlAlt | ShortcutModifiers.Shift | ShortcutModifiers.Command).Spoken("S"));
    }

    [Fact]
    public void TheStopButtonSaysWhatToPressAndSitsTopRightClearOfABoard() => Languages.With(Language.English, () =>
    {
        Assert.Equal("Stop · Ctrl + Alt + Q", StopButton.Label("Ctrl + Alt + Q"));
        Assert.Equal("Stop the activity (Ctrl + Alt + Q)", StopButton.Tag("Ctrl + Alt + Q"));
        Assert.Equal("Stop", StopButton.Label(null));
        var screen = new Rect(1920, -1080, 1920, 1080);
        var place = StopButton.Frame(300, 40, screen, topInset: 0);
        Assert.Equal(screen.MaxX - StopButton.Margin, place.MaxX);
        Assert.Equal(screen.MaxY - StopButton.Margin, place.MaxY);
        var board = new Rect(3500, -60, 400, 50);
        var below = StopButton.Frame(300, 40, screen, 0, new[] { board });
        Assert.False(below.Intersects(board));
        Assert.True(below.MaxY <= board.MinY);
        Assert.Equal(place, StopButton.Frame(300, 40, screen, 0, new[] { new Rect(2000, -60, 400, 50) }));     // a board elsewhere is no matter
        Assert.Equal(12, StopButton.Icon.Length);
        Assert.All(StopButton.Icon, row => Assert.Equal(12, row.Length));
        Languages.With(Language.Russian, () => Assert.Equal("Стоп · Ctrl + Alt + Q", StopButton.Label("Ctrl + Alt + Q")));
    });

    [Fact]
    public void TheToolAndThePageAndTheStopShortcut()
    {
        Assert.Equal(Tools.Tool.Dive, Tools.All[^2]);                                     // before the chat (0.70), so every older tile keeps its number key
        Assert.Equal(SettingsPage.Diving, Tools.Tool.Dive.Page());
        Assert.Equal("dive", Tools.Tool.Dive.Code());
        Assert.Equal(new[] { SettingsPage.Chases, SettingsPage.Play, SettingsPage.BallGames, SettingsPage.Surfing, SettingsPage.Diving }, SettingsGroup.Games.Pages());
        Assert.Equal(SettingsPage.Diving, SettingsPages.Named("diving"));
        Assert.Equal(new Shortcut(0x51, ShortcutModifiers.Control | ShortcutModifiers.Option), Shortcut.StopActivity);
        Assert.True(Shortcut.StopActivity.IsUsable);
        Assert.Equal(new[] { "fish-a", "fish-b", "fish-c", "jelly", "crab", "turtle", "octopus" }, Dive.AllLives.Select(l => l.Code()));
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal("Дайвинг", SettingsPage.Diving.Title());
            Assert.Equal("стайка рыб", Dive.Life.FishB.Spoken());
            Assert.Equal("ныряли с аквалангом: Pip, в 10:00, и видели: стайка рыб", L10n.Tr("went diving with %@ at %@ and saw %@", "Pip", "10:00", "стайка рыб"));
            Assert.Equal("3 погружения", L10n.TrCount(3, "dive", "dives"));
        });
    }
}
