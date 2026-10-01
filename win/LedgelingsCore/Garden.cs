namespace Ledgelings.Core;

/// <summary>
/// Flowers planted in the screen edge, and how each character decides where and
/// when to plant the one it was given.
///
/// A creature wearing a flower keeps it on its head for a while, then plants it
/// the first time it passes a spot it likes. What it likes is read from its
/// persona and its species' kind, the way <c>Casting</c> reads them for a voice:
/// Blocky ("the bottom edge is the only respectable edge") plants on the floor,
/// Pip ("loves the ceiling") on the top edge, Ruth ("keeps count") beside the
/// flowers already there, Dot ("fast") at once, Zed ("sleepy") at nightfall.
/// Rules, not understanding: a persona in words the rules do not know plants
/// wherever it is once it has worn the flower a little while.
/// </summary>
public sealed class Garden
{
    /// <summary>A kind of spot a character can prefer.</summary>
    public enum Place
    {
        /// <summary>The bottom edge of a screen.</summary>
        Floor,
        /// <summary>The top edge.</summary>
        Ceiling,
        /// <summary>A left or right edge.</summary>
        Wall,
        /// <summary>Close to where the edge turns.</summary>
        Corner,
        /// <summary>Nobody else near.</summary>
        Alone,
        /// <summary>Someone else close by.</summary>
        Company,
        /// <summary>Next to a flower already planted, in a row.</summary>
        Row,
        /// <summary>After dark.</summary>
        Night,
        /// <summary>In daylight.</summary>
        Day,
    }

    /// <summary>The place's name as the Mac writes it: "floor", "ceiling"…</summary>
    public static string Key(Place place) => place.ToString().ToLowerInvariant();

    /// <summary>Where, in words: "on the bottom edge".</summary>
    public static string Phrase(Place place) => place switch
    {
        Place.Floor => L10n.Tr("on the bottom edge"),
        Place.Ceiling => L10n.Tr("on the top edge"),
        Place.Wall => L10n.Tr("on a side edge"),
        Place.Corner => L10n.Tr("in a corner"),
        Place.Alone => L10n.Tr("where nobody is"),
        Place.Company => L10n.Tr("next to someone"),
        Place.Row => L10n.Tr("beside the flowers already planted"),
        Place.Night => L10n.Tr("after dark"),
        _ => L10n.Tr("in daylight"),
    };

    /// <summary>How one character goes about it: how much of the flower's time it wears
    /// it before thinking of planting, and the places it likes, best first.</summary>
    public sealed record Temper(double Keep, IReadOnlyList<Place> Likes)
    {
        public bool Equals(Temper? other) => other is not null && Keep == other.Keep && Likes.SequenceEqual(other.Likes);
        public override int GetHashCode() => HashCode.Combine(Keep, Likes.Count);
    }

    /// <summary>What is around a creature right now, for <see cref="Fits"/>.</summary>
    /// <param name="Inward">Away from its edge, into the screen.</param>
    /// <param name="ToCorner">Points along the edge to the nearest turn.</param>
    /// <param name="ToCreature">Points to the nearest other creature; infinity when alone on screen.</param>
    /// <param name="ToFlower">Points to the nearest planted flower; infinity when none is planted.</param>
    public readonly record struct Surroundings(Vec Inward, double ToCorner, double ToCreature, double ToFlower, bool IsNight);

    /// <summary>One flower in the ground.</summary>
    /// <param name="Floor">The middle of its stem's foot, on the screen edge.</param>
    /// <param name="Rotation">The edge's turn, as a creature standing there has it.</param>
    /// <param name="Scale">Screen points per sprite pixel: the planter's size.</param>
    /// <param name="Planter">Who planted it.</param>
    public readonly record struct Bed(string Flower, Pt Floor, double Rotation, double Scale, string Planter, double Planted, double Until);

    /// <summary>Distances behind the places, in points.</summary>
    public const double CornerReach = 60;
    public const double AloneBeyond = 320;
    public const double CompanyWithin = 160;
    public const double RowWithin = 90;
    /// <summary>No flower goes closer than this to another, in sprite pixels times the size,
    /// so a row does not end up as one flower drawn on another.</summary>
    public const double Spacing = 12;
    /// <summary>Past this share of the flower's time on the head, any spot will do: it is
    /// planted wherever the wearer stands rather than left to wilt.</summary>
    public const double LastChance = 0.9;
    /// <summary>Seconds a flower takes to come up out of the ground.</summary>
    public const double GrowTime = 0.5;

    private readonly List<Bed> beds = new();
    public IReadOnlyList<Bed> Beds => beds;

    // MARK: Character

    /// <summary>One rule: any of these word starts in the text, and the character likes this place.
    /// <c>Strong</c> rules name a place outright ("bottom edge", "ceiling"); the rest are
    /// temperament (grumpy, cheerful). Named places come first.</summary>
    private sealed record Rule(string[] Words, Place Place, bool Strong = false);

    private static readonly Rule[] Rules =
    {
        new(new[] { "bottom", "floor", "ground" }, Place.Floor, true),
        new(new[] { "ceiling", "top", "sky", "high" }, Place.Ceiling, true),
        new(new[] { "wall", "climb", "cling", "sideways" }, Place.Wall, true),
        new(new[] { "corner", "nook" }, Place.Corner, true),
        new(new[] { "garden", "row", "neat", "tidy" }, Place.Row, true),
        new(new[] { "night", "dark", "moon" }, Place.Night, true),
        new(new[] { "sun", "warm", "light", "daylight" }, Place.Day, true),
        new(new[] { "damp", "pond", "earth", "moss", "puddle", "dirt", "mud" }, Place.Floor),
        new(new[] { "hover", "float", "fly", "cloud", "ghost" }, Place.Ceiling),
        new(new[] { "stable", "stubborn", "precise", "literal", "anxi", "worr", "scared", "afraid", "stepped",
                    "sharp", "point" }, Place.Corner),
        new(new[] { "aloof", "quiet", "shy", "deadpan", "grump", "gruff", "lonel", "wistful", "hates", "suspect" },
            Place.Alone),
        new(new[] { "cheer", "friend", "social", "gigg", "laugh", "playful", "sweet", "simple", "pleased", "loud" },
            Place.Company),
        new(new[] { "count", "organis", "organiz", "boss", "maintenance", "bolt", "differen", "change", "notice" },
            Place.Row),
        new(new[] { "sleep", "nap", "drows", "yawn", "bed", "scary", "spook", "haunt" }, Place.Night),
    };

    /// <summary>Wears it a moment and plants it.</summary>
    private static readonly string[] Hasty = { "fast", "quick", "hyper", "rush", "speed", "bounc", "excit", "enthus", "impatien" };
    /// <summary>Wants to wear it a good while first.</summary>
    private static readonly string[] Fond = { "sweet", "ador", "wistful", "poet", "dream", "sentiment", "romantic", "proud" };
    /// <summary>Takes its time over everything.</summary>
    private static readonly string[] Slow = { "slow", "patien", "calm", "old", "wise", "philosoph", "sleep" };

    /// <summary>How the character with this persona, of this kind, plants its flowers.</summary>
    public static Temper TemperOf(string persona, string kind)
    {
        var own = Casting.Words(persona);
        var theirs = Casting.Words(kind);
        static int? First(string[] stems, List<string> words)
        {
            var at = words.FindIndex(word => stems.Any(stem => word.StartsWith(stem, StringComparison.Ordinal)));
            return at < 0 ? null : at;
        }
        // Persona words outrank the species' kind; a named place outranks a temperament;
        // otherwise whichever the text says first.
        var ranked = new List<(Place Place, int Rank)>();
        foreach (var rule in Rules)
        {
            int rank;
            if (First(rule.Words, own) is int at) rank = (rule.Strong ? 0 : 1_000) + at;
            else if (First(rule.Words, theirs) is int at2) rank = (rule.Strong ? 2_000 : 3_000) + at2;
            else continue;
            var known = ranked.FindIndex(r => r.Place == rule.Place);
            if (known >= 0) ranked[known] = (rule.Place, Math.Min(ranked[known].Rank, rank));
            else ranked.Add((rule.Place, rank));
        }
        var likes = ranked.OrderBy(r => r.Rank).Select(r => r.Place).Take(3).ToList();
        var keep = First(Hasty, own) is not null ? 0.05
            : First(Fond, own) is not null ? 0.6
            : First(Slow, own) is not null ? 0.45
            : 0.25;
        return new Temper(keep, likes);
    }

    /// <summary>The temper in a sentence, for the settings window: "After a good while, on the bottom edge or where nobody is."</summary>
    public static string Describe(Temper temper)
    {
        var when = temper.Keep < 0.1 ? L10n.Tr("At once") : temper.Keep < 0.3 ? L10n.Tr("After a little while")
            : temper.Keep < 0.5 ? L10n.Tr("After a good while") : L10n.Tr("After showing it off for most of its time");
        var places = temper.Likes.Select(Phrase).ToList();
        if (places.Count == 0) return L10n.Tr("%@, wherever it is.", when);
        var listed = places.Count == 1 ? places[0]
            : L10n.Tr("%@ or %@", string.Join(", ", places.Take(places.Count - 1)), places[^1]);
        return when + ", " + listed + ".";
    }

    // MARK: Deciding

    /// <summary>Whether a character of this temper plants now: <paramref name="share"/> is how far through
    /// its time on the head the flower is. Before <c>Keep</c> it is still wearing it.
    /// For the first half of the time left until <see cref="LastChance"/> only its favourite
    /// place will do, after that any place it likes, and at the last chance anywhere.</summary>
    public static bool WantsToPlant(Temper temper, double share, Surroundings around)
    {
        if (share < temper.Keep) return false;
        if (share >= LastChance || temper.Likes.Count == 0) return true;
        var picky = share < temper.Keep + (LastChance - temper.Keep) / 2;
        var choices = picky ? temper.Likes.Take(1) : temper.Likes;
        return choices.Any(p => Fits(p, around));
    }

    public static bool Fits(Place place, Surroundings around) => place switch
    {
        Place.Floor => around.Inward.Dy > 0.5,
        Place.Ceiling => around.Inward.Dy < -0.5,
        Place.Wall => Math.Abs(around.Inward.Dx) > 0.5,
        Place.Corner => around.ToCorner <= CornerReach,
        Place.Alone => around.ToCreature >= AloneBeyond,
        Place.Company => around.ToCreature <= CompanyWithin,
        Place.Row => around.ToFlower <= RowWithin,
        Place.Night => around.IsNight,
        _ => !around.IsNight,
    };

    // MARK: The beds

    /// <summary>Whether there is room for a flower of this size at <paramref name="floor"/>.</summary>
    public bool HasRoom(Pt floor, double scale) => DistanceTo(floor) >= Spacing * scale;

    /// <summary>Points from <paramref name="point"/> to the nearest planted flower; infinity with none planted.</summary>
    public double DistanceTo(Pt point) =>
        beds.Count == 0 ? double.PositiveInfinity : beds.Min(b => b.Floor.DistanceTo(point));

    /// <summary>Plant a flower that stays <paramref name="lasts"/> seconds. With <paramref name="most"/> already in the
    /// ground, the oldest wilts to make room.</summary>
    public void Plant(string flower, Pt floor, double rotation, double scale, string planter, double time, double lasts, int most)
    {
        beds.Add(new Bed(flower, floor, rotation, scale, planter, time, time + lasts));
        Trim(most);
    }

    /// <summary>0 as it is planted, 1 once it is fully up.</summary>
    public static double Grown(Bed bed, double time) => Math.Min(1, Math.Max(0, (time - bed.Planted) / GrowTime));

    /// <summary>Wilt every flower past its time, and the oldest beyond <paramref name="most"/>.</summary>
    public void Update(double time, int most)
    {
        beds.RemoveAll(b => b.Until <= time);
        Trim(most);
    }

    private void Trim(int most)
    {
        var room = Math.Max(most, 0);
        if (beds.Count > room) beds.RemoveRange(0, beds.Count - room);
    }

    /// <summary>Keep only the flowers <paramref name="keep"/> approves of (the monitors changed).</summary>
    public void Keep(Func<Bed, bool> keep) => beds.RemoveAll(b => !keep(b));

    public void Clear() => beds.Clear();
}
