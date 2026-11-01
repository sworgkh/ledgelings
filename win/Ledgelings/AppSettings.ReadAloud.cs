using System.Text.Json;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Read aloud (SPEC §7.16): text in, sound out. The Mac's keys and defaults, with Ctrl+Alt+Shift+R (Windows'
/// Ctrl+Alt+R is Add a Reminder).</summary>
public sealed partial class AppSettings
{
    /// <summary>Where Save puts the sound file first: <c>~</c> is the user's folder, and <c>~/Desktop</c> the Desktop
    /// wherever Windows keeps it (OneDrive moves it).</summary>
    public const string DefaultReadAloudFolder = "~/Desktop";

    private bool readAloudEnabled, readAloudShortcutEnabled, readAloudFromClipboard, readAloudStartAtOnce, readAloudKeepReading,
                 readAloudPickerButton, readAloudHelperEnabled;
    private Shortcut readAloudShortcut;
    private string readAloudHelper = "", readAloudDefaultPreset = "", readAloudFolder = DefaultReadAloudFolder, readAloudShortcutProblem = "";
    private IReadOnlyList<ReadAloud.Preset> readAloudPresets = ReadAloud.DefaultPresets;
    private ReadAloud.Format readAloudFormat;
    private int readAloudLongLimit;

    private void LoadReadAloud()
    {
        readAloudEnabled = store.Get<bool?>("readAloudEnabled") ?? true;
        readAloudShortcutEnabled = store.Get<bool?>("readAloudShortcutEnabled") ?? true;
        readAloudShortcut = Shortcut.Saved(store.Get<int?>("readAloudShortcutKeyCode"), store.Get<int?>("readAloudShortcutModifiers"), Shortcut.ReadAloud);
        readAloudFromClipboard = store.Get<bool?>("readAloudFromClipboard") ?? true;
        readAloudStartAtOnce = store.Get<bool?>("readAloudStartAtOnce") ?? true;
        readAloudKeepReading = store.Get<bool?>("readAloudKeepReading") ?? true;
        readAloudPickerButton = store.Get<bool?>("readAloudPickerButton") ?? true;
        readAloudHelperEnabled = store.Get<bool?>("readAloudHelperEnabled") ?? true;
        readAloudHelper = store.Get<string>("readAloudHelper") ?? "";
        // Read leniently and clamped, each id once, at most nine, never none.
        List<ReadAloud.Preset>? saved;
        try { saved = store.Get<List<ReadAloud.Preset>>("readAloudPresets"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { saved = null; }
        readAloudPresets = ReadAloud.Cleaned(saved ?? ReadAloud.DefaultPresets.ToList());
        // An unknown default is the first.
        var chosen = store.Get<string>("readAloudDefaultPreset") ?? ReadAloud.IdString(ReadAloud.DefaultPresetId);
        readAloudDefaultPreset = PresetNamed(chosen) is { } known ? ReadAloud.IdString(known.Id) : ReadAloud.IdString(readAloudPresets[0].Id);
        var folder = store.Get<string>("readAloudFolder");
        readAloudFolder = string.IsNullOrWhiteSpace(folder) ? DefaultReadAloudFolder : folder;
        readAloudFormat = ReadAloud.FormatNamed(store.Get<string>("readAloudFormat")) ?? ReadAloud.Format.M4a;
        readAloudLongLimit = Math.Clamp(store.Get<int?>("readAloudLongLimit") ?? ReadAloud.DefaultLongLimit, ReadAloud.LongLimitMin, ReadAloud.LongLimitMax);
    }

    private ReadAloud.Preset? PresetNamed(string id) =>
        Guid.TryParse(id, out var guid) ? readAloudPresets.FirstOrDefault(p => p.Id == guid) : null;

    /// <summary>Read aloud. Off: its shortcut is let go, the picker has no button, the tray item goes.</summary>
    public bool ReadAloudEnabled { get => readAloudEnabled; set => Put(ref readAloudEnabled, value, "readAloudEnabled"); }
    public bool ReadAloudShortcutEnabled { get => readAloudShortcutEnabled; set => Put(ref readAloudShortcutEnabled, value, "readAloudShortcutEnabled"); }
    /// <summary>Opens the sheet with the clipboard's text, from any app.</summary>
    public Shortcut ReadAloudShortcut { get => readAloudShortcut; set => PutShortcut(ref readAloudShortcut, value, "readAloudShortcut"); }
    /// <summary>The sheet opens with the clipboard's text already in it.</summary>
    public bool ReadAloudFromClipboard { get => readAloudFromClipboard; set => Put(ref readAloudFromClipboard, value, "readAloudFromClipboard"); }
    /// <summary>…and starts reading it at once (a long paid text still waits for Enter).</summary>
    public bool ReadAloudStartAtOnce { get => readAloudStartAtOnce; set => Put(ref readAloudStartAtOnce, value, "readAloudStartAtOnce"); }
    /// <summary>The reading goes on when the sheet closes; the tray's Stop Reading ends it.</summary>
    public bool ReadAloudKeepReading { get => readAloudKeepReading; set => Put(ref readAloudKeepReading, value, "readAloudKeepReading"); }
    /// <summary>A loudspeaker on every text row of the clipboard picker (Ctrl+R).</summary>
    public bool ReadAloudPickerButton { get => readAloudPickerButton; set => Put(ref readAloudPickerButton, value, "readAloudPickerButton"); }
    /// <summary>A creature brings the sheet and reads beside it.</summary>
    public bool ReadAloudHelperEnabled { get => readAloudHelperEnabled; set => Put(ref readAloudHelperEnabled, value, "readAloudHelperEnabled"); }
    /// <summary>Who: a name, or empty for whoever is nearest the middle.</summary>
    public string ReadAloudHelper { get => readAloudHelper; set => Put(ref readAloudHelper, value, "readAloudHelper"); }

    /// <summary>The presets, in the sheet's order (Ctrl+1…); never empty, each clamped. The default follows a
    /// deleted one to the first.</summary>
    public IReadOnlyList<ReadAloud.Preset> ReadAloudPresets
    {
        get => readAloudPresets;
        set
        {
            var clean = ReadAloud.Cleaned(value);
            if (clean.SequenceEqual(readAloudPresets)) return;
            readAloudPresets = clean;
            store.Set("readAloudPresets", clean.ToList());
            Raise(nameof(ReadAloudPresets));
            if (PresetNamed(readAloudDefaultPreset) is null) ReadAloudDefaultPreset = ReadAloud.IdString(clean[0].Id);
        }
    }

    /// <summary>The id of the preset the sheet starts with, as the Mac writes it.</summary>
    public string ReadAloudDefaultPreset
    {
        get => readAloudDefaultPreset;
        set
        {
            var id = PresetNamed(value) is { } p ? ReadAloud.IdString(p.Id) : ReadAloud.IdString(readAloudPresets[0].Id);
            Put(ref readAloudDefaultPreset, id, "readAloudDefaultPreset");
        }
    }

    /// <summary>The preset the sheet starts with: the chosen one, else the first.</summary>
    public ReadAloud.Preset ReadAloudDefault => PresetNamed(readAloudDefaultPreset) ?? readAloudPresets.FirstOrDefault() ?? ReadAloud.DefaultPresets[0];

    /// <summary>Where Save puts the file; empty reads as the Desktop.</summary>
    public string ReadAloudFolder
    {
        get => readAloudFolder;
        set => Put(ref readAloudFolder, string.IsNullOrWhiteSpace(value) ? DefaultReadAloudFolder : value, "readAloudFolder");
    }

    /// <summary>The save folder as a path on this PC: the Desktop for <c>~/Desktop</c>, the user's folder for <c>~</c>.</summary>
    public string ReadAloudFolderPath => FolderPath(readAloudFolder);

    public static string FolderPath(string folder)
    {
        var f = folder.Trim();
        if (f.Length == 0 || f.Replace('\\', '/').TrimEnd('/') == DefaultReadAloudFolder) return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        if (f == "~") return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (f.StartsWith("~/", StringComparison.Ordinal) || f.StartsWith("~\\", StringComparison.Ordinal))
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), f[2..].Replace('/', Path.DirectorySeparatorChar));
        return f;
    }

    /// <summary>The folder as saved: under the user's folder written with <c>~</c>, as the Mac writes it; the Desktop as <c>~/Desktop</c>.</summary>
    public static string FolderSaved(string path)
    {
        var full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory).TrimEnd(Path.DirectorySeparatorChar);
        if (desktop.Length > 0 && string.Equals(full, desktop, StringComparison.OrdinalIgnoreCase)) return DefaultReadAloudFolder;
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).TrimEnd(Path.DirectorySeparatorChar);
        if (home.Length > 0 && full.StartsWith(home + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            return "~/" + full[(home.Length + 1)..].Replace(Path.DirectorySeparatorChar, '/');
        return full;
    }

    /// <summary><c>m4a</c> or <c>wav</c>, the Mac's choice. Windows has no AAC encoder without a new dependency, so
    /// it writes WAV either way; the choice is kept for a settings file shared with a Mac's habits.</summary>
    public ReadAloud.Format ReadAloudFormat
    {
        get => readAloudFormat;
        set { if (readAloudFormat == value) return; readAloudFormat = value; store.Set("readAloudFormat", value.Code()); Raise(nameof(ReadAloudFormat)); }
    }

    /// <summary>Longer than this many characters, a paid reading waits for Enter, its price shown first.</summary>
    public int ReadAloudLongLimit
    {
        get => readAloudLongLimit;
        set => Put(ref readAloudLongLimit, Math.Clamp(value, ReadAloud.LongLimitMin, ReadAloud.LongLimitMax), "readAloudLongLimit");
    }

    /// <summary>Why the read-aloud shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string ReadAloudShortcutProblem
    {
        get => readAloudShortcutProblem;
        set { if (readAloudShortcutProblem == value) return; readAloudShortcutProblem = value; Raise(nameof(ReadAloudShortcutProblem)); }
    }
}
