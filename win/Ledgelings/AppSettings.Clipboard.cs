using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The clipboard manager (SPEC §7.11): the history of copies, the snippets, their pickers and
/// the creature who brings them. The Mac's keys and defaults, with Ctrl-based shortcuts. No fingerprint
/// guard on Windows: protected snippets are kept in Credential Manager and masked, nothing more.</summary>
public sealed partial class AppSettings
{
    public const int ClipHistoryLimitMin = 10, ClipHistoryLimitMax = 2000;
    public const int ClipKeepDaysMin = 0, ClipKeepDaysMax = 365;
    public const double ClipAnimationSpeedMin = 0.5, ClipAnimationSpeedMax = 3;
    public const int ClipLargestImageMin = 1, ClipLargestImageMax = 100;

    private bool clipboardEnabled, clipHistoryEnabled, clipKeepFormatting, clipKeepFiles, clipKeepImages, clipAutoPaste, clipPlainText;
    private bool clipHistoryShortcutEnabled, clipSnippetsShortcutEnabled, clipSnippetShortcutsEnabled;
    private bool clipAnimate, clipHelperEnabled, clipHelperTalks;
    private int clipHistoryLimit, clipKeepDays, clipLargestImageMB;
    private double clipAnimationSpeed;
    private IReadOnlyList<string> clipExcludedApps = Array.Empty<string>();
    private Shortcut clipHistoryShortcut, clipSnippetsShortcut;
    private string clipHelper = "", clipShortcutProblem = "";

    private void LoadClipboard()
    {
        clipboardEnabled = store.Get<bool?>("clipboardEnabled") ?? true;
        clipHistoryEnabled = store.Get<bool?>("clipHistoryEnabled") ?? true;
        // 200 copies and a month: a working week's worth to search through, small enough to load at once.
        clipHistoryLimit = Math.Clamp(store.Get<int?>("clipHistoryLimit") ?? 200, ClipHistoryLimitMin, ClipHistoryLimitMax);
        clipKeepDays = Math.Clamp(store.Get<int?>("clipKeepDays") ?? 30, ClipKeepDaysMin, ClipKeepDaysMax);
        clipExcludedApps = store.Get<List<string>>("clipExcludedApps") ?? Clipboard.DefaultExcludedWindowsApps.ToList();
        clipKeepFormatting = store.Get<bool?>("clipKeepFormatting") ?? true;
        clipKeepFiles = store.Get<bool?>("clipKeepFiles") ?? true;
        clipKeepImages = store.Get<bool?>("clipKeepImages") ?? true;
        // 20 MB: a full-screen 4K screenshot as PNG, with room; a bigger copy is rarely one to paste again.
        clipLargestImageMB = Math.Clamp(store.Get<int?>("clipLargestImageMB") ?? 20, ClipLargestImageMin, ClipLargestImageMax);
        clipAutoPaste = store.Get<bool?>("clipAutoPaste") ?? true;
        clipPlainText = store.Get<bool?>("clipPlainText") ?? false;
        clipHistoryShortcutEnabled = store.Get<bool?>("clipHistoryShortcutEnabled") ?? true;
        clipHistoryShortcut = Shortcut.Saved(store.Get<int?>("clipHistoryShortcutKeyCode"), store.Get<int?>("clipHistoryShortcutModifiers"), Shortcut.ClipHistory);
        clipSnippetsShortcutEnabled = store.Get<bool?>("clipSnippetsShortcutEnabled") ?? true;
        clipSnippetsShortcut = Shortcut.Saved(store.Get<int?>("clipSnippetsShortcutKeyCode"), store.Get<int?>("clipSnippetsShortcutModifiers"), Shortcut.ClipSnippets);
        clipSnippetShortcutsEnabled = store.Get<bool?>("clipSnippetShortcutsEnabled") ?? true;
        clipAnimate = store.Get<bool?>("clipAnimate") ?? true;
        clipAnimationSpeed = Math.Clamp(store.Get<double?>("clipAnimationSpeed") ?? 1, ClipAnimationSpeedMin, ClipAnimationSpeedMax);
        clipHelperEnabled = store.Get<bool?>("clipHelperEnabled") ?? true;
        clipHelper = store.Get<string>("clipHelper") ?? "";
        clipHelperTalks = store.Get<bool?>("clipHelperTalks") ?? true;
    }

    /// <summary>The clipboard manager. Off: nothing is watched, no clipboard shortcut is taken.</summary>
    public bool ClipboardEnabled { get => clipboardEnabled; set => Put(ref clipboardEnabled, value, "clipboardEnabled"); }
    /// <summary>Every copy goes into the history. Off: only the snippets.</summary>
    public bool ClipHistoryEnabled { get => clipHistoryEnabled; set => Put(ref clipHistoryEnabled, value, "clipHistoryEnabled"); }
    public int ClipHistoryLimit { get => clipHistoryLimit; set => Put(ref clipHistoryLimit, Math.Clamp(value, ClipHistoryLimitMin, ClipHistoryLimitMax), "clipHistoryLimit"); }
    /// <summary>Days a copy is kept; 0 keeps it until the limit pushes it out.</summary>
    public int ClipKeepDays { get => clipKeepDays; set => Put(ref clipKeepDays, Math.Clamp(value, ClipKeepDaysMin, ClipKeepDaysMax), "clipKeepDays"); }
    /// <summary>Apps, by process name, whose copies are never kept: password managers to begin with.</summary>
    public IReadOnlyList<string> ClipExcludedApps { get => clipExcludedApps; set => Put(ref clipExcludedApps, value.ToList(), "clipExcludedApps"); }
    /// <summary>A copy's formatting (RTF) is kept beside its words.</summary>
    public bool ClipKeepFormatting { get => clipKeepFormatting; set => Put(ref clipKeepFormatting, value, "clipKeepFormatting"); }
    /// <summary>Files copied in Explorer are kept, as their paths, and paste back as files.</summary>
    public bool ClipKeepFiles { get => clipKeepFiles; set => Put(ref clipKeepFiles, value, "clipKeepFiles"); }
    /// <summary>Copied pictures (screenshots, images from a browser) are kept and paste back as pictures.</summary>
    public bool ClipKeepImages { get => clipKeepImages; set => Put(ref clipKeepImages, value, "clipKeepImages"); }
    /// <summary>The largest picture kept, in MB, all its formats together; a bigger one is left out.</summary>
    public int ClipLargestImageMB
    {
        get => clipLargestImageMB;
        set => Put(ref clipLargestImageMB, Math.Clamp(value, ClipLargestImageMin, ClipLargestImageMax), "clipLargestImageMB");
    }
    /// <summary>Choosing an item pastes it into the app you were in (Ctrl+V pressed for you). Off: it is only copied.</summary>
    public bool ClipAutoPaste { get => clipAutoPaste; set => Put(ref clipAutoPaste, value, "clipAutoPaste"); }
    /// <summary>Paste the words without their formatting; Alt+Enter in the picker does the other one.</summary>
    public bool ClipPlainText { get => clipPlainText; set => Put(ref clipPlainText, value, "clipPlainText"); }
    public bool ClipHistoryShortcutEnabled { get => clipHistoryShortcutEnabled; set => Put(ref clipHistoryShortcutEnabled, value, "clipHistoryShortcutEnabled"); }
    public Shortcut ClipHistoryShortcut { get => clipHistoryShortcut; set => PutShortcut(ref clipHistoryShortcut, value, "clipHistoryShortcut"); }
    public bool ClipSnippetsShortcutEnabled { get => clipSnippetsShortcutEnabled; set => Put(ref clipSnippetsShortcutEnabled, value, "clipSnippetsShortcutEnabled"); }
    public Shortcut ClipSnippetsShortcut { get => clipSnippetsShortcut; set => PutShortcut(ref clipSnippetsShortcut, value, "clipSnippetsShortcut"); }
    /// <summary>A snippet given its own shortcut pastes at once when it is pressed.</summary>
    public bool ClipSnippetShortcutsEnabled { get => clipSnippetShortcutsEnabled; set => Put(ref clipSnippetShortcutsEnabled, value, "clipSnippetShortcutsEnabled"); }
    /// <summary>The picker unfolds and collapses into where the words go. Off: it simply appears and goes.</summary>
    public bool ClipAnimate { get => clipAnimate; set => Put(ref clipAnimate, value, "clipAnimate"); }
    /// <summary>How fast it unfolds and collapses: 2 is twice as fast. The paste itself never waits for it.</summary>
    public double ClipAnimationSpeed
    {
        get => clipAnimationSpeed;
        set => Put(ref clipAnimationSpeed, Math.Clamp(value, ClipAnimationSpeedMin, ClipAnimationSpeedMax), "clipAnimationSpeed");
    }
    /// <summary>A creature leaps to the middle of the screen with the picker and holds it by a corner.</summary>
    public bool ClipHelperEnabled { get => clipHelperEnabled; set => Put(ref clipHelperEnabled, value, "clipHelperEnabled"); }
    /// <summary>Which character brings it, by name; empty: whoever is nearest the middle of the screen.</summary>
    public string ClipHelper { get => clipHelper; set => Put(ref clipHelper, value, "clipHelper"); }
    /// <summary>It says a short line of its own as the sheet unfolds (with talk on).</summary>
    public bool ClipHelperTalks { get => clipHelperTalks; set => Put(ref clipHelperTalks, value, "clipHelperTalks"); }

    /// <summary>Why a clipboard shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string ClipShortcutProblem
    {
        get => clipShortcutProblem;
        set { if (clipShortcutProblem == value) return; clipShortcutProblem = value; Raise(nameof(ClipShortcutProblem)); }
    }

    private void PutShortcut(ref Shortcut field, Shortcut value, string key, [System.Runtime.CompilerServices.CallerMemberName] string? property = null)
    {
        if (field == value) return;
        field = value;
        store.Set(key + "KeyCode", value.KeyCode);
        store.Set(key + "Modifiers", (int)value.Modifiers);
        Raise(property);
    }
}
