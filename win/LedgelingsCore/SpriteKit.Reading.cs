namespace Ledgelings.Core;

public static partial class SpriteKit
{
    public sealed class ReadException : Exception
    {
        public int Found { get; }
        public ReadException(int found)
            : base(L10n.Tr("found %d creatures in the picture, not %d: it needs one per pose, apart from each other, on a plain background", found, SpriteText.Poses.Count))
        { Found = found; }
    }

    /// <summary>What a picture held: each pose's open-eyes grid, and the body colour it was painted in.</summary>
    public sealed record Reading(IReadOnlyDictionary<string, SpriteText.Ink[][]> Poses, SpriteText.Tint Colour)
    {
        /// <summary>The whole sheet in the built-in palette, eye variants and all, ready to save.</summary>
        public SpriteText.Image Sheet => SpriteText.Pixels(new SpriteText.Sheet { Poses = Poses }, SpriteText.Palette.Blocky);
    }

    /// <summary>
    /// Read nine creatures out of a picture an image model (or anyone) painted: any size,
    /// any layout that reads left to right and top to bottom (one row, three rows of the
    /// old sheet, a 3×3 grid), on magenta, white, a checkerboard or transparency. Lines,
    /// labels and specks are left out. Each creature is brought down to the size the
    /// built-in creature has, every sprite pixel taking the colour most of its square
    /// has, then snapped to the sheet's inks: a 1-pixel outline all round, black eyes,
    /// light, shade and body. Step for step the Mac's <c>SpriteKit.read</c>.
    /// </summary>
    public static Reading Read(SpriteText.Image image)
    {
        int w = image.Width, h = image.Height;
        var paper = BackgroundColours(image);
        var solid = new bool[w * h];
        for (var i = 0; i < w * h; i++) solid[i] = !IsBackground(image, i, paper);

        // A grid or frame line is not a creature.
        var found = Blobs(solid, w, h).Where(b => Math.Min(b.W, b.H) * 12 >= Math.Max(b.W, b.H)).ToList();
        // How far apart two patches may be and still be one creature: a tenth of a big patch's size.
        var big = found.OrderByDescending(b => b.Count).Take(SpriteText.Poses.Count).Select(b => Math.Max(b.W, b.H)).OrderBy(v => v).ToList();
        // A word is many small letters; a creature is one big patch with a few small ones (feet, a shine).
        // A creature is not a speck beside the picture (a lone letter of a label): at least a 33rd of its longer side.
        var least = Math.Max(w, h) / 33;
        var groups = Merged(found, Math.Max(1, Median(big) / 10)).Where(g => g.Largest * 2 >= g.Count && Math.Max(g.W, g.H) >= least).ToList();
        var reference = Median(groups.Select(g => g.Count).OrderByDescending(c => c).Take(SpriteText.Poses.Count).ToList());
        // Labels, words and specks.
        groups = groups.Where(g => g.Count * 5 >= reference && Math.Max(g.W, g.H) <= 4 * Math.Min(g.W, g.H)).ToList();
        if (groups.Count < SpriteText.Poses.Count) throw new ReadException(groups.Count);
        var ordered = ReadingOrder(groups).Take(SpriteText.Poses.Count).ToList();

        // One scale for all nine, so a squashed pose stays squashed: the biggest fills the body box.
        var side = (double)ordered.Max(g => Math.Max(g.W, g.H)) / SpriteText.Box.W;
        var grids = ordered.Select(g => Downscale(image, solid, g, side)).ToList();
        var body = BodyColour(grids);
        var poses = new Dictionary<string, SpriteText.Ink[][]>();
        for (var i = 0; i < SpriteText.Poses.Count; i++) poses[SpriteText.Poses[i]] = Inks(Placed(grids[i]), body);
        return new Reading(poses, body);
    }

    // MARK: Background

    /// <summary>Colours that cover at least a tenth of the picture's edge: the paper it was painted on.</summary>
    internal static List<SpriteText.Tint> BackgroundColours(SpriteText.Image image)
    {
        var counts = new Dictionary<int, (int N, int R, int G, int B)>();
        var total = 0;
        void Look(int x, int y)
        {
            var i = (y * image.Width + x) * 4;
            if (image.Rgba[i + 3] < 128) return;
            total++;
            int r = image.Rgba[i], g = image.Rgba[i + 1], b = image.Rgba[i + 2];
            var bucket = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
            var c = counts.TryGetValue(bucket, out var had) ? had : (N: 0, R: 0, G: 0, B: 0);
            counts[bucket] = (c.N + 1, c.R + r, c.G + g, c.B + b);
        }
        for (var x = 0; x < image.Width; x++) { Look(x, 0); Look(x, image.Height - 1); }
        for (var y = 0; y < image.Height; y++) { Look(0, y); Look(image.Width - 1, y); }
        if (total == 0) return new List<SpriteText.Tint>();
        return counts.Values.Where(c => c.N * 10 >= total)
            .Select(c => new SpriteText.Tint((byte)(c.R / c.N), (byte)(c.G / c.N), (byte)(c.B / c.N))).ToList();
    }

    internal static bool IsBackground(SpriteText.Image image, int pixel, List<SpriteText.Tint> paper)
    {
        var i = pixel * 4;
        if (image.Rgba[i + 3] < 128) return true;
        int r = image.Rgba[i], g = image.Rgba[i + 1], b = image.Rgba[i + 2];
        // Magenta and everything mixed from it: the template's lines, a blurred edge of the key.
        if (r >= 140 && b >= 140 && g * 10 < Math.Min(r, b) * 6) return true;
        foreach (var t in paper)
        {
            int dr = r - t.R, dg = g - t.G, db = b - t.B;
            if (dr * dr + dg * dg + db * db <= 40 * 40) return true;
        }
        return false;
    }

    // MARK: Finding the creatures

    /// <summary><c>Largest</c>: pixels in its biggest single patch.</summary>
    internal readonly record struct Blob(int X, int Y, int W, int H, int Count, int Largest)
    {
        public double MidX => X + W / 2.0;
        public double MidY => Y + H / 2.0;
    }

    /// <summary>Every 8-connected patch of painted pixels, specks dropped.</summary>
    internal static List<Blob> Blobs(bool[] solid, int w, int h)
    {
        var seen = new bool[w * h];
        var output = new List<Blob>();
        var speck = Math.Max(3, w * h / 50000);
        var stack = new Stack<int>();
        for (var start = 0; start < w * h; start++)
        {
            if (!solid[start] || seen[start]) continue;
            seen[start] = true;
            stack.Push(start);
            int x0 = w, y0 = h, x1 = -1, y1 = -1, n = 0;
            while (stack.Count > 0)
            {
                var p = stack.Pop();
                int x = p % w, y = p / w;
                n++;
                x0 = Math.Min(x0, x); x1 = Math.Max(x1, x); y0 = Math.Min(y0, y); y1 = Math.Max(y1, y);
                for (var dy = -1; dy <= 1; dy++)
                {
                    var yy = y + dy;
                    if (yy < 0 || yy >= h) continue;
                    for (var dx = -1; dx <= 1; dx++)
                    {
                        var xx = x + dx;
                        if (xx < 0 || xx >= w) continue;
                        var q = yy * w + xx;
                        if (solid[q] && !seen[q]) { seen[q] = true; stack.Push(q); }
                    }
                }
            }
            if (n >= speck) output.Add(new Blob(x0, y0, x1 - x0 + 1, y1 - y0 + 1, n, n));
        }
        return output;
    }

    /// <summary>Patches close together are one creature (feet drawn apart from the body, an eye's shine).</summary>
    internal static List<Blob> Merged(List<Blob> blobs, int margin)
    {
        var groups = blobs.ToList();
        var changed = true;
        while (changed)
        {
            changed = false;
            for (var a = 0; a < groups.Count && !changed; a++)
                for (var b = a + 1; b < groups.Count; b++)
                {
                    Blob p = groups[a], q = groups[b];
                    var apart = p.X - margin > q.X + q.W || q.X - margin > p.X + p.W
                             || p.Y - margin > q.Y + q.H || q.Y - margin > p.Y + p.H;
                    if (apart) continue;
                    int x0 = Math.Min(p.X, q.X), y0 = Math.Min(p.Y, q.Y);
                    int x1 = Math.Max(p.X + p.W, q.X + q.W), y1 = Math.Max(p.Y + p.H, q.Y + q.H);
                    groups[a] = new Blob(x0, y0, x1 - x0, y1 - y0, p.Count + q.Count, Math.Max(p.Largest, q.Largest));
                    groups.RemoveAt(b);
                    changed = true;
                    break;
                }
        }
        return groups;
    }

    /// <summary>Top row first, each row left to right; a row is everything whose middle is
    /// within half a creature of the row's first.</summary>
    internal static List<Blob> ReadingOrder(List<Blob> groups)
    {
        var tall = Median(groups.Select(g => g.H).OrderBy(v => v).ToList());
        var rows = new List<List<Blob>>();
        foreach (var g in groups.OrderBy(g => g.MidY))
        {
            if (rows.Count > 0 && Math.Abs(g.MidY - rows[^1][0].MidY) <= tall / 2.0) rows[^1].Add(g);
            else rows.Add(new List<Blob> { g });
        }
        return rows.SelectMany(r => r.OrderBy(g => g.MidX)).ToList();
    }

    internal static int Median(List<int> sorted) => sorted.Count == 0 ? 0 : sorted[sorted.Count / 2];

    // MARK: Down to sprite pixels

    private static int Round(double v) => (int)Math.Round(v, MidpointRounding.AwayFromZero);

    /// <summary>The creature in <paramref name="g"/> as a grid of colours (null = nothing), each sprite
    /// pixel <paramref name="side"/> picture pixels wide. A sprite pixel is painted when most of the
    /// middle of its square is, in the middle colour of what is painted there, so a blurred
    /// or anti-aliased edge never decides it.</summary>
    internal static SpriteText.Tint?[][] Downscale(SpriteText.Image image, bool[] solid, Blob g, double side)
    {
        var limit = SpriteText.Box.W;
        int tw = Math.Min(limit, Math.Max(1, Round(g.W / side))), th = Math.Min(limit, Math.Max(1, Round(g.H / side)));
        double sx = (double)g.W / tw, sy = (double)g.H / th;
        var grid = new SpriteText.Tint?[th][];
        for (var ty = 0; ty < th; ty++)
        {
            grid[ty] = new SpriteText.Tint?[tw];
            for (var tx = 0; tx < tw; tx++)
            {
                double x0 = g.X + (tx + 0.2) * sx, x1 = g.X + (tx + 0.8) * sx;
                double y0 = g.Y + (ty + 0.2) * sy, y1 = g.Y + (ty + 0.8) * sy;
                var r = new List<byte>(); var gg = new List<byte>(); var b = new List<byte>();
                var total = 0;
                foreach (var y in Samples(y0, y1))
                {
                    if (y < 0 || y >= image.Height) continue;
                    foreach (var x in Samples(x0, x1))
                    {
                        if (x < 0 || x >= image.Width) continue;
                        total++;
                        var p = y * image.Width + x;
                        if (!solid[p]) continue;
                        r.Add(image.Rgba[p * 4]); gg.Add(image.Rgba[p * 4 + 1]); b.Add(image.Rgba[p * 4 + 2]);
                    }
                }
                if (total == 0 || r.Count * 2 <= total) continue;
                r.Sort(); gg.Sort(); b.Sort();
                grid[ty][tx] = new SpriteText.Tint(r[r.Count / 2], gg[gg.Count / 2], b[b.Count / 2]);
            }
        }
        return grid;
    }

    /// <summary>Up to nine evenly spaced picture coordinates across [a, b).</summary>
    internal static List<int> Samples(double a, double b)
    {
        int first = (int)Math.Floor(a), last = Math.Max(first, (int)Math.Ceiling(b) - 1);
        var span = last - first + 1;
        if (span <= 9) return Enumerable.Range(first, span).ToList();
        return Enumerable.Range(0, 9).Select(i => first + i * (span - 1) / 8).ToList();
    }

    /// <summary>The grid trimmed and put in a 32×32 cell: centred left to right in the body
    /// box, standing on the floor.</summary>
    internal static SpriteText.Tint?[][] Placed(SpriteText.Tint?[][] grid)
    {
        int cell = SpriteText.Cell;
        var box = SpriteText.Box;
        var output = Enumerable.Range(0, cell).Select(_ => new SpriteText.Tint?[cell]).ToArray();
        var rows = Enumerable.Range(0, grid.Length).Where(y => grid[y].Any(t => t is not null)).ToList();
        var width = grid.Length == 0 ? 0 : grid[0].Length;
        var columns = Enumerable.Range(0, width).Where(x => grid.Any(row => row[x] is not null)).ToList();
        if (rows.Count == 0 || columns.Count == 0) return output;
        int top = rows[0], bottom = rows[^1], left = columns[0], right = columns[^1];
        int w = right - left + 1, h = bottom - top + 1;
        int ox = box.X + (box.W - w) / 2, oy = SpriteText.Floor - h;
        for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) output[oy + y][ox + x] = grid[top + y][left + x];
        return output;
    }

    // MARK: Inks

    internal static double Luma(SpriteText.Tint t) => 0.299 * t.R + 0.587 * t.G + 0.114 * t.B;

    internal static bool NearBlack(SpriteText.Tint t)
    {
        int hi = Math.Max(t.R, Math.Max(t.G, t.B)), lo = Math.Min(t.R, Math.Min(t.G, t.B));
        return hi < 72 && hi - lo < 36;
    }

    private static readonly (int Dx, int Dy)[] Four = { (0, -1), (0, 1), (-1, 0), (1, 0) };

    /// <summary>The colour most of the creatures' insides are painted in.</summary>
    internal static SpriteText.Tint BodyColour(List<SpriteText.Tint?[][]> grids)
    {
        var counts = new Dictionary<int, (int N, int R, int G, int B)>();
        void Count(bool insideOnly)
        {
            foreach (var grid in grids)
                for (var y = 0; y < grid.Length; y++)
                    for (var x = 0; x < grid[y].Length; x++)
                    {
                        if (grid[y][x] is not SpriteText.Tint t) continue;
                        if (insideOnly)
                        {
                            var edge = Four.Any(d =>
                            {
                                int yy = y + d.Dy, xx = x + d.Dx;
                                return yy < 0 || yy >= grid.Length || xx < 0 || xx >= grid[yy].Length || grid[yy][xx] is null;
                            });
                            if (edge || NearBlack(t)) continue;
                        }
                        var bucket = (t.R >> 4) << 8 | (t.G >> 4) << 4 | (t.B >> 4);
                        var c = counts.TryGetValue(bucket, out var had) ? had : (N: 0, R: 0, G: 0, B: 0);
                        counts[bucket] = (c.N + 1, c.R + t.R, c.G + t.G, c.B + t.B);
                    }
        }
        Count(true);
        if (counts.Count == 0) Count(false);
        if (counts.Count == 0) return SpriteText.Palette.Blocky.Body;
        var top = counts.Values.MaxBy(c => c.N);
        return new SpriteText.Tint((byte)(top.R / top.N), (byte)(top.G / top.N), (byte)(top.B / top.N));
    }

    /// <summary>Colours to inks, in Blocky's style: every pixel on the edge is outline;
    /// inside, a dark patch touching the outline is more outline (the feet), a black
    /// patch on its own is an eye, and the rest is light, shade or body by how bright
    /// it is beside the body colour.</summary>
    internal static SpriteText.Ink[][] Inks(SpriteText.Tint?[][] grid, SpriteText.Tint body)
    {
        var n = grid.Length;
        var lb = Luma(body);
        var step = Math.Max(16, lb * 0.1);
        bool Painted(int x, int y) => y >= 0 && y < n && x >= 0 && x < n && grid[y][x] is not null;
        bool Edge(int x, int y) => !Painted(x - 1, y) || !Painted(x + 1, y) || !Painted(x, y - 1) || !Painted(x, y + 1);
        bool Dark(SpriteText.Tint t) => NearBlack(t) || Luma(t) < lb * 0.55;

        var output = Enumerable.Range(0, n).Select(_ => new SpriteText.Ink[n]).ToArray();
        var done = Enumerable.Range(0, n).Select(_ => new bool[n]).ToArray();
        for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                if (grid[y][x] is not SpriteText.Tint t) continue;
                if (Edge(x, y)) { output[y][x] = SpriteText.Ink.Outline; done[y][x] = true; continue; }
                if (Dark(t)) continue;
                var l = Luma(t);
                output[y][x] = l > lb + step ? SpriteText.Ink.Light : l < lb - step ? SpriteText.Ink.Shade : SpriteText.Ink.Body;
                done[y][x] = true;
            }
        // What is left is dark and inside: one patch at a time.
        for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                if (done[y][x] || grid[y][x] is null) continue;
                var patch = new List<(int X, int Y)>();
                var stack = new Stack<(int X, int Y)>();
                stack.Push((x, y));
                var touchesOutline = false;
                var black = 0;
                done[y][x] = true;
                while (stack.Count > 0)
                {
                    var (px, py) = stack.Pop();
                    patch.Add((px, py));
                    if (NearBlack(grid[py][px]!.Value)) black++;
                    foreach (var (dx, dy) in Four)
                    {
                        int qx = px + dx, qy = py + dy;
                        if (!Painted(qx, qy)) continue;
                        if (Edge(qx, qy)) { if (Dark(grid[qy][qx]!.Value)) touchesOutline = true; continue; }
                        if (!done[qy][qx] && Dark(grid[qy][qx]!.Value)) { done[qy][qx] = true; stack.Push((qx, qy)); }
                    }
                }
                var ink = touchesOutline ? SpriteText.Ink.Outline : black * 2 >= patch.Count ? SpriteText.Ink.Eye : SpriteText.Ink.Shade;
                foreach (var (px, py) in patch) output[py][px] = ink;
            }
        // A blurred eye leaves a shade-dark halo beside it, which would stay put
        // when the lid comes down. Shade touching an eye, away from the outline
        // (where the real shade line runs), is part of the eye.
        // One pixel deep: a whole darker patch beside an eye stays shade.
        var halo = new List<(int X, int Y)>();
        for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
            {
                if (output[y][x] != SpriteText.Ink.Shade) continue;
                var around = Four.Select(d =>
                    y + d.Dy >= 0 && y + d.Dy < n && x + d.Dx >= 0 && x + d.Dx < n ? output[y + d.Dy][x + d.Dx] : SpriteText.Ink.Clear).ToList();
                if (around.Contains(SpriteText.Ink.Eye) && !around.Contains(SpriteText.Ink.Outline)) halo.Add((x, y));
            }
        foreach (var (x, y) in halo) output[y][x] = SpriteText.Ink.Eye;
        return output;
    }
}
