using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The lines out loud: the talk's voice hooks, filled with <see cref="Ledgelings.Voice"/>, and how
/// much of a bubble is on show while its line is being said.</summary>
public sealed partial class Colony
{
    private sealed partial class Bubble
    {
        /// <summary>Dots while the sound is on its way, then the text typing out as it is said.</summary>
        public SpeechReveal Reveal { get; set; } = SpeechReveal.All;
    }

    private Voice? voice;

    /// <summary>Reads every line out loud when voice is on. Null: every line is a silent bubble.</summary>
    public Voice? Voice
    {
        get => voice;
        set
        {
            voice = value;
            if (voice is null) return;
            voice.Cast = () => Enumerable.Range(0, creatures.Count).Select(i => CharacterFor(i).Name).ToList();
            voice.Describe = name =>
            {
                for (int i = 0; i < creatures.Count; i++)
                    if (CharacterFor(i).Name == name) return (CharacterFor(i).Persona, KindOf(i));
                return null;
            };
        }
    }

    partial void VoiceIsOn(ref bool on) => on = voice is not null && Settings.VoiceEnabled;

    partial void VoiceSay(int serial, int index, string text, bool builtIn, ref bool voiced)
    {
        if (voice is null) return;
        voiced = voice.Say(text, CharacterFor(index).Name, builtIn, cue => Heard(cue, serial, index));
        if (voiced && bubbles.TryGetValue(index, out var bubble) && bubble.Serial == serial) bubble.Reveal = new SpeechReveal.Waiting(Elapsed);
    }

    partial void VoicePrefetch(string text, string name, bool builtIn) => voice?.Prefetch(text, name, builtIn);

    partial void VoiceTurnPause(ref double pause) => pause = Settings.VoiceTurnPause;

    /// <summary>The note, in the writer's own voice and with no bubble.</summary>
    partial void ReadReminderAloud(string note, string writer, bool builtIn) => voice?.Say(note, writer, builtIn);

    /// <summary>The voice's news about a bubble's line.</summary>
    private void Heard(Voice.Cue cue, int serial, int index)
    {
        // Whatever waits for this line goes on even if its bubble was since replaced.
        if (cue is not Voice.Cue.Progress) Trace?.Invoke($"cue #{serial} {CueName(cue)}");
        if (cue is Voice.Cue.Done or Voice.Cue.Dropped) EndLine(serial);
        if (!bubbles.TryGetValue(index, out var bubble) || bubble.Serial != serial) return;
        var showTime = Banter.ShowTime(bubble.Text, Settings.BubbleSeconds);
        switch (cue)
        {
            case Voice.Cue.Started { Duration: double duration }:
                bubble.Reveal = new SpeechReveal.Timed(Elapsed, duration);
                bubble.Until = Elapsed + Math.Max(showTime, duration + 2);
                break;
            case Voice.Cue.Started:
                bubble.Reveal = new SpeechReveal.Spoken(0);
                bubble.Until = Elapsed + LongestWaitForVoice;
                break;
            case Voice.Cue.Progress p:
                if (bubble.Reveal is SpeechReveal.Spoken before) bubble.Reveal = new SpeechReveal.Spoken(Math.Max(before.Share, p.Share));
                break;
            case Voice.Cue.Done:
                bubble.Reveal = SpeechReveal.All;
                bubble.Until = Math.Max(Math.Min(bubble.Until, Elapsed + showTime), Elapsed + 2);
                break;
            case Voice.Cue.Dropped:
                bubble.Reveal = SpeechReveal.All;
                bubble.Until = Elapsed + showTime;
                break;
        }
    }

    /// <summary>The Mac prints its cues as <c>started(duration: 1.2)</c>, <c>done</c>, <c>dropped</c>.</summary>
    private static string CueName(Voice.Cue cue) => cue switch
    {
        Voice.Cue.Started { Duration: double d } => $"started(duration: {d:0.##})",
        Voice.Cue.Started => "started(duration: nil)",
        Voice.Cue.Done => "done",
        Voice.Cue.Dropped => "dropped",
        _ => "progress",
    };

    /// <summary>What creature <paramref name="i"/>'s bubble shows now, and the share of it on show; no text, no bubble.</summary>
    private (string? Text, double Share) BubbleShown(int i)
    {
        if (!bubbles.TryGetValue(i, out var bubble)) return (null, 1);
        var (text, share) = bubble.Reveal.Shown(bubble.Text, Elapsed);
        return (text, share);
    }
}
