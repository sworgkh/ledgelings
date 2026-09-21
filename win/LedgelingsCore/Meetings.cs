namespace Ledgelings.Core;

/// <summary>
/// Notices when two creatures walk into each other on the same edge.
///
/// A "bump" fires once when a pair comes together, not every frame they stay
/// together, and the same pair cannot bump again until <c>Cooldown</c> seconds have
/// passed. Every <c>GiftEvery</c>-th bump of a pair is a gift.
/// </summary>
public sealed class Meetings
{
    /// <summary>One creature, as far as meeting is concerned.</summary>
    public readonly record struct Party(int Loop, int Segment, Pt Position, double HalfSize, bool CanTalk);

    /// <summary>Two creatures just came together. <c>A &lt; B</c>. <c>Count</c> is how many times
    /// this pair has bumped since its last gift, this one included.</summary>
    public readonly record struct Bump(int A, int B, int Count, bool Gift);

    /// <summary>How close the two bodies must be, beyond touching, to count.</summary>
    public double Gap { get; set; }
    public double Cooldown { get; set; }
    public int GiftEvery { get; set; }

    private HashSet<(int, int)> touching = new();
    private readonly Dictionary<(int, int), double> lastBump = new();
    private readonly Dictionary<(int, int), int> counts = new();

    public Meetings(double gap = 12, double cooldown = 60, int giftEvery = 3)
    {
        Gap = gap; Cooldown = cooldown; GiftEvery = giftEvery;
    }

    /// <summary>Feed it everyone, every frame. Returns the pairs that came together this frame.</summary>
    public List<Bump> Update(IReadOnlyList<Party> parties, double time)
    {
        var bumps = new List<Bump>();
        var nowTouching = new HashSet<(int, int)>();
        for (int a = 0; a < parties.Count; a++)
        {
            for (int b = a + 1; b < parties.Count; b++)
            {
                var p = parties[a];
                var q = parties[b];
                if (!p.CanTalk || !q.CanTalk || p.Loop != q.Loop || p.Segment != q.Segment) continue;
                var distance = q.Position.DistanceTo(p.Position);
                if (distance > p.HalfSize + q.HalfSize + Gap) continue;
                var pair = (a, b);
                nowTouching.Add(pair);
                if (touching.Contains(pair)) continue;
                if (lastBump.TryGetValue(pair, out var last) && time - last < Cooldown) continue;
                lastBump[pair] = time;
                var count = (counts.TryGetValue(pair, out var n) ? n : 0) + 1;
                var gift = GiftEvery > 0 && count >= GiftEvery;
                counts[pair] = gift ? 0 : count;
                bumps.Add(new Bump(a, b, count, gift));
            }
        }
        touching = nowTouching;
        return bumps;
    }
}
