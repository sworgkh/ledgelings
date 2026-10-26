using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;
using T = Ledgelings.Core.Translate;

namespace Ledgelings;

/// <summary>
/// The translator from the outside (SPEC §7.14), the Mac's <c>TranslateController.swift</c>: Ctrl+Alt+T opens the
/// sheet, Ctrl+Alt+Shift+T translates the newest copy (in the sheet, or quietly onto the clipboard with a note by
/// the text cursor), the tray's Translate… item, and the clipboard picker's translate button. Every call is
/// priced on Costs as Translation, every guess as Autocomplete.
/// </summary>
public sealed partial class App
{
    private Translator? translator;
    private TranslateSheetController? translateSheet;
    private GlobalHotkey? translateKey, translateClipKey;

    private void StartTranslate()
    {
        if (settings is null || spend is null || clipBook is null) return;
        translator = new Translator(settings, spend);
        translateSheet = new TranslateSheetController(settings, translator, clipBook, () => colony);
        clipPicker?.UseTranslator(TranslateRow, (text, into) => translateSheet?.Show(text, into), () => settings.TranslateEnabled && settings.TranslatePickerButton);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.TranslateEnabled) or nameof(AppSettings.TranslateShortcutEnabled) or nameof(AppSettings.TranslateShortcut)
                or nameof(AppSettings.TranslateClipShortcutEnabled) or nameof(AppSettings.TranslateClipShortcut) or nameof(AppSettings.RecordingShortcut))
                HoldTranslateKeys();
        };
        HoldTranslateKeys();
    }

    private void StopTranslate()
    {
        translateKey?.Dispose();
        translateClipKey?.Dispose();
    }

    /// <summary>Both shortcuts from any app, following the settings; none while a new shortcut is recorded.</summary>
    private void HoldTranslateKeys()
    {
        if (settings is null) return;
        translateKey?.Dispose();
        translateClipKey?.Dispose();
        translateKey = translateClipKey = null;
        var refused = new List<string>();
        GlobalHotkey? Take(Shortcut shortcut, Action pressed)
        {
            GlobalHotkey? key = null;
            try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, pressed); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (key is { IsRegistered: true }) return key;
            key?.Dispose();
            refused.Add(ShortcutKeys.Label(shortcut));
            return null;
        }
        if (settings.TranslateEnabled && !settings.RecordingShortcut)
        {
            if (settings.TranslateShortcutEnabled) translateKey = Take(settings.TranslateShortcut, OpenTranslate);
            if (settings.TranslateClipShortcutEnabled) translateClipKey = Take(settings.TranslateClipShortcut, TranslateLastCopy);
        }
        settings.TranslateShortcutProblem = refused.Count == 0 ? ""
            : L10n.Tr("Windows would not take %@: another app holds it. Record another.", string.Join(", ", refused));
    }

    /// <summary>The sheet, empty; pressed again while up, it closes.</summary>
    private void OpenTranslate()
    {
        if (settings is not { TranslateEnabled: true }) return;
        translateSheet?.Toggle();
    }

    /// <summary>The tray's Translate… line, under the dictation's.</summary>
    private void AddTranslateItems(List<TrayIcon.Item> items)
    {
        if (settings is not { TranslateEnabled: true }) return;
        var keys = settings.TranslateShortcutEnabled ? "\t" + ShortcutKeys.Label(settings.TranslateShortcut) : "";
        items.Add(new TrayIcon.Item(L10n.Tr("Translate…") + keys, () => translateSheet?.Show()));
    }

    // MARK: The last copy

    /// <summary>The newest text copy: into the sheet, already translated, or quietly onto the clipboard.</summary>
    private void TranslateLastCopy()
    {
        if (settings is not { TranslateEnabled: true } || clipBook is null) return;
        var caret = Caret();
        if (T.Newest(clipBook.History, clipBook.Snippets) is not { } clip)
        {
            ClipToast.Show(T.Refusal.NotText.Line(), caret);
            return;
        }
        if (settings.TranslateClipMode == T.ClipMode.Sheet) translateSheet?.Show(clip.Text);
        else Quietly(clip.Text, caret).ContinueWith(t => ClipToast.Show(new Translator.Trouble(Translator.TroubleKind.Network, t.Exception?.GetBaseException().Message ?? "").Line, caret),
                                                     CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.FromCurrentSynchronizationContext());
    }

    private static Win32.RECT? Caret()
    {
        var front = ClipboardNative.GetForegroundWindow();
        return front == IntPtr.Zero ? null : ClipboardNative.Caret(front);
    }

    /// <summary>No sheet: the translation replaces the clipboard, a note by the text cursor says so.</summary>
    private async Task Quietly(string text, Win32.RECT? caret)
    {
        if (settings is null || translator is null || clipBook is null) return;
        var on = settings.TranslateLanguagesOn;
        if (T.Detect(T.Protect(text).Text, on) is not { } source) { ClipToast.Show(T.Refusal.NothingToTranslate.Line(), caret); return; }
        var target = T.Target(source, settings.TranslateTargets, on);
        translator.Refresh();
        var (done, trouble) = await translator.Translate(text, source, target);
        if (done is null) { ClipToast.Show(trouble?.Line ?? "", caret); return; }
        ClipPaster.Put(new ClipPaster.Item(done.Text), plain: true);
        TranslateSheetController.KeepInHistory(done.Text, clipBook, settings);
        ClipToast.Show(L10n.Tr("In %@ on the clipboard: Ctrl+V pastes it", target.Title), caret);
    }

    // MARK: For the clipboard picker

    /// <summary>A row's translation into its "goes into" language, or the next one after <paramref name="after"/>
    /// (Ctrl+Tab); the target with it, or the reason there is none.</summary>
    private async Task<(T.Lang? Target, string? Text, string? Trouble)> TranslateRow(string text, T.Lang? after)
    {
        if (settings is null || translator is null) return (null, null, null);
        var on = settings.TranslateLanguagesOn;
        if (T.Detect(T.Protect(text).Text, on) is not { } source) return (null, null, T.Refusal.NothingToTranslate.Line());
        var target = T.Target(source, settings.TranslateTargets, on);
        if (after is not null && on.ToList().IndexOf(after) is var at and >= 0)
            target = on.Skip(at + 1).FirstOrDefault(l => l != source) ?? on.FirstOrDefault(l => l != source) ?? target;
        translator.Refresh();
        if (!translator.HasModel) return (target, null, new Translator.Trouble(Translator.TroubleKind.NoModel).Line);
        var (done, trouble) = await translator.Translate(text, source, target);
        return (target, done?.Text, trouble?.Line);
    }
}
