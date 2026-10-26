using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The creature who brings the clipboard picker (SPEC §7.11.1), the Mac's <c>Colony+Clipboard.swift</c>.
/// On the shortcut it leaps from its edge to the paper's top-left corner and holds it while the picker is
/// open; the picker unfolds out of it once it lands. When the picker goes, it leaps back and walks on.</summary>
public sealed partial class Colony
{
    private enum ClipStage { Going, Holding, Returning }

    /// <summary>How the creature holding a sheet looks while the Translate sheet works (SPEC §7.14): still, thinking
    /// dots while the model answers, or a shrug with a "?" at trouble.</summary>
    public enum ClipHelperMood { Calm, Thinking, Puzzled }

    private sealed class ClipHelp
    {
        public int Index;
        public ClipStage Stage;
        public ClipHelper.Leap Leap = null!;
        public Pt Perch;
        /// <summary>Where it was on its edge before it came.</summary>
        public Pt Home;
        public ClipHelperMood Mood;
        public double MoodSince;
    }

    private ClipHelp? clipHelp;

    /// <summary>Someone is on the way to the picker, holding it, or going back.</summary>
    public bool IsClipHelping => clipHelp is not null;

    /// <summary>Where it holds the paper, while it is on its way there or holding it.</summary>
    public Pt? ClipHelperPerch => clipHelp is { Stage: ClipStage.Going or ClipStage.Holding } h ? h.Perch : null;

    /// <summary>Sends a creature to hold <paramref name="paper"/> (global points, y up). Seconds until it lands
    /// there, or null when nobody can come: all busy, hiding, or nobody at all.</summary>
    public double? ClipHelperCome(Rect paper, Pt centre) => ClipHelperCome(paper, centre, Settings.ClipHelper);

    /// <summary>The same, <paramref name="wanted"/> coming if free (empty: whoever is nearest the middle).</summary>
    public double? ClipHelperCome(Rect paper, Pt centre, string wanted)
    {
        if (clipHelp is { } old) ClipHelperLand(old.Index);
        if (hideout.IsActive) return null;
        var candidates = Enumerable.Range(0, creatures.Count).Select(i =>
        {
            var c = creatures[i];
            return new ClipHelper.Candidate(CharacterFor(i).Name, c.Position, c.LooksAsleep,
                !busy.Contains(i) && held?.Index != i && CurrentGrab?.Index != i && !IsMoving(i)
                && !c.IsPlaying && !c.IsChatting && !c.IsHeld && !bubbles.ContainsKey(i));
        }).ToList();
        if (ClipHelper.Choose(candidates, centre, wanted) is not int i || !creatures[i].TakeOff(waking: true)) return null;
        bedTrips.Remove(i);
        gardeners.Remove(i);
        busy.Add(i);
        var from = creatures[i].Position;
        var perch = ClipHelper.Perch(paper, atlas.BodyHalfSize * sizes[i]);
        var leap = new ClipHelper.Leap(from, perch, ClipHelper.Flight(from.DistanceTo(perch), Settings.ClipAnimationSpeed));
        clipHelp = new ClipHelp { Index = i, Stage = ClipStage.Going, Leap = leap, Perch = perch, Home = from };
        RaiseOverlays();
        Trace?.Invoke($"clip {CharacterFor(i).Name} leaps to ({perch.X:F0}, {perch.Y:F0}) in {leap.Duration:F2} s");
        return leap.Duration;
    }

    /// <summary>The picker is gone: back to its edge, now. The caller waits out the collapse first.</summary>
    public void ClipHelperGoHome()
    {
        if (clipHelp is not { Stage: not ClipStage.Returning } help || help.Index >= creatures.Count) return;
        var from = creatures[help.Index].Position;
        help.Leap = new ClipHelper.Leap(from, help.Home, ClipHelper.Flight(from.DistanceTo(help.Home), Settings.ClipAnimationSpeed));
        help.Stage = ClipStage.Returning;
        Trace?.Invoke($"clip {CharacterFor(help.Index).Name} leaps home");
    }

    /// <summary>Thinking dots while the model answers, a shrug at trouble, calm again: for the Translate sheet.</summary>
    public void ClipHelperMoodTo(ClipHelperMood mood)
    {
        if (clipHelp is not { } help || help.Mood == mood) return;
        help.Mood = mood;
        help.MoodSince = Elapsed;
        if (mood == ClipHelperMood.Calm) bubbles.Remove(help.Index);
        Trace?.Invoke($"clip {CharacterFor(help.Index).Name} is {mood.ToString().ToLowerInvariant()}");
    }

    /// <summary>The creatures' overlays over every other topmost window: the picker came up after them, and the
    /// creature holding it must be drawn over the paper.</summary>
    public void RaiseOverlays()
    {
        foreach (var overlay in overlays) overlay.Raise();
    }

    private void UpdateClipHelp(double dt)
    {
        if (clipHelp is not { } help) return;
        var i = help.Index;
        if (i >= creatures.Count || !creatures[i].IsPlaying) { clipHelp = null; busy.Remove(i); return; }
        switch (help.Stage)
        {
            case ClipStage.Going:
                help.Leap.Update(dt);
                creatures[i].Carry(help.Leap.Position, help.Leap.Rotation, help.Leap.Pose);
                if (!help.Leap.IsDone) break;
                help.Stage = ClipStage.Holding;
                Trace?.Invoke($"clip {CharacterFor(i).Name} holds the corner");
                if (Settings.ClipHelperTalks && Settings.TalkEnabled) Say(ClipHelper.Line(CharacterFor(i).Name, rng), i, builtIn: true);
                break;
            case ClipStage.Holding:
                var since = Elapsed - help.MoodSince;
                switch (help.Mood)
                {
                    case ClipHelperMood.Thinking:
                        creatures[i].Carry(help.Perch, 0, "idle");
                        // One, two, three dots, round and round: never said, never voiced.
                        var dots = new string('•', (int)(since * 3) % 3 + 1);
                        if (!bubbles.TryGetValue(i, out var shown) || shown.Text != dots)
                        {
                            bubbleSerial += 1;
                            bubbles[i] = new Bubble { Text = dots, Until = Elapsed + 1, Serial = bubbleSerial };
                        }
                        break;
                    case ClipHelperMood.Puzzled:
                        // A shrug: up a few points and down again, a "?" over it for two seconds.
                        var lift = since < 0.3 ? 6 * Math.Sin(Math.PI * since / 0.3) : 0;
                        creatures[i].Carry(new Pt(help.Perch.X, help.Perch.Y + lift), 0, since < 0.3 ? "jump" : "idle");
                        if (since < 2 && (!bubbles.TryGetValue(i, out var asked) || asked.Text != "?"))
                        {
                            bubbleSerial += 1;
                            bubbles[i] = new Bubble { Text = "?", Until = Elapsed + 2 - since, Serial = bubbleSerial };
                        }
                        break;
                    default:
                        creatures[i].Carry(help.Perch, 0, "idle");
                        break;
                }
                break;
            case ClipStage.Returning:
                help.Leap.Update(dt);
                creatures[i].Carry(help.Leap.Position, help.Leap.Rotation, help.Leap.Pose);
                if (!help.Leap.IsDone) break;
                ClipHelperLand(i);
                Trace?.Invoke($"clip {CharacterFor(i).Name} is back at ({creatures[i].Position.X:F0}, {creatures[i].Position.Y:F0})");
                break;
        }
    }

    /// <summary>Done helping, or cut short: onto the nearest edge, free again.</summary>
    private void ClipHelperLand(int i)
    {
        clipHelp = null;
        busy.Remove(i);
        if (i >= creatures.Count) return;
        bubbles.Remove(i);
        creatures[i].TouchDown();
    }
}
