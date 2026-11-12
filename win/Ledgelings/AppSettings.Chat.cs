using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Chat with the creatures (SPEC §7.18): the Mac's keys and defaults, Ctrl+Alt+C.</summary>
public sealed partial class AppSettings
{
    private bool chatEnabled, chatShortcutEnabled, chatSpeak, chatBubbles, chatRemember;
    private Shortcut chatShortcut;
    private int chatEveryone, chatMemoryExchanges;
    private OwnerChat.Length chatLength;
    private string chatShortcutProblem = "";

    private void LoadChat()
    {
        chatEnabled = store.Get<bool?>("chatEnabled") ?? true;
        chatShortcutEnabled = store.Get<bool?>("chatShortcutEnabled") ?? true;
        chatShortcut = Shortcut.Saved(store.Get<int?>("chatShortcutKeyCode"), store.Get<int?>("chatShortcutModifiers"), Shortcut.Chat);
        chatEveryone = Math.Clamp(store.Get<int?>("chatEveryone") ?? OwnerChat.DefaultEveryone, OwnerChat.EveryoneMin, OwnerChat.EveryoneMax);
        chatLength = OwnerChat.LengthNamed(store.Get<string>("chatLength")) ?? OwnerChat.Length.Short;
        chatSpeak = store.Get<bool?>("chatSpeak") ?? true;
        chatBubbles = store.Get<bool?>("chatBubbles") ?? true;
        chatRemember = store.Get<bool?>("chatRemember") ?? true;
        chatMemoryExchanges = Math.Clamp(store.Get<int?>("chatMemoryExchanges") ?? OwnerChat.DefaultExchanges, OwnerChat.ExchangesMin, OwnerChat.ExchangesMax);
    }

    /// <summary>Chat with the creatures. Off: no shortcut, no tray item, no Creature Actions button, the tile greyed.</summary>
    public bool ChatEnabled { get => chatEnabled; set => Put(ref chatEnabled, value, "chatEnabled"); }
    public bool ChatShortcutEnabled { get => chatShortcutEnabled; set => Put(ref chatShortcutEnabled, value, "chatShortcutEnabled"); }
    /// <summary>Opens the chat window from any app.</summary>
    public Shortcut ChatShortcut { get => chatShortcut; set => PutShortcut(ref chatShortcut, value, "chatShortcut"); }
    /// <summary>How many answer a message to everyone, one after another.</summary>
    public int ChatEveryone { get => chatEveryone; set => Put(ref chatEveryone, Math.Clamp(value, OwnerChat.EveryoneMin, OwnerChat.EveryoneMax), "chatEveryone"); }
    public OwnerChat.Length ChatLength
    {
        get => chatLength;
        set { if (chatLength == value) return; chatLength = value; store.Set("chatLength", value.Code()); Raise(nameof(ChatLength)); }
    }
    /// <summary>Answers are said out loud in each one's voice, when voice is on.</summary>
    public bool ChatSpeak { get => chatSpeak; set => Put(ref chatSpeak, value, "chatSpeak"); }
    /// <summary>Answers show in a bubble over the creature too, and dots while it thinks.</summary>
    public bool ChatBubbles { get => chatBubbles; set => Put(ref chatBubbles, value, "chatBubbles"); }
    /// <summary>Each keeps its talks with the owner, and they go into its next answer.</summary>
    public bool ChatRemember { get => chatRemember; set => Put(ref chatRemember, value, "chatRemember"); }
    /// <summary>How many past exchanges each keeps word for word.</summary>
    public int ChatMemoryExchanges { get => chatMemoryExchanges; set => Put(ref chatMemoryExchanges, Math.Clamp(value, OwnerChat.ExchangesMin, OwnerChat.ExchangesMax), "chatMemoryExchanges"); }

    /// <summary>Why the chat shortcut does nothing, when Windows refused it; empty while all is well. Not saved.</summary>
    public string ChatShortcutProblem
    {
        get => chatShortcutProblem;
        set { if (chatShortcutProblem == value) return; chatShortcutProblem = value; Raise(nameof(ChatShortcutProblem)); }
    }
}
