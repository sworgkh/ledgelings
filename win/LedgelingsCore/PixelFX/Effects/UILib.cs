// Helpers for the ui effects: big pixel words with a hand-made finish and a character lit or flashed by
// the effect. pixelfx's `fx/ui/_lib.js` (MIT); tintActor adapts the body flash of Sprite Fusion's
// open-source power-up (https://www.spritefusion.com/pixel-art-vfx/power-up), MIT License,
// Copyright (c) 2026 Hugo Duprez. The Mac's twin is UILib.swift.

namespace Ledgelings.Core.PixelFX;

public static class FXUI
{
    /// <summary>A glyph of a font: its width and rows of inked pixels.</summary>
    public sealed record Glyph(int W, bool[][] Rows);
    public readonly record struct Letter(char Ch, Glyph? G, int X, int W, int H);

    static readonly Dictionary<(FXFont, char), Glyph?> glyphs = new();

    /// <summary>One character's glyph, read back through the font's own width and raster (null when it has none).</summary>
    static Glyph? GlyphOf(FXFont font, char ch)
    {
        lock (glyphs)
        {
            if (glyphs.TryGetValue((font, ch), out var known)) return known;
            var s = ch.ToString();
            int w = font.Width(s);
            var rows = new bool[font.H][];
            for (int r = 0; r < font.H; r++) rows[r] = new bool[w];
            bool inked = false;
            font.Raster(s, (x, y) => { rows[(int)y][(int)x] = true; inked = true; });
            var g = inked ? new Glyph(w, rows) : null;
            glyphs[(font, ch)] = g;
            return g;
        }
    }

    /// <summary>The letters of str in a pixel font, laid out left to right in font pixels.</summary>
    public static (List<Letter> Letters, int W, int H) Spell(string str, FXFont? font = null)
    {
        font ??= FXFont.Big;
        var letters = new List<Letter>();
        int x = 0;
        foreach (var ch in str)
        {
            var g = GlyphOf(font, ch);
            int w = g?.W ?? font.Space;
            letters.Add(new Letter(ch, g, x, w, font.H));
            x += w + font.Gap;
        }
        return (letters, Math.Max(0, x - font.Gap), font.H);
    }

    /// <summary>One letter of a word: its glyph, top-left, px per font pixel, alpha, white flash, italic lean.</summary>
    public struct Item
    {
        public Glyph G;
        public double X, Y, Sx, Sy, A, Flash, Slant;
        public Item(Glyph g, double x, double y, double sx, double sy, double a = 1, double flash = 0, double slant = 0)
        { G = g; X = x; Y = y; Sx = sx; Sy = sy; A = a; Flash = flash; Slant = slant; }
    }
    public sealed class WordStyle
    {
        public required FXColor[] Fill;
        public FXColor? Edge, Under, Shadow, Glint;
        public required FXColor Outline;
        public int Ow = 1;
        public double? Shine, ShineY;
    }

    /// <summary>Letters drawn as one word: a gradient down each letter, a lit top edge, a shaded underside, a 1 px dark
    /// outline and a drop shadow, an optional diagonal shine and a white flash.</summary>
    public static void DrawWord(Painter p, IReadOnlyList<Item> items, WordStyle st)
    {
        if (items.Count == 0) return;
        double bx0 = double.PositiveInfinity, by0 = double.PositiveInfinity, bx1 = double.NegativeInfinity, by1 = double.NegativeInfinity;
        foreach (var it in items)
        {
            double h = it.G.Rows.Length * it.Sy, w = it.G.W * it.Sx, sl = Math.Abs(it.Slant) * it.G.Rows.Length;
            bx0 = Math.Min(bx0, it.X - sl); bx1 = Math.Max(bx1, it.X + w + sl);
            by0 = Math.Min(by0, it.Y); by1 = Math.Max(by1, it.Y + h);
        }
        int ow = st.Ow;
        int x0 = (int)FX.Floor(bx0) - 1 - ow, y0 = (int)FX.Floor(by0) - 1 - ow, x1 = (int)FX.Ceil(bx1) + 2 + ow, y1 = (int)FX.Ceil(by1) + 3 + ow;
        int W = x1 - x0, H = y1 - y0;
        var ids = new int[W * H];
        var edges = new int[W * H];
        static bool Cell(bool[]? r, int i) => r != null && i >= 0 && i < r.Length && r[i];
        for (int k = 0; k < items.Count; k++)
        {
            var it = items[k];
            var g = it.G;
            int gh = g.Rows.Length;
            double h = gh * it.Sy, bot = it.Y + h, sl = it.Slant;
            for (var py = FX.Floor(it.Y); py < FX.Ceil(bot); py++)
            {
                int gy = (int)FX.Floor((py + 0.5 - it.Y) / it.Sy);
                if (gy < 0 || gy >= gh) continue;
                var shift = FX.Round(((bot - py - 0.5) / it.Sy) * sl);
                double ry = py + 0.5 - it.Y - gy * it.Sy;
                var row = g.Rows[gy];
                for (var px = FX.Floor(it.X + shift) - 1; px <= FX.Ceil(it.X + shift + g.W * it.Sx); px++)
                {
                    double fx = px + 0.5 - it.X - shift, gxd = FX.Floor(fx / it.Sx);
                    if (gxd < 0 || gxd >= g.W) continue;
                    int gx = (int)gxd;
                    if (!row[gx]) continue;
                    int i = ((int)py - y0) * W + ((int)px - x0);
                    if (i < 0 || i >= W * H) continue;
                    ids[i] = k + 1;
                    // the bevel follows the font pixels: lit top, shaded underside, lit left; diagonals stay whole
                    double rx = fx - gxd * it.Sx;
                    bool[]? up = gy > 0 ? g.Rows[gy - 1] : null, dn = gy < gh - 1 ? g.Rows[gy + 1] : null;
                    bool Open(bool[]? r) => r == null || (!Cell(r, gx) && !Cell(r, gx - 1) && !Cell(r, gx + 1));
                    edges[i] = (ry < 1 && Open(up) ? 1 : 0) | (ry >= it.Sy - 1 && Open(dn) ? 2 : 0) | (rx < 1 && !(gx > 0 && row[gx - 1]) ? 4 : 0);
                }
            }
        }
        int At(int x, int y) => x < x0 || y < y0 || x >= x1 || y >= y1 ? 0 : ids[(y - y0) * W + (x - x0)];
        var F = st.Fill;
        int nF = F.Length;
        var glint = st.Glint ?? FX.White;
        double sy0 = st.ShineY ?? y0;
        for (int y = y0; y < y1; y++)
            for (int x = x0; x < x1; x++)
            {
                int id = At(x, y);
                if (id != 0)
                {
                    var it = items[id - 1];
                    double v = (y + 0.5 - it.Y) / (it.G.Rows.Length * it.Sy);
                    int i = (int)Math.Min(nF - 1, Math.Max(0, FX.Floor((1 - v) * nF)));
                    var c = F[i];
                    int e = edges[(y - y0) * W + (x - x0)];
                    if ((e & 1) != 0) c = st.Edge ?? F[nF - 1];
                    else if ((e & 2) != 0) c = st.Under ?? F[0];
                    else if ((e & 4) != 0 && i < nF - 1) c = F[i + 1];
                    if (st.Shine is double shine)
                    {
                        var d = Math.Abs(x + 0.5 - (y + 0.5 - sy0) * 0.6 - shine);
                        if (d < 1.1) c = FX.White; else if (d < 2.4) c = glint;
                    }
                    // a flash is white all over, then wipes up off the letter (no dither)
                    if (it.Flash > 0.6 || (it.Flash > 0.25 && v < 0.5)) c = FX.White;
                    p.Dot(x, y, c, it.A);
                    continue;
                }
                // the outline hugs every letter; the shadow drops below and right of it
                int n = 0;
                for (int dy = -ow; dy <= ow && n == 0; dy++)
                    for (int dx = -ow; dx <= ow && n == 0; dx++)
                        if (ow < 2 || Math.Abs(dx) + Math.Abs(dy) < 4) n = At(x + dx, y + dy);
                if (n != 0) { p.Dot(x, y, st.Outline, items[n - 1].A); continue; }
                int s = At(x - ow, y - 1 - ow);
                if (s == 0) s = At(x + 1 - ow, y - 1 - ow);
                if (s == 0) s = At(x - ow, y - ow);
                if (s != 0 && st.Shadow is FXColor sh) p.Dot(x, y, sh, items[s - 1].A * 0.9);
            }
    }

    /// <summary>Flash a character in light: its own pixels recoloured by brightness into ramp ([shadow, middle, light]);
    /// k steps down without dither, above 0.8 the lightest go white.</summary>
    public static void TintActor(Painter p, FXActor A, double k, FXColor[] ramp)
    {
        if (k <= 0.12) return;
        var m = A.Mask;
        var pix = A.Pixels;
        double cut = k > 0.6 ? 0 : k > 0.3 ? 0.22 : 0.5;
        for (int j = 0; j < m.H; j++)
            for (int i = 0; i < m.W; i++)
            {
                int q = j * m.W + i;
                if (m.Data[q] == 0) continue;
                var l = FX.Luma(pix[q]);
                if (l < cut) continue;
                p.Px(A.X + i, A.Y + j, l > 0.5 ? (k > 0.8 ? FX.White : ramp[2]) : l > 0.22 ? ramp[1] : ramp[0]);
            }
    }

    /// <summary>Light a character: additive light over its body (k), stronger towards the top, and light catching the
    /// edge just inside its outline (rim), mixed into its own colours.</summary>
    public static void LightActor(Painter p, FXActor A, FXColor c, double k, double rim = 0, double t = 0)
    {
        if (k <= 0.01 && rim <= 0.01) return;
        var m = A.Mask;
        var pix = A.Pixels;
        bool Has(int i, int j) => i >= 0 && j >= 0 && i < m.W && j < m.H && m.Data[j * m.W + i] != 0;
        for (int j = 0; j < m.H; j++)
            for (int i = 0; i < m.W; i++)
            {
                if (m.Data[j * m.W + i] == 0) continue;
                if (k > 0.01) p.Light(A.X + i, A.Y + j, c, k * (1.1 - (0.5 * j) / m.H));
                if (rim <= 0.01 || !Has(i - 1, j) || !Has(i + 1, j) || !Has(i, j - 1)) continue;
                if (Has(i - 2, j) && Has(i + 2, j) && Has(i, j - 2)) continue;
                var f = rim * (0.75 + 0.35 * FX.Noise(j * 0.6 - t * 8, i * 3));
                if (f > 0.25)
                {
                    var own = pix[j * m.W + i];
                    p.Px(A.X + i, A.Y + j, FX.Mix(own != 0 ? own : c, c, Math.Min(0.85, f)));
                }
            }
    }

    /// <summary>A glowing 1 px line just outside a character, flickering: an aura's edge.</summary>
    public static void HaloActor(Painter p, FXActor A, FXColor c, double k, double t = 0)
    {
        if (k <= 0.02) return;
        p.Outline(A.Mask, A.X, A.Y, (_, _) => c, (mx, my) => k * (0.75 + 0.45 * FX.Noise(my * 0.45 - t * 7, mx * 3)));
    }
}
