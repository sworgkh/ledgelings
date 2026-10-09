namespace Ledgelings.Core.Tests;

/// <summary>Who sleeps in which bed, how the favourite place is learned, and the file it is kept in (SPEC §7.9).
/// The Mac's BedsTests.</summary>
public class BedsTests
{
    private static readonly string Root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));

    /// <summary>Every character of every shipped species, and Blocky's built-in cast.</summary>
    private static List<string> Shipped()
    {
        var sprites = Path.Combine(Root, "Sources/Ledgelings/Resources/sprites");
        var names = Banter.DefaultCharacters.Select(c => c.Name).ToList();
        foreach (var file in Directory.GetFiles(sprites, "*.json"))
        {
            using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(file));
            if (doc.RootElement.TryGetProperty("cast", out var cast))
                names.AddRange(cast.EnumerateArray().Select(c => c.GetProperty("name").GetString()!));
        }
        return names;
    }

    [Fact]
    public void EveryShippedCharacterHasABedOfItsOwn()
    {
        var names = Shipped();
        Assert.Equal(27, names.Count);
        Assert.All(names, n => Assert.True(Beds.BuiltIn.ContainsKey(n), n + " has no bed"));
        var beds = names.Select(n => Beds.BuiltIn[n]).ToList();
        Assert.Equal(names.Count, beds.Distinct().Count());                                   // no two share a bed
        Assert.True(beds.ToHashSet().SetEquals(Enum.GetValues<Beds.Kind>()));                // every picture is somebody's
    }

    [Fact]
    public void ANewCharacterGetsABedFromItsWords()
    {
        Assert.Equal(Beds.Kind.Catbed, Beds.KindOf("Tom", "Purrs a lot.", "a small pixel creature"));
        Assert.Equal(Beds.Kind.Dock, Beds.KindOf("Bolt", "Curious and new here.", "a tall robot with a lamp"));
        Assert.Equal(Beds.Kind.Matchbox, Beds.KindOf("Nobody", "Curious and new here.", "a small pixel creature"));
        Assert.Equal(Beds.Kind.Grass, Beds.KindOf("X", "", ""));
        Assert.Equal(Beds.Kind.Crate, Beds.KindOf("Blocky", "Purrs.", "a cat"));                // a built-in name keeps its own
    }

    /// <summary>The app lifts a sleeper by <c>Lift</c>; the painter draws the mattress at <c>LIFT</c>; the sheet has each picture.</summary>
    [Fact]
    public void TheLiftMatchesThePainterAndEveryBedIsInTheSheet()
    {
        var painter = File.ReadAllText(Path.Combine(Root, "spritetool/painters/beds.py"));
        var table = painter[(painter.IndexOf("LIFT = {", StringComparison.Ordinal) + 8)..];
        table = table[..table.IndexOf('}')];
        var lifts = table.Split(',').Select(p => p.Split(':')).Where(p => p.Length == 2)
            .ToDictionary(p => p[0].Trim().Trim('"'), p => int.Parse(p[1].Trim()));
        var sheet = File.ReadAllText(Path.Combine(Root, "Sources/Ledgelings/Resources/sprites/beds.json"));
        foreach (var kind in Enum.GetValues<Beds.Kind>())
        {
            Assert.Equal(lifts[kind.Name()], kind.Lift());
            Assert.Contains("\"" + kind.Name() + "\"", sheet);
        }
    }

    [Fact]
    public void ThePullGrowsWithEveryNight()
    {
        Assert.Equal(0, Beds.Pull(0, 1));
        Assert.Equal(0.5, Beds.Pull(1, 1));
        Assert.Equal(0.875, Beds.Pull(3, 1));
        Assert.Equal(0.7, Beds.Pull(3, 0.8), 9);
        Assert.Equal(0, Beds.Pull(12, 0));
    }

    [Fact]
    public void TheFavouriteSettlesWhereItSleepsMostAndMovesWhenTheHabitWearsOff()
    {
        var book = new Beds.Book();
        Pt a = new(100, 22), b = new(900, 22);
        book.Slept("Zed", a);
        Assert.Equal(Beds.Spot.At(a, 1), book.Spots["Zed"]);
        for (var k = 0; k < 20; k++) book.Slept("Zed", new Pt(110, 22));
        Assert.Equal(Beds.MostNights, book.Spots["Zed"].Nights);
        Assert.Equal(110, book.Spots["Zed"].X);
        for (var k = 0; k < Beds.MostNights - 1; k++) book.Slept("Zed", b);
        Assert.Equal((110.0, 1), (book.Spots["Zed"].X, book.Spots["Zed"].Nights));
        book.Slept("Zed", b);
        Assert.Equal(Beds.Spot.At(b, 1), book.Spots["Zed"]);
    }

    [Fact]
    public void ABedMovedByTheUserIsTheFavouriteAtOnce()
    {
        var book = new Beds.Book();
        book.Moved("Pip", new Pt(5, 590));
        Assert.Equal(new Beds.Spot(5, 590, Beds.MovedNights), book.Spots["Pip"]);
        for (var k = 0; k < 5; k++) book.Slept("Pip", new Pt(5, 590));
        book.Moved("Pip", new Pt(700, 590));
        Assert.Equal(Beds.MovedNights + 5, book.Spots["Pip"].Nights);
        book.Forget("Pip");
        Assert.Empty(book.Spots);
    }

    [Fact]
    public void TheBookSurvivesARelaunchInTheMacsShape()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ledgelings-beds-" + Guid.NewGuid());
        try
        {
            var store = new Beds.Store(dir);
            var book = new Beds.Book();
            book.Slept("Blocky", new Pt(320, 22));
            store.Save(book);
            Assert.Equal(book.Spots, new Beds.Store(dir).Load().Spots);
            var json = File.ReadAllText(store.File);
            Assert.Contains("\"spots\"", json);
            Assert.Contains("\"nights\": 1", json);
            // A file the Mac wrote reads here.
            File.WriteAllText(store.File, "{\n  \"spots\" : {\n    \"Zed\" : {\n      \"nights\" : 4,\n      \"x\" : 10.5,\n      \"y\" : 22\n    }\n  }\n}");
            Assert.Equal(new Beds.Spot(10.5, 22, 4), new Beds.Store(dir).Load().Spots["Zed"]);
            Assert.Empty(new Beds.Store(Path.Combine(dir, "nothing")).Load().Spots);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void EveryCharacterHasItsOwnBedtimeLinesInEveryLanguage()
    {
        var swift = File.ReadAllText(Path.Combine(Root, "Sources/LedgelingsCore/Beds+Lines.swift"));
        foreach (var language in Enum.GetValues<Language>())
        {
            var settle = Beds.SettleLinesIn(language);
            var moved = Beds.MovedLinesIn(language);
            foreach (var name in Shipped())
            {
                Assert.Equal(2, settle[name].Length);
                Assert.NotEmpty(moved[name]);
                if (language == Language.English)
                    foreach (var line in settle[name].Concat(moved[name])) Assert.Contains("\"" + line + "\"", swift);      // word for word
            }
            Assert.NotEmpty(Beds.SettleAnyoneIn(language));
            Assert.NotEmpty(Beds.MovedAnyoneIn(language));
        }
        Assert.NotEqual(Beds.SettleLinesIn(Language.English)["Zed"], Beds.SettleLinesIn(Language.Russian)["Zed"]);      // from ru.json
        var anyone = Beds.SettleLine("Stranger", Beds.Kind.Grass, new Random(1));
        Assert.DoesNotContain("{", anyone);
    }

    [Fact]
    public void WordsForWhereItSleeps()
    {
        var screen = new Rect(0, 0, 800, 600);
        Languages.With(Language.English, () =>
        {
            Assert.Equal("on the bottom edge", Beds.Place(new Pt(400, 2), new[] { screen }));
            Assert.Equal("on the ceiling", Beds.Place(new Pt(400, 598), new[] { screen }));
            Assert.Equal("on the left edge", Beds.Place(new Pt(1, 300), new[] { screen }));
            Assert.Equal("on the ceiling of screen 2", Beds.Place(new Pt(1000, 299), new[] { screen, new Rect(800, 0, 400, 300) }));
        });
    }
}
