using System.Drawing;
using System.Drawing.Imaging;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The creature who holds the microphone (SPEC §7.13), the Mac's <c>Colony+Dictation.swift</c>. When
/// dictation starts it leaps from its edge to the middle of the screen and stands there holding a pixel microphone
/// whose bars follow the voice, the clock in its bubble. Stopped, it thinks (three dots) while the model writes the
/// words down, then says "Copied: …the first words…" and hops back. Trouble it says in plain words, and goes home.</summary>
public sealed partial class Colony
{
    private enum DictationStage { Going, Listening, Thinking, Telling, Returning }

    private sealed class DictationHelp
    {
        public int Index;
        public DictationStage Stage;
        public ClipHelper.Leap Leap = null!;
        public Pt Perch, Home;
        public double Level, Seconds, ThinkingSince, TellUntil;
        /// <summary>A line to say once it has landed, when it was given one on the way.</summary>
        public (string Text, bool Voiced)? Waiting;
    }

    private DictationHelp? dictationHelp;
    private readonly Dictionary<string, Bitmap> microphones = new();

    /// <summary>Who is holding the microphone, if anyone.</summary>
    public int? DictationHelper => dictationHelp?.Index;
    public bool IsDictationHelping => dictationHelp is not null;

    /// <summary>Sends a creature to the middle of the screen under the pointer. False when nobody can come.</summary>
    public bool DictationCome(Pt? spot = null)
    {
        if (dictationHelp is { } help)
        {
            if (help.Stage == DictationStage.Returning) DictationLand(help.Index);
            else
            {
                if (help.Stage != DictationStage.Going) help.Stage = DictationStage.Listening;
                help.Waiting = null;
                bubbles.Remove(help.Index);
                return true;
            }
        }
        if (hideout.IsActive) return false;
        var free = Enumerable.Range(0, creatures.Count).Where(i =>
        {
            var c = creatures[i];
            return !busy.Contains(i) && held?.Index != i && CurrentGrab?.Index != i && !IsMoving(i) && !c.IsPlaying && !c.IsChatting
                && !c.IsHeld && !bubbles.ContainsKey(i) && clipHelp?.Index != i;
        }).ToList();
        var wanted = Settings.DictationHelper;
        int? chosen = free.Cast<int?>().FirstOrDefault(i => wanted.Length > 0 && CharacterFor(i!.Value).Name == wanted)
                      ?? (free.Count > 0 ? free[rng.Next(free.Count)] : null);
        if (chosen is not int k || !creatures[k].TakeOff(waking: true)) return false;
        bedTrips.Remove(k);
        gardeners.Remove(k);
        busy.Add(k);
        var from = creatures[k].Position;
        var middle = spot ?? MiddleOfScreen(PointerLocation());
        var leap = new ClipHelper.Leap(from, middle, ClipHelper.Flight(from.DistanceTo(middle), 1));
        dictationHelp = new DictationHelp { Index = k, Stage = DictationStage.Going, Leap = leap, Perch = middle, Home = from };
        RaiseOverlays();
        Trace?.Invoke($"dictate {CharacterFor(k).Name} leaps to ({middle.X:F0}, {middle.Y:F0}) in {leap.Duration:F2} s");
        return true;
    }

    /// <summary>The middle of the monitor the pointer is on, a little below its centre so the bubble has room.</summary>
    private static Pt MiddleOfScreen(Pt point)
    {
        var monitors = Desktop.Monitors();
        var screen = monitors.FirstOrDefault(m => m.Frame.Contains(point)) ?? Desktop.Primary(monitors);
        if (screen is null) return point;
        var f = screen.Frame;
        return new Pt(f.X + f.Width / 2, f.Y + f.Height / 2 - 40);
    }

    /// <summary>What the microphone hears now: the meter and the clock.</summary>
    public void DictationHear(double level, double seconds, double dt)
    {
        if (dictationHelp is not { } help) return;
        help.Level = Dictation.Meter(help.Level, level, dt);
        help.Seconds = seconds;
    }

    /// <summary>Stopped: it thinks while the model writes.</summary>
    public void DictationThink()
    {
        if (dictationHelp is not { } help) return;
        help.Level = 0;
        if (help.Stage == DictationStage.Going) return;
        help.Stage = DictationStage.Thinking;
        help.ThinkingSince = Elapsed;
        Trace?.Invoke($"dictate {CharacterFor(help.Index).Name} thinks");
    }

    /// <summary>It says <paramref name="text"/> and then goes home; <paramref name="voiced"/>: out loud too, with voice on.</summary>
    public void DictationTell(string text, bool voiced)
    {
        if (dictationHelp is not { } help) return;
        if (help.Stage == DictationStage.Going) { help.Waiting = (text, voiced); return; }
        var i = help.Index;
        // Long enough to read, short enough not to keep it standing there.
        var shown = Math.Min(Banter.ShowTime(text, Settings.BubbleSeconds), voiced ? 7 : 3.5);
        if (voiced) Say(text, i, builtIn: true);
        else
        {
            bubbleSerial += 1;
            bubbles[i] = new Bubble { Text = text, Until = Elapsed + shown, Serial = bubbleSerial };
        }
        help.Stage = DictationStage.Telling;
        help.TellUntil = Elapsed + shown;
        Trace?.Invoke($"dictate {CharacterFor(i).Name} says: {text}");
    }

    /// <summary>Let go with nothing said (Esc): straight home.</summary>
    public void DictationGoHome()
    {
        if (dictationHelp is not { } help) return;
        bubbles.Remove(help.Index);
        DictationReturn(help);
    }

    private void DictationReturn(DictationHelp help)
    {
        var from = creatures[help.Index].Position;
        help.Leap = new ClipHelper.Leap(from, help.Home, ClipHelper.Flight(from.DistanceTo(help.Home), 1));
        help.Stage = DictationStage.Returning;
        help.Waiting = null;
        Trace?.Invoke($"dictate {CharacterFor(help.Index).Name} hops home");
    }

    private void UpdateDictationHelp(double dt)
    {
        if (dictationHelp is not { } help) return;
        var i = help.Index;
        if (i >= creatures.Count || !creatures[i].IsPlaying) { dictationHelp = null; busy.Remove(i); return; }
        void Show(string text, double hold)
        {
            if (bubbles.TryGetValue(i, out var b) && b.Text == text) { b.Until = Elapsed + hold; return; }
            bubbleSerial += 1;
            bubbles[i] = new Bubble { Text = text, Until = Elapsed + hold, Serial = bubbleSerial };
        }
        switch (help.Stage)
        {
            case DictationStage.Going:
                help.Leap.Update(dt);
                creatures[i].Carry(help.Leap.Position, help.Leap.Rotation, help.Leap.Pose);
                if (!help.Leap.IsDone) break;
                help.Stage = DictationStage.Listening;
                Trace?.Invoke($"dictate {CharacterFor(i).Name} holds the microphone");
                if (help.Waiting is { } waiting) { help.Waiting = null; DictationTell(waiting.Text, waiting.Voiced); }
                break;
            case DictationStage.Listening:
                creatures[i].Carry(help.Perch, 0, "idle");
                // The clock, in a bubble that is never said out loud.
                Show("● " + Dictation.Clock(help.Seconds), 2);
                break;
            case DictationStage.Thinking:
                creatures[i].Carry(help.Perch, 0, "idle");
                Show(Dictation.ThinkingBubble, 120);
                break;
            case DictationStage.Telling:
                creatures[i].Carry(help.Perch, 0, "idle");
                var serial = bubbles.TryGetValue(i, out var said) ? said.Serial : -1;
                if (Elapsed >= help.TellUntil && !voicedLines.Contains(serial))
                {
                    bubbles.Remove(i);
                    DictationReturn(help);
                }
                break;
            case DictationStage.Returning:
                help.Leap.Update(dt);
                creatures[i].Carry(help.Leap.Position, help.Leap.Rotation, help.Leap.Pose);
                if (!help.Leap.IsDone) break;
                DictationLand(i);
                Trace?.Invoke($"dictate {CharacterFor(i).Name} is back at ({creatures[i].Position.X:F0}, {creatures[i].Position.Y:F0})");
                break;
        }
    }

    /// <summary>Done, or cut short: onto the nearest edge, free again.</summary>
    private void DictationLand(int i)
    {
        dictationHelp = null;
        busy.Remove(i);
        if (i >= creatures.Count) return;
        bubbles.Remove(i);
        creatures[i].TouchDown();
    }

    /// <summary>The microphone creature <paramref name="i"/> holds out, its bars or its thinking dots, while it helps.
    /// Facing left, the picture turns round: the microphone by the body, the bars outside.</summary>
    private Bitmap? DictationMicrophone(int i)
    {
        if (dictationHelp is not { } help || help.Index != i) return null;
        var grid = help.Stage switch
        {
            DictationStage.Thinking => Dictation.Microphone(0, thinking: true, tick: (int)((Elapsed - help.ThinkingSince) * 4)),
            DictationStage.Listening => Dictation.Microphone(Dictation.Bars(help.Level)),
            _ => Dictation.Microphone(0),
        };
        var mirrored = creatures[i].IsMirrored;
        var key = (mirrored ? "<" : ">") + string.Concat(grid.Cast<Dictation.Ink>().Select(ink => (char)('0' + (int)ink)));
        if (microphones.TryGetValue(key, out var made)) return made;
        made = Picture(grid, mirrored);
        microphones[key] = made;
        return made;
    }

    /// <summary>The colours of the microphone: a dark grey body, the game's ink for the outline and grille, green
    /// bars that light and faint ones that wait. The Mac's, in ARGB.</summary>
    internal static readonly Dictionary<Dictation.Ink, Color> MicrophoneInks = new()
    {
        [Dictation.Ink.Outline] = Color.FromArgb(255, 40, 34, 58),
        [Dictation.Ink.Body] = Color.FromArgb(255, 132, 138, 152),
        [Dictation.Ink.Light] = Color.FromArgb(255, 186, 191, 202),
        [Dictation.Ink.Shade] = Color.FromArgb(255, 88, 92, 106),
        [Dictation.Ink.Grille] = Color.FromArgb(255, 40, 34, 58),
        [Dictation.Ink.Lit] = Color.FromArgb(255, 92, 206, 96),
        [Dictation.Ink.Unlit] = Color.FromArgb(140, 150, 146, 170),
    };

    /// <summary>A grid of inks as a picture, one pixel each: the overlay scales it up crisp.</summary>
    internal static Bitmap Picture(Dictation.Ink[,] grid, bool mirrored = false)
    {
        int h = grid.GetLength(0), w = grid.GetLength(1);
        var bitmap = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        for (int r = 0; r < h; r++)
            for (int c = 0; c < w; c++)
                if (MicrophoneInks.TryGetValue(grid[r, c], out var colour)) bitmap.SetPixel(mirrored ? w - 1 - c : c, r, colour);
        return bitmap;
    }
}
