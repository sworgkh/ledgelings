using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Every character's own bed (SPEC §7.9), the Mac's <c>Colony+Beds.swift</c>. Nodding off at
/// nightfall, a creature walks to its favourite place if the habit pulls it there and the place is near
/// enough along its edge, puts its bed down and sleeps on it; the bed goes when it wakes. The user can drag
/// a bed, sleeper and all, to a new place, which is then the favourite. Dragging a bed is not a hunt:
/// nobody is chased or picked up, nobody complains.</summary>
public sealed partial class Colony
{
    /// <summary>Seconds a bed takes to come up under its sleeper, and to fade once it wakes.</summary>
    private const double BedGrowTime = 0.35, BedFadeTime = 0.4;
    /// <summary>The share of nights a creature says something as it lays its bed down.</summary>
    private const double BedLineChance = 0.3;

    private BedBook? bedBook;
    /// <summary>Where each character likes to sleep.</summary>
    public BedBook Beds => bedBook ??= new BedBook(Spend.Ledger.Directory);

    private SpriteAtlas.Frames? bedFrames;
    private System.Drawing.Size bedCell;
    /// <summary>Every character's bed, one picture each, cut once.</summary>
    private SpriteAtlas.Frames BedFrames
    {
        get
        {
            if (bedFrames is null) { var sheet = SpriteAtlas.Named("beds"); bedFrames = sheet.MakeFrames(); bedCell = sheet.CellSize; }
            return bedFrames;
        }
    }
    public System.Drawing.Size BedCell { get { _ = BedFrames; return bedCell; } }

    /// <summary>Creatures walking to their favourite place for the night, and where on their loop it is.</summary>
    private readonly Dictionary<int, double> bedTrips = new();
    /// <summary>Sleepers whose bed is out, by when it came out.</summary>
    private readonly Dictionary<int, double> bedSince = new();
    /// <summary>Beds fading away under someone who just woke up: how they last looked, and when they are gone.</summary>
    private readonly Dictionary<int, (PlantedSnapshot Shown, double Until)> bedFades = new();
    /// <summary>Who was asleep last frame, so a creature nodding off is noticed once.</summary>
    private readonly HashSet<int> wasAsleep = new();
    /// <summary>The sleeper whose bed the user is carrying, until it lands.</summary>
    private int? bedCarry;

    public IReadOnlyDictionary<int, double> BedTrips => bedTrips;
    public bool BedIsOut(int i) => bedSince.ContainsKey(i);
    public int? BedCarry => bedCarry;

    /// <summary>Which bed creature <paramref name="i"/> sleeps in.</summary>
    public Core.Beds.Kind BedKindOf(int i)
    {
        var who = CharacterFor(i);
        return Core.Beds.KindOf(who.Name, who.Persona, KindOf(i));
    }

    /// <summary>Every frame, after the creatures have moved: who just nodded off, who reached its bed,
    /// whose bed comes out and whose goes away.</summary>
    private void UpdateBeds()
    {
        if (!Settings.BedsEnabled || hideout.IsActive)
        {
            foreach (var i in bedTrips.Keys.ToList())
                if (i < creatures.Count && creatures[i].IsRunning && !hideout.IsActive)
                {
                    if (IsNight) creatures[i].Settle(); else creatures[i].Pause(0.5);
                }
            bedTrips.Clear();
            bedCarry = null;
            foreach (var i in bedSince.Keys.ToList()) PutBedAway(i);
            wasAsleep.Clear();
            for (int i = 0; i < creatures.Count; i++) if (creatures[i].LooksAsleep) wasAsleep.Add(i);
            ExpireBedFades();
            return;
        }
        for (int i = 0; i < creatures.Count; i++)
        {
            if (hideout.IsInside(i)) continue;
            if (bedTrips.ContainsKey(i)) WalkingToBed(i);
            var c = creatures[i];
            var noddedOff = c.LooksAsleep && !wasAsleep.Contains(i);
            if (c.LooksAsleep) wasAsleep.Add(i); else wasAsleep.Remove(i);
            if (noddedOff && c.IsSleeping && !c.IsHeld) NodOff(i);
            if (bedCarry == i && creatures[i].IsSleeping && !creatures[i].IsHeld) BedPutDown(i);
            var lying = creatures[i].IsSleeping && !creatures[i].IsHeld;
            if (lying || bedCarry == i)
            {
                if (!bedSince.ContainsKey(i)) bedSince[i] = Elapsed;
            }
            else if (bedSince.ContainsKey(i)) PutBedAway(i);
        }
        ExpireBedFades();
    }

    private void ExpireBedFades()
    {
        foreach (var i in bedFades.Where(f => f.Value.Until <= Elapsed).Select(f => f.Key).ToList()) bedFades.Remove(i);
    }

    /// <summary>Creatures from <paramref name="count"/> on are gone (fewer creatures in the settings).</summary>
    private void ForgetBeds(int count)
    {
        foreach (var i in bedTrips.Keys.Where(k => k >= count).ToList()) bedTrips.Remove(i);
        foreach (var i in bedSince.Keys.Where(k => k >= count).ToList()) bedSince.Remove(i);
        foreach (var i in bedFades.Keys.Where(k => k >= count).ToList()) bedFades.Remove(i);
        wasAsleep.RemoveWhere(k => k >= count);
        if (bedCarry >= count) bedCarry = null;
    }

    // Nightfall

    /// <summary>Creature <paramref name="i"/> has just fallen asleep on its edge. By night it may get up again
    /// and walk to its favourite place; a nap the user asked for is slept where it is, and teaches it nothing.</summary>
    private void NodOff(int i)
    {
        var c = creatures[i];
        if (!IsNight || c.IsNapping) return;
        var name = CharacterFor(i).Name;
        if (Beds.SpotOf(name) is { } spot)
        {
            if (spot.Point.DistanceTo(c.Position) <= Core.Beds.Near) { SleepWithRoom(i); return; }
            var pull = Core.Beds.Pull(spot.Nights, Settings.BedPull / 100);
            if (rng.NextDouble() < pull && Reach(spot.Point, i) is double t) { GoToBed(i, t, "favourite"); return; }
        }
        else
        {
            // The first night: off to a place its character likes, the way it picks where to plant a flower.
            foreach (var place in TemperOf(i).Likes)
            {
                if (Target(place, i) is not double t || AlongLoop(i, t) > Settings.BedWalkDistance) continue;
                GoToBed(i, t, place.ToString().ToLowerInvariant());
                return;
            }
        }
        SleepWithRoom(i);
    }

    /// <summary>Where on creature <paramref name="i"/>'s own loop <paramref name="point"/> is, if it is on that
    /// loop at all and no further along it than the Beds tab lets it walk.</summary>
    private double? Reach(Pt point, int i)
    {
        var hit = creatures[i].Loop.Nearest(point);
        if (hit.Distance > Core.Beds.Near * 2 || AlongLoop(i, hit.T) > Settings.BedWalkDistance) return null;
        return hit.T;
    }

    /// <summary>Points along creature <paramref name="i"/>'s loop to <paramref name="t"/>, the short way round.</summary>
    private double AlongLoop(int i, double t)
    {
        var loop = creatures[i].Loop;
        var d = loop.Wrap(t - creatures[i].T);
        return Math.Min(d, loop.Length - d);
    }

    /// <summary><paramref name="t"/>, or the nearest place beside it with room for creature <paramref name="i"/>'s
    /// bed: nobody sleeps on top of somebody else.</summary>
    private double RoomForBed(double t, int i)
    {
        var loop = creatures[i].Loop;
        var width = BedCell.Width * sizes[i] + 4;
        var taken = new List<double>();
        for (int j = 0; j < creatures.Count; j++)
        {
            if (j == i || creatures[j].Spot.Loop != creatures[i].Spot.Loop) continue;
            if (bedTrips.TryGetValue(j, out var trip)) taken.Add(trip);
            else if (bedSince.ContainsKey(j)) taken.Add(creatures[j].T);
        }
        bool Free(double c) => taken.All(o => { var d = loop.Wrap(o - c); return Math.Min(d, loop.Length - d) >= width; });
        foreach (var k in new[] { 0, 1, -1, 2, -2, 3, -3, 4, -4 })
        {
            var c = loop.Wrap(t + k * width);
            if (Free(c)) return c;
        }
        return t;
    }

    private void GoToBed(int i, double target, string why)
    {
        var t = RoomForBed(target, i);
        creatures[i].Run(t, pace: 1);
        bedTrips[i] = t;
        wasAsleep.Remove(i);
        Trace?.Invoke($"bed {CharacterFor(i).Name} walks to {BedKindOf(i).Name()} ({why})");
    }

    /// <summary>On the way: arrived, it lies down; stopped by something else (a chat, the house), it forgets
    /// about it and sleeps wherever night finds it next.</summary>
    private void WalkingToBed(int i)
    {
        var c = creatures[i];
        if (c.IsRunning) return;
        bedTrips.Remove(i);
        if (!c.HasArrived) return;
        if (IsNight)
        {
            creatures[i].Settle();
            wasAsleep.Add(i);
            SleepHere(i);
        }
        else creatures[i].Pause(0.5);      // morning came first: on with the day
    }

    /// <summary>Lie down here, or a step aside when somebody's bed is already here.</summary>
    private void SleepWithRoom(int i)
    {
        var c = creatures[i];
        var room = RoomForBed(c.T, i);
        var d = c.Loop.Wrap(room - c.T);
        if (Math.Min(d, c.Loop.Length - d) < 1) SleepHere(i); else GoToBed(i, room, "room");
    }

    /// <summary>The night is spent here: the habit grows, or wears down.</summary>
    private void SleepHere(int i)
    {
        var name = CharacterFor(i).Name;
        Beds.Slept(name, creatures[i].Position);
        Trace?.Invoke($"bed {name} sleeps in {BedKindOf(i).Name()} {OnEdge(creatures[i])}, {Beds.SpotOf(name)?.Nights ?? 0} nights");
        if (rng.NextDouble() < BedLineChance) BedLine(Core.Beds.SettleLine(name, BedKindOf(i), rng), i);
    }

    private void BedLine(string line, int i)
    {
        if (!Settings.BedTalk || !Settings.TalkEnabled || bubbles.ContainsKey(i) || busy.Contains(i) || VoiceIsTakenNow) return;
        Say(line, i, builtIn: true);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now,
            Situation = string.Join(" ", new[] { AlmanacSentence, TimeOfDay, Describe(i) + "." }.Where(s => s.Length > 0)),
            Provider = AppSettings.BrainTitle(BrainKind.Script), Model = "",
            Lines = new List<ChatLog.Line> { new(CharacterFor(i).Name, line) },
        });
    }

    private void PutBedAway(int i)
    {
        if (bedSince.Remove(i, out var since) && BedSnapshot(i, since) is { } shown) bedFades[i] = (shown, Elapsed + BedFadeTime);
    }

    // The user's hand

    /// <summary>The sleeper whose bed (not its body) is under <paramref name="point"/>.</summary>
    public int? BedAt(Pt point)
    {
        for (int i = creatures.Count - 1; i >= 0; i--)
        {
            if (!bedSince.ContainsKey(i) || !creatures[i].IsSleeping || creatures[i].IsHeld || hideout.IsInside(i)) continue;
            var (floor, up) = BedFloor(i);
            var dx = point.X - floor.X;
            var dy = point.Y - floor.Y;
            var across = dx * up.Dy - dy * up.Dx;
            var height = dx * up.Dx + dy * up.Dy;
            var half = BedCell.Width * sizes[i] / 2 + 3;
            if (Math.Abs(across) <= half && height >= -3 && height <= BedCell.Height * sizes[i] + 3) return i;
        }
        return null;
    }

    /// <summary>Whether <paramref name="point"/> is on creature <paramref name="i"/>'s body itself, without the
    /// forgiveness <see cref="CreatureAt"/> allows.</summary>
    public bool OnBody(int i, Pt point)
    {
        var half = atlas.BodyHalfSize * sizes[i];
        var p = DrawnPosition(i);
        return Math.Abs(point.X - p.X) <= half && Math.Abs(point.Y - p.Y) <= half;
    }

    /// <summary>Pick the bed up with its sleeper on it; dropped, it lands on the nearest edge and stays there.</summary>
    private void LiftBed(int i, Pt point)
    {
        if (!creatures[i].PickUp()) return;
        var p = creatures[i].Position;
        held = (i, new Vec(p.X - point.X, p.Y - point.Y));
        bedCarry = i;
        Trace?.Invoke($"bed {CharacterFor(i).Name} lifted");
    }

    /// <summary>The carried bed has landed with its sleeper: this is the favourite place now.</summary>
    private void BedPutDown(int i)
    {
        bedCarry = null;
        var name = CharacterFor(i).Name;
        Beds.Moved(name, creatures[i].Position);
        Trace?.Invoke($"bed {name} moved {OnEdge(creatures[i])}");
        BedLine(Core.Beds.MovedLine(name, BedKindOf(i), rng), i);
    }

    // Drawing

    /// <summary>Which way is up for creature <paramref name="i"/>, from its turn: away from its edge.</summary>
    private Vec Up(int i)
    {
        var r = creatures[i].Rotation;
        return new Vec(-Math.Sin(r), Math.Cos(r));
    }

    /// <summary>How far a sleeper lying in its bed is raised off its edge: to the top of the mattress.</summary>
    public Vec BedLift(int i)
    {
        if (i >= creatures.Count || !bedSince.TryGetValue(i, out var since) || !creatures[i].IsSleeping || creatures[i].IsHeld) return new Vec(0, 0);
        var grown = Math.Min(1, (Elapsed - since) / BedGrowTime);
        var lift = BedKindOf(i).Lift() * sizes[i] * grown;
        var u = Up(i);
        return new Vec(u.Dx * lift, u.Dy * lift);
    }

    /// <summary>Where creature <paramref name="i"/> is drawn: lifted onto its bed when lying in one.</summary>
    public Pt DrawnPosition(int i)
    {
        var p = creatures[i].Position;
        var lift = BedLift(i);
        return new Pt(p.X + lift.Dx, p.Y + lift.Dy);
    }

    /// <summary>The middle of the bed's foot, and which way is up: on the edge under a sleeper lying in it,
    /// hanging under the feet of one being carried.</summary>
    private (Pt Floor, Vec Up) BedFloor(int i)
    {
        var u = Up(i);
        var p = creatures[i].Position;
        var lying = creatures[i].IsSleeping && !creatures[i].IsHeld;
        var below = atlas.BodyHalfSize * sizes[i] + (lying ? 0 : BedKindOf(i).Lift() * sizes[i]);
        return (new Pt(p.X - u.Dx * below, p.Y - u.Dy * below), u);
    }

    private PlantedSnapshot? BedSnapshot(int i, double since)
    {
        if (i >= creatures.Count || i >= sizes.Count) return null;
        var (floor, _) = BedFloor(i);
        return new PlantedSnapshot(BedFrames.Frame(BedKindOf(i).Name(), 0), floor, creatures[i].Rotation, sizes[i],
                                   Math.Clamp((Elapsed - since) / BedGrowTime, 0.001, 1), 1);
    }

    public List<PlantedSnapshot> BedSnapshots()
    {
        var out_ = new List<PlantedSnapshot>();
        foreach (var i in bedSince.Keys.OrderBy(k => k))
            if (!hideout.IsInside(i) && BedSnapshot(i, bedSince[i]) is { } shown) out_.Add(shown);
        foreach (var i in bedFades.Keys.OrderBy(k => k))
        {
            var (shown, until) = bedFades[i];
            out_.Add(shown with { Opacity = (float)Math.Clamp((until - Elapsed) / BedFadeTime, 0, 1) });
        }
        return out_;
    }
}
