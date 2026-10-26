using System.Diagnostics;
using System.Windows.Threading;
using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;
using Clipboard = Ledgelings.Core.Clipboard;

namespace Ledgelings;

/// <summary>
/// Dictation from the outside (SPEC §7.13), the Mac's <c>DictationController.swift</c>: the shortcut (and the tray
/// item) start and stop a recording here; the audio goes to the chosen OpenRouter model, the words come back onto
/// the clipboard and into the clipboard history, pasted into the app in front when asked, and every call is priced.
/// A creature holds the microphone while it listens; without one, a toast says how it went.
///
/// Windows' hot keys say only when they are pressed, so holding to talk watches the key itself every tick.
/// </summary>
public sealed partial class App
{
    private GlobalHotkey? dictationKey;
    private GlobalHotkey? dictationEscape, dictationEnter;
    private readonly Dictation.Recorder dictationRecorder = new();
    private DictationRecorder? microphone;
    private DispatcherTimer? dictationClock;
    private readonly Stopwatch dictationWatch = Stopwatch.StartNew();
    private double dictationLastTick;
    /// <summary>The window in front when it started: the words are pasted back into it.</summary>
    private IntPtr dictationFront;

    private double DictationNow => dictationWatch.Elapsed.TotalSeconds;
    private bool IsDictating => dictationRecorder.IsRecording;

    private void StartDictation()
    {
        if (settings is null) return;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.DictationEnabled) or nameof(AppSettings.DictationShortcutEnabled)
                or nameof(AppSettings.DictationShortcut) or nameof(AppSettings.RecordingShortcut))
                HoldDictationKey();
        };
        HoldDictationKey();
    }

    private void StopDictation()
    {
        dictationKey?.Dispose();
        TakeDictationKeys(false);
        microphone?.Dispose();
    }

    /// <summary>The shortcut from any app, following the settings; none while a new shortcut is recorded.</summary>
    private void HoldDictationKey()
    {
        if (settings is null) return;
        dictationKey?.Dispose();
        dictationKey = null;
        var problem = "";
        if (settings.DictationEnabled && settings.DictationShortcutEnabled && !settings.RecordingShortcut)
        {
            var shortcut = settings.DictationShortcut;
            GlobalHotkey? key = null;
            try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, DictationPress); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (key is { IsRegistered: true }) dictationKey = key;
            else
            {
                key?.Dispose();
                problem = L10n.Tr("Windows would not take %@: another app holds it. Record another.", ShortcutKeys.Label(shortcut));
            }
        }
        settings.DictationShortcutProblem = problem;
    }

    /// <summary>The tray's dictation line, under the clipboard's.</summary>
    private void AddDictationItems(List<TrayIcon.Item> items)
    {
        if (settings is not { DictationEnabled: true }) return;
        var keys = settings.DictationShortcutEnabled ? "\t" + ShortcutKeys.Label(settings.DictationShortcut) : "";
        items.Add(new TrayIcon.Item((IsDictating ? L10n.Tr("Stop Dictating") : L10n.Tr("Dictate")) + keys, DictationPress));
    }

    // Pressing

    /// <summary>The shortcut or the tray: starts, or (pressed again) stops and sends.</summary>
    private void DictationPress()
    {
        if (settings is null) return;
        switch (dictationRecorder.Press(DictationNow, settings.DictationHoldToTalk))
        {
            case Dictation.Step.Start: DictationBegin(); break;
            case Dictation.Step.Send send: DictationSend(send.Seconds); break;
            case Dictation.Step.Discard discard: DictationDiscard(discard.TooShort); break;
        }
    }

    private void DictationEnter()
    {
        switch (dictationRecorder.Enter(DictationNow))
        {
            case Dictation.Step.Send send: DictationSend(send.Seconds); break;
            case Dictation.Step.Discard discard: DictationDiscard(discard.TooShort); break;
        }
    }

    /// <summary>Esc while listening: nothing is sent.</summary>
    private void DictationCancel()
    {
        if (dictationRecorder.Cancel() is not Dictation.Step.Discard) return;
        StopListening();
        colony?.DictationGoHome();
    }

    // Listening

    private void DictationBegin()
    {
        if (settings is null) return;
        dictationFront = ClipboardNative.GetForegroundWindow();
        if (settings.OpenRouterKey.Trim().Length == 0) { dictationRecorder.Done(); DictationFail(new(Dictation.TroubleKind.NoKey)); return; }
        var made = new DictationRecorder();
        try { made.Start(); }
        catch (DictationRecorder.Failure e)
        {
            made.Dispose();
            dictationRecorder.Done();
            DictationFail(new(e.NoMicrophone ? Dictation.TroubleKind.NoMicrophone : Dictation.TroubleKind.MicrophoneRefused));
            return;
        }
        microphone = made;
        dictationRecorder.MaxSeconds = settings.DictationMaxSeconds;
        TakeDictationKeys(true);
        if (settings.DictationCreature) colony?.DictationCome();
        dictationLastTick = DictationNow;
        dictationClock = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        dictationClock.Tick += (_, _) => DictationTick();
        dictationClock.Start();
    }

    private void DictationTick()
    {
        if (settings is null || microphone is null) return;
        var now = DictationNow;
        var dt = now - dictationLastTick;
        dictationLastTick = now;
        microphone.Collect();
        colony?.DictationHear(microphone.Level, dictationRecorder.Seconds(now), dt);
        // Holding to talk: the key let go is the end of it.
        if (settings.DictationHoldToTalk && (Win32.GetAsyncKeyState(settings.DictationShortcut.KeyCode) & 0x8000) == 0)
        {
            switch (dictationRecorder.Release(now, hold: true))
            {
                case Dictation.Step.Send send: DictationSend(send.Seconds); return;
                case Dictation.Step.Discard discard: DictationDiscard(discard.TooShort); return;
            }
        }
        if (dictationRecorder.Tick(now) is Dictation.Step.Send cut) DictationSend(cut.Seconds);
    }

    /// <summary>Esc and Enter, from every app, while it listens; let go after.</summary>
    private void TakeDictationKeys(bool on)
    {
        dictationEscape?.Dispose(); dictationEscape = null;
        dictationEnter?.Dispose(); dictationEnter = null;
        if (!on) return;
        try
        {
            dictationEscape = new GlobalHotkey(0, Win32.VK_ESCAPE, DictationCancel);
            dictationEnter = new GlobalHotkey(0, 0x0D, DictationEnter);
        }
        catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
    }

    private short[] StopListening()
    {
        dictationClock?.Stop();
        dictationClock = null;
        TakeDictationKeys(false);
        var samples = microphone?.Stop() ?? Array.Empty<short>();
        microphone?.Dispose();
        microphone = null;
        return samples;
    }

    private void DictationDiscard(bool tooShort)
    {
        StopListening();
        if (tooShort) DictationTell(new Dictation.Trouble(Dictation.TroubleKind.TooShort).Line, voiced: false);
        else colony?.DictationGoHome();
    }

    // Writing it down

    private void DictationSend(double seconds)
    {
        var samples = StopListening();
        var heard = (double)samples.Length / Dictation.SampleRate;
        if (heard < Dictation.Shortest) { dictationRecorder.Done(); DictationFail(new(Dictation.TroubleKind.TooShort)); return; }
        colony?.DictationThink();
        _ = DictationTranscribe(Dictation.Wav(samples), heard);
    }

    /// <summary>Sends a recording (a WAV) and delivers the words. The WAV lives only in this call: it is never written
    /// anywhere and is gone once it returns.</summary>
    private async Task DictationTranscribe(byte[] wav, double seconds)
    {
        if (settings is null || spend is null) return;
        var key = settings.OpenRouterKey.Trim();
        var model = settings.DictationModel.Trim();
        if (key.Length == 0) { dictationRecorder.Done(); DictationFail(new(Dictation.TroubleKind.NoKey)); return; }
        var client = ChatClient.OpenRouter(key, model);
        var instruction = Dictation.Instruction(settings.DictationLanguage, settings.DictationCleanUp);
        try
        {
            var answer = await client.Transcribe(wav, instruction, seconds);
            // Paid for whatever it says, empty or not.
            spend.Record(ChatClient.Provider.OpenRouter, model, answer.Usage ?? new Spend.Usage(0, 0, null), Spend.Purpose.Dictation);
            dictationRecorder.Done();
            var text = Dictation.Cleaned(answer.Text);
            if (text.Length == 0) { DictationFail(new(Dictation.TroubleKind.NothingHeard)); return; }
            DictationDeliver(text);
        }
        catch (ChatClient.Failure e)
        {
            dictationRecorder.Done();
            DictationFail(e.Refusal is string why ? new(Dictation.TroubleKind.Refused, why) : new(Dictation.TroubleKind.Network, e.Message));
        }
    }

    /// <summary>Onto the clipboard and into its history; into the app in front when asked.</summary>
    private void DictationDeliver(string text)
    {
        if (settings is null) return;
        // Marked as ours, so the watcher does not keep it a second time under another app's name.
        ClipPaster.Put(new ClipPaster.Item(text), plain: true);
        if (settings.ClipboardEnabled && settings.ClipHistoryEnabled)
            clipBook?.Add(new Clipboard.Clip { Text = text, CopiedAt = DateTimeOffset.Now, App = L10n.Tr("Dictation") },
                          settings.ClipHistoryLimit, settings.ClipKeepDays);
        if (settings.DictationPaste && dictationFront != IntPtr.Zero)
        {
            Win32.SetForegroundWindow(dictationFront);
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
            timer.Tick += (_, _) => { timer.Stop(); ClipboardNative.PressPaste(); };
            timer.Start();
        }
        DictationTell(Dictation.CopiedBubble(text), voiced: false);
    }

    private void DictationFail(Dictation.Trouble trouble) => DictationTell(trouble.Line, voiced: true);

    /// <summary>The creature says it when there is one (coming to say it, if it is not out yet); otherwise a toast.</summary>
    private void DictationTell(string text, bool voiced)
    {
        if (settings is { DictationCreature: true } && colony is not null && (colony.IsDictationHelping || colony.DictationCome()))
            colony.DictationTell(text, voiced);
        else
            ClipToast.Show(text, null);
    }
}
