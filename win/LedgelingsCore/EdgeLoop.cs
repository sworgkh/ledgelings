namespace Ledgelings.Core;

/// <summary>
/// A closed path made only of horizontal and vertical segments, walked with the
/// inside of the screens on the LEFT. Coordinates are global points, origin
/// bottom-left, y up.
///
/// A position on the loop is one number <c>t</c> in <c>[0, length)</c>. Each segment has a
/// <c>rotation</c>: how far a sprite drawn "standing on a floor, facing right" must be
/// turned (radians, counter-clockwise) to stand on that segment with its body
/// pointing inside. Walking rightwards along a floor is rotation 0.
/// </summary>
public sealed class EdgeLoop : IEquatable<EdgeLoop>
{
    public IReadOnlyList<Pt> Vertices { get; }
    private readonly double[] starts;      // loop position where each segment begins
    public double Length { get; }

    public EdgeLoop(IReadOnlyList<Pt> vertices)
    {
        if (vertices.Count < 4) throw new ArgumentException("a loop needs at least four corners");
        Vertices = vertices.ToArray();
        starts = new double[vertices.Count];
        double total = 0;
        for (int i = 0; i < vertices.Count; i++)
        {
            starts[i] = total;
            var a = vertices[i];
            var b = vertices[(i + 1) % vertices.Count];
            total += Math.Abs(b.X - a.X) + Math.Abs(b.Y - a.Y);
        }
        Length = total;
    }

    /// <summary>The loop just inside one rectangle, starting at its bottom-left corner.</summary>
    public EdgeLoop(Rect rect) : this(new[]
    {
        new Pt(rect.MinX, rect.MinY), new Pt(rect.MaxX, rect.MinY),
        new Pt(rect.MaxX, rect.MaxY), new Pt(rect.MinX, rect.MaxY),
    }) { }

    public int SegmentCount => Vertices.Count;

    /// <summary>The truncating remainder, made non-negative.</summary>
    public double Wrap(double t)
    {
        var m = t - Math.Truncate(t / Length) * Length;
        return m < 0 ? m + Length : m;
    }

    public int Segment(double t)
    {
        var w = Wrap(t);
        for (int i = starts.Length - 1; i >= 0; i--) if (starts[i] <= w) return i;
        return 0;
    }

    public double SegmentLength(int i) => (i + 1 < starts.Length ? starts[i + 1] : Length) - starts[i];

    /// <summary>Unit vector along segment <paramref name="i"/>, in walking (+t) direction.</summary>
    public Vec Direction(int i)
    {
        var a = Vertices[i];
        var b = Vertices[(i + 1) % Vertices.Count];
        var len = Math.Max(SegmentLength(i), double.Epsilon);
        return new Vec((b.X - a.X) / len, (b.Y - a.Y) / len);
    }

    /// <summary>Unit vector pointing from segment <paramref name="i"/> into the screen.</summary>
    public Vec Inward(int i)
    {
        var d = Direction(i);
        return new Vec(-d.Dy, d.Dx);
    }

    public double Rotation(int i)
    {
        var d = Direction(i);
        var angle = Math.Atan2(d.Dy, d.Dx);
        return angle < 0 ? angle + 2 * Math.PI : angle;
    }

    public Pt Point(double t)
    {
        var i = Segment(t);
        var d = Direction(i);
        var along = Wrap(t) - starts[i];
        return new Pt(Vertices[i].X + d.Dx * along, Vertices[i].Y + d.Dy * along);
    }

    public double T(int segment, double fraction) => starts[segment] + SegmentLength(segment) * Math.Min(Math.Max(fraction, 0), 1);

    /// <summary>The loop position closest to <paramref name="point"/>, and how far away it is.</summary>
    public (double T, double Distance) Nearest(Pt point)
    {
        (double T, double Distance) best = (0, double.PositiveInfinity);
        for (int i = 0; i < Vertices.Count; i++)
        {
            var a = Vertices[i];
            var d = Direction(i);
            var along = Math.Min(Math.Max((point.X - a.X) * d.Dx + (point.Y - a.Y) * d.Dy, 0), SegmentLength(i));
            var dx = a.X + d.Dx * along - point.X;
            var dy = a.Y + d.Dy * along - point.Y;
            var distance = Math.Sqrt(dx * dx + dy * dy);
            if (distance < best.Distance) best = (starts[i] + along, distance);
        }
        return best;
    }

    public bool Equals(EdgeLoop? other) => other is not null && Vertices.SequenceEqual(other.Vertices);
    public override bool Equals(object? obj) => Equals(obj as EdgeLoop);
    public override int GetHashCode() => Vertices.Aggregate(17, (h, v) => h * 31 + v.GetHashCode());
    public override string ToString() => "[" + string.Join(", ", Vertices) + "]";
}
