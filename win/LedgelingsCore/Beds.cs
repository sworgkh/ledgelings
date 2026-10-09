using System.Text.Json;

namespace Ledgelings.Core;

/// <summary>
/// Every character's own little bed, and the place it likes to sleep (SPEC §7.9). The Mac's <c>Beds</c>.
///
/// When a creature nods off for the night it puts its bed down and sleeps on it. Each character remembers
/// one favourite place, kept by name in <c>beds.json</c> (the same file shape as the Mac's): the first night
/// it walks to a place its character likes (the bottom edge for Blocky, the ceiling for Pip, as
/// <see cref="Garden.TemperOf"/> reads them), and each night after that it is a little likelier to walk
/// back there (<see cref="Pull"/>). A night spent somewhere else wears the habit down, and enough of them
/// move it. A bed the user drags somewhere while its owner sleeps makes that place the favourite.
/// </summary>
public static partial class Beds
{
    /// <summary>Which bed, by the name of its picture in the <c>beds</c> sheet (<see cref="Name"/>).</summary>
    public enum Kind
    {
        Crate, Hammock, Quilt, Pillow, Matchbox, Bed, Box, Catbed, Cushion, Lilypad, Moss, Puddle,
        Cloud, Leaf, Blanket, Log, Grass, Flowerpot, Dock, Toolbox, Spacebar, Sponge, Teacup,
        Bubblewrap, Pincushion, Books, Sock,
    }

    /// <summary>The picture's name in the sheet: <c>catbed</c>.</summary>
    public static string Name(this Kind kind) => kind.ToString().ToLowerInvariant();

    /// <summary>Sheet pixels above the floor the sleeper's feet rest on: the top of the mattress.
    /// Kept in step with <c>LIFT</c> in <c>spritetool/painters/beds.py</c>.</summary>
    public static int Lift(this Kind kind) => kind switch
    {
        Kind.Puddle => 2,
        Kind.Box or Kind.Grass => 3,
        Kind.Lilypad or Kind.Leaf or Kind.Dock => 4,
        Kind.Quilt or Kind.Matchbox or Kind.Moss => 5,
        Kind.Crate or Kind.Bed or Kind.Catbed or Kind.Cushion or Kind.Cloud or Kind.Blanket or Kind.Log or Kind.Bubblewrap or Kind.Sock => 6,
        Kind.Pillow or Kind.Toolbox or Kind.Sponge or Kind.Pincushion => 7,
        Kind.Hammock or Kind.Spacebar or Kind.Books => 8,
        Kind.Teacup => 9,
        _ => 10,      // the flowerpot
    };

    /// <summary>What it is, in words: "a round cat basket".</summary>
    public static string Title(this Kind kind) => L10n.Tr(kind switch
    {
        Kind.Crate => "a wooden crate full of straw",
        Kind.Hammock => "a striped hammock",
        Kind.Quilt => "a patchwork quilt",
        Kind.Pillow => "an enormous fluffy pillow",
        Kind.Matchbox => "a matchbox",
        Kind.Bed => "a neatly made little bed",
        Kind.Box => "a cardboard box",
        Kind.Catbed => "a round cat basket",
        Kind.Cushion => "a royal red cushion",
        Kind.Lilypad => "a lily pad",
        Kind.Moss => "a mound of soft moss",
        Kind.Puddle => "a puddle",
        Kind.Cloud => "a little cloud",
        Kind.Leaf => "a big autumn leaf",
        Kind.Blanket => "a folded check blanket",
        Kind.Log => "a slice of old log",
        Kind.Grass => "a tuft of grass",
        Kind.Flowerpot => "a flowerpot of good soil",
        Kind.Dock => "a charging dock",
        Kind.Toolbox => "a toolbox",
        Kind.Spacebar => "a spacebar keycap",
        Kind.Sponge => "a kitchen sponge",
        Kind.Teacup => "a teacup on its saucer",
        Kind.Bubblewrap => "a sheet of bubble wrap",
        Kind.Pincushion => "a pincushion",
        Kind.Books => "a stack of books",
        _ => "a striped sock",
    });

    /// <summary>The built-in characters' beds, chosen for each one's persona and kind.</summary>
    public static readonly IReadOnlyDictionary<string, Kind> BuiltIn = new Dictionary<string, Kind>
    {
        ["Blocky"] = Kind.Crate, ["Pip"] = Kind.Hammock, ["Mortimer"] = Kind.Quilt, ["Zed"] = Kind.Pillow, ["Dot"] = Kind.Matchbox, ["Ruth"] = Kind.Bed,
        ["Whiskers"] = Kind.Box, ["Mittens"] = Kind.Catbed, ["Sir Pounce"] = Kind.Cushion,
        ["Hopper"] = Kind.Lilypad, ["Mossy"] = Kind.Moss, ["Croak"] = Kind.Puddle,
        ["Boo"] = Kind.Cloud, ["Wisp"] = Kind.Leaf, ["Sheet"] = Kind.Blanket,
        ["Morel"] = Kind.Log, ["Puff"] = Kind.Grass, ["Cap"] = Kind.Flowerpot,
        ["Unit 7"] = Kind.Dock, ["Sprocket"] = Kind.Toolbox, ["Glitch"] = Kind.Spacebar,
        ["Goop"] = Kind.Sponge, ["Puddle"] = Kind.Teacup, ["Blorp"] = Kind.Bubblewrap,
        ["Spike"] = Kind.Pincushion, ["Wedge"] = Kind.Books, ["Delta"] = Kind.Sock,
    };

    /// <summary>For a character nobody wrote a bed for: word starts in its persona, then its species' kind.</summary>
    private static readonly (string[] Words, Kind Kind)[] Rules =
    {
        (new[] { "cat", "kitten", "purr", "whisker" }, Kind.Catbed),
        (new[] { "frog", "toad", "pond", "lily" }, Kind.Lilypad),
        (new[] { "ghost", "spook", "haunt", "float", "hover", "cloud" }, Kind.Cloud),
        (new[] { "mushroom", "fung", "moss", "damp", "earth" }, Kind.Moss),
        (new[] { "robot", "machine", "android", "metal", "antenna", "bolt" }, Kind.Dock),
        (new[] { "slime", "blob", "goo", "sticky", "wobbl" }, Kind.Sponge),
        (new[] { "sleep", "nap", "drows", "yawn", "tired" }, Kind.Pillow),
        (new[] { "old", "wise", "philosoph" }, Kind.Quilt),
        (new[] { "tiny", "small", "little" }, Kind.Matchbox),
        (new[] { "boss", "tidy", "neat", "organis", "organiz" }, Kind.Bed),
    };

    /// <summary>Whose bed is which: the built-in choice by name, else read from the words; grass when nothing fits.</summary>
    public static Kind KindOf(string name, string persona, string kind)
    {
        if (BuiltIn.TryGetValue(name, out var known)) return known;
        foreach (var text in new[] { persona, kind })
        {
            var words = Casting.Words(text);
            foreach (var rule in Rules)
                if (words.Any(w => rule.Words.Any(w.StartsWith))) return rule.Kind;
        }
        return Kind.Grass;
    }

    // The favourite place

    /// <summary>Where a character likes to sleep: a creature's centre on its edge, in global screen
    /// points, and how many nights the habit has behind it.</summary>
    public sealed record Spot(double X, double Y, int Nights)
    {
        public static Spot At(Pt point, int nights) => new(point.X, point.Y, nights);
        [System.Text.Json.Serialization.JsonIgnore] public Pt Point => new(X, Y);
    }

    /// <summary>A habit stops growing here, so a few nights elsewhere can still move it.</summary>
    public const int MostNights = 12;
    /// <summary>Dragged there by the user: the habit is at least this strong at once.</summary>
    public const int MovedNights = 3;
    /// <summary>Points: asleep this close to the favourite counts as asleep there.</summary>
    public const double Near = 48;

    /// <summary>The chance it walks back to its favourite at nightfall after <paramref name="nights"/> there.</summary>
    public static double Pull(int nights, double strength) =>
        nights <= 0 ? 0 : Math.Clamp(strength, 0, 1) * (1 - Math.Pow(0.5, nights));

    /// <summary>Every character's favourite place, by name.</summary>
    public sealed class Book
    {
        public Dictionary<string, Spot> Spots { get; set; } = new();

        /// <summary><paramref name="name"/> slept the night at <paramref name="point"/>: there (within <see cref="Near"/>)
        /// the habit grows; elsewhere it wears down, and once worn out this is the new favourite.</summary>
        public void Slept(string name, Pt point)
        {
            if (!Spots.TryGetValue(name, out var spot)) { Spots[name] = Spot.At(point, 1); return; }
            if (spot.Point.DistanceTo(point) <= Near) Spots[name] = Spot.At(point, Math.Min(spot.Nights + 1, MostNights));
            else Spots[name] = spot.Nights - 1 <= 0 ? Spot.At(point, 1) : spot with { Nights = spot.Nights - 1 };
        }

        /// <summary>The user put <paramref name="name"/>'s bed down at <paramref name="point"/>: the favourite from now on.</summary>
        public void Moved(string name, Pt point) =>
            Spots[name] = Spot.At(point, Math.Max(Spots.TryGetValue(name, out var s) ? s.Nights : 0, MovedNights));

        /// <summary>Forget one character's place, or everyone's.</summary>
        public void Forget(string? name = null)
        {
            if (name is null) Spots.Clear(); else Spots.Remove(name);
        }
    }

    /// <summary><c>beds.json</c> beside the chats and the hunts.</summary>
    public sealed class Store
    {
        private static readonly JsonSerializerOptions Options = new(JsonLines.Options) { WriteIndented = true };

        public string Directory { get; }
        public Store(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "beds.json");

        public Book Load()
        {
            try
            {
                if (!System.IO.File.Exists(File)) return new Book();
                return JsonSerializer.Deserialize<Book>(System.IO.File.ReadAllText(File), Options) ?? new Book();
            }
            catch (Exception e) when (e is JsonException or IOException or NotSupportedException) { return new Book(); }
        }

        public void Save(Book book)
        {
            System.IO.Directory.CreateDirectory(Directory);
            var temp = File + ".tmp";
            System.IO.File.WriteAllText(temp, JsonSerializer.Serialize(book, Options), new System.Text.UTF8Encoding(false));
            System.IO.File.Move(temp, File, true);
        }
    }

    /// <summary>Where <paramref name="point"/> is, in words, on these screens: "on the bottom edge", with the
    /// screen's number when there is more than one.</summary>
    public static string Place(Pt point, IReadOnlyList<Rect> screens)
    {
        if (screens.Count == 0) return "";
        var world = new EdgeWorld(screens.ToList(), 0);
        var spot = world.Nearest(point);
        var loop = world.Loops[spot.Loop];
        var inward = loop.Inward(loop.Segment(spot.T));
        var edge = inward.Dy > 0.5 ? L10n.Tr("on the bottom edge") : inward.Dy < -0.5 ? L10n.Tr("on the ceiling")
            : inward.Dx > 0.5 ? L10n.Tr("on the left edge") : L10n.Tr("on the right edge");
        if (screens.Count == 1) return edge;
        static double Away(Pt p, Rect r) => Math.Sqrt(Math.Pow(Math.Max(Math.Max(r.MinX - p.X, 0), p.X - r.MaxX), 2)
                                                      + Math.Pow(Math.Max(Math.Max(r.MinY - p.Y, 0), p.Y - r.MaxY), 2));
        var screen = Enumerable.Range(0, screens.Count).MinBy(k => Away(point, screens[k]));
        return L10n.Tr("%@ of screen %d", edge, screen + 1);
    }

    // Words

    /// <summary>A built-in line as it lays its bed down for the night, in its own voice.</summary>
    public static string SettleLine(string name, Kind bed, Random rng) =>
        Banter.Render(rng.Pick(SettleLines.TryGetValue(name, out var own) ? own : SettleAnyone),
                      new Dictionary<string, string> { ["bed"] = bed.Title() });

    /// <summary>A built-in line, half asleep, when the user has just moved its bed.</summary>
    public static string MovedLine(string name, Kind bed, Random rng) =>
        Banter.Render(rng.Pick(MovedLines.TryGetValue(name, out var own) ? own : MovedAnyone),
                      new Dictionary<string, string> { ["bed"] = bed.Title() });

    public static IReadOnlyDictionary<string, string[]> SettleLines => SettleLinesIn(Languages.Current);
    public static IReadOnlyList<string> SettleAnyone => SettleAnyoneIn(Languages.Current);
    public static IReadOnlyDictionary<string, string[]> MovedLines => MovedLinesIn(Languages.Current);
    public static IReadOnlyList<string> MovedAnyone => MovedAnyoneIn(Languages.Current);

    public static IReadOnlyDictionary<string, string[]> SettleLinesIn(Language l) =>
        Translated.Lists(Shared.In(l)?.BedSettleLines, EnglishSettleLines, t => t);
    public static IReadOnlyList<string> SettleAnyoneIn(Language l) => Translated.List(Shared.In(l)?.BedSettleAnyone, EnglishSettleAnyone);
    public static IReadOnlyDictionary<string, string[]> MovedLinesIn(Language l) =>
        Translated.Lists(Shared.In(l)?.BedMovedLines, EnglishMovedLines, t => t);
    public static IReadOnlyList<string> MovedAnyoneIn(Language l) => Translated.List(Shared.In(l)?.BedMovedAnyone, EnglishMovedAnyone);
}
