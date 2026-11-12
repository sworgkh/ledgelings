using Ledgelings.Core.PixelFX;

namespace Ledgelings.Core;

public static partial class Weather
{
    /// <summary>A prop's pixels, row by row from the top, 0 for nothing, the Mac's <c>Weather+Art.swift</c>: drawn in
    /// Blocky's style (square pixels, flat fill, a 1-pixel dark-tint outline, a light line top-left, a shade line
    /// bottom-right, no curves: a dome is steps).</summary>
    public sealed class Art
    {
        public readonly int W, H;
        public readonly FXColor[] Pixels;
        public Art(int w, int h) { W = w; H = h; Pixels = new FXColor[w * h]; }
        public FXColor At(int x, int y) => x >= 0 && y >= 0 && x < W && y < H ? Pixels[y * W + x] : 0;
        public void Set(int x, int y, FXColor c) { if (x >= 0 && y >= 0 && x < W && y < H) Pixels[y * W + x] = c; }

        /// <summary>The pixels as straight RGBA bytes, for a picture.</summary>
        public byte[] Rgba
        {
            get
            {
                var o = new byte[W * H * 4];
                for (int i = 0; i < Pixels.Length; i++)
                {
                    var c = Pixels[i];
                    if (c == 0) continue;
                    o[i * 4] = (byte)(c & 255); o[i * 4 + 1] = (byte)((c >> 8) & 255); o[i * 4 + 2] = (byte)((c >> 16) & 255); o[i * 4 + 3] = 255;
                }
                return o;
            }
        }

        /// <summary>The outline, light and shade of a filled shape (every pixel of <paramref name="fill"/> colour), as Blocky is drawn.</summary>
        public void ShapeUp(FXColor fill)
        {
            var inside = Pixels.Select(p => p == fill).ToArray();
            bool Filled(int x, int y) => x >= 0 && y >= 0 && x < W && y < H && inside[y * W + x];
            FXColor dark = FX.Scale(fill, 0.45), light = FX.Mix(fill, FX.White, 0.45), shade = FX.Scale(fill, 0.78);
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    if (!Filled(x, y)) continue;
                    if (!Filled(x - 1, y) || !Filled(x + 1, y) || !Filled(x, y - 1) || !Filled(x, y + 1)) { Set(x, y, dark); continue; }
                    if (!Filled(x - 2, y) || !Filled(x, y - 2)) Set(x, y, light);
                    else if (!Filled(x + 2, y) || !Filled(x, y + 2)) Set(x, y, shade);
                }
        }
    }

    /// <summary>The colours an umbrella may take, one per creature or group: bright and flat.</summary>
    public static readonly FXColor[] UmbrellaColours = new[] { "#e8463c", "#f2b134", "#3d9be9", "#5bbf5a", "#b55fd6", "#ef7fb0", "#2fb8a8", "#f07c2a" }.Select(FX.Hex).ToArray();
    static readonly FXColor Handle = FX.Hex("#3a2a1e");

    /// <summary>The colour of <paramref name="name"/>'s umbrella: always the same one for the same character.</summary>
    public static FXColor UmbrellaColour(string name)
    {
        var h = 0;
        foreach (var r in name.EnumerateRunes()) h = (h * 31 + r.Value) % 9973;
        return UmbrellaColours[h % UmbrellaColours.Length];
    }

    /// <summary>An umbrella <paramref name="width"/> pixels across, open over whoever holds it (the handle's foot at the
    /// bottom middle): a stepped dome with a scalloped rim. Inside out, the canopy is a cup pointing up, its ribs showing.</summary>
    public static Art Umbrella(int width, FXColor colour, bool insideOut = false)
    {
        var w = Math.Max(12, width | 1);                 // odd, so the handle stands in the middle
        int dome = UmbrellaDome(w), stick = 9, h = dome + stick + 1;
        var a = new Art(w, h);
        var mid = w / 2;
        // Each row of the dome, from the top, reaches out as far as a quarter circle would: steps, not a curve.
        var reach = Enumerable.Range(0, dome).Select(r =>
        {
            var k = 1 - (double)(r + 1) / dome;
            return Math.Max(2, Math.Min(mid, (int)Math.Round(mid * Math.Sqrt(1 - k * k), MidpointRounding.AwayFromZero)));
        }).ToArray();
        for (int r = 0; r < dome; r++)
        {
            var row = insideOut ? dome - 1 - r : r;
            for (int x = mid - reach[r]; x <= mid + reach[r]; x++) a.Set(x, row, colour);
        }
        // The rim: a notch between ribs every few pixels (open), or the ribs sticking out (inside out).
        if (!insideOut)
            for (int x = mid % 5; x < w; x += 5) if (x != mid) a.Set(x, dome - 1, 0);
        a.ShapeUp(colour);
        if (insideOut)
            for (int x = mid % 5; x < w; x += 5) if (x != mid) a.Set(x, 0, Handle);
        // The stick and the hook at its foot.
        var top = insideOut ? dome - 1 : 1;
        for (int y = top; y < dome + stick; y++) a.Set(mid, y, Handle);
        a.Set(mid - 1, dome + stick, Handle);
        a.Set(mid - 2, dome + stick - 1, Handle);
        return a;
    }

    /// <summary>Rows in an umbrella's dome <paramref name="width"/> pixels across: a third as tall as it is wide, at least five.</summary>
    public static int UmbrellaDome(int width) => Math.Max(5, width / 3);

    /// <summary>A tiny snowman: two square blocks of snow, black square eyes, a carrot nose.</summary>
    public static Art Snowman()
    {
        FXColor white = FX.Hex("#eef4fc"), eye = FX.Hex("#000000"), carrot = FX.Hex("#f08a24");
        var a = new Art(11, 15);
        for (int y = 0; y < 6; y++) for (int x = 3; x < 9; x++) a.Set(x, y, white);      // the head, a square
        for (int y = 6; y < 15; y++) for (int x = 1; x < 10; x++) a.Set(x, y, white);     // the body, a bigger square
        a.ShapeUp(white);
        a.Set(5, 2, eye); a.Set(7, 2, eye);
        a.Set(8, 3, carrot); a.Set(9, 3, carrot);
        foreach (var y in new[] { 9, 12 }) a.Set(5, y, FX.Hex("#3a2a1e"));              // two buttons
        return a;
    }

    /// <summary>A snowball, four pixels square.</summary>
    public static Art Snowball()
    {
        var white = FX.Hex("#f4f8ff");
        var a = new Art(4, 4);
        for (int i = 0; i < a.Pixels.Length; i++) a.Pixels[i] = white;
        a.ShapeUp(white);
        return a;
    }

    /// <summary>A drop of water falling off a wet creature.</summary>
    public static Art Drip()
    {
        var a = new Art(1, 2);
        a.Set(0, 0, FX.Hex("#b4d4ff")); a.Set(0, 1, FX.Hex("#4f82d6"));
        return a;
    }

    /// <summary>Three gusts of wind, stepped streaks: the Wind row's picture.</summary>
    public static Art Gusts()
    {
        var c = FX.Hex("#9fc2e0");
        var a = new Art(16, 11);
        foreach (var (y, x0, x1) in new[] { (1, 2, 12), (5, 0, 15), (8, 4, 13) })
        {
            for (int yy = y; yy <= y + 1; yy++) for (int x = x0; x <= x1; x++) a.Set(x, yy, c);
            a.Set(x1 - 1, y - 1, c); a.Set(x1, y - 1, c);          // the curl at the tip, a step up
        }
        a.ShapeUp(c);
        return a;
    }

    /// <summary>The sun, a square with four stubby rays: Clear sky's picture.</summary>
    public static Art Sun()
    {
        var c = FX.Hex("#f6c63c");
        var a = new Art(14, 14);
        for (int y = 3; y < 11; y++) for (int x = 3; x < 11; x++) a.Set(x, y, c);
        for (int k = 6; k < 8; k++) { a.Set(k, 0, c); a.Set(k, 1, c); a.Set(k, 12, c); a.Set(k, 13, c); a.Set(0, k, c); a.Set(1, k, c); a.Set(12, k, c); a.Set(13, k, c); }
        a.ShapeUp(c);
        return a;
    }

    /// <summary>Each weather's picture, and Clear sky's (null): for a menu or a button.</summary>
    public static Art Icon(Kind? kind) => kind switch
    {
        Kind.Snow => Snowman(),
        Kind.Rain => Umbrella(15, UmbrellaColours[2]),
        Kind.Wind => Gusts(),
        Kind.Storm => Umbrella(15, UmbrellaColours[4], insideOut: true),
        _ => Sun(),
    };
}
