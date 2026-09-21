using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The creatures' words: who speaks to whom, the prompt for the moment, the bubbles.</summary>
public sealed partial class Colony
{
    private static readonly (double Angle, string Name)[] edgeNames =
    {
        (0, "the bottom edge"), (Math.PI / 2, "the right edge"), (Math.PI, "the ceiling"), (3 * Math.PI / 2, "the left edge"),
    };

    private static string EdgeName(Creature c) =>
        edgeNames.MinBy(e => Math.Abs(Creature.ShortestArc(c.Rotation, e.Angle))).Name;

    /// <summary>Who creature <paramref name="i"/> is: the k-th creature wearing its species takes the k-th
    /// character of that species' cast, wrapping round.</summary>
    public Character CharacterFor(int i)
    {
        var species = Settings.SpeciesFor(i);
        var cast = Settings.CastOf(species, Library.Cast(species));
        if (cast.Count == 0) return new Character($"Ledgeling {i + 1}", "");
        var k = Enumerable.Range(0, i).Count(j => Settings.SpeciesFor(j) == species);
        return cast[k % cast.Count];
    }

    private string KindOf(int i) => Library.Kind(Settings.SpeciesFor(i));

    private string Describe(int i)
    {
        var c = creatures[i];
        var name = CharacterFor(i).Name;
        if (c.IsHeld) return name + " is dangling from the user's cursor";
        if (c.IsJumping) return name + " is mid-jump";
        return $"{name} is {(c.IsSleeping ? "asleep on" : "on")} {EdgeName(c)}";
    }

    /// <summary>"Make Someone Talk" from the menu, or a Shift-poke on <paramref name="chosen"/>: the speaker
    /// says something to the nearest creature that is not already talking.</summary>
    public void TalkNow(int? chosen = null)
    {
        if (creatures.Count < 2) { TalkStatus = "needs at least two creatures"; return; }
        if (hideout.IsActive) return;
        var free = Enumerable.Range(0, creatures.Count).Where(i => !busy.Contains(i)).ToList();
        var awake = free.Where(i => !creatures[i].IsSleeping && !creatures[i].IsJumping).ToList();
        var pool = awake.Count == 0 ? free : awake;
        int? speaker = chosen ?? (pool.Count == 0 ? null : rng.Pick(pool));
        if (speaker is not int s || s >= creatures.Count || busy.Contains(s)) { TalkStatus = "everyone is mid-conversation"; return; }
        var me = creatures[s].Position;
        var listeners = free.Where(i => i != s).ToList();
        if (listeners.Count == 0) { TalkStatus = "nobody free to listen"; return; }
        var listener = listeners.MinBy(i => creatures[i].Position.DistanceTo(me));
        Hold(s, listener);
        if (!Talk(s, listener)) EndChat(s, listener, 1);
    }

    /// <summary>One creature says a line to another; the other answers. Runs in the background;
    /// other pairs can talk at the same time. Returns false when it could not even
    /// start, so the caller can release the pair.</summary>
    private bool Talk(int speaker, int listener, string? because = null)
    {
        if (speaker >= creatures.Count || listener >= creatures.Count || speaker == listener || busy.Contains(speaker) || busy.Contains(listener)) return false;
        var service = Settings.ChatClient();
        if (service is null) { TalkStatus = Settings.BrainProblem; return false; }
        var a = CharacterFor(speaker);
        var b = CharacterFor(listener);
        var situation = $"It is {(IsNight ? "night" : "day")}. {Describe(speaker)}. {Describe(listener)}.";
        if (because is not null) situation += " " + because;
        busy.Add(speaker); busy.Add(listener);
        TalkStatus = $"asking {service.Model} via {service.ProviderTitle}\u2026";
        _ = Converse(service, speaker, listener, a, b, KindOf(speaker), KindOf(listener), situation);
        return true;
    }

    private void Say(string text, int index)
    {
        if (index >= creatures.Count) return;
        bubbles[index] = (text, Elapsed + Banter.ShowTime(text, Settings.BubbleSeconds));
        Render();
    }

    /// <summary>The creature whose speech bubble is under <paramref name="point"/>, on any monitor.</summary>
    private int? BubbleAt(Pt point)
    {
        foreach (var overlay in overlays) if (overlay.BubbleIndex(point) is int i) return i;
        return null;
    }
}
