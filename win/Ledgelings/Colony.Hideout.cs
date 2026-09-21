using Ledgelings.Core;

namespace Ledgelings;

/// <summary>"Hide them for a while": the house comes out on the main screen's floor,
/// everyone runs (or jumps) home, the house packs itself away, and when the
/// time is up it comes back and they walk out one by one.</summary>
public sealed partial class Colony
{
    /// <summary>The house is drawn at the largest creature's pixel scale, so its doorway
    /// (26 sheet px) takes a 22 px body with room to spare.</summary>
    private double HouseScale => Settings.MaxSize * pixelScale;
    /// <summary>The doorway's middle, in sheet pixels from the cell's left edge:
    /// content box x (2) + DOOR_X (4) + DOOR_W / 2 (13). See spritetool/painters/house.py.</summary>
    private const double DoorMiddle = 19;
    /// <summary>How close to the door, along the loop, counts as "in".</summary>
    private const double DoorReach = 6;
    /// <summary>Seconds to shrink into the doorway, and to grow back out of it.</summary>
    private const double DoorTime = 0.35;
    /// <summary>Farther than this along the loop, a creature jumps to the porch instead of running the whole way.</summary>
    private const double RunReach = 420;
    /// <summary>The porch: this far left of the doorway, on the floor. Jumps land here, then it is a short run in.</summary>
    private const double PorchOffset = 150;

    /// <summary>The house's own bottom-right corner sits on the primary screen's bottom-right
    /// corner, so growing and shrinking happen about that corner.</summary>
    private Pt HouseCorner
    {
        get
        {
            var frame = Desktop.Primary(monitors)?.Frame ?? new Rect(0, 0, 1000, 600);
            // Two sheet px of margin sit right of the wall; let them hang off the screen.
            return new Pt(frame.MaxX + 2 * HouseScale, frame.MinY);
        }
    }

    /// <summary>Where a creature should be to count as inside: the middle of the doorway, on the floor.</summary>
    private Pt DoorPoint => new(HouseCorner.X - houseCell.Width * HouseScale + DoorMiddle * HouseScale, HouseCorner.Y);

    /// <summary>The nearest point of this creature's own loops to the doorway.</summary>
    private EdgeWorld.Spot DoorSpot(int i) => creatures[i].World.Nearest(DoorPoint);

    private EdgeWorld.Spot PorchSpot(int i) => creatures[i].World.Nearest(new Pt(DoorPoint.X - PorchOffset, DoorPoint.Y));

    public bool IsHiding => hideout.IsActive;

    public void Hide(double seconds)
    {
        if (hideout.IsActive || creatures.Count == 0) return;
        LetGo();
        ReleaseChat();
        bubbles.Clear();
        entering.Clear();
        leaving.Clear();
        hideout.Hide(creatures.Count, Elapsed, seconds);
        Render();
    }

    public void BringThemBack() => hideout.Recall(Elapsed);

    private void UpdateHideout()
    {
        if (!hideout.IsActive) return;
        foreach (var e in hideout.Update(Elapsed))
        {
            switch (e)
            {
                case Hideout.Event.ForceInside(var stragglers):
                    foreach (var i in stragglers) hideout.Entered(i, Elapsed);
                    break;
                case Hideout.Event.LetOut(var i):
                    if (i >= creatures.Count) continue;
                    // Out through the door and away from the corner, so nobody walks straight behind the house.
                    creatures[i].Emerge(DoorSpot(i), -1, rng);
                    leaving[i] = Elapsed;
                    break;
            }
        }
        if (hideout.CurrentPhase == Hideout.Phase.Gathering)
        {
            foreach (var i in entering.Where(e => Elapsed - e.Value >= DoorTime).Select(e => e.Key).ToList())
            {
                entering.Remove(i);
                hideout.Entered(i, Elapsed);
            }
            for (int i = 0; i < creatures.Count; i++)
                if (!hideout.IsInside(i) && !entering.ContainsKey(i)) Herd(i);
        }
        else if (entering.Count > 0) entering.Clear();          // recalled mid-shrink: pop back to full size and stay out
        foreach (var i in leaving.Where(l => Elapsed - l.Value >= DoorTime).Select(l => l.Key).ToList()) leaving.Remove(i);
    }

    /// <summary>1 = full size; on the way in it falls to 0, on the way out it rises from 0.</summary>
    private double DoorShrink(int i)
    {
        if (entering.TryGetValue(i, out var since)) return Math.Max(0, 1 - (Elapsed - since) / DoorTime);
        if (leaving.TryGetValue(i, out var left)) return Math.Min(1, (Elapsed - left) / DoorTime);
        return 1;
    }

    /// <summary>Send one creature home: a short run in if it is near the door, otherwise a
    /// jump to the porch first (from anywhere: another monitor, the ceiling, far
    /// down the floor), then the run.</summary>
    private void Herd(int i)
    {
        if (held is { } h && h.Index == i) LetGo();
        if (creatures[i].IsJumping) return;
        var door = DoorSpot(i);
        var c = creatures[i];
        var along = c.Spot.Loop == door.Loop ? Math.Min(c.Loop.Wrap(c.T - door.T), c.Loop.Wrap(door.T - c.T)) : double.PositiveInfinity;
        if (along <= DoorReach) entering[i] = Elapsed;         // at the door: shrink away, then it is inside
        else if (along > RunReach && !c.HasArrived) creatures[i].Leap(PorchSpot(i));
        else if (!c.IsRunning) creatures[i].Run(door.T);
    }

    private HouseSnapshot? HouseSnapshot()
    {
        if (!hideout.IsActive) return null;
        var grown = hideout.Scale(Elapsed);
        if (grown <= 0) return null;
        return new HouseSnapshot(houseFrames.Frame("house", 0), HouseCorner, HouseScale * grown);
    }
}
