using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>What happens when two creatures walk into each other: the stop, the stars,
/// the flower every third time, and letting them go again.</summary>
public sealed partial class Colony
{
    /// <summary>Two creatures stopped face to face. Several pairs can be talking at once.</summary>
    private sealed class Conversation
    {
        public int A, B;
        public double? ReleaseAt;
        public bool Involves(int i) => i == A || i == B;
    }

    private List<Meetings.Party> Parties()
    {
        var parties = new List<Meetings.Party>(creatures.Count);
        for (int i = 0; i < creatures.Count; i++)
        {
            var c = creatures[i];
            parties.Add(new Meetings.Party(c.Spot.Loop, c.Segment, c.Position, atlas.BodyHalfSize * sizes[i],
                !hideout.IsActive && !busy.Contains(i) && !c.IsJumping && !c.LooksAsleep && !c.IsHeld && !c.IsChatting));
        }
        return parties;
    }

    /// <summary>Two creatures walked into each other. They chat about it, and every
    /// third time one of them brings a flower.</summary>
    private void Bumped(Meetings.Bump bump)
    {
        var (giver, receiver) = rng.Coin() ? (bump.A, bump.B) : (bump.B, bump.A);
        Hold(bump.A, bump.B);
        var pa = creatures[bump.A].Position;
        var pb = creatures[bump.B].Position;
        sparkPalette = new List<Color>
        {
            Color.White, Color.FromArgb(255, 209, 61), Settings.ColorFor(bump.A).ToColor(), Settings.ColorFor(bump.B).ToColor(),
        };
        sparks.Burst(new Pt((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2), creatures[bump.A].Loop.Inward(creatures[bump.A].Segment), 8, rng);
        var eventText = "They just walked into each other.";
        string? given = null;
        if (bump.Gift)
        {
            var flower = rng.Pick(Gifts.Flowers);
            if (gifts.Give(flower, giver, receiver, Elapsed))
            {
                var a = CharacterFor(giver).Name;
                var b = CharacterFor(receiver).Name;
                eventText = $"{a} just walked into {b} and gave {b} a {flower}.";
                given = flower;
            }
        }
        if (!Settings.TalkEnabled || !Talk(giver, receiver, eventText, given)) EndChat(giver, receiver, 2);
    }

    /// <summary>Whoever wears a flower trails the one who gave it, stopping about a body apart.
    /// Not while either is talking, and not while they are going home.</summary>
    private void FollowGivers()
    {
        if (hideout.IsActive) return;
        foreach (var (wearer, hat) in gifts.WornFlowers)
        {
            var giver = hat.From;
            if (giver == wearer || wearer >= creatures.Count || giver < 0 || giver >= creatures.Count) continue;
            if (busy.Contains(wearer) || busy.Contains(giver)) continue;
            var gap = (sizes[wearer] + sizes[giver]) / 2 + 16;
            creatures[wearer].Follow(creatures[giver], gap);
        }
    }

    private List<SparkSnapshot> SparkSnapshots()
    {
        var size = 2 * (sizes.Count == 0 ? 2 : sizes.Max());
        return sparks.Alive.Select(spark => new SparkSnapshot(spark.Position, size,
            sparkPalette.Count == 0 ? Color.White : sparkPalette[spark.Tint % sparkPalette.Count], (float)spark.Opacity)).ToList();
    }

    /// <summary>Both stop and turn to face each other, like two people who meet in the street.</summary>
    private void Hold(int i, int j)
    {
        if (i < 0 || j < 0 || i >= creatures.Count || j >= creatures.Count || i == j) return;
        creatures[i].Meet(Facing(i, j));
        creatures[j].Meet(Facing(j, i));
        chats.RemoveAll(c => c.Involves(i) || c.Involves(j));
        chats.Add(new Conversation { A = i, B = j, ReleaseAt = null });
    }

    /// <summary>+1 when <paramref name="j"/> is further round the loop from <paramref name="i"/>, -1 when behind; on another
    /// loop there is nothing to face, so keep the current heading.</summary>
    private double Facing(int i, int j)
    {
        var a = creatures[i];
        var b = creatures[j];
        if (a.Spot.Loop != b.Spot.Loop) return a.Direction;
        return a.Loop.Wrap(b.T - a.T) < a.Loop.Length / 2 ? 1 : -1;
    }

    /// <summary>This pair's conversation is done, or never started: let them go in a moment.</summary>
    private void EndChat(int i, int j, double seconds)
    {
        foreach (var chat in chats.Where(c => c.Involves(i) && c.Involves(j)))
            chat.ReleaseAt = Math.Min(chat.ReleaseAt ?? double.PositiveInfinity, Elapsed + seconds);
    }

    /// <summary>Everyone walks on, now.</summary>
    private void ReleaseChat()
    {
        foreach (var chat in chats) Release(chat);
        chats.Clear();
    }

    private void Release(Conversation chat)
    {
        foreach (var i in new[] { chat.A, chat.B }) if (i < creatures.Count) creatures[i].WalkOn(rng);
    }

    /// <summary>Where a flower sits or lands: on the head, away from the edge.</summary>
    private Pt Head(int i)
    {
        var c = creatures[i];
        var up = c.IsHeld ? new Vec(0, 1) : c.Loop.Inward(c.Segment);
        var lift = (atlas.BodyHalfSize + flowerCell.Height / 2.0) * sizes[i];
        return new Pt(c.Position.X + up.Dx * lift, c.Position.Y + up.Dy * lift);
    }

    /// <summary>Let a pair go once its reply is out, or as soon as one of them is no longer standing there.</summary>
    private void ReleaseChatIfOver()
    {
        var over = chats.Where(chat =>
        {
            var stillThere = new[] { chat.A, chat.B }.All(i => i < creatures.Count && creatures[i].IsChatting);
            return !stillThere || (chat.ReleaseAt is double at && at <= Elapsed);
        }).ToList();
        if (over.Count == 0) return;
        foreach (var chat in over) Release(chat);
        chats.RemoveAll(over.Contains);
    }

    private FlowerFlight? FlightSnapshot()
    {
        if (gifts.CurrentFlight is not Gifts.Flight flight || gifts.FlightProgress(Elapsed) is not double p) return null;
        if (flight.From >= creatures.Count || flight.To >= creatures.Count) return null;
        var from = Head(flight.From);
        var to = Head(flight.To);
        var arc = Math.Sin(p * Math.PI) * 24;
        var up = creatures[flight.To].Loop.Inward(creatures[flight.To].Segment);
        return new FlowerFlight(flowerFrames.Frame(flight.Flower, 0),
            new Pt(from.X + (to.X - from.X) * p + up.Dx * arc, from.Y + (to.Y - from.Y) * p + up.Dy * arc),
            creatures[flight.To].Rotation, sizes[flight.To]);
    }
}
