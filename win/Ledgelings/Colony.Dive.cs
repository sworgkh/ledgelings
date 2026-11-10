using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Scuba diving (SPEC §7.17), the Mac's <c>Colony+Dive</c>: started by hand only (Creature Actions, the
/// Tools screen, the tray), never on its own. Water rises over the bottom of the screen, a few creatures gear up and
/// jump in, swim among the sea life and come up for air, and when the time is up the water drains and they climb out
/// dripping. Stop activity (<see cref="StopDive"/>) clears it all at once. The water is drawn, not a window: clicks go
/// through it to the apps below.</summary>
public sealed partial class Colony
{
    /// <summary>The dive going on, and what the colony keeps beside it.</summary>
    private sealed class DiveSession
    {
        public required Dive Model;
        /// <summary>What the divers saw, for their memory.</summary>
        public readonly HashSet<Dive.Life> Saw = new();
        /// <summary>When a diver last said something: one line every few seconds at most.</summary>
        public double LastLine = -100;
        /// <summary>Splashes and ink puffs, where and when.</summary>
        public readonly List<(Pt At, double Since)> Splashes = new();
        public readonly List<(Pt At, double Since)> Inks = new();
    }

    private const double DiveLineGap = 6, DripSeconds = 3, SplashSeconds = 0.6, InkSeconds = 1.4;

    /// <summary>The sea life's and the gear's sheet.</summary>
    private static readonly SpriteAtlas seaSheet = SpriteAtlas.Named("sea");
    private readonly SpriteAtlas.Frames seaFrames = seaSheet.MakeFrames();
    private DiveSession? dive;
    /// <summary>Divers just out of the water, dripping until then.</summary>
    private readonly Dictionary<int, double> dripping = new();

    public bool IsDiving => dive is not null;

    // MARK: Starting and stopping

    /// <summary>Start a dive now. False when one is on, or nobody is free to dive.</summary>
    public bool StartDive()
    {
        if (dive is not null || hideout.IsActive) return false;
        if (play is not null) EndPlay(false);
        var pools = DivePools();
        bool OnPools(int i) => pools.Any(p => p.InsetBy(-1, -1).Contains(creatures[i].Position));
        var chosen = Enumerable.Range(0, creatures.Count).Where(FreeToPlay).OrderBy(i => OnPools(i) ? 0 : 1).Take(Settings.DiveDivers).ToList();
        if (chosen.Count == 0) { TalkStatus = L10n.Tr("nobody is free to dive"); return false; }
        var scale = chosen.Average(i => sizes[i]);
        var divers = new List<(int Index, Pt At, double Half)>();
        foreach (var i in chosen.Where(i => creatures[i].TakeOff()))
        {
            busy.Add(i);
            divers.Add((i, creatures[i].Position, atlas.BodyHalfSize * sizes[i]));
        }
        var model = new Dive(pools, Settings.DiveWaterShare, Settings.DiveMinutes * 60, scale, divers, Settings.DiveSeaLife, rng);
        dive = new DiveSession { Model = model };
        Trace?.Invoke($"dive starts: {string.Join(", ", divers.Select(d => CharacterFor(d.Index).Name))}, water {(int)(Settings.DiveWaterShare * 100)}% of {pools.Count} screen(s)");
        return true;
    }

    /// <summary>The monitors the water covers: the creatures' home monitor (the one most of them are on), or every monitor.</summary>
    private List<Rect> DivePools()
    {
        var frames = monitors.Select(m => m.Frame).ToList();
        if (Settings.DiveAllScreens || frames.Count <= 1) return frames.Count == 0 ? HomeFrames : frames;
        var home = HomeFrames;
        var candidates = home.Count == 0 ? frames : home;
        return new List<Rect> { candidates.OrderByDescending(f => creatures.Count(c => f.Contains(c.Position))).First() };
    }

    /// <summary>Stop activity: everything goes at once, water, fish and gear, and the divers drop back onto their edges.</summary>
    public void StopDive()
    {
        if (dive is null) return;
        EndDive(false);
        Render();
    }

    private void EndDive(bool completed)
    {
        if (dive is not DiveSession s) return;
        dive = null;
        var divers = s.Model.Divers.Select(d => d.Index).Where(i => i < creatures.Count).ToList();
        foreach (var i in divers)
        {
            if (creatures[i].IsPlaying) creatures[i].TouchDown();
            if (completed) dripping[i] = Elapsed + DripSeconds;
        }
        foreach (var i in divers) busy.Remove(i);
        // A dive they were in together, even one cut short, is in their memory.
        if (s.Model.FilledAt is not null)
        {
            var saw = Dive.Memory(s.Saw);
            for (int k = 0; k < divers.Count; k++)
                for (int m = k + 1; m < divers.Count; m++) Shared(divers[k], divers[m], Core.Bonds.MomentKind.Dive, saw.Length == 0 ? null : saw);
        }
        if (completed && divers.Count > 0) DiveLine("out", divers[0], force: true);
        NextPlayAt = Elapsed + Plays.Wait(Settings.PlayEveryMinutes, Settings.PlayBondBoost, 0, rng);
        Trace?.Invoke($"dive {(completed ? "over" : "stopped")}, saw {string.Join(", ", s.Saw.Select(l => l.Code()).OrderBy(x => x))}");
    }

    // MARK: Every frame

    private void UpdateDive(double dt)
    {
        foreach (var i in dripping.Where(d => d.Value <= Elapsed || d.Key >= creatures.Count).Select(d => d.Key).ToList()) dripping.Remove(i);
        if (dive is not DiveSession s) return;
        if (hideout.IsActive) { StopDive(); return; }
        var events = s.Model.Update(dt, rng);
        s.Splashes.RemoveAll(x => Elapsed - x.Since > SplashSeconds);
        s.Inks.RemoveAll(x => Elapsed - x.Since > InkSeconds);
        foreach (var e in events) DiveEvent(s, e);
        if (dive != s) return;
        foreach (var d in s.Model.Divers.Where(d => d.Index < creatures.Count))
        {
            // Picked up mid-dive: that one is out of it.
            if (!creatures[d.Index].IsPlaying) continue;
            creatures[d.Index].Face(d.FacingRight ? 1 : -1);
            creatures[d.Index].Carry(d.Position, DiverTilt(d), DiverPose(d));
        }
        if (s.Model.IsOver) { EndDive(true); return; }
        s.Model.Divers.RemoveAll(d => d.Index >= creatures.Count || !creatures[d.Index].IsPlaying);
    }

    private static string DiverPose(Dive.Diver d) => d.State switch
    {
        Dive.DiverState.Leaping => "jump",
        Dive.DiverState.Swimming => "walk",
        Dive.DiverState.Settling => "land",
        _ => "idle",
    };

    /// <summary>Nose up swimming up, down swimming down; level otherwise.</summary>
    private static double DiverTilt(Dive.Diver d)
    {
        if (d.State != Dive.DiverState.Swimming) return 0;
        var tilt = Math.Clamp(Math.Atan2(d.Velocity.Dy, Math.Max(1, Math.Abs(d.Velocity.Dx))), -0.5, 0.5);
        return d.FacingRight ? tilt : -tilt;
    }

    private void DiveEvent(DiveSession s, Dive.Event e)
    {
        switch (e.Kind)
        {
            case Dive.EventKind.Splash when e.At is Pt at:
                s.Splashes.Add((at, Elapsed));
                Trace?.Invoke($"dive splash at ({(int)at.X}, {(int)at.Y})");
                // The first one in says so.
                if (s.Splashes.Count == 1 && s.Model.Divers.Count > 0 && s.Model.Time < Dive.RiseSeconds + Dive.LeapSeconds + 0.5)
                    DiveLine("in", s.Model.Divers[0].Index, force: true);
                break;
            case Dive.EventKind.Filled:
                Trace?.Invoke("dive water up");
                break;
            case Dive.EventKind.Sees when e.What is Dive.Life life:
                s.Saw.Add(life);
                Trace?.Invoke($"dive {CharacterFor(e.Diver).Name} sees {life.Code()}");
                DiveLine("see", e.Diver, life);
                break;
            case Dive.EventKind.Scattered:
                s.Saw.Add(Dive.Life.FishA);
                Trace?.Invoke($"dive fish scatter from {CharacterFor(e.Diver).Name}");
                DiveLine("fish", e.Diver);
                break;
            case Dive.EventKind.Startled:
                s.Saw.Add(Dive.Life.Octopus);
                if (s.Model.Critters.FirstOrDefault(c => c.Kind == Dive.Life.Octopus) is { } octopus) s.Inks.Add((octopus.Position, Elapsed));
                Trace?.Invoke($"dive {CharacterFor(e.Diver).Name} startled by the octopus");
                DiveLine("octopus", e.Diver, force: true);
                break;
            case Dive.EventKind.Surfaced:
                Trace?.Invoke($"dive {CharacterFor(e.Diver).Name} up for air");
                DiveLine("air", e.Diver);
                break;
            case Dive.EventKind.Drained:
                Trace?.Invoke("dive water gone");
                break;
        }
    }

    /// <summary>Diver <paramref name="i"/> says its line for <paramref name="kind"/>, unless one was said just now
    /// (<paramref name="force"/> says it anyway).</summary>
    private void DiveLine(string kind, int i, Dive.Life? what = null, bool force = false)
    {
        if (!Settings.DiveTalk || !Settings.TalkEnabled || VoiceIsTakenNow || i < 0 || i >= creatures.Count) return;
        if (dive is DiveSession s)
        {
            if (!force && Elapsed - s.LastLine < DiveLineGap) return;
            s.LastLine = Elapsed;
        }
        var name = CharacterFor(i).Name;
        var text = Dive.Line(name, kind, what, rng);
        if (text.Length == 0) return;
        Say(text, i, builtIn: true);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = L10n.Tr("Scuba diving.") + " " + Describe(i) + ".",
            Provider = AppSettings.BrainTitle(BrainKind.Script), Model = "",
            Lines = new List<ChatLog.Line> { new(name, text) },
        });
    }

    // MARK: Drawing

    /// <summary>The gear on each diver, the splashes, the ink, and the drops off those just out.</summary>
    internal List<PropSnapshot> DiveProps()
    {
        var props = new List<PropSnapshot>();
        Bitmap? Image(string name, double time = 0) => seaFrames.Frame(name, time);
        if (dive is DiveSession s)
        {
            foreach (var d in s.Model.Divers.Where(d => d.Index < creatures.Count && creatures[d.Index].IsPlaying))
            {
                var c = creatures[d.Index];
                var p = DrawnPosition(d.Index);
                // The gear goes on while the water comes up: it fades in.
                var shown = d.State == Dive.DiverState.Gearing ? (float)Math.Clamp(1 - (d.Until - s.Model.Time - 0.4) / 1.2, 0, 1) : 1f;
                props.Add(new PropSnapshot(Image("tank"), p, c.Rotation, sizes[d.Index], c.IsMirrored, shown));
                props.Add(new PropSnapshot(Image("mask"), p, c.Rotation, sizes[d.Index], c.IsMirrored, shown, InFront: true));
            }
            var scale = s.Model.Scale;
            foreach (var (at, since) in s.Splashes)
            {
                var t = Elapsed - since;
                props.Add(new PropSnapshot(Image("splash", t), new Pt(at.X, at.Y + PlayCell.Height * scale * 0.3), 0, scale * 1.3,
                                           Opacity: (float)(1 - t / SplashSeconds * 0.6), InFront: true));
            }
            foreach (var (at, since) in s.Inks)
            {
                var t = Elapsed - since;
                props.Add(new PropSnapshot(Image("ink"), new Pt(at.X, at.Y + t * 12), 0, scale * (1 + t * 0.8), Opacity: (float)Math.Max(0, 1 - t / InkSeconds)));
            }
        }
        foreach (var (i, until) in dripping.Where(d => d.Key < creatures.Count))
        {
            var left = until - Elapsed;
            var scale = sizes[i];
            var p = DrawnPosition(i);
            for (int k = 0; k < 2; k++)
            {
                var fall = (Elapsed * 1.6 + k * 0.5) % 1;
                var side = k == 0 ? -0.5 : 0.45;
                props.Add(new PropSnapshot(playFrames.Frame("drop", 0),
                                           new Pt(p.X + atlas.BodyHalfSize * scale * side, p.Y - atlas.BodyHalfSize * scale * fall * 0.9), 0, scale,
                                           Opacity: (float)(Math.Min(1, left) * (1 - fall * 0.5)), InFront: true));
            }
        }
        return props;
    }

    /// <summary>The water on each monitor it covers, with everything living in it.</summary>
    internal List<WaterSnapshot> WaterSnapshots()
    {
        var made = new List<WaterSnapshot>();
        if (dive is not DiveSession s) return made;
        var m = s.Model;
        for (int k = 0; k < m.Pools.Count; k++)
        {
            var pool = m.Pools[k];
            var critters = m.Critters.Where(c => c.Pool == k).Select(c =>
            {
                // Claws up, arms spread: frightened.
                var up = c.Kind is Dive.Life.Crab or Dive.Life.Octopus && c.Scared > 0;
                return new WaterSnapshot.Sprite(seaFrames.Frame(up ? c.Kind.Code() + "-up" : c.Kind.Code(), c.Time), c.Position, !c.FacingRight);
            }).ToList();
            var bubbles = m.Bubbles.Where(b => pool.MinX <= b.Position.X && b.Position.X <= pool.MaxX)
                .Select(b => new WaterSnapshot.Sprite(seaFrames.Frame($"bubble-{b.Size}", 0), b.Position, false)).ToList();
            var weeds = m.Weeds.Where(w => w.Pool == k).Select(w => new WaterSnapshot.Weed(w.X, w.Height, w.Phase)).ToList();
            made.Add(new WaterSnapshot(pool, m.Surface(k), Settings.DiveWaterOpacity, m.Time, m.Scale, seaSheet.CellSize,
                                       critters, bubbles, weeds, seaFrames.Frame("coral", 0)));
        }
        return made;
    }

    /// <summary>Whether a click at <paramref name="cursor"/> is the creatures' to take; anywhere else (the dive's water
    /// too) it goes through to the app below.</summary>
    internal bool TakesClick(Pt cursor, bool shift) =>
        held is not null || (CreatureAt(cursor) is int i && (shift || creatures[i].IsSleeping)) || BubbleAt(cursor) is not null
        || LetterContains(cursor) || BedAt(cursor) is not null || OnStopButton(cursor);

    /// <summary>Whether any overlay has water on it now (tests, Stop activity).</summary>
    internal bool AnyWaterShown => overlays.Any(o => o.HasWater);
}
