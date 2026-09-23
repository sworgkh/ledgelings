using System.Windows;
using System.Windows.Media;
using Ledgelings.Core;
using Microsoft.Win32;

namespace Ledgelings.UI;

/// <summary>Settings › Talk › Brain › Built-in lines: the script itself, what is wrong with it
/// if anything, and the ways to get more of it.</summary>
public sealed partial class SettingsWindow
{
    private string? scriptNotice;

    private void RefreshScriptStatus()
    {
        if (ScriptStatus is null) return;
        if (scriptNotice is string notice) { ScriptStatus.Text = notice; ScriptStatus.Foreground = Brushes.Gray; return; }
        try
        {
            var c = Script.Parse(settings.Script).Conversations;
            ScriptStatus.Text = $"{c.Count} conversations, {c.Count(x => x.Tags.Contains("flower"))} with a flower, {c.Count(x => x.Tags.Contains("night"))} at night";
            ScriptStatus.Foreground = Brushes.Gray;
        }
        catch (Script.ParseException e)
        {
            ScriptStatus.Text = e.Message + "; the creatures stay quiet until this is fixed";
            ScriptStatus.Foreground = Brushes.Firebrick;
        }
    }

    /// <summary>Show a message in place of the status for a few seconds.</summary>
    private async void Flash(string text)
    {
        scriptNotice = text;
        RefreshScriptStatus();
        await Task.Delay(6000);
        if (scriptNotice == text) { scriptNotice = null; RefreshScriptStatus(); }
    }

    /// <summary>Everyone who could be talking right now, for the agent prompt.</summary>
    private List<Character> CastInUse()
    {
        var seen = new List<Character>();
        foreach (var species in settings.Species.Distinct())
            foreach (var member in settings.CastOf(species, library.Cast(species)))
                if (!seen.Contains(member)) seen.Add(member);
        return seen;
    }

    private void ScriptImport_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Title = "Lines to use, in the built-in format", Filter = "Text (*.txt)|*.txt|All files|*.*" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            settings.Script = File.ReadAllText(dialog.FileName);
            Flash("imported " + Path.GetFileName(dialog.FileName));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Flash($"could not read {Path.GetFileName(dialog.FileName)}: {ex.Message}");
        }
    }

    private void ScriptExport_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { FileName = "ledgelings-lines.txt", Filter = "Text (*.txt)|*.txt" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            File.WriteAllText(dialog.FileName, settings.Script);
            Flash("saved " + Path.GetFileName(dialog.FileName));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Flash("could not save: " + ex.Message);
        }
    }

    private async void CopyAgentPrompt_Click(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(Script.AgentPrompt(CastInUse())); }
        catch (System.Runtime.InteropServices.COMException) { Flash("the clipboard is busy; try again"); return; }
        CopyAgentPrompt.Content = "Copied";
        await Task.Delay(2000);
        CopyAgentPrompt.Content = "Copy Agent Prompt";
    }

    private void ScriptReset_Click(object sender, RoutedEventArgs e) => settings.ResetScript();
}
