using Ledgelings.Core;

namespace Ledgelings;

/// <summary>A creature with a flower on its head plants it in the edge, when and where its
/// character likes (<see cref="Garden.TemperOf"/>), and the flowers stand there a while.</summary>
public sealed partial class Colony
{
    /// <summary>Flowers planted in the edge.</summary>
    private readonly Garden garden = new();
    public Garden Garden => garden;
    /// <summary>Flower wearers done wearing theirs and looking for a place to plant it; they no longer trail their giver.</summary>
    private readonly HashSet<int> gardeners = new();

    /// <summary>Every frame: wilt what is past its time, then let each wearer at leisure
    /// decide whether this is the spot.</summary>
    partial void UpdateGarden()
    {
        garden.Update(Elapsed, Settings.GardenSize);
        if (!Settings.PlantFlowers || hideout.IsActive) return;
        gardeners.Clear();
        foreach (var wearer in gifts.WornFlowers.Keys.OrderBy(k => k).ToList())
        {
            if (!CanPlant(wearer)) continue;
            if (gifts.WornShare(wearer, Elapsed) is not double share || PlantingSpot(wearer) is not { } spot) continue;
            var temper = TemperOf(wearer);
            var around = SurroundingsOf(wearer, spot.Floor);
            if (share < temper.Keep) continue;
            if (Garden.WantsToPlant(temper, share, around) && garden.HasRoom(spot.Floor, sizes[wearer]))
            {
                Plant(wearer, spot);
                continue;
            }
            // Done wearing it: it stops trailing its giver and goes looking for its place.
            gardeners.Add(wearer);
            if (temper.Likes.Count > 0 && Target(temper.Likes[0], wearer) is double t)
                creatures[wearer].HeadToward(t, 4);
        }
    }

    /// <summary>Where on its own loop the nearest spot of this kind is, for the places a
    /// creature can walk to: an edge facing the right way, a corner, a planted
    /// row. Null for the rest (company, being alone, the time of day): those it
    /// comes across as it wanders. Null too when it is already there.</summary>
    private double? Target(Garden.Place place, int i)
    {
        var c = creatures[i];
        var loop = c.Loop;
        var half = atlas.BodyHalfSize * sizes[i];
        // Loop distance from the creature to t, the short way round.
        double Away(double t) { var d = loop.Wrap(t - c.T); return Math.Min(d, loop.Length - d); }
        double? Edges(Func<Vec, bool> wanted)
        {
            var matching = Enumerable.Range(0, loop.SegmentCount)
                .Where(s => wanted(loop.Inward(s)) && loop.SegmentLength(s) > 4 * half).ToList();
            if (matching.Contains(c.Segment) || matching.Count == 0) return null;
            return matching.Select(s => loop.T(s, 0.5)).MinBy(Away);
        }
        switch (place)
        {
            case Garden.Place.Floor: return Edges(v => v.Dy > 0.5);
            case Garden.Place.Ceiling: return Edges(v => v.Dy < -0.5);
            case Garden.Place.Wall: return Edges(v => Math.Abs(v.Dx) > 0.5);
            case Garden.Place.Corner:
            {
                // The nearer end of its own edge, far enough in for the flower to fit before the turn.
                var start = loop.T(c.Segment, 0);
                var length = loop.SegmentLength(c.Segment);
                var inset = Math.Min(Garden.CornerReach / 2 + half, length / 2);
                var nearer = new[] { start + inset, start + length - inset }.MinBy(Away);
                return Away(nearer) > Garden.CornerReach / 2 ? nearer : null;
            }
            case Garden.Place.Row:
            {
                var close = garden.Beds.Select(bed => loop.Nearest(bed.Floor))
                    .Where(hit => hit.Distance <= half * 1.5).Select(hit => hit.T).ToList();
                if (close.Count == 0) return null;
                var nearest = close.MinBy(Away);
                return Away(nearest) > Garden.RowWithin / 2 ? nearest : null;
            }
            default: return null;
        }
    }

    /// <summary>How this creature's character plants, from its persona and its species' kind.</summary>
    private Garden.Temper TemperOf(int i) => Garden.TemperOf(CharacterFor(i).Persona, KindOf(i));

    /// <summary>Not while it is talking, reading, carried, asleep, jumping or on its way home.</summary>
    private bool CanPlant(int i) =>
        i >= 0 && i < creatures.Count && !busy.Contains(i) && !ExpectsPlane(i) && !HoldsLetter(i)
        && !hideout.IsInside(i) && creatures[i].IsAtLeisure && !creatures[i].LooksAsleep;

    /// <summary>Where its flower would go: on the edge just in front of its feet, or just
    /// behind them when the edge turns in front of it.</summary>
    private (Pt Floor, double Rotation)? PlantingSpot(int i)
    {
        var c = creatures[i];
        var loop = c.Loop;
        var segment = c.Segment;
        var half = atlas.BodyHalfSize * sizes[i];
        var start = loop.T(segment, 0);
        var length = loop.SegmentLength(segment);
        var along = loop.Wrap(c.T - start);
        var reach = half + 6 * sizes[i];
        var ahead = along + c.Direction * reach;
        var behind = along - c.Direction * reach;
        double offset;
        if (ahead >= 0 && ahead <= length) offset = ahead;
        else if (behind >= 0 && behind <= length) offset = behind;
        else return null;
        var point = loop.Point(start + offset);
        var inward = loop.Inward(segment);
        return (new Pt(point.X - inward.Dx * half, point.Y - inward.Dy * half), loop.Rotation(segment));
    }

    private Garden.Surroundings SurroundingsOf(int i, Pt floor)
    {
        var c = creatures[i];
        var start = c.Loop.T(c.Segment, 0);
        var along = c.Loop.Wrap(c.T - start);
        var others = Enumerable.Range(0, creatures.Count).Where(j => j != i && !hideout.IsInside(j)).ToList();
        var nearest = others.Count == 0 ? double.PositiveInfinity : others.Min(j => creatures[j].Position.DistanceTo(c.Position));
        return new Garden.Surroundings(c.Loop.Inward(c.Segment), Math.Min(along, c.Loop.SegmentLength(c.Segment) - along),
                                       nearest, garden.DistanceTo(floor), IsNight);
    }

    /// <summary>Take the flower off its head and put it in the ground. It stops a moment to do it.</summary>
    private void Plant(int i, (Pt Floor, double Rotation) spot)
    {
        if (gifts.TakeOff(i) is not Gifts.Worn worn) return;
        garden.Plant(worn.Flower, spot.Floor, spot.Rotation, sizes[i], CharacterFor(i).Name,
                     Elapsed, Settings.GardenMinutes * 60, Settings.GardenSize);
        creatures[i].Pause(1.2);
    }

    /// <summary>Pull up every planted flower at once (the menu, the Flowers tab). Returns how many went.</summary>
    public int ClearGarden()
    {
        var count = garden.Beds.Count;
        garden.Clear();
        Render();
        return count;
    }

    /// <summary>The monitors changed: a flower no longer standing on an edge goes.</summary>
    private void ReplantAfterScreensChanged()
    {
        var outline = new EdgeWorld(monitors.Select(m => m.Frame).ToList(), 0);
        garden.Keep(bed => outline.Loops.Any(l => l.Nearest(bed.Floor).Distance < 2));
    }

    private List<PlantedSnapshot> GardenSnapshots() =>
        garden.Beds.Select(bed => new PlantedSnapshot(
            flowerFrames.Frame(bed.Flower, 0), bed.Floor, bed.Rotation, bed.Scale,
            Garden.Grown(bed, Elapsed),
            // Fades over its last two seconds.
            (float)Math.Min(1, Math.Max(0, (bed.Until - Elapsed) / 2)))).ToList();
}
