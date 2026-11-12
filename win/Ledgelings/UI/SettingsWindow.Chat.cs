using System.Windows;
using System.Windows.Controls;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Talk › Chat with you (SPEC §7.18): the shortcut, how they answer, and what they remember of you with its
/// Forget buttons. The Mac's <c>ChatSettingsView.swift</c>, one column.</summary>
public sealed partial class SettingsWindow
{
    private sealed record LengthChoice(OwnerChat.Length Length, string Title);
    private OwnerChatBook? ownerChats;

    private void InitChat()
    {
        ChatLengthBox.ItemsSource = Enum.GetValues<OwnerChat.Length>().Select(l => new LengthChoice(l, l.Title())).ToList();
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ChatShortcut) or nameof(AppSettings.RecordingShortcut)) ShowChat();
            if (e.PropertyName is nameof(AppSettings.Language))
            {
                ChatLengthBox.ItemsSource = Enum.GetValues<OwnerChat.Length>().Select(l => new LengthChoice(l, l.Title())).ToList();
                ChatLengthBox.SelectedValue = settings.ChatLength;
                ShowChatMemory();
            }
        };
        ShowChat();
    }

    /// <summary>Hand the page the memory it shows and forgets. Called by the app, once per window.</summary>
    public void AttachOwnerChats(OwnerChatBook book)
    {
        if (ReferenceEquals(ownerChats, book)) return;
        ownerChats = book;
        book.Changed += () => Dispatcher.BeginInvoke(ShowChatMemory);
        IsVisibleChanged += (_, _) => { if (IsVisible) ShowChatMemory(); };
        ShowChatMemory();
    }

    private void ShowChat()
    {
        ChatShortcutButton.Content = settings.RecordingShortcut && recordingButton == ChatShortcutButton
            ? L10n.Tr("Press the keys…") : ShortcutKeys.Label(settings.ChatShortcut);
    }

    private void ShowChatMemory()
    {
        var names = ownerChats?.Book.Names ?? Array.Empty<string>();
        var chosen = ChatWhoBox.SelectedItem as string;
        ChatWhoBox.ItemsSource = names;
        ChatWhoBox.SelectedItem = chosen is not null && names.Contains(chosen) ? chosen : names.FirstOrDefault();
        ChatWhoBox.IsEnabled = ChatForgetButton.IsEnabled = ChatForgetAllButton.IsEnabled = names.Count > 0;
        ShowChosenMemory();
    }

    private void ShowChosenMemory()
    {
        if (ownerChats is null || ChatWhoBox.SelectedItem is not string name || ownerChats.MemoryOf(name) is not { } m)
        {
            ChatMemoryText.Text = L10n.Tr("Nobody remembers a talk with you yet.");
            return;
        }
        ChatMemoryText.Text = L10n.Tr("%@ kept, summary: %@", L10n.TrCount(m.Exchanges.Count, "exchange", "exchanges"), m.Summary ?? L10n.Tr("none yet"));
    }

    private void ChatWho_Changed(object sender, SelectionChangedEventArgs e) => ShowChosenMemory();

    private void ChatForget_Click(object sender, RoutedEventArgs e)
    {
        if (ChatWhoBox.SelectedItem is string name) ownerChats?.Forget(name);
    }

    private void ChatForgetAll_Click(object sender, RoutedEventArgs e) => ownerChats?.ForgetAll();

    private void ChatShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        Record(ChatShortcutButton, made => settings.ChatShortcut = made);
        ShowChat();
    }
}
