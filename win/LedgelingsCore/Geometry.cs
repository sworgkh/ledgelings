namespace Ledgelings.Core;

/// <summary>A point in global desktop points: origin bottom-left, y up (the macOS
/// convention the whole simulation is written in; the window flips it once).</summary>
public readonly record struct Pt(double X, double Y)
{
    public static readonly Pt Zero = new(0, 0);
    public static Pt operator +(Pt p, Vec v) => new(p.X + v.Dx, p.Y + v.Dy);
    public static Pt operator -(Pt p, Vec v) => new(p.X - v.Dx, p.Y - v.Dy);
    public static Vec operator -(Pt a, Pt b) => new(a.X - b.X, a.Y - b.Y);
    public double DistanceTo(Pt other) => Math.Sqrt((X - other.X) * (X - other.X) + (Y - other.Y) * (Y - other.Y));
    public override string ToString() => $"({X}, {Y})";
}

public readonly record struct Vec(double Dx, double Dy)
{
    public static readonly Vec Zero = new(0, 0);
    public static Vec operator *(Vec v, double k) => new(v.Dx * k, v.Dy * k);
    public static Vec operator +(Vec a, Vec b) => new(a.Dx + b.Dx, a.Dy + b.Dy);
    public static Vec operator -(Vec v) => new(-v.Dx, -v.Dy);
    public double Length => Math.Sqrt(Dx * Dx + Dy * Dy);
    public override string ToString() => $"<{Dx}, {Dy}>";
}

/// <summary>An axis-aligned rectangle, y up.</summary>
public readonly record struct Rect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;
    public Pt Origin => new(X, Y);

    public bool Contains(Pt p) => p.X >= MinX && p.X < MaxX && p.Y >= MinY && p.Y < MaxY;

    /// <summary>Grow (negative) or shrink (positive) on every side, like CGRect.insetBy.</summary>
    public Rect InsetBy(double dx, double dy) => new(X + dx, Y + dy, Width - 2 * dx, Height - 2 * dy);

    public Rect OffsetBy(double dx, double dy) => new(X + dx, Y + dy, Width, Height);
}
