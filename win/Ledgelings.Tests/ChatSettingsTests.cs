using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>Talk › Chat with you: its settings, the Mac's ChatSettingsTests (the colony-level talk is not ported: it
/// opens real overlay windows).</summary>
public sealed class ChatSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.ChatEnabled && s.ChatShortcutEnabled);
        Assert.Equal(Shortcut.Chat, s.ChatShortcut);
        Assert.Equal("Ctrl+Alt+C", ShortcutKeys.Label(s.ChatShortcut));
        Assert.Equal(3, s.ChatEveryone);
        Assert.Equal(OwnerChat.Length.Short, s.ChatLength);
        Assert.True(s.ChatSpeak && s.ChatBubbles && s.ChatRemember);
        Assert.Equal(10, s.ChatMemoryExchanges);

        s.ChatEnabled = false; s.ChatShortcutEnabled = false;
        s.ChatShortcut = new Shortcut(0x43, ShortcutModifiers.Control | ShortcutModifiers.Shift);
        s.ChatEveryone = 6; s.ChatLength = OwnerChat.Length.Long; s.ChatSpeak = false; s.ChatBubbles = false;
        s.ChatRemember = false; s.ChatMemoryExchanges = 25;
        var again = new AppSettings(store, secrets);
        Assert.False(again.ChatEnabled || again.ChatShortcutEnabled || again.ChatSpeak || again.ChatBubbles || again.ChatRemember);
        Assert.Equal(new Shortcut(0x43, ShortcutModifiers.Control | ShortcutModifiers.Shift), again.ChatShortcut);
        Assert.Equal(6, again.ChatEveryone);
        Assert.Equal(OwnerChat.Length.Long, again.ChatLength);
        Assert.Equal(25, again.ChatMemoryExchanges);
        Assert.Equal("long", store.Get<string>("chatLength"));                // the Mac's word
    }

    [Fact]
    public void NonsenseIsClampedOnLoad()
    {
        var store = new MemorySettingsStore();
        store.Set("chatEveryone", 40); store.Set("chatMemoryExchanges", -3); store.Set("chatLength", "epic");
        var s = new AppSettings(store, new MemorySecretStore());
        Assert.Equal(8, s.ChatEveryone);
        Assert.Equal(0, s.ChatMemoryExchanges);
        Assert.Equal(OwnerChat.Length.Short, s.ChatLength);
        s.ChatEveryone = 0; s.ChatMemoryExchanges = 500;
        Assert.Equal(1, s.ChatEveryone);
        Assert.Equal(50, s.ChatMemoryExchanges);
    }
}
