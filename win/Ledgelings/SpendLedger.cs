using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The spend file as the app sees it: <c>spend.jsonl</c> next to the chats, a summary
/// that refreshes whenever a call is recorded, and a way to open the file.</summary>
public sealed class SpendLedger
{
    public Spend.Ledger Ledger { get; }
    public Spend.Summary Summary { get; private set; } = new();
    public event Action? Changed;

    public SpendLedger(string? directory = null)
    {
        Ledger = new Spend.Ledger(directory ?? AppFolders.Root);
        Reload();
    }

    public string File => Ledger.File;

    /// <summary>One model call. A local server is free, so its cost is zero, not unknown.</summary>
    public void Record(ChatClient.Provider provider, string model, Spend.Usage usage, DateTimeOffset? time = null)
    {
        if (provider == ChatClient.Provider.LmStudio) usage.Cost = 0;
        try
        {
            Ledger.Append(new Spend.Record(time ?? DateTimeOffset.Now, ChatClient.Title(provider), model, usage));
            Reload();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings spend: " + e.Message);
        }
    }

    public void Reload()
    {
        try { Summary = Spend.Summarise(Ledger.Records()); } catch (IOException) { Summary = new Spend.Summary(); }
        Changed?.Invoke();
    }

    public void RevealInExplorer()
    {
        Directory.CreateDirectory(Ledger.Directory);
        if (System.IO.File.Exists(File)) Shell.RevealFile(File); else Shell.OpenFolder(Ledger.Directory);
    }
}
