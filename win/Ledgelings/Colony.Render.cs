using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Turning the simulation into snapshots for every monitor's overlay.</summary>
public sealed partial class Colony
{
    private void Render()
    {
        if (frames.Count < creatures.Count) return;
        var snapshots = new List<CreatureSnapshot>(creatures.Count);
        for (int i = 0; i < creatures.Count; i++)
        {
            var c = creatures[i];
            var shrink = DoorShrink(i);
            var inward = c.IsHeld ? new Vec(0, 1) : c.Loop.Inward(c.Segment);
            // Shrinking, it keeps its feet on the floor: the centre sinks as the body gets smaller.
            var sink = atlas.BodyHalfSize * sizes[i] * (1 - shrink);
            snapshots.Add(new CreatureSnapshot
            {
                Position = new Pt(c.Position.X - inward.Dx * sink, c.Position.Y - inward.Dy * sink),
                Rotation = c.Rotation,
                IsMirrored = c.IsMirrored,
                Image = frames[i].Frame(c.Animation, c.AnimationTime, c.Eyes),
                Scale = sizes[i],
                AsleepFor = c.LooksAsleep ? asleepFor[i] : null,
                Inward = inward,
                Bubble = bubbles.TryGetValue(i, out var bubble) ? bubble.Text : null,
                Hat = gifts.Hat(i) is string flower ? flowerFrames.Frame(flower, 0) : null,
                Hidden = hideout.IsInside(i),
                Shrink = shrink,
            });
        }
        var z = zFrames.Frame("float", 0);
        var inFlight = FlightSnapshot();
        var stars = SparkSnapshots();
        var home = HouseSnapshot();
        foreach (var overlay in overlays)
            overlay.Render(snapshots, z, atlas.CellSize, zCell, flowerCell, inFlight, stars, home, houseCell);
    }
}
