using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The spend file as the app sees it: <c>spend.jsonl</c> next to the chats, a summary
/// that refreshes whenever a call is recorded, and a way to open the file.</summary>
public sealed class SpendLedger
{
    public Spend.Ledger Ledger { get; }
    public Spend.Summary Summary { get; private set; } = new();
    /// <summary>The latest calls, newest first, for the Costs tab.</summary>
    public IReadOnlyList<Spend.Record> Recent { get; private set; } = Array.Empty<Spend.Record>();
    public const int RecentCount = 200;
    public event Action? Changed;

    public SpendLedger(string? directory = null)
    {
        Ledger = new Spend.Ledger(directory ?? AppFolders.Root);
        Reload();
    }

    public string File => Ledger.File;

    /// <summary>One model call, and the feature that made it. A local server is free, so
    /// its cost is zero, not unknown. <paramref name="purpose"/> has no default on purpose: a new
    /// feature that calls a model must say which it is (see AGENTS.md).</summary>
    public void Record(ChatClient.Provider provider, string model, Spend.Usage usage, Spend.Purpose purpose, DateTimeOffset? time = null)
    {
        if (provider == ChatClient.Provider.LmStudio) usage.Cost = 0;
        try
        {
            Ledger.Append(new Spend.Record(time ?? DateTimeOffset.Now, ChatClient.Title(provider), model, usage, purpose));
            Reload();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings spend: " + e.Message);
        }
    }

    public void Reload()
    {
        try
        {
            var records = Ledger.Records();
            Summary = Spend.Summarise(records);
            Recent = Enumerable.Reverse(records.TakeLast(RecentCount)).ToList();
        }
        catch (IOException) { Summary = new Spend.Summary(); Recent = Array.Empty<Spend.Record>(); }
        Changed?.Invoke();
    }

    public void RevealInExplorer()
    {
        Directory.CreateDirectory(Ledger.Directory);
        if (System.IO.File.Exists(File)) Shell.RevealFile(File); else Shell.OpenFolder(Ledger.Directory);
    }
}
