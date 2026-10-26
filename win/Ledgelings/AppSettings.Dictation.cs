using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Dictation (SPEC §7.13): a shortcut records the microphone and an OpenRouter model writes it down onto
/// the clipboard. The Mac's keys and defaults, with Ctrl+Alt+D.</summary>
public sealed partial class AppSettings
{
    private bool dictationEnabled, dictationShortcutEnabled, dictationHoldToTalk, dictationCleanUp, dictationPaste, dictationCreature;
    private Shortcut dictationShortcut;
    private string dictationModel = Dictation.DefaultModel, dictationHelper = "", dictationShortcutProblem = "";
    private Dictation.Spoken dictationLanguage;
    private int dictationMaxSeconds;

    private void LoadDictation()
    {
        dictationEnabled = store.Get<bool?>("dictationEnabled") ?? true;
        dictationShortcutEnabled = store.Get<bool?>("dictationShortcutEnabled") ?? true;
        dictationShortcut = Shortcut.Saved(store.Get<int?>("dictationShortcutKeyCode"), store.Get<int?>("dictationShortcutModifiers"), Shortcut.Dictation);
        dictationHoldToTalk = store.Get<bool?>("dictationHoldToTalk") ?? false;
        var model = store.Get<string>("dictationModel");
        dictationModel = string.IsNullOrWhiteSpace(model) ? Dictation.DefaultModel : model;
        dictationLanguage = Dictation.SpokenFrom(store.Get<string>("dictationLanguage")) ?? Dictation.Spoken.Auto;
        dictationCleanUp = store.Get<bool?>("dictationCleanUp") ?? true;
        dictationMaxSeconds = Math.Clamp(store.Get<int?>("dictationMaxSeconds") ?? Dictation.DefaultMaxSeconds, Dictation.MaxSecondsMin, Dictation.MaxSecondsMax);
        dictationPaste = store.Get<bool?>("dictationPaste") ?? false;
        dictationCreature = store.Get<bool?>("dictationCreature") ?? true;
        dictationHelper = store.Get<string>("dictationHelper") ?? "";
    }

    /// <summary>Dictation. Off: no dictation shortcut is taken and the tray item goes.</summary>
    public bool DictationEnabled { get => dictationEnabled; set => Put(ref dictationEnabled, value, "dictationEnabled"); }
    public bool DictationShortcutEnabled { get => dictationShortcutEnabled; set => Put(ref dictationShortcutEnabled, value, "dictationShortcutEnabled"); }
    public Shortcut DictationShortcut { get => dictationShortcut; set => PutShortcut(ref dictationShortcut, value, "dictationShortcut"); }
    /// <summary>Record only while the shortcut is held down; let go and it is written down. Off: press to start, press again to stop.</summary>
    public bool DictationHoldToTalk { get => dictationHoldToTalk; set => Put(ref dictationHoldToTalk, value, "dictationHoldToTalk"); }
    /// <summary>The OpenRouter model that listens (one that takes audio in).</summary>
    public string DictationModel { get => dictationModel; set => Put(ref dictationModel, value, "dictationModel"); }
    /// <summary>The language it is spoken in, or <c>auto</c> for the model to hear.</summary>
    public Dictation.Spoken DictationLanguage
    {
        get => dictationLanguage;
        set { if (dictationLanguage == value) return; dictationLanguage = value; store.Set("dictationLanguage", value.Raw()); Raise(nameof(DictationLanguage)); }
    }
    /// <summary>Leave out filler words and stutters, add punctuation; in the same call.</summary>
    public bool DictationCleanUp { get => dictationCleanUp; set => Put(ref dictationCleanUp, value, "dictationCleanUp"); }
    /// <summary>The longest recording, in seconds; at the end it stops by itself and is written down.</summary>
    public int DictationMaxSeconds
    {
        get => dictationMaxSeconds;
        set => Put(ref dictationMaxSeconds, Math.Clamp(value, Dictation.MaxSecondsMin, Dictation.MaxSecondsMax), "dictationMaxSeconds");
    }
    /// <summary>The words are also pasted into the app that was in front (Ctrl+V pressed for you).</summary>
    public bool DictationPaste { get => dictationPaste; set => Put(ref dictationPaste, value, "dictationPaste"); }
    /// <summary>A creature leaps to the middle of the screen with a microphone while it listens.</summary>
    public bool DictationCreature { get => dictationCreature; set => Put(ref dictationCreature, value, "dictationCreature"); }
    /// <summary>Which character holds the microphone, by name; empty: any free one, by chance.</summary>
    public string DictationHelper { get => dictationHelper; set => Put(ref dictationHelper, value, "dictationHelper"); }

    /// <summary>Why the dictation shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string DictationShortcutProblem
    {
        get => dictationShortcutProblem;
        set { if (dictationShortcutProblem == value) return; dictationShortcutProblem = value; Raise(nameof(DictationShortcutProblem)); }
    }
}
