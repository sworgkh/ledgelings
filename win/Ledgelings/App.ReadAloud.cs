using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>
/// Read aloud from the outside (SPEC §7.16), the Mac's <c>ReadAloudController.swift</c>: Ctrl+Alt+Shift+R from any
/// app opens the sheet with the clipboard's text and reads it, the clipboard picker's rows read theirs (Ctrl+R), its
/// tile on the Tools screen, the tray's Read Aloud… and, while it reads, Stop Reading. Every call to a speech model is
/// priced on Costs as Read aloud.
/// </summary>
public sealed partial class App
{
    private ReadAloudPlayer? readAloudPlayer;
    private ReadAloudSheetController? readAloudSheet;
    private GlobalHotkey? readAloudKey;

    private void StartReadAloud()
    {
        if (settings is null || spend is null || voice is null || clipBook is null) return;
        readAloudPlayer = new ReadAloudPlayer(settings, spend, voice) { Describe = DescribeReader };
        readAloudSheet = new ReadAloudSheetController(settings, readAloudPlayer, clipBook, () => colony) { AllReaders = Readers };
        clipPicker?.UseReader(text => readAloudSheet?.Show(text, start: true), () => settings.ReadAloudEnabled && settings.ReadAloudPickerButton);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ReadAloudEnabled) or nameof(AppSettings.ReadAloudShortcutEnabled) or nameof(AppSettings.ReadAloudShortcut)
                or nameof(AppSettings.RecordingShortcut))
                HoldReadAloudKey();
            if (e.PropertyName == nameof(AppSettings.ReadAloudEnabled) && !settings.ReadAloudEnabled) { readAloudSheet?.Close(); readAloudPlayer?.Stop(); }
        };
        HoldReadAloudKey();
    }

    private void StopReadAloud()
    {
        readAloudKey?.Dispose();
        readAloudPlayer?.Stop();
    }

    /// <summary>The shortcut from any app, following the settings; none while a new shortcut is recorded.</summary>
    private void HoldReadAloudKey()
    {
        if (settings is null) return;
        readAloudKey?.Dispose();
        readAloudKey = null;
        var problem = "";
        if (settings.ReadAloudEnabled && settings.ReadAloudShortcutEnabled && !settings.RecordingShortcut)
        {
            var shortcut = settings.ReadAloudShortcut;
            GlobalHotkey? key = null;
            try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, OpenReadAloud); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (key is { IsRegistered: true }) readAloudKey = key;
            else
            {
                key?.Dispose();
                problem = L10n.Tr("Windows would not take %@: another app holds it. Record another.", ShortcutKeys.Label(shortcut));
            }
        }
        settings.ReadAloudShortcutProblem = problem;
    }

    /// <summary>The sheet with the clipboard's text, read at once; pressed again while up, it closes.</summary>
    private void OpenReadAloud()
    {
        if (settings is not { ReadAloudEnabled: true }) return;
        readAloudSheet?.Toggle();
    }

    /// <summary>The sheet up, never closed by it: the tray and the Tools screen.</summary>
    private void ShowReadAloud()
    {
        if (settings is not { ReadAloudEnabled: true } || readAloudSheet is null || readAloudSheet.IsUp) return;
        readAloudSheet.Toggle();
    }

    /// <summary>The tray's Read Aloud… line, under the translator's, and Stop Reading while a reading goes on.</summary>
    private void AddReadAloudItems(List<TrayIcon.Item> items)
    {
        if (settings is not { ReadAloudEnabled: true }) return;
        var keys = settings.ReadAloudShortcutEnabled ? "\t" + ShortcutKeys.Label(settings.ReadAloudShortcut) : "";
        items.Add(new TrayIcon.Item(L10n.Tr("Read Aloud…") + keys, ShowReadAloud));
        if (readAloudPlayer is { IsActive: true }) items.Add(new TrayIcon.Item(L10n.Tr("Stop Reading"), () => readAloudPlayer?.Stop()));
    }

    /// <summary>Every character there is, species by species in the library's order, each name once.</summary>
    private IReadOnlyList<string> Readers()
    {
        var names = new List<string>();
        if (settings is null || library is null) return names;
        foreach (var species in library.AllSpecies)
            foreach (var who in settings.CastOf(species.Name, library.Cast(species.Name)))
                if (!names.Contains(who.Name)) names.Add(who.Name);
        return names;
    }

    /// <summary>Who a character is, from whichever species' cast has it: for casting its voice.</summary>
    private (string Persona, string Kind)? DescribeReader(string name)
    {
        if (settings is null || library is null) return null;
        foreach (var species in library.AllSpecies)
            if (settings.CastOf(species.Name, library.Cast(species.Name)).FirstOrDefault(c => c.Name == name) is { } who)
                return (who.Persona, library.Kind(species.Name));
        return null;
    }

    /// <summary>The settings page's readers and Try it.</summary>
    private void AttachReadAloud(SettingsWindow window)
    {
        window.ReadAloudPlayer = readAloudPlayer;
        window.ReadAloudReaders = Readers;
    }
}
