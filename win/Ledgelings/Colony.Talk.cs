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

    /// <summary>One line per talking creature: what it says, when it stops showing, and which
    /// <see cref="Say"/> put it up, so a late word from the voice about an older line is ignored.
    /// Partial: the voice adds how much of it is on show while it is being said out loud.</summary>
    private sealed partial class Bubble
    {
        public string Text { get; set; } = "";
        public double Until { get; set; }
        public int Serial { get; set; }
    }

    private int bubbleSerial;
    /// <summary>Lines being said out loud, by serial, and what waits for each to end.</summary>
    private readonly HashSet<int> voicedLines = new();
    private readonly Dictionary<int, List<Action>> afterLine = new();
    /// <summary>Conversations being said out loud right now. There is one voice to go
    /// round, so out loud there is one conversation at a time.</summary>
    private int voicedDialogues;

    /// <summary>The user's wall clock, for what the creatures know of the day (<see cref="Almanac"/>); tests set it.</summary>
    public Func<DateTimeOffset> Now { get; set; } = () => DateTimeOffset.Now;
    /// <summary>Every line and voice cue, as it happens (the Mac's <c>--converse</c> trace); null when nobody listens.</summary>
    public Action<string>? Trace { get; set; }

    /// <summary>Who creature <paramref name="i"/> is (<see cref="AppSettings.CharacterFor"/>).</summary>
    public Character CharacterFor(int i) => Settings.CharacterFor(i, Library);

    private string KindOf(int i) => Library.Kind(Settings.SpeciesFor(i));

    /// <summary>The user's time, date and holidays, as far as the Calendar tab lets them know; "" when nothing is on.
    /// (The Mac's <c>almanac</c>.)</summary>
    public string AlmanacSentence => Almanac.Sentence(Now(), Settings.Awareness);

    /// <summary>Today's holiday for a built-in <c>[holiday]</c> block, one conversation in three,
    /// so a holiday colours the day without being all anyone talks about.</summary>
    public string? HolidayForLines()
    {
        if (Almanac.Today(Now(), Settings.Awareness.Faiths) is not string name || rng.Next(3) != 0) return null;
        return name;
    }

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

    /// <summary>One creature says a line to another; the other answers. With a model this runs in the background;
    /// other pairs can talk at the same time. Returns false when it could not even
    /// start, so the caller can release the pair. <paramref name="flower"/>: the one just given, for a line about it.</summary>
    private bool Talk(int speaker, int listener, string? because = null, string? flower = null)
    {
        if (speaker >= creatures.Count || listener >= creatures.Count || speaker == listener || busy.Contains(speaker) || busy.Contains(listener)) return false;
        if (VoiceIsTakenNow) { TalkStatus = "someone else is talking; out loud it is one conversation at a time"; return false; }
        // The colony's own day and night say who is asleep; the user's clock is the almanac's.
        var situation = $"On the edge it is {(IsNight ? "night" : "day")}. {Describe(speaker)}. {Describe(listener)}.";
        var almanac = AlmanacSentence;
        if (almanac.Length > 0) situation = almanac + " " + situation;
        if (because is not null) situation += " " + because;
        if (Settings.Brain == BrainKind.Script) return Recite(speaker, listener, flower, situation);
        var service = Settings.ChatClient();
        if (service is null) { TalkStatus = Settings.BrainProblem; return false; }
        busy.Add(speaker); busy.Add(listener);
        TalkStatus = $"asking {service.Model} via {service.ProviderTitle}…";
        _ = Converse(service, speaker, listener, situation, flower);
        return true;
    }

    /// <summary>Put <paramref name="text"/> up in creature <paramref name="index"/>'s bubble. With voice on, the bubble
    /// waits for the sound and is then said (<see cref="VoiceSay"/>). Returns the line's serial, for
    /// <see cref="WhenSaid"/>. <paramref name="builtIn"/>: written in advance, so its sound can be kept and played again.</summary>
    private int Say(string text, int index, bool builtIn = false)
    {
        if (index < 0 || index >= creatures.Count) return 0;
        bubbleSerial += 1;
        var serial = bubbleSerial;
        bubbles[index] = new Bubble { Text = text, Until = Elapsed + Banter.ShowTime(text, Settings.BubbleSeconds), Serial = serial };
        var voiced = false;
        if (IsVoiced) VoiceSay(serial, index, text, builtIn, ref voiced);
        if (voiced && bubbles.TryGetValue(index, out var bubble) && bubble.Serial == serial)
        {
            bubble.Until = Elapsed + LongestWaitForVoice;
            voicedLines.Add(serial);
        }
        Render();
        Trace?.Invoke($"say #{serial} {CharacterFor(index).Name}{(voiced ? " (voiced)" : "")}: {text}");
        return serial;
    }

    /// <summary>A bubble waiting on its sound gives up after this, even if the voice never says why.</summary>
    private const double LongestWaitForVoice = 45;

    /// <summary>Line <paramref name="serial"/> is over: whatever waits for it goes on.</summary>
    private void EndLine(int serial)
    {
        voicedLines.Remove(serial);
        if (afterLine.Remove(serial, out var waiting)) foreach (var action in waiting) action();
    }

    /// <summary>A bubble is taken down: a voiced line that gave up waiting for its sound still ends its turn.</summary>
    partial void BubbleGone(int i)
    {
        if (!bubbles.TryGetValue(i, out var bubble)) return;
        Trace?.Invoke($"bubble #{bubble.Serial} gone");
        if (voicedLines.Contains(bubble.Serial)) EndLine(bubble.Serial);
    }

    // MARK: Taking turns out loud

    /// <summary>True when lines are being said out loud: the next line of a dialogue then
    /// waits for the one before to end, instead of the silent-bubble clock.</summary>
    private bool IsVoiced
    {
        get
        {
            var on = false;
            VoiceIsOn(ref on);
            return on;
        }
    }

    /// <summary>Out loud, someone is mid-conversation: another pair meeting now only
    /// bumps, and a plane that lands waits to be read, rather than talking over them.</summary>
    private bool VoiceIsTakenNow => IsVoiced && voicedDialogues > 0;

    /// <summary>Run <paramref name="action"/> once line <paramref name="serial"/> has been said (or will not be): at once for
    /// a line that is not being voiced or has already ended.</summary>
    private void WhenSaid(int serial, Action action)
    {
        if (!voicedLines.Contains(serial)) { action(); return; }
        if (!afterLine.TryGetValue(serial, out var waiting)) afterLine[serial] = waiting = new List<Action>();
        waiting.Add(action);
    }

    /// <summary>Wait until line <paramref name="serial"/> has been said.</summary>
    private Task Said(int serial)
    {
        // Asynchronous continuations: whatever awaits this must not run inside the frame that ended the line.
        var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        WhenSaid(serial, () => done.TrySetResult());
        return done.Task;
    }

    /// <summary>The beat between one voiced line ending and the next starting.</summary>
    private double TurnPause
    {
        get
        {
            var pause = 0.35;
            VoiceTurnPause(ref pause);
            return pause;
        }
    }

    /// <summary>Say <paramref name="lines"/> one after another, each starting a beat after the one before
    /// has been said, the sound of each fetched ahead of its turn; then <paramref name="done"/>.
    /// A line that cannot be voiced waits the silent-bubble time instead.</summary>
    private async Task SayInTurns(IReadOnlyList<(int Who, string Text, bool BuiltIn)> lines, Action done)
    {
        foreach (var line in lines.Skip(1))
            if (line.Who < creatures.Count) VoicePrefetch(line.Text, CharacterFor(line.Who).Name, line.BuiltIn);
        voicedDialogues += 1;
        try
        {
            foreach (var line in lines)
            {
                if (line.Who >= creatures.Count) continue;
                var serial = Say(line.Text, line.Who, line.BuiltIn);
                var wait = voicedLines.Contains(serial) ? TurnPause : Banter.ShowTime(line.Text, Settings.BubbleSeconds) * 0.6;
                await Said(serial);
                await Task.Delay(TimeSpan.FromSeconds(wait));
            }
        }
        finally
        {
            voicedDialogues -= 1;
            done();
        }
    }

    // MARK: Hooks the voice fills (Colony.Voice). Unimplemented, every line is a silent bubble on its own clock.

    /// <summary>Voice is on (the Mac's <c>voice != nil &amp;&amp; settings.voiceEnabled</c>).</summary>
    partial void VoiceIsOn(ref bool on);
    /// <summary>Line <paramref name="serial"/> has just gone up in <paramref name="index"/>'s bubble: start saying it
    /// and set <paramref name="voiced"/> when it will be; call <see cref="EndLine"/> with the serial once it has been
    /// said or dropped. The bubble is <c>bubbles[index]</c>, for its reveal.</summary>
    partial void VoiceSay(int serial, int index, string text, bool builtIn, ref bool voiced);
    /// <summary>Fetch the sound of a line that is coming next, so it is ready on its turn.</summary>
    partial void VoicePrefetch(string text, string name, bool builtIn);
    /// <summary>The beat between voiced lines (Settings › Voice).</summary>
    partial void VoiceTurnPause(ref double pause);

    // MARK: Hooks other features declared for the talk to fill

    /// <summary>The creature whose speech bubble is under <paramref name="point"/>, on any monitor.</summary>
    private int? BubbleAt(Pt point)
    {
        foreach (var overlay in overlays) if (overlay.BubbleIndex(point) is int i) return i;
        return null;
    }
}
