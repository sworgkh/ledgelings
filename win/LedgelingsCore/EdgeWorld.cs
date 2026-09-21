namespace Ledgelings.Core;

/// <summary>
/// Every edge a creature can walk, across all monitors.
///
/// Monitors that touch are fused: the creature walks the OUTLINE of the whole
/// desktop, not the border of each screen. So it crosses from one monitor to the
/// next along a shared floor, climbs the wall where a taller monitor begins, and
/// never walks the invisible seam between two screens.
///
/// The outline is pulled inwards by <c>inset</c> (half the body), so a loop
/// position is where the creature's CENTRE goes. That makes every corner a
/// plain rotation about the creature's own centre.
/// </summary>
public sealed class EdgeWorld : IEquatable<EdgeWorld>
{
    public readonly record struct Spot(int Loop, double T);

    public readonly record struct SegmentRef(int Loop, int Segment, double Length);

    public IReadOnlyList<EdgeLoop> Loops { get; }

    public EdgeWorld(IReadOnlyList<EdgeLoop> loops)
    {
        if (loops.Count == 0) throw new ArgumentException("a world needs at least one loop");
        Loops = loops.ToArray();
    }

    public EdgeWorld(IReadOnlyList<Rect> screens, double inset)
    {
        var usable = screens.Where(s => s.Width > 4 && s.Height > 4).ToList();
        var smallest = usable.Count == 0 ? 0 : usable.Min(s => Math.Min(s.Width, s.Height));
        var d = Math.Max(0, Math.Min(inset, smallest / 2 - 1));
        var traced = Trace(usable, d);
        Loops = traced.Count == 0 ? new[] { new EdgeLoop(new Rect(0, 0, 100, 100)) } : traced.ToArray();
    }

    public Pt Point(Spot spot) => Loops[spot.Loop].Point(spot.T);

    public Spot Nearest(Pt point)
    {
        var best = new Spot(0, 0);
        var bestDistance = double.PositiveInfinity;
        for (int l = 0; l < Loops.Count; l++)
        {
            var hit = Loops[l].Nearest(point);
            if (hit.Distance < bestDistance) { bestDistance = hit.Distance; best = new Spot(l, hit.T); }
        }
        return best;
    }

    /// <summary>Every (loop, segment) pair, for choosing somewhere to jump to.</summary>
    public IReadOnlyList<SegmentRef> Segments
    {
        get
        {
            var all = new List<SegmentRef>();
            for (int l = 0; l < Loops.Count; l++)
                for (int s = 0; s < Loops[l].SegmentCount; s++)
                    all.Add(new SegmentRef(l, s, Loops[l].SegmentLength(s)));
            return all;
        }
    }

    // MARK: Tracing the outline

    /// <summary>
    /// Shrink the union of <paramref name="screens"/> by <paramref name="d"/> and return its boundary loops.
    ///
    /// Works on a grid whose lines are every screen edge and every screen edge
    /// moved by ±d -- the only places the shrunken outline can turn. A grid cell
    /// survives if the cell grown back by <c>d</c> is still fully on screen.
    /// </summary>
    internal static List<EdgeLoop> Trace(IReadOnlyList<Rect> screens, double d)
    {
        var loops = new List<EdgeLoop>();
        if (screens.Count == 0) return loops;

        static List<double> Lines(IEnumerable<double> edges, double d)
        {
            var all = edges.SelectMany(e => new[] { e - d, e, e + d }).OrderBy(x => x).ToList();
            var kept = new List<double>();
            foreach (var x in all) if (kept.Count == 0 || x - kept[^1] > 0.01) kept.Add(x);
            return kept;
        }

        var edgeXs = screens.SelectMany(s => new[] { s.MinX, s.MaxX }).ToList();
        var edgeYs = screens.SelectMany(s => new[] { s.MinY, s.MaxY }).ToList();
        var xs = Lines(edgeXs, d);
        var ys = Lines(edgeYs, d);

        bool Covered(Rect r)
        {
            var cx = new List<double> { r.MinX, r.MaxX };
            cx.AddRange(edgeXs.Where(x => x > r.MinX && x < r.MaxX));
            cx.Sort();
            var cy = new List<double> { r.MinY, r.MaxY };
            cy.AddRange(edgeYs.Where(y => y > r.MinY && y < r.MaxY));
            cy.Sort();
            for (int i = 0; i < cx.Count - 1; i++)
            {
                if (cx[i + 1] - cx[i] <= 0.001) continue;
                for (int j = 0; j < cy.Count - 1; j++)
                {
                    if (cy[j + 1] - cy[j] <= 0.001) continue;
                    var mid = new Pt((cx[i] + cx[i + 1]) / 2, (cy[j] + cy[j + 1]) / 2);
                    if (!screens.Any(s => s.Contains(mid))) return false;
                }
            }
            return true;
        }

        int nx = xs.Count - 1, ny = ys.Count - 1;
        var inside = new bool[nx, ny];
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
            {
                var cell = new Rect(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]);
                inside[i, j] = Covered(cell.InsetBy(-d + 0.01, -d + 0.01));
            }
        bool IsIn(int i, int j) => i >= 0 && j >= 0 && i < nx && j < ny && inside[i, j];

        // Boundary edges between grid points, directed so the inside is on the left.
        var outEdges = new Dictionary<(int I, int J), List<(int I, int J)>>();
        void Add((int, int) from, (int, int) to)
        {
            if (!outEdges.TryGetValue(from, out var list)) outEdges[from] = list = new List<(int, int)>();
            list.Add(to);
        }
        for (int i = 0; i < nx; i++)
            for (int j = 0; j < ny; j++)
            {
                if (!inside[i, j]) continue;
                if (!IsIn(i, j - 1)) Add((i, j), (i + 1, j));
                if (!IsIn(i + 1, j)) Add((i + 1, j), (i + 1, j + 1));
                if (!IsIn(i, j + 1)) Add((i + 1, j + 1), (i, j + 1));
                if (!IsIn(i - 1, j)) Add((i, j + 1), (i, j));
            }

        while (outEdges.Count > 0)
        {
            var start = outEdges.Keys.OrderBy(p => p.J).ThenBy(p => p.I).First();
            var path = new List<(int I, int J)> { start };
            var here = start;
            do
            {
                if (!outEdges.TryGetValue(here, out var nexts) || nexts.Count == 0) break;
                var next = nexts[0];
                nexts.RemoveAt(0);
                if (nexts.Count == 0) outEdges.Remove(here);
                path.Add(next);
                here = next;
            } while (here != start);
            if (here != start || path.Count <= 4) continue;
            path.RemoveAt(path.Count - 1);
            // Keep only real corners.
            var n = path.Count;
            var corners = new List<int>();
            for (int k = 0; k < n; k++)
            {
                var a = path[(k + n - 1) % n];
                var b = path[k];
                var c = path[(k + 1) % n];
                if ((b.I - a.I) * (c.J - b.J) - (b.J - a.J) * (c.I - b.I) != 0) corners.Add(k);
            }
            if (corners.Count < 4) continue;
            loops.Add(new EdgeLoop(corners.Select(k => new Pt(xs[path[k].I], ys[path[k].J])).ToList()));
        }
        return loops;
    }

    public bool Equals(EdgeWorld? other) => other is not null && Loops.SequenceEqual(other.Loops);
    public override bool Equals(object? obj) => Equals(obj as EdgeWorld);
    public override int GetHashCode() => Loops.Aggregate(19, (h, l) => h * 31 + l.GetHashCode());
}
