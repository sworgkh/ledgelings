using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Everything big that runs on the screen for a while and must stop the moment the owner needs the
/// computer (SPEC §7.17): a dive, a surf, a game. Each registers how to tell it is running and how to stop it;
/// Stop activity (Ctrl+Alt+Q, the tray, the Stop button in the top-right corner) calls <see cref="StopAll"/>. Nothing
/// else does: a click or a key in another app goes on to that app and the activity runs on.</summary>
public sealed class Activities
{
    public enum Kind { Surf, Dive, Game }

    public static Activities Shared { get; } = new();

    private readonly List<(Kind Kind, Func<bool> IsRunning, Action Stop)> entries = new();
    /// <summary>Each stop, as it happens.</summary>
    public Action<string>? Trace { get; set; }

    /// <summary><paramref name="kind"/> is running while <paramref name="isRunning"/> says so; <paramref name="stop"/>
    /// clears it off the screen at once. Registering a kind again replaces it.</summary>
    public void Register(Kind kind, Func<bool> isRunning, Action stop)
    {
        entries.RemoveAll(e => e.Kind == kind);
        entries.Add((kind, isRunning, stop));
    }

    public void Unregister(Kind kind) => entries.RemoveAll(e => e.Kind == kind);

    public bool IsKindRunning(Kind kind) => entries.Any(e => e.Kind == kind && e.IsRunning());

    /// <summary>Whether anything at all is running.</summary>
    public bool IsRunning => entries.Any(e => e.IsRunning());

    public IReadOnlyList<Kind> Running => entries.Where(e => e.IsRunning()).Select(e => e.Kind).ToList();

    /// <summary>Stop everything that runs. Returns what was stopped.</summary>
    public IReadOnlyList<Kind> StopAll(string why = "stop activity")
    {
        var stopped = Running;
        foreach (var e in entries.ToList()) if (e.IsRunning()) e.Stop();
        if (stopped.Count > 0) Trace?.Invoke($"activity stopped: {string.Join(", ", stopped.Select(k => k.ToString().ToLowerInvariant()))} ({why})");
        return stopped;
    }
}
