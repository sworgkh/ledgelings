using Ledgelings.Core;
using Ledgelings.UI;

namespace Ledgelings;

/// <summary>
/// Chat with the creatures from the outside (SPEC §7.18): Ctrl+Alt+C from any app, the tray's Chat with the
/// Creatures…, its tile on the Tools screen and C on Creature Actions. Every answer is priced on Costs as Chat with you.
/// <c>LEDGELINGS_FAKE_CHAT=1</c>: hand-written answers, no key, no network.
/// </summary>
public sealed partial class App
{
    private ChatController? chat;
    private GlobalHotkey? chatKey;

    private void StartChat()
    {
        if (settings is null) return;
        chat = new ChatController(settings, () => colony) { OpenSettings = page => OpenSettings(page) };
        if (Environment.GetEnvironmentVariable("LEDGELINGS_FAKE_CHAT") is { Length: > 0 }) chat.Fake = FakeChat;
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ChatEnabled) or nameof(AppSettings.ChatShortcutEnabled) or nameof(AppSettings.ChatShortcut)
                or nameof(AppSettings.RecordingShortcut))
                HoldChatKey();
            if (e.PropertyName == nameof(AppSettings.ChatEnabled) && !settings.ChatEnabled) chat?.Close();
        };
        HoldChatKey();
    }

    /// <summary>The shortcut from any app, following the settings; none while a new shortcut is recorded.</summary>
    private void HoldChatKey()
    {
        if (settings is null) return;
        chatKey?.Dispose();
        chatKey = null;
        var problem = "";
        if (settings.ChatEnabled && settings.ChatShortcutEnabled && !settings.RecordingShortcut)
        {
            var shortcut = settings.ChatShortcut;
            GlobalHotkey? key = null;
            try { key = new GlobalHotkey(ShortcutKeys.Win32Modifiers(shortcut.Modifiers), (uint)shortcut.KeyCode, () => { if (settings.ChatEnabled) chat?.Toggle(); }); }
            catch (InvalidOperationException e) { Console.Error.WriteLine("Ledgelings hotkey: " + e.Message); }
            if (key is { IsRegistered: true }) chatKey = key;
            else
            {
                key?.Dispose();
                problem = L10n.Tr("Windows would not take %@: another app holds it. Record another.", ShortcutKeys.Label(shortcut));
            }
        }
        settings.ChatShortcutProblem = problem;
    }

    /// <summary>The window up, never closed by it: the tray, the Tools screen and Creature Actions.</summary>
    private void ShowChat()
    {
        if (settings is not { ChatEnabled: true } || chat is null || chat.IsUp) return;
        chat.Show();
    }

    /// <summary>The tray's Chat with the Creatures… line, with its shortcut.</summary>
    private void AddChatItem(List<TrayIcon.Item> items)
    {
        if (settings is not { ChatEnabled: true }) return;
        var keys = settings.ChatShortcutEnabled ? "\t" + ShortcutKeys.Label(settings.ChatShortcut) : "";
        items.Add(new TrayIcon.Item(L10n.Tr("Chat with the Creatures…") + keys, ShowChat));
    }

    /// <summary>Stand-in answers, each in its character's manner, reacting to the one before when there is one.</summary>
    private static string FakeChat(string name, string message, IReadOnlyList<(string Name, string Text)> earlier)
    {
        var topic = string.Join(" ", message.Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(4));
        var before = earlier.Count > 0 ? earlier[^1].Name : null;
        return name switch
        {
            "Blocky" => before is null ? $"\"{topic}\"? Fine. As long as the cursor stays off my edge." : $"{before} is wrong, as usual. I'd rather glare at the cursor.",
            "Zed" => $"Mm… {topic}… sounds nice… can we talk about it after a nap…",
            "Unit 7" => $"Message received: {message.Length} characters. Joy level: 7 of 10.",
            _ => before is null ? $"Hello! \"{topic}\": I'll think about that on my edge." : $"Like {before} said, more or less. But mostly: hello!",
        };
    }
}
