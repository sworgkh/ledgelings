using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The Tools screen (SPEC §7.15): every tool on one sheet, a tile each. The Mac's keys, with Ctrl+Alt+K.</summary>
public sealed partial class AppSettings
{
    private bool toolsScreenEnabled, toolsScreenShortcutEnabled;
    private Shortcut toolsScreenShortcut;
    private List<string> toolsScreenTools = new();
    private string toolsScreenShortcutProblem = "";

    private void LoadToolsScreen()
    {
        toolsScreenEnabled = store.Get<bool?>("toolsScreenEnabled") ?? true;
        toolsScreenShortcutEnabled = store.Get<bool?>("toolsScreenShortcutEnabled") ?? true;
        toolsScreenShortcut = Shortcut.Saved(store.Get<int?>("toolsScreenShortcutKeyCode"), store.Get<int?>("toolsScreenShortcutModifiers"), Shortcut.Tools);
        // Unknown codes (a Mac's screenshot tiles) and doubled ones go on load.
        toolsScreenTools = Tools.Shown(store.Get<List<string>>("toolsScreenTools") ?? Tools.DefaultShown.ToList()).Select(t => t.Code()).ToList();
    }

    /// <summary>The Tools screen. Off: its shortcut is let go, the tray item and the Actions sheet's wrench go.</summary>
    public bool ToolsScreenEnabled { get => toolsScreenEnabled; set => Put(ref toolsScreenEnabled, value, "toolsScreenEnabled"); }
    public bool ToolsScreenShortcutEnabled { get => toolsScreenShortcutEnabled; set => Put(ref toolsScreenShortcutEnabled, value, "toolsScreenShortcutEnabled"); }
    public Shortcut ToolsScreenShortcut { get => toolsScreenShortcut; set => PutShortcut(ref toolsScreenShortcut, value, "toolsScreenShortcut"); }
    /// <summary>The tiles shown, in order, by code.</summary>
    public List<string> ToolsScreenTools
    {
        get => toolsScreenTools;
        set
        {
            var codes = Tools.Shown(value).Select(t => t.Code()).ToList();
            if (codes.SequenceEqual(toolsScreenTools)) return;
            toolsScreenTools = codes;
            store.Set("toolsScreenTools", codes);
            Raise(nameof(ToolsScreenTools));
        }
    }

    /// <summary>Why the Tools screen shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string ToolsScreenShortcutProblem
    {
        get => toolsScreenShortcutProblem;
        set { if (toolsScreenShortcutProblem == value) return; toolsScreenShortcutProblem = value; Raise(nameof(ToolsScreenShortcutProblem)); }
    }
}
