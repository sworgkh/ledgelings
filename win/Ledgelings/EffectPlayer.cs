using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.CompilerServices;
using Ledgelings.Core;
using Ledgelings.Core.PixelFX;

namespace Ledgelings;

/// <summary>
/// One effect on show, drawn as two pixel pictures, the Mac's <c>EffectPlayer</c>: what goes behind the
/// creature's sprite, and what goes in front of it. The creature itself stays the overlay's own sprite, walking
/// as ever; the front picture only carries the pixels the effect changed over it (a film of frost, a glow), so
/// between the two the screen shows exactly what pixelfx composites: back, creature, front (SPEC §7.19).
/// </summary>
public sealed class EffectPlayer
{
    public FXInstance Instance { get; }
    /// <summary>The pixelfx effect, the style or moment it plays for.</summary>
    public string Name { get; }
    public Effects.Style? Style { get; }
    public Effects.Moment? Moment { get; }
    private readonly FXFrame back, front;
    /// <summary>Where the creature's box sits in its sprite cell, so the pictures line up with the sprite.</summary>
    public (int X, int Y, int W, int H) Box { get; }
    /// <summary>Wears off at this time on the colony's clock (a style), or null: when it is done, or let go of.</summary>
    public double? Until { get; set; }
    /// <summary>Played by hand (a preview): it runs its time whatever the moment's state says.</summary>
    public bool ByHand { get; set; }
    /// <summary>The creature stays hidden until this many seconds in: inside the egg until it hatches.</summary>
    public double? HiddenUntil { get; set; }

    public EffectPlayer(FXEffectType type, string name, FXActor actor, (int X, int Y, int W, int H) box, double seed,
                        Effects.Style? style = null, Effects.Moment? moment = null)
    {
        var o = new FXOptions(type.Meta, actor, seed) { X = type.Meta.Origin.X, Y = type.Meta.Origin.Y };
        Instance = new FXInstance(type, o);
        Name = name;
        Style = style;
        Moment = moment;
        Box = box;
        back = new FXFrame(type.Meta.Size.W, type.Meta.Size.H);
        front = new FXFrame(type.Meta.Size.W, type.Meta.Size.H);
    }

    public Size Size => new(back.W, back.H);
    public bool Done => Instance.Done;

    /// <summary>The frame's top-left corner in the sprite cell's pixels (y down), where the pictures are drawn.</summary>
    public Point CellOrigin
    {
        get
        {
            var a = Instance.Options.Actor;
            var m = Instance.Meta;
            return new Point(Box.X + a.W / 2 - (int)m.Origin.X, Box.Y + a.H - (int)m.Origin.Y);
        }
    }

    /// <summary>Both pictures for now. <paramref name="actor"/> is the creature as its sprite shows it this frame (the same
    /// box): it is drawn between the layers so the front's blends and light land on it, then left out of the front
    /// picture wherever the front did not change it.</summary>
    public (Bitmap? Back, Bitmap? Front, bool HidesBody) Pictures(uint[]? actor)
    {
        var shown = Instance.ActorAlpha > 0.5 && Instance.T >= (HiddenUntil ?? 0);
        back.Clear();
        Instance.Draw(back, FXLayer.Back);

        // The front draws over what the back left, with one light for both, as pixelfx's single frame does.
        Array.Copy(back.Color, front.Color, back.Color.Length);
        Array.Copy(back.Light, front.Light, back.Light.Length);
        var a = Instance.Options.Actor;
        int ox = (int)Instance.Options.X + a.X, oy = (int)Instance.Options.Y + a.Y;
        var body = actor ?? a.Pixels;
        if (shown && body.Length == a.W * a.H) Stamp(body, a.W, a.H, ox, oy, front);
        var before = (uint[])front.Color.Clone();
        Instance.Draw(front, FXLayer.Front);
        var rgba = FXComposite.Rgba(front);
        // Unchanged and unlit, a pixel is not the front's: the back picture or the sprite shows it.
        for (var i = 0; i < front.W * front.H; i++)
            if (front.Color[i] == before[i] && front.Light[i] == 0) rgba[i * 4 + 3] = 0;

        // The back's light is drawn with the front, over the sprite too.
        Array.Clear(back.Light);
        return (Image(FXComposite.Rgba(back), back.W, back.H), Image(rgba, front.W, front.H), !shown);
    }

    /// <summary>Everything in one picture, the creature as it stands included: for a picture of the effect.</summary>
    public Bitmap? Still()
    {
        Instance.Render(back);
        return Image(FXComposite.Rgba(back), back.W, back.H);
    }

    /// <summary>Everything in one picture, no creature: the ambient particles.</summary>
    public Bitmap? Whole()
    {
        Instance.Render(back, drawActor: false);
        return Image(FXComposite.Rgba(back), back.W, back.H);
    }

    private static void Stamp(uint[] px, int w, int h, int ox, int oy, FXFrame f)
    {
        for (var yy = 0; yy < h; yy++)
            for (var xx = 0; xx < w; xx++)
            {
                var c = px[yy * w + xx];
                if (c == 0) continue;
                int x = ox + xx, y = oy + yy;
                if (x >= 0 && y >= 0 && x < f.W && y < f.H) f.Color[y * f.W + x] = c;
            }
    }

    // MARK: Pictures

    /// <summary>Straight RGBA bytes as a bitmap, null when nothing is drawn. Pixel art has 1-bit alpha, so
    /// premultiplied is the same bytes.</summary>
    public static Bitmap? Image(byte[] rgba, int w, int h)
    {
        var any = false;
        for (var i = 3; i < rgba.Length && !any; i += 4) any = rgba[i] != 0;
        if (!any) return null;
        var bitmap = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        var data = bitmap.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        var bgra = new byte[w * h * 4];
        for (var i = 0; i < w * h; i++)
        {
            var alpha = rgba[i * 4 + 3];
            if (alpha == 0) continue;
            bgra[i * 4] = rgba[i * 4 + 2]; bgra[i * 4 + 1] = rgba[i * 4 + 1]; bgra[i * 4 + 2] = rgba[i * 4]; bgra[i * 4 + 3] = alpha;
        }
        for (var y = 0; y < h; y++) System.Runtime.InteropServices.Marshal.Copy(bgra, y * w * 4, data.Scan0 + y * data.Stride, w * 4);
        bitmap.UnlockBits(data);
        return bitmap;
    }

    /// <summary>A bitmap's straight RGBA bytes.</summary>
    public static byte[] Rgba(Bitmap image)
    {
        int w = image.Width, h = image.Height;
        var data = image.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var bgra = new byte[w * h * 4];
        for (var y = 0; y < h; y++) System.Runtime.InteropServices.Marshal.Copy(data.Scan0 + y * data.Stride, bgra, y * w * 4, w * 4);
        image.UnlockBits(data);
        var rgba = new byte[bgra.Length];
        for (var i = 0; i < w * h; i++)
        {
            rgba[i * 4] = bgra[i * 4 + 2]; rgba[i * 4 + 1] = bgra[i * 4 + 1]; rgba[i * 4 + 2] = bgra[i * 4]; rgba[i * 4 + 3] = bgra[i * 4 + 3];
        }
        return rgba;
    }
}

/// <summary>The creatures as the effects see them: each sprite frame's pixels, worked out once per picture.</summary>
public sealed class EffectActors
{
    private readonly ConditionalWeakTable<Bitmap, uint[]> bodies = new();
    private readonly ConditionalWeakTable<Bitmap, Tuple<FXActor, (int X, int Y, int W, int H)>> actors = new();

    /// <summary>The creature to shape an effect round, from its standing picture: its box in the cell, and its colours.</summary>
    public (FXActor Actor, (int X, int Y, int W, int H) Box)? Actor(Bitmap standing)
    {
        if (actors.TryGetValue(standing, out var made)) return (made.Item1, made.Item2);
        var rgba = EffectPlayer.Rgba(standing);
        if (FXActor.Box(rgba, standing.Width, standing.Height) is not { } box
            || FXActor.FromRgba(rgba, standing.Width, standing.Height, box) is not { } actor) return null;
        actors.AddOrUpdate(standing, Tuple.Create(actor, box));
        return (actor, box);
    }

    /// <summary>The pixels of one sprite frame inside <paramref name="box"/>, as the effect draws the creature between its layers.</summary>
    public uint[] Pixels(Bitmap image, (int X, int Y, int W, int H) box)
    {
        if (bodies.TryGetValue(image, out var made) && made.Length == box.W * box.H) return made;
        var px = FXActor.FromRgba(EffectPlayer.Rgba(image), image.Width, image.Height, box)?.Pixels ?? Array.Empty<uint>();
        bodies.AddOrUpdate(image, px);
        return px;
    }
}
