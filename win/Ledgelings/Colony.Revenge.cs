using Ledgelings.Core;
using Microsoft.Win32;

namespace Ledgelings;

/// <summary>Revenge (SPEC §4.7.3): chased or picked up too often in a short time, a creature jumps on the
/// cursor, hangs on to it and tells the user what it thinks of them. Shaking the mouse hard throws it off;
/// Escape, or the longest hold running out, lets go too. The same as the Mac's <c>Colony+Revenge.swift</c>.</summary>
public sealed partial class Colony
{
    /// <summary>The one creature holding the cursor.</summary>
    public sealed class Grab
    {
        public int Index;
        /// <summary>On the colony's clock.</summary>
        public double Since;
        /// <summary>Where the cursor is held, and where it was last seen.</summary>
        public Pt Pin, Last;
        public Revenge.Shake Shake = new();
        /// <summary>Whether the real pointer is held; without it the creature only clings and rides along.</summary>
        public bool Pinned;
        public int Serial;
    }

    /// <summary>Hunts in the last few minutes per creature: too many and one grabs the cursor.</summary>
    private readonly Revenge.Fuse revengeFuse = new();
    /// <summary>The creature hanging on to the cursor right now, if any.</summary>
    public Grab? CurrentGrab { get; private set; }
    /// <summary>Counts grabs, so a model's late line finds whether its grab is still on.</summary>
    private int grabCount;
    /// <summary>The real pointer, for a grab; tests set their own.</summary>
    public IPointerHold? Pointer { get; set; } = new SystemPointer();
    /// <summary>Whether a mouse button is down: nobody grabs the cursor mid-drag. Tests set it.</summary>
    public Func<bool> MouseIsDown { get; set; } = () => SystemPointer.AnyButtonDown;
    /// <summary>Where the pointer is; tests set it.</summary>
    public Func<Pt> PointerLocation { get; set; } = Desktop.Cursor;
    private bool watchingTheSession;

    /// <summary>A grab ends at once when the session locks or switches, or the machine goes to sleep.</summary>
    private void WatchTheSession()
    {
        if (watchingTheSession) return;
        watchingTheSession = true;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    private void OnSessionSwitch(object? sender, SessionSwitchEventArgs e) => UiDispatcher().BeginInvoke(() => LetGoOfCursor(Revenge.Release.Escape));
    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) UiDispatcher().BeginInvoke(() => LetGoOfCursor(Revenge.Release.Escape));
    }
    private static System.Windows.Threading.Dispatcher UiDispatcher() => System.Windows.Application.Current?.Dispatcher
                                                                       ?? System.Windows.Threading.Dispatcher.CurrentDispatcher;

    private void StopWatchingTheSession()
    {
        if (!watchingTheSession) return;
        watchingTheSession = false;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
    }

    /// <summary>The settings changed: how the fuse counts, and a grab that may no longer stand.</summary>
    partial void ApplyRevenge()
    {
        revengeFuse.After = Settings.RevengeAfter;
        revengeFuse.Window = Settings.RevengeWindowSeconds;
        revengeFuse.Cooldown = Settings.RevengeCooldownMinutes * 60;
        revengeFuse.Forget(creatures.Count);
        if (CurrentGrab is { } g && (!Settings.RevengeEnabled || g.Index >= Settings.CreatureCount)) LetGoOfCursor(Revenge.Release.Escape);
    }

    /// <summary>Creature <paramref name="i"/> was just hunted. True when that was once too often and it grabbed the cursor.</summary>
    private bool TakeRevenge(int i)
    {
        if (!Settings.RevengeEnabled || i < 0 || i >= creatures.Count) return false;
        if (!revengeFuse.Hunted(i, Elapsed) || !CanGrab(i)) return false;
        GrabCursor(i);
        return true;
    }

    /// <summary>Not while the user holds the mouse button (a drag, a carry), not mid-conversation, not while they hide.</summary>
    private bool CanGrab(int i) =>
        CurrentGrab is null && held is null && poke is null && !MouseIsDown()
        && !busy.Contains(i) && !complaining.Contains(i) && !hideout.IsActive && !hideout.IsInside(i);

    /// <summary>Where a creature hangs from the cursor: the arrow's tip in the top of its body.</summary>
    private Pt Hang(int i, Pt cursor)
    {
        var half = atlas.BodyHalfSize * sizes[i];
        return new Pt(cursor.X + half * 0.2, cursor.Y - half * 0.55);
    }

    public void GrabCursor(int i)
    {
        if (i < 0 || i >= creatures.Count) return;
        var cursor = PointerLocation();
        if (!creatures[i].Cling()) return;
        var times = Math.Max(revengeFuse.Recent(i, Elapsed), 1);
        revengeFuse.Grabbed(Elapsed);
        annoyance.Forgive(i);
        grabCount++;
        var pinned = Pointer?.Pin(cursor) ?? false;
        if (Pointer is not null) Pointer.OnEscape = () => LetGoOfCursor(Revenge.Release.Escape);
        WatchTheSession();
        CurrentGrab = new Grab
        {
            Index = i, Since = Elapsed, Pin = cursor, Last = cursor,
            Shake = new Revenge.Shake(Settings.RevengeShakes), Pinned = pinned, Serial = grabCount,
        };
        creatures[i].Drag(Hang(i, cursor));
        Trace?.Invoke($"grab {CharacterFor(i).Name}{(pinned ? "" : " (clinging only)")}");
        Shame(i, times, grabCount);
    }

    /// <summary>Every frame of a grab: count the struggle, keep the cursor held, and let go when it has been held long enough.</summary>
    partial void UpdateGrab(Pt cursor)
    {
        if (CurrentGrab is not { } g) return;
        if (g.Index >= creatures.Count || !creatures[g.Index].IsHeld) { LetGoOfCursor(Revenge.Release.Escape); return; }
        if (Elapsed - g.Since >= Settings.RevengeHoldSeconds) { LetGoOfCursor(Revenge.Release.Tired); return; }
        Struggle(cursor);
    }

    /// <summary>The user moved the cursor to <paramref name="point"/>: that is part of a shake, and a held cursor
    /// goes straight back. Hard enough, and the creature is thrown off.</summary>
    public void Struggle(Pt point)
    {
        if (CurrentGrab is not { } g) return;
        double dx = point.X - g.Last.X, dy = point.Y - g.Last.Y;
        var shaken = (dx != 0 || dy != 0) && g.Shake.Moved(dx, dy, Elapsed);
        if (g.Pinned)
        {
            if (point != g.Pin) Pointer?.Hold(g.Pin);
            g.Last = g.Pin;
        }
        else g.Last = point;
        if (shaken) { LetGoOfCursor(Revenge.Release.Shaken); return; }
        // It wobbles harder the closer it is to coming loose.
        var wobble = g.Shake.Vigour(Elapsed) * 7 * Math.Sin(Elapsed * 45);
        var at = Hang(g.Index, g.Pinned ? g.Pin : point);
        creatures[g.Index].Drag(new Pt(at.X + wobble, at.Y));
    }

    /// <summary>Let go of the cursor, if anyone has it. Shaken off, it tumbles down with a last word.</summary>
    public void LetGoOfCursor(Revenge.Release why)
    {
        if (CurrentGrab is not { } g) return;
        CurrentGrab = null;
        Pointer?.Release();
        if (Pointer is not null) Pointer.OnEscape = null;
        StopWatchingTheSession();
        if (g.Index >= creatures.Count) return;
        creatures[g.Index].Drop(tumbling: why == Revenge.Release.Shaken);
        var name = CharacterFor(g.Index).Name;
        Trace?.Invoke($"let go {name}: {why.ToString().ToLowerInvariant()}");
        if (why != Revenge.Release.Shaken || !Settings.TalkEnabled) return;
        Say(Revenge.LastWord(name, Settings.CursorMood, rng), g.Index, builtIn: true);
    }

    /// <summary>What it says while it holds the cursor: the model's line, or its own built-in one.</summary>
    private void Shame(int i, int times, int serial)
    {
        if (!Settings.TalkEnabled) return;
        var me = CharacterFor(i);
        var n = Hunts.NumbersOf(me.Name);
        var situation = string.Join(" ", new[] { AlmanacSentence, Describe(i) + ".",
                L10n.Tr("%@ has been chased or picked up by the user's cursor %d times in the last few minutes.", me.Name, times),
                HuntSentence(new[] { i }, always: true) }.Where(s => s.Length > 0));
        string BuiltIn() => Revenge.Line(me.Name, Math.Max(n.Today, 1), Math.Max(n.All, 1), Settings.CursorMood, rng);
        var service = Settings.Brain != BrainKind.Script ? Settings.ChatClient() : null;
        if (service is null)
        {
            var line = BuiltIn();
            Say(line, i, builtIn: true);
            RecordRevenge(line, me.Name, situation);
            return;
        }
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = me.Name, ["speakerKind"] = Banter.Spoken(KindOf(i)), ["speakerPersona"] = Banter.Persona(me.Persona),
            ["listener"] = L10n.Tr("you"), ["listenerKind"] = L10n.Tr("the person at the computer"),
            ["listenerPersona"] = L10n.Tr("The person whose screen you all live on."),
            ["situation"] = situation, ["times"] = times.ToString(),
        };
        var system = LineMemory.WithRecent(Core.Bonds.WithRelationship(Settings.SystemPrompt, vars, ""), History.Memory.Recent(me.Name));
        var user = Banter.Render(Revenge.Prompt(Settings.CursorMood), vars).Trim();
        _ = WriteShame(service, i, me, serial, situation, system, user, BuiltIn);
    }

    private async Task WriteShame(ChatClient service, int i, Character me, int serial, string situation, string system, string user,
                                  Func<string> builtIn)
    {
        var line = "";
        double? cost = null;
        int? tokens = null;
        try
        {
            await service.CheckModel();
            var answer = await service.Line(system, user);
            // Paid for, whatever comes back, and even if the grab is over by now.
            if (answer.Usage is Spend.Usage usage)
            {
                if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
                Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Revenge);
                cost = usage.Cost;
                tokens = usage.PromptTokens + usage.CompletionTokens;
            }
            line = Banter.CleanLine(answer.Text, me.Name, cut: answer.Cut);
        }
        catch (Exception e)       // any failure: a built-in line takes its place
        {
            TalkStatus = e.Message;
            Console.Error.WriteLine("Ledgelings revenge: " + e.Message);
        }
        if (CurrentGrab?.Serial != serial || i >= creatures.Count || CharacterFor(i).Name != me.Name) return;
        var modelWrote = line.Length > 0;
        if (!modelWrote) line = builtIn();
        Say(line, i, builtIn: !modelWrote);
        RecordRevenge(line, me.Name, situation, modelWrote ? service.ProviderTitle : null, service.Model, cost, tokens);
    }

    /// <summary>Into the Chats tab, with what it cost when a model wrote it.</summary>
    private void RecordRevenge(string line, string name, string situation,
                               string? provider = null, string model = "", double? cost = null, int? tokens = null)
    {
        TalkStatus = L10n.Tr("%@ grabbed your cursor: “%@”", name, line);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = situation,
            Provider = provider ?? AppSettings.BrainTitle(BrainKind.Script), Model = provider is null ? "" : model,
            Lines = new List<ChatLog.Line> { new(name, line) }, Cost = cost, Tokens = tokens,
        });
        Trace?.Invoke($"revenge {name}: {line}");
    }
}
