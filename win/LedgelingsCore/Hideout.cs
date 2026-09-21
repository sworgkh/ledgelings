namespace Ledgelings.Core;

/// <summary>
/// The little house the creatures hide in when asked to go away for a while.
///
/// away → appearing → gathering → shrinking → hidden → growing → releasing → vanishing → away
///
/// The colony drives it: it calls <see cref="Entered"/> as each creature reaches the door,
/// acts on the events <see cref="Update"/> returns, and draws the house at <see cref="Scale"/>.
/// </summary>
public sealed class Hideout
{
    public enum Phase { Away, Appearing, Gathering, Shrinking, Hidden, Growing, Releasing, Vanishing }

    public abstract record Event
    {
        /// <summary>The gathering took too long: put these creatures inside right now.</summary>
        public sealed record ForceInside(IReadOnlyList<int> Creatures) : Event
        {
            public bool Equals(ForceInside? other) => other is not null && Creatures.SequenceEqual(other.Creatures);
            public override int GetHashCode() => Creatures.Count;
        }
        /// <summary>This creature walks out of the door.</summary>
        public sealed record LetOut(int Creature) : Event;
    }

    public double AppearTime { get; set; } = 0.4;
    public double ShrinkTime { get; set; } = 0.5;
    /// <summary>Longest the house waits at the door before pulling the stragglers in.</summary>
    public double GatherCap { get; set; } = 25;
    public double ReleaseEvery { get; set; } = 0.6;

    public Phase CurrentPhase { get; private set; } = Phase.Away;
    public int Count { get; private set; }
    private readonly SortedSet<int> inside = new();
    public IReadOnlySet<int> Inside => inside;
    private double phaseStarted;
    private double until;
    private double lastRelease;

    public bool IsActive => CurrentPhase != Phase.Away;
    public bool IsInside(int creature) => inside.Contains(creature);
    public double Remaining(double time) => Math.Max(0, until - time);

    /// <summary>Start hiding <paramref name="count"/> creatures for <paramref name="seconds"/>. Ignored while already busy.</summary>
    public void Hide(int count, double time, double seconds)
    {
        if (IsActive) return;
        Count = count;
        inside.Clear();
        until = time + seconds;
        Enter(Phase.Appearing, time);
    }

    /// <summary>One creature reached the door.</summary>
    public void Entered(int creature, double time)
    {
        if (CurrentPhase != Phase.Gathering) return;
        inside.Add(creature);
        if (inside.Count >= Count) Enter(Phase.Shrinking, time);
    }

    /// <summary>"Bring them back now": open up wherever we are.</summary>
    public void Recall(double time)
    {
        until = time;
        switch (CurrentPhase)
        {
            case Phase.Hidden: Enter(Phase.Growing, time); break;
            case Phase.Shrinking: Enter(Phase.Growing, time - AppearTime * (1 - Scale(time))); break;
            case Phase.Appearing:
            case Phase.Gathering: Enter(Phase.Releasing, time); break;
        }
    }

    /// <summary>0 = not there, 1 = full size.</summary>
    public double Scale(double time)
    {
        var sincePhase = time - phaseStarted;
        return CurrentPhase switch
        {
            Phase.Away or Phase.Hidden => 0,
            Phase.Appearing or Phase.Growing => Math.Min(1, Math.Max(0, sincePhase / AppearTime)),
            Phase.Gathering or Phase.Releasing => 1,
            _ => Math.Min(1, Math.Max(0, 1 - sincePhase / ShrinkTime)),
        };
    }

    public List<Event> Update(double time)
    {
        var events = new List<Event>();
        var sincePhase = time - phaseStarted;
        switch (CurrentPhase)
        {
            case Phase.Away:
                break;
            case Phase.Appearing:
                if (sincePhase >= AppearTime) Enter(Phase.Gathering, phaseStarted + AppearTime);
                break;
            case Phase.Gathering:
                if (inside.Count >= Count) { Enter(Phase.Shrinking, time); break; }
                if (sincePhase < GatherCap) break;
                events.Add(new Event.ForceInside(Enumerable.Range(0, Count).Where(i => !inside.Contains(i)).ToList()));
                break;
            case Phase.Shrinking:
                if (sincePhase >= ShrinkTime) Enter(Phase.Hidden, time);
                break;
            case Phase.Hidden:
                if (time >= until) Enter(Phase.Growing, time);
                break;
            case Phase.Growing:
                if (sincePhase >= AppearTime) Enter(Phase.Releasing, time);
                break;
            case Phase.Releasing:
                if (inside.Count == 0) { Enter(Phase.Vanishing, time); break; }
                if (time - lastRelease < ReleaseEvery) break;
                var next = inside.Min;
                inside.Remove(next);
                lastRelease = time;
                events.Add(new Event.LetOut(next));
                break;
            case Phase.Vanishing:
                if (sincePhase >= ShrinkTime) Enter(Phase.Away, time);
                break;
        }
        return events;
    }

    private void Enter(Phase next, double time)
    {
        CurrentPhase = next;
        phaseStarted = time;
        if (next == Phase.Releasing) lastRelease = time - ReleaseEvery;     // the first one steps out at once
    }
}
