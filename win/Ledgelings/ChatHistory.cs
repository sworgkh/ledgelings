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

    /// <summary>What each character said lately, from every exchange written, and at
    /// launch from the last days on disk, so a relaunch does not reset it.</summary>
    public LineMemory Memory { get; private set; } = new(0);

    public ChatHistory(string? directory = null) { Log = new ChatLog(directory ?? AppFolders.Chats); }

    /// <summary>Remember <paramref name="limit"/> lines per character; the first call reads them back from disk.</summary>
    public void Remember(int limit)
    {
        if (limit == Memory.Limit) return;
        if (limit < Memory.Limit) { Memory.Trim(limit); return; }
        Memory = new LineMemory(limit);
        foreach (var day in Days().Take(2).Reverse())
            foreach (var exchange in Exchanges(day)) Memory.Remember(exchange);
    }

    public string Directory => Log.Directory;

    public void Record(ChatLog.Exchange exchange)
    {
        try
        {
            Log.Append(exchange);
            Memory.Remember(exchange);
            Version += 1;
            Changed?.Invoke();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings chat log: " + e.Message);
        }
    }

    public void RecordVoice(ChatLog.VoiceCharge charge)
    {
        try
        {
            Log.AppendVoice(charge);
            Version += 1;
            Changed?.Invoke();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings chat log: " + e.Message);
        }
    }

    public Dictionary<int, ChatLog.VoiceTotal> VoiceTotals(string day, IReadOnlyList<ChatLog.Exchange> exchanges)
    {
        try { return ChatLog.VoiceTotals(Log.VoiceCharges(day), exchanges); }
        catch (IOException) { return new Dictionary<int, ChatLog.VoiceTotal>(); }
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
