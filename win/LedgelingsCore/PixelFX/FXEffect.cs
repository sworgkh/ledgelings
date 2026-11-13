// What an effect is, a live instance of one, the creature it is drawn around, and the 1-bit picture
// the overlay shows: pixelfx's `createFx`, `resolveOptions` and `composite`
// (https://github.com/patch-gg/pixelfx, MIT), with one change of ours. pixelfx composites light and
// translucent smoke over a backdrop; our creatures stand on the user's desktop, so what would be partly
// transparent is dithered to whole pixels instead (`FXComposite`), and nothing is ever half drawn.
// The Mac's twin is FXEffect.swift.

namespace Ledgelings.Core.PixelFX;

/// <summary>An effect's fixed facts: its frame, where its origin sits in it, how long it plays.</summary>
public sealed class FXMeta(string id, (int W, int H) size, (int X, int Y) origin, double duration, bool loop, string[] palette, double seed)
{
    public readonly string Id = id;
    public readonly (int W, int H) Size = size;
    public readonly (int X, int Y) Origin = origin;
    public readonly double Duration = duration;
    public readonly bool Loop = loop;
    public readonly string[] Palette = palette;
    public readonly double Seed = seed;
}

/// <summary>The creature an effect is drawn around, in local space with its feet at (0, 0): its mask and own colours
/// (row by row, 0 where empty), the top-left of the mask, the top of its head and its chest.</summary>
public sealed class FXActor
{
    public readonly FXMask Mask;
    public readonly FXColor[] Pixels;
    public readonly int X, Y, W, H;
    public readonly int K;
    public readonly (double X, double Y) Head;
    public readonly (double X, double Y) Chest;
    /// <summary>Where its eyes are, when the body says so; null to find them (<c>FXStatus.Eyes</c>).</summary>
    public readonly (int X, int Y)[]? Eyes;
    /// <summary>A number unique to this mask, so what is worked out once per shape can be kept.</summary>
    public readonly int Key;

    /// <summary>From w × h colours (0 = empty): its feet at the middle of its bottom row, as pixelfx's runner placed ours.</summary>
    public FXActor(int w, int h, FXColor[] pixels, (int X, int Y)[]? eyes = null)
    {
        W = w; H = h; Pixels = pixels;
        Mask = new FXMask(w, h, pixels.Select(c => c != 0 ? (byte)1 : (byte)0).ToArray());
        X = -(w / 2); Y = -h; K = 2;
        Head = (0, Y);
        Chest = (0, Y + FX.Round(h * 0.45));
        Eyes = eyes;
        // FNV-1a over the size and the colours: the same body gives the same key on every run
        ulong hash = 14695981039346656037;
        void Mix(uint v) { unchecked { hash = (hash ^ v) * 1099511628211; } }
        Mix((uint)w); Mix((uint)h);
        foreach (var c in pixels) Mix(c);
        Key = unchecked((int)(hash ^ (hash >> 32)));
    }

    /// <summary>From RGBA bytes (any alpha above 128 is a pixel), cut to the box that holds the body; null for an empty box.</summary>
    public static FXActor? FromRgba(byte[] rgba, int width, int height, (int X, int Y, int W, int H) box)
    {
        if (box.W <= 0 || box.H <= 0) return null;
        var px = new FXColor[box.W * box.H];
        for (int yy = 0; yy < box.H; yy++)
        {
            for (int xx = 0; xx < box.W; xx++)
            {
                int sx = box.X + xx, sy = box.Y + yy;
                if (sx < 0 || sy < 0 || sx >= width || sy >= height) continue;
                var i = (sy * width + sx) * 4;
                if (rgba[i + 3] > 128) px[yy * box.W + xx] = FX.Rgb(rgba[i], rgba[i + 1], rgba[i + 2]);
            }
        }
        return new FXActor(box.W, box.H, px);
    }

    /// <summary>The box round every pixel of an RGBA picture, null when it is empty.</summary>
    public static (int X, int Y, int W, int H)? Box(byte[] rgba, int width, int height)
    {
        int x0 = width, y0 = height, x1 = -1, y1 = -1;
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                if (rgba[(y * width + x) * 4 + 3] > 128)
                {
                    x0 = Math.Min(x0, x); x1 = Math.Max(x1, x); y0 = Math.Min(y0, y); y1 = Math.Max(y1, y);
                }
        return x1 < 0 ? null : (x0, y0, x1 - x0 + 1, y1 - y0 + 1);
    }
}

/// <summary>What an effect is given: where its origin is, which way it faces, its seed and palette, the creature.
/// A struct, as in Swift: an effect keeps its own copy.</summary>
public struct FXOptions
{
    public double X = 0, Y = 0;
    public bool Flip = false;
    public double Seed;
    public FXColor[] Palette;
    /// <summary>How strong its light is.</summary>
    public double Light = 1;
    public FXActor Actor;

    public FXOptions(FXMeta meta, FXActor actor, double? seed = null, string[]? palette = null)
    {
        Seed = seed ?? meta.Seed;
        var own = FX.Ramp(meta.Palette);
        if (palette != null) Palette = palette.Length == own.Length ? FX.Ramp(palette) : FX.Fit(FX.Ramp(palette), own.Length);
        else Palette = own;
        Actor = actor;
    }
}

/// <summary>One effect's drawing code. A stateless effect draws from t alone; one that keeps state steps in
/// <c>Update</c>. Every effect also has <c>public static readonly FXMeta Meta</c> and a constructor taking
/// <c>FXOptions</c>: that is how <c>FXCatalog</c> finds it.</summary>
public interface IFXEffect
{
    /// <summary>One step of its simulation (called at 120 Hz or finer).</summary>
    void Update(double dt) { }
    /// <summary>What goes behind the creature.</summary>
    void DrawBack(Painter p, double t) { }
    /// <summary>What goes in front of it.</summary>
    void Draw(Painter p, double t);
    /// <summary>How visible the creature itself should be at t: 0 while the effect draws the body itself or it has gone.</summary>
    double ActorAlpha(double t) => 1;
}

/// <summary>An effect drawn over a backdrop of its own (the weather's sky haze), which it can leave out over the desktop.</summary>
public interface IFXBackdropped
{
    bool Backdrop { get; set; }
}

/// <summary>A live effect: <c>createFx</c>'s clock, its stop-and-fade, and its draw.</summary>
public sealed class FXInstance
{
    const double FadeTime = 0.3;
    public readonly FXMeta Meta;
    public readonly FXOptions Options;
    readonly IFXEffect impl;
    public double T { get; private set; }
    double stopAt = double.PositiveInfinity;

    public FXInstance(FXEffectType type, FXOptions options)
    {
        Meta = type.Meta;
        Options = options;
        impl = type.Make(options);
    }

    public void Update(double dt)
    {
        T += dt;
        // simulations step at 120 Hz or finer whatever the caller's frame rate, so they look the same everywhere
        var n = Math.Max(1, (int)FX.Ceil(dt * 120 - 1e-9));
        for (int i = 0; i < n; i++) impl.Update(dt / n);
    }

    /// <summary>Its time within the effect: wrapped for a loop, held at the end for a one-shot.</summary>
    public double LocalTime => Meta.Loop ? FX.Mod(T, Meta.Duration) : Math.Min(T, Meta.Duration);

    /// <summary>null draws both layers.</summary>
    public void Draw(FXFrame frame, FXLayer? layer)
    {
        var p = frame.Painter.Reset();
        p.Place(Options.X, Options.Y, Options.Flip, 0);
        p.Fade = double.IsPositiveInfinity(stopAt) ? 1 : FX.Clamp(1 - (T - stopAt) / FadeTime);
        p.LightK = Options.Light;
        var tt = LocalTime;
        if (layer != FXLayer.Front) { p.Layer = FXLayer.Back; impl.DrawBack(p, tt); }
        if (layer != FXLayer.Back) { p.Layer = FXLayer.Front; impl.Draw(p, tt); }
    }

    public double ActorAlpha => impl.ActorAlpha(LocalTime);

    /// <summary>Leave out the effect's own backdrop, if it has one.</summary>
    public void DropBackdrop() { if (impl is IFXBackdropped b) b.Backdrop = false; }

    /// <summary>Fireflies only: how many fly, of 32.</summary>
    public void SetFireflies(int n) { if (impl is FXFireflies f) f.Flies = n; }

    /// <summary>Let it end: loops fade out, one-shots are cut short.</summary>
    public void Stop() { if (double.IsPositiveInfinity(stopAt)) stopAt = T; }
    public bool Stopping => !double.IsPositiveInfinity(stopAt);
    public bool Done => T - stopAt >= FadeTime || (!Meta.Loop && T >= Meta.Duration);

    /// <summary>The whole picture at this moment: the back layer, the creature, the front layer, into <c>frame</c>
    /// (sized <c>Meta.Size</c>, cleared first). Returns whether the creature was drawn.</summary>
    public bool Render(FXFrame frame, bool drawActor = true)
    {
        frame.Clear();
        Draw(frame, FXLayer.Back);
        var show = ActorAlpha > 0.5;
        if (show && drawActor)
        {
            var a = Options.Actor;
            int OX = (int)Options.X, OY = (int)Options.Y;
            for (int yy = 0; yy < a.H; yy++)
            {
                for (int xx = 0; xx < a.W; xx++)
                {
                    var c = a.Pixels[yy * a.W + xx];
                    if (c == 0) continue;
                    int X = OX + a.X + xx, Y = OY + a.Y + yy;
                    if (X >= 0 && Y >= 0 && X < frame.W && Y < frame.H) frame.Color[Y * frame.W + X] = c;
                }
            }
        }
        Draw(frame, FXLayer.Front);
        return show;
    }
}

/// <summary>Colour and light turned into the RGBA bytes the overlay shows, every pixel fully there or fully not.</summary>
public static class FXComposite
{
    /// <summary>pixelfx's composite over nothing, then: a pixel less than fully opaque is kept, whole, where its alpha
    /// beats the ordered-dither threshold of its cell, and only if it is at least <c>floor</c> opaque.</summary>
    public static byte[] Rgba(FXFrame f, double lightK = 1, double floor = 0.25)
    {
        var n = f.W * f.H;
        var o = new byte[n * 4];
        for (int i = 0; i < n; i++)
        {
            uint c = f.Color[i], l = f.Light[i] & 0xffffff;
            double r = c & 255, g = (c >> 8) & 255, b = (c >> 16) & 255, a = c >> 24;
            if (l != 0)
            {
                double lr = (l & 255) * lightK, lg = ((l >> 8) & 255) * lightK, lb = ((l >> 16) & 255) * lightK;
                if (a < 255)
                {
                    double pa = a / 255, pr = r * pa + lr, pg = g * pa + lg, pb = b * pa + lb;
                    var na = Math.Min(1, Math.Max(pa, Math.Max(lr, Math.Max(lg, lb)) / 255));
                    if (na > 0) { r = Math.Min(255, pr / na); g = Math.Min(255, pg / na); b = Math.Min(255, pb / na); a = na * 255; }
                }
                else
                {
                    r = Math.Min(255, r + lr); g = Math.Min(255, g + lg); b = Math.Min(255, b + lb);
                }
            }
            if (a < 255)
            {
                int x = i % f.W, y = i / f.W;
                var alpha = a / 255;
                if (alpha < floor || alpha <= Painter.Bayer[((y & 3) << 2) | (x & 3)]) continue;
            }
            var j = i * 4;
            o[j] = (byte)r; o[j + 1] = (byte)g; o[j + 2] = (byte)b; o[j + 3] = 255;
        }
        return o;
    }
}
