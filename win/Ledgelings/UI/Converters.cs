using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Ledgelings.Core;

namespace Ledgelings.UI;

public enum SettingsTab { Creatures, Sprites, Talk, Flowers, Bonds, Calendar, Reminders, Voice, Costs, Chats }

/// <summary>Fills a TextBlock with a chat line: the speaker in bold, then the text with the
/// model's *marks* shown as italic and bold runs. <c>ui:StyledLine.Line="{Binding}"</c>.</summary>
public static class StyledLine
{
    public static readonly DependencyProperty LineProperty = DependencyProperty.RegisterAttached(
        "Line", typeof(ChatLog.Line), typeof(StyledLine), new PropertyMetadata(null, OnLineChanged));

    public static void SetLine(TextBlock block, ChatLog.Line? value) => block.SetValue(LineProperty, value);
    public static ChatLog.Line? GetLine(TextBlock block) => (ChatLog.Line?)block.GetValue(LineProperty);

    private static void OnLineChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not TextBlock block) return;
        block.Inlines.Clear();
        if (e.NewValue is not ChatLog.Line line) return;
        block.Inlines.Add(new Run(line.Speaker) { FontWeight = FontWeights.Bold });
        block.Inlines.Add(new Run(": "));
        foreach (var run in Banter.Styled(line.Text))
        {
            block.Inlines.Add(new Run(run.Text)
            {
                FontWeight = run.Bold ? FontWeights.Bold : FontWeights.Normal,
                FontStyle = run.Italic ? FontStyles.Italic : FontStyles.Normal,
            });
        }
    }
}
