using System.Diagnostics;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The chat log as the app sees it: a folder under %APPDATA%, a counter that
/// ticks whenever something is written so a view can refresh, and the two ways of
/// opening the folder.</summary>
public sealed class ChatHistory
{
    public ChatLog Log { get; }
    /// <summary>Goes up by one for every exchange written; observe it to reload.</summary>
    public int Version { get; private set; }
    public event Action? Changed;

    public ChatHistory(string? directory = null) { Log = new ChatLog(directory ?? AppFolders.Chats); }

    public string Directory => Log.Directory;

    public void Record(ChatLog.Exchange exchange)
    {
        try
        {
            Log.Append(exchange);
            Version += 1;
            Changed?.Invoke();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings chat log: " + e.Message);
        }
    }

    public List<string> Days() { try { return Log.Days(); } catch (IOException) { return new List<string>(); } }
    public List<ChatLog.Exchange> Exchanges(string day) { try { return Log.Exchanges(day); } catch (IOException) { return new List<ChatLog.Exchange>(); } }

    /// <summary>Make sure the folder exists before handing it to another app.</summary>
    private string Prepared()
    {
        System.IO.Directory.CreateDirectory(Directory);
        return Directory;
    }

    public void RevealInExplorer() => Shell.OpenFolder(Prepared());

    public void OpenInTerminal() => Shell.OpenTerminal(Prepared());
}

/// <summary>Handing folders and files to Explorer and the terminal.</summary>
public static class Shell
{
    private static void Start(ProcessStartInfo info)
    {
        try { Process.Start(info); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { Console.Error.WriteLine(e.Message); }
    }

    public static void OpenFolder(string path) => Start(new ProcessStartInfo("explorer.exe", "\"" + path + "\"") { UseShellExecute = false });

    public static void RevealFile(string file) => Start(new ProcessStartInfo("explorer.exe", "/select,\"" + file + "\"") { UseShellExecute = false });

    /// <summary>Windows Terminal when it is installed, else a plain command prompt, in <paramref name="directory"/>.</summary>
    public static void OpenTerminal(string directory)
    {
        try { Process.Start(new ProcessStartInfo("wt.exe", "-d \"" + directory + "\"") { UseShellExecute = true }); return; }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { }
        Start(new ProcessStartInfo("cmd.exe", "/K cd /d \"" + directory + "\"") { UseShellExecute = true });
    }

    public static void OpenUrl(string url) => Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
