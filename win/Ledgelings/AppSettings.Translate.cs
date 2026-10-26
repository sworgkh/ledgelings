using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The translator (SPEC §7.14): a sheet that translates as you type, the newest copy translated, and a
/// translate button in the clipboard picker. The Mac's keys and defaults, with Ctrl+Alt+T and Ctrl+Alt+Shift+T.</summary>
public sealed partial class AppSettings
{
    private bool translateEnabled, translateShortcutEnabled, translateClipShortcutEnabled, translateAutocomplete,
                 translatePickerButton, translateKeepInHistory, translateHelperEnabled;
    private Shortcut translateShortcut, translateClipShortcut;
    private Translate.ClipMode translateClipMode;
    private List<string> translateLanguages = new();
    private Dictionary<string, string> translateTargets = new();
    private string translateModel = Translate.DefaultModel, translateAutocompleteModel = "", translateHelper = "", translateShortcutProblem = "";
    private int translateDelayMs, translateLiveLimit;

    private void LoadTranslate()
    {
        translateEnabled = store.Get<bool?>("translateEnabled") ?? true;
        translateShortcutEnabled = store.Get<bool?>("translateShortcutEnabled") ?? true;
        translateShortcut = Shortcut.Saved(store.Get<int?>("translateShortcutKeyCode"), store.Get<int?>("translateShortcutModifiers"), Shortcut.Translate);
        translateClipShortcutEnabled = store.Get<bool?>("translateClipShortcutEnabled") ?? true;
        translateClipShortcut = Shortcut.Saved(store.Get<int?>("translateClipShortcutKeyCode"), store.Get<int?>("translateClipShortcutModifiers"), Shortcut.TranslateClip);
        translateClipMode = Translate.ClipModeNamed(store.Get<string>("translateClipMode"));
        // Fewer than two reads as all three.
        translateLanguages = Translate.On(store.Get<List<string>>("translateLanguages") ?? Translate.DefaultLanguages.ToList()).Select(l => l.Code).ToList();
        translateTargets = CleanTargets(store.Get<Dictionary<string, string>>("translateTargets"));
        var model = store.Get<string>("translateModel");
        translateModel = string.IsNullOrWhiteSpace(model) ? Translate.DefaultModel : model;
        translateAutocomplete = store.Get<bool?>("translateAutocomplete") ?? true;
        translateAutocompleteModel = store.Get<string>("translateAutocompleteModel") ?? "";
        translateDelayMs = Math.Clamp(store.Get<int?>("translateDelayMs") ?? Translate.DefaultDelay, Translate.DelayMin, Translate.DelayMax);
        translateLiveLimit = Math.Clamp(store.Get<int?>("translateLiveLimit") ?? Translate.DefaultLiveLimit, Translate.LiveLimitMin, Translate.LiveLimitMax);
        translatePickerButton = store.Get<bool?>("translatePickerButton") ?? true;
        translateKeepInHistory = store.Get<bool?>("translateKeepInHistory") ?? true;
        translateHelperEnabled = store.Get<bool?>("translateHelperEnabled") ?? true;
        translateHelper = store.Get<string>("translateHelper") ?? "";
    }

    /// <summary>What each language goes into, the defaults under what was saved; into itself or an unknown language is dropped.</summary>
    private static Dictionary<string, string> CleanTargets(Dictionary<string, string>? saved)
    {
        var targets = Translate.DefaultTargets.ToDictionary(kv => kv.Key, kv => kv.Value);
        foreach (var (from, to) in saved ?? new())
            if (Translate.Language(from) is not null && Translate.Language(to) is not null && from != to) targets[from] = to;
        return targets;
    }

    /// <summary>The translator. Off: both shortcuts are let go, the picker has no button, the tray item goes.</summary>
    public bool TranslateEnabled { get => translateEnabled; set => Put(ref translateEnabled, value, "translateEnabled"); }
    public bool TranslateShortcutEnabled { get => translateShortcutEnabled; set => Put(ref translateShortcutEnabled, value, "translateShortcutEnabled"); }
    /// <summary>Opens the sheet, from any app.</summary>
    public Shortcut TranslateShortcut { get => translateShortcut; set => PutShortcut(ref translateShortcut, value, "translateShortcut"); }
    public bool TranslateClipShortcutEnabled { get => translateClipShortcutEnabled; set => Put(ref translateClipShortcutEnabled, value, "translateClipShortcutEnabled"); }
    /// <summary>Translates the newest text copy, from any app.</summary>
    public Shortcut TranslateClipShortcut { get => translateClipShortcut; set => PutShortcut(ref translateClipShortcut, value, "translateClipShortcut"); }
    /// <summary>What that shortcut does with the copy: opens the sheet, or replaces the clipboard quietly.</summary>
    public Translate.ClipMode TranslateClipMode
    {
        get => translateClipMode;
        set { if (translateClipMode == value) return; translateClipMode = value; store.Set("translateClipMode", value.Code()); Raise(nameof(TranslateClipMode)); }
    }
    /// <summary>The languages on, by code; never fewer than two.</summary>
    public List<string> TranslateLanguages
    {
        get => translateLanguages;
        set
        {
            var codes = Translate.On(value).Select(l => l.Code).ToList();
            if (codes.SequenceEqual(translateLanguages)) return;
            translateLanguages = codes;
            store.Set("translateLanguages", codes);
            Raise(nameof(TranslateLanguages));
        }
    }
    public IReadOnlyList<Translate.Lang> TranslateLanguagesOn => Translate.On(translateLanguages);
    /// <summary>What each language goes into when no target is picked.</summary>
    public Dictionary<string, string> TranslateTargets
    {
        get => translateTargets;
        set
        {
            var clean = CleanTargets(value);
            if (clean.Count == translateTargets.Count && clean.All(kv => translateTargets.GetValueOrDefault(kv.Key) == kv.Value)) return;
            translateTargets = clean;
            store.Set("translateTargets", clean);
            Raise(nameof(TranslateTargets));
        }
    }
    /// <summary>The OpenRouter model that translates; empty reads as the default.</summary>
    public string TranslateModel { get => translateModel; set => Put(ref translateModel, value, "translateModel"); }
    /// <summary>Guess the rest of the phrase, in grey after the cursor.</summary>
    public bool TranslateAutocomplete { get => translateAutocomplete; set => Put(ref translateAutocomplete, value, "translateAutocomplete"); }
    /// <summary>The model that guesses; empty: the translating one.</summary>
    public string TranslateAutocompleteModel { get => translateAutocompleteModel; set => Put(ref translateAutocompleteModel, value, "translateAutocompleteModel"); }
    /// <summary>The wait after typing before it translates, in milliseconds.</summary>
    public int TranslateDelayMs { get => translateDelayMs; set => Put(ref translateDelayMs, Math.Clamp(value, Translate.DelayMin, Translate.DelayMax), "translateDelayMs"); }
    /// <summary>Longer texts wait for Enter and say their parts and price first.</summary>
    public int TranslateLiveLimit { get => translateLiveLimit; set => Put(ref translateLiveLimit, Math.Clamp(value, Translate.LiveLimitMin, Translate.LiveLimitMax), "translateLiveLimit"); }
    /// <summary>The clipboard picker's translate button and Ctrl+T.</summary>
    public bool TranslatePickerButton { get => translatePickerButton; set => Put(ref translatePickerButton, value, "translatePickerButton"); }
    /// <summary>A copied or pasted translation goes into the clipboard history.</summary>
    public bool TranslateKeepInHistory { get => translateKeepInHistory; set => Put(ref translateKeepInHistory, value, "translateKeepInHistory"); }
    /// <summary>A creature brings the sheet.</summary>
    public bool TranslateHelperEnabled { get => translateHelperEnabled; set => Put(ref translateHelperEnabled, value, "translateHelperEnabled"); }
    /// <summary>Which character brings it, by name; empty: whoever is nearest the middle.</summary>
    public string TranslateHelper { get => translateHelper; set => Put(ref translateHelper, value, "translateHelper"); }

    /// <summary>Why a translate shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string TranslateShortcutProblem
    {
        get => translateShortcutProblem;
        set { if (translateShortcutProblem == value) return; translateShortcutProblem = value; Raise(nameof(TranslateShortcutProblem)); }
    }
}
