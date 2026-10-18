using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// Which monitors the creatures live on (<c>homeScreen</c>, SPEC §2.4), and moving house. The Mac's Colony+Screens.
///
/// Every overlay stays up on every monitor, so a creature is drawn wherever it is; only the edges they walk,
/// the sky a plane flies in, the house, the garden and the cursor they grab are limited to the home monitors.
/// Choosing another monitor live, each creature not on it springs up out of the top of its screen and comes
/// down on the new one by parachute, one after another.
/// </summary>
public sealed partial class Colony
{
    /// <summary>A creature on its way to the monitors the colony lives on now: springing up and out of its
    /// old screen (<c>Hop</c>), out of sight until <c>Turn</c>, then under its parachute (<c>Chute</c>).</summary>
    private sealed class Move
    {
        public HomeScreen.Hop? Hop;
        public Plays.Chute? Chute;
        /// <summary>When it comes down, on the colony's clock: arrivals are spaced out.</summary>
        public double Turn;
    }

    private readonly Dictionary<int, Move> moves = new();
    /// <summary>The home monitors' frames when the edges were last traced, to notice a change.</summary>
    private List<Rect> homeWas = new();

    /// <summary>The monitors they live on: the chosen one while attached, else all.</summary>
    internal IReadOnlyList<Monitor> HomeMonitors
    {
        get
        {
            var home = HomeScreen.Home(Settings.HomeScreenId, monitors.Select(m => m.Home).ToList()).Select(m => m.Id).ToHashSet();
            var picked = monitors.Where(m => home.Contains(m.Id)).ToList();
            return picked.Count == 0 ? monitors : picked;
        }
    }

    internal List<Rect> HomeFrames => HomeMonitors.Select(m => m.Frame).ToList();

    /// <summary>Whether <paramref name="point"/> is on a monitor they live on.</summary>
    internal bool IsHome(Pt point, double slack = 0) => HomeScreen.IsHome(point, HomeFrames, slack);

    /// <summary>Whether creature <paramref name="i"/> is moving house.</summary>
    internal bool IsMoving(int i) => moves.ContainsKey(i);
    public int MovingCount => moves.Count;

    // MARK: When the home changes

    /// <summary>The setting or the monitors changed: if the home monitors are not what they were, the edges
    /// are traced afresh and whoever is not on them moves over.</summary>
    private void HomeMayHaveChanged()
    {
        var home = HomeFrames;
        if (home.SequenceEqual(homeWas)) return;
        homeWas = home;
        Trace?.Invoke("screens home " + string.Join(", ", HomeMonitors.Select(m => m.Name)));
        MoveHome();
    }

    /// <summary>Rebuild the edges on the home monitors and send everyone not there over.</summary>
    private void MoveHome()
    {
        // Whatever they were up to across the old edges is off.
        LetGo();
        LetGoOfCursor(Revenge.Release.Escape);
        EndPlay(false);
        // Movers still on the way finish where they are, then everyone is judged afresh.
        foreach (var i in moves.Keys.ToList()) LandNow(i);
        worlds.Clear();
        ReplantAfterScreensChanged();
        var leavers = new List<int>();
        for (int i = 0; i < creatures.Count; i++)
        {
            // Its centre is always inside the screen it walks; outside every home one, it moves.
            if (hideout.IsInside(i) || IsHome(creatures[i].Position, 1)) creatures[i].Rehome(World(sizes[i]));
            else leavers.Add(i);
        }
        if (leavers.Any(i => teaParty?.Involves(i) == true)) BreakUpTea();
        if (leavers.Count > 0) ReleaseChat();
        var turn = Elapsed;
        foreach (var i in leavers.OrderBy(_ => rng.NextDouble()))
        {
            if (!creatures[i].TakeOff(waking: true)) { creatures[i].Rehome(World(sizes[i])); continue; }
            bedTrips.Remove(i);
            gardeners.Remove(i);
            busy.Add(i);
            var half = atlas.BodyHalfSize * sizes[i];
            var p = creatures[i].Position;
            if (monitors.FirstOrDefault(m => m.Frame.Contains(p)) is { } screen)
            {
                var hop = new HomeScreen.Hop(p, creatures[i].Rotation, screen.Frame.MaxY + half * 3, creatures[i].IsMirrored ? -1 : 1);
                turn = Math.Max(turn, Elapsed + HomeScreen.Hop.Crouch + hop.FlightTime);
                moves[i] = new Move { Hop = hop, Turn = turn };
                Trace?.Invoke($"move {CharacterFor(i).Name} hops off {screen.Name}");
            }
            else
            {
                // On a monitor that is gone: nothing to see leave, it just comes down.
                moves[i] = new Move { Turn = turn };
            }
            turn += HomeScreen.ArrivalGap;
        }
        Render();
    }

    // MARK: Every frame

    private void UpdateMoves(double dt)
    {
        foreach (var i in moves.Keys.ToList())
        {
            var move = moves[i];
            if (i >= creatures.Count) { moves.Remove(i); continue; }
            if (move.Hop is { IsGone: false } hop)
            {
                hop.Update(dt);
                creatures[i].Carry(hop.Position, hop.Rotation, hop.Pose);
            }
            else if (move.Chute is { } chute)
            {
                var events = chute.Update(dt);
                creatures[i].Carry(chute.Position, chute.Rotation, chute.Pose);
                if (events.Contains(Plays.Chute.Event.Packed))
                {
                    LandNow(i);
                    Trace?.Invoke($"move {CharacterFor(i).Name} lands at ({creatures[i].Position.X:F0}, {creatures[i].Position.Y:F0})");
                }
            }
            else if (Elapsed >= move.Turn)
            {
                if (ChuteFor(i) is not { } made) { LandNow(i); continue; }
                move.Chute = made;
                creatures[i].Carry(made.Position, made.Rotation, made.Pose);
                Trace?.Invoke($"move {CharacterFor(i).Name} comes down at {made.Position.X:F0}");
            }
        }
    }

    /// <summary>A parachute over a random spot of the home floor, starting just above the top of that monitor,
    /// out of sight; null if the home has no floor at all.</summary>
    private Plays.Chute? ChuteFor(int i)
    {
        var w = World(sizes[i]);
        var half = atlas.BodyHalfSize * sizes[i];
        foreach (var frame in HomeFrames.OrderBy(_ => rng.NextDouble()))
        {
            var margin = Math.Min(half * 3, frame.Width / 2);
            var x = rng.Range(frame.MinX + margin, frame.MaxX - margin);
            if (w.Floor(new Pt(x, frame.MaxY)) is not { } floor) continue;
            // Brisker than the game's float, and never more than about 4.5 s down a tall monitor.
            var speed = Math.Max(Settings.ParachuteFallSpeed * 1.6, (frame.MaxY - floor.Y) / 4.5);
            return new Plays.Chute(new Pt(Math.Clamp(x, floor.From, floor.To), frame.MaxY + half * 1.5), floor.Y, floor.From, floor.To, speed);
        }
        return null;
    }

    /// <summary>Done moving (or cut short): onto the nearest home edge, walking.</summary>
    private void LandNow(int i)
    {
        moves.Remove(i);
        busy.Remove(i);
        if (i < creatures.Count) creatures[i].Rehome(World(sizes[i]));
    }

    /// <summary>The open parachutes of everyone coming down, in global points.</summary>
    internal List<PropSnapshot> MoveProps()
    {
        var props = new List<PropSnapshot>();
        foreach (var (i, move) in moves)
        {
            if (move.Chute is not { Canopy: > 0 } chute || i >= creatures.Count) continue;
            var c = creatures[i];
            var scale = sizes[i];
            var half = atlas.BodyHalfSize * scale;
            var up = new Vec(-Math.Sin(c.Rotation), Math.Cos(c.Rotation));
            var lift = half * 0.8 + PlayCell.Height * scale * chute.Canopy / 2;
            props.Add(new PropSnapshot(playFrames.Frame("chute", 0), new Pt(c.Position.X + up.Dx * lift, c.Position.Y + up.Dy * lift), c.Rotation, scale * chute.Canopy));
        }
        return props;
    }
}
