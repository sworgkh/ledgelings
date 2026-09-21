using System.Drawing;
using System.Drawing.Drawing2D;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Everything needed to draw one creature for one frame, in GLOBAL coordinates.</summary>
public sealed class CreatureSnapshot
{
    public Pt Position;
    public double Rotation;
    public bool IsMirrored;
    public Bitmap? Image;
    /// <summary>Screen pixels per sprite pixel, for this creature.</summary>
    public double Scale;
    /// <summary>Seconds asleep, or null when awake. Drives the floating Zs.</summary>
    public double? AsleepFor;
    /// <summary>Which way is "up" for this creature: away from its edge, into the screen.</summary>
    public Vec Inward = new(0, 1);
    /// <summary>What it is saying right now, if anything.</summary>
    public string? Bubble;
    /// <summary>The flower on its head, if it was given one.</summary>
    public Bitmap? Hat;
    /// <summary>Inside the house: draw nothing at all.</summary>
    public bool Hidden;
    /// <summary>1 = full size; falls to 0 as it disappears into the doorway, rises from 0 as it comes out.</summary>
    public double Shrink = 1;
}

/// <summary>The house, at whatever size it currently is, pinned by its bottom-right corner.
/// Drawn behind the creatures; at the doorway they shrink to nothing on top of it.</summary>
public sealed record HouseSnapshot(Bitmap? Image, Pt Corner, double Scale);

/// <summary>A flower on its way from one creature to another, in GLOBAL coordinates.</summary>
public sealed record FlowerFlight(Bitmap? Image, Pt Position, double Rotation, double Scale);

/// <summary>One pixel star from a bump, already coloured and faded.</summary>
public readonly record struct SparkSnapshot(Pt Position, double Size, Color Color, float Opacity);

/// <summary>
/// One monitor's glass, drawing EVERY creature -- not only the ones on this
/// monitor. A window cannot span two displays, so a creature crossing a seam is
/// drawn by both overlays, each clipping its own half.
///
/// Each frame it works out which rectangles changed (where things were, where
/// they are), clears and redraws only those, and hands only those to the compositor.
/// </summary>
public sealed partial class ScreenOverlay : IDisposable
{
    private const int ZCount = 3;
    private const double ZCycle = 2.6;        // seconds for one Z to rise and fade

    public Monitor Monitor { get; }
    public event Action<HandEvent>? Hand;

    private readonly OverlayWindow window;
    /// <summary>Text and bubble metrics grow with the monitor's dpi.</summary>
    private readonly float ui;
    private readonly Font bubbleFont;
    private Dictionary<int, (RectangleF Plate, string Text, SizeF TextSize)> bubbles = new();
    private List<Rectangle> previous = new();

    public ScreenOverlay(Monitor monitor)
    {
        Monitor = monitor;
        window = new OverlayWindow(monitor);
        window.Hand += e => Hand?.Invoke(e);
        ui = (float)monitor.DpiScale;
        bubbleFont = new Font("Consolas", 16 * ui, FontStyle.Bold, GraphicsUnit.Pixel);
    }

    public void SetClickable(bool clickable) => window.SetClickable(clickable);

    /// <summary>The creature whose speech bubble is under <paramref name="point"/>, if any.</summary>
    public int? BubbleIndex(Pt point)
    {
        var p = ToWindow(point);
        foreach (var (index, bubble) in bubbles) if (bubble.Plate.Contains(p)) return index;
        return null;
    }

    private PointF ToWindow(Pt p) => new((float)(p.X - Monitor.Left), (float)(-p.Y - Monitor.Top));

    public void Render(IReadOnlyList<CreatureSnapshot> snapshots, Bitmap? z, Size cell, Size zCell, Size flowerCell,
                       FlowerFlight? flight, IReadOnlyList<SparkSnapshot> sparks, HouseSnapshot? house, Size houseCell)
    {
        var ops = new List<(Rectangle Bounds, Action<Graphics> Draw)>();
        AddHouse(ops, house, houseCell);
        var newBubbles = new Dictionary<int, (RectangleF, string, SizeF)>();
        for (int index = 0; index < snapshots.Count; index++)
        {
            var snap = snapshots[index];
            if (snap.Hidden || snap.Image is null) continue;
            var scale = snap.Scale;
            var reach = Math.Max(cell.Width, cell.Height) * scale * 2.5;
            // A creature nowhere near this monitor costs it nothing.
            if (!Monitor.Frame.InsetBy(-reach, -reach).Contains(snap.Position)) continue;
            var hatHeight = snap.Hat is null ? 0 : flowerCell.Height * scale;
            AddCreature(ops, snap, z, cell, hatHeight);
            AddBubble(ops, newBubbles, snap, index, cell.Width * scale / 2 + hatHeight);
        }
        AddFlight(ops, flight, flowerCell);
        AddSparks(ops, sparks);
        bubbles = newBubbles;

        var current = ops.Select(o => o.Bounds).ToList();
        var dirty = Merge(previous.Concat(current).Select(Clip).Where(r => r.Width > 0 && r.Height > 0).ToList());
        previous = current;
        if (dirty.Count == 0) return;

        var g = window.Graphics;
        g.ResetTransform();
        g.ResetClip();
        g.CompositingMode = CompositingMode.SourceCopy;
        using (var clear = new SolidBrush(Color.FromArgb(0, 0, 0, 0)))
            foreach (var r in dirty) g.FillRectangle(clear, r);
        g.CompositingMode = CompositingMode.SourceOver;
        using var region = new Region(dirty[0]);
        for (int i = 1; i < dirty.Count; i++) region.Union(dirty[i]);
        g.SetClip(region, CombineMode.Replace);
        foreach (var (bounds, draw) in ops)
        {
            if (!dirty.Any(d => d.IntersectsWith(bounds))) continue;
            g.ResetTransform();
            draw(g);
        }
        g.ResetTransform();
        g.ResetClip();
        window.Present(dirty);
    }

    private Rectangle Clip(Rectangle r) => Rectangle.Intersect(r, new Rectangle(0, 0, Monitor.Width, Monitor.Height));

    /// <summary>Fold rectangles that overlap into their union, so the compositor gets a few
    /// blocks instead of one that spans the whole screen.</summary>
    private static List<Rectangle> Merge(List<Rectangle> rects)
    {
        var merged = true;
        while (merged)
        {
            merged = false;
            for (int i = 0; i < rects.Count && !merged; i++)
                for (int j = i + 1; j < rects.Count; j++)
                {
                    var a = rects[i];
                    var b = rects[j];
                    a.Inflate(2, 2);
                    if (!a.IntersectsWith(b)) continue;
                    rects[i] = Rectangle.Union(rects[i], b);
                    rects.RemoveAt(j);
                    merged = true;
                    break;
                }
        }
        return rects;
    }

    public void Dispose()
    {
        window.Dispose();
        bubbleFont.Dispose();
    }
}
