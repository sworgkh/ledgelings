using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Turning the simulation into snapshots for every monitor's overlay.</summary>
public sealed partial class Colony
{
    /// <summary>Last frame's effect pictures: made afresh every frame, let go of once the next is drawn.</summary>
    private readonly List<Bitmap> fxPictures = new();

    private void Render()
    {
        if (frames.Count < creatures.Count) return;
        var used = fxPictures.ToList();
        fxPictures.Clear();
        var snapshots = new List<CreatureSnapshot>(creatures.Count);
        for (int i = 0; i < creatures.Count; i++)
        {
            var c = creatures[i];
            var shrink = DoorShrink(i);
            var inward = c.IsHeld || c.IsPlaying ? new Vec(0, 1) : c.Loop.Inward(c.Segment);
            // Shrinking, it keeps its feet on the floor: the centre sinks as the body gets smaller.
            var sink = atlas.BodyHalfSize * sizes[i] * (1 - shrink);
            var p = DrawnPosition(i);       // lying in its bed, a sleeper is raised onto the mattress
            var image = frames[i].Frame(c.Animation, c.AnimationTime, c.Eyes);
            snapshots.Add(new CreatureSnapshot
            {
                Position = new Pt(p.X - inward.Dx * sink, p.Y - inward.Dy * sink),
                Rotation = c.Rotation,
                IsMirrored = c.IsMirrored,
                Image = image,
                Scale = sizes[i],
                AsleepFor = c.LooksAsleep ? asleepFor[i] : null,
                Inward = inward,
                Bubble = BubbleShown(i).Text,
                BubbleShare = BubbleShown(i).Share,
                Hat = gifts.Hat(i) is string flower ? flowerFrames.Frame(flower, 0) : null,
                Hidden = hideout.IsInside(i),
                Shrink = shrink,
                Letter = LetterImage(i) ?? DictationMicrophone(i),
                BubbleLift = PlayBubbleLift(i),
                Effect = hideout.IsInside(i) ? null : EffectSnapshot(i, image),
            });
        }
        var z = zFrames.Frame("float", 0);
        var inFlight = FlightSnapshot();
        var stars = SparkSnapshots();
        var home = HouseSnapshot();
        var planted = GardenSnapshots();
        var sleepers = BedSnapshots();
        var plane = MailSnapshot();
        var reminder = DeliverySnapshot();
        var table = TeaTableSnapshot();
        var props = PlayProps();
        props.AddRange(MoveProps());
        props.AddRange(DiveProps());
        var water = WaterSnapshots();
        var surf = SurfWater();
        var stop = StopButtonNow();
        var loose = LooseEffectSnapshots();
        var ambient = AmbientSnapshots();
        foreach (var e in snapshots.Select(s => s.Effect).OfType<CreatureEffect>()) fxPictures.AddRange(new[] { e.Back, e.Front }.OfType<Bitmap>());
        foreach (var e in loose) fxPictures.AddRange(new[] { e.Back, e.Front }.OfType<Bitmap>());
        for (int k = 0; k < overlays.Count; k++)
            overlays[k].Render(snapshots, z, atlas.CellSize, zCell, flowerCell, inFlight, stars, home, houseCell, garden: planted, beds: sleepers, bedCell: BedCell,
                               plane: plane, planeCell: planeCell, reminder: reminder,
                               tea: table, teaCell: TeaCell, props: props, propCell: PlayCell, water: water, surf: surf,
                               stop: stop?.Overlay == k ? stop : null, loose: loose, ambient: ambient);
        foreach (var b in used) b.Dispose();
    }
}
