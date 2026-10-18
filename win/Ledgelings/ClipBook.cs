using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>The clipboard history and the snippets, kept in <c>clipboard.json</c> and <c>snippets.json</c> beside
/// the chats, saved on every change: the Mac's files. A protected snippet's words are kept in Credential
/// Manager, one generic credential per snippet under <c>Ledgelings Snippets/snippet.&lt;id&gt;</c>.</summary>
public sealed class ClipBook
{
    public const string SecretService = "Ledgelings Snippets";
    public Clipboard.Store Store { get; }
    private readonly ISecretStore secrets;
    public Clipboard.History History { get; }
    public Clipboard.SnippetBook Snippets { get; }
    /// <summary>The history or the snippets changed.</summary>
    public event Action? Changed;

    public ClipBook(string? directory = null, ISecretStore? secrets = null)
    {
        Store = new Clipboard.Store(directory ?? AppFolders.Root);
        this.secrets = secrets ?? new CredentialStore(SecretService);
        History = Store.LoadHistory();
        Snippets = Store.LoadSnippets();
    }

    // MARK: History

    public void ChangeHistory(Action<Clipboard.History> edit)
    {
        edit(History);
        try { Store.Save(History); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Complain(e); }
        Changed?.Invoke();
    }

    /// <summary>A new copy, then the limits applied.</summary>
    public void Add(Clipboard.Clip clip, int limit, int days) => ChangeHistory(h => { h.Add(clip); h.Prune(limit, days, clip.CopiedAt); });

    /// <summary>A clip pasted from the picker goes back to the top, as copying it again would.</summary>
    public void Bump(Guid id, DateTimeOffset? now = null)
    {
        if (History.Clips.FirstOrDefault(c => c.Id == id) is not { } clip) return;
        ChangeHistory(h => h.Add(clip with { CopiedAt = now ?? DateTimeOffset.Now }));
    }

    public void TogglePin(Guid id) => ChangeHistory(h => h.TogglePin(id));
    public void Remove(Guid id) => ChangeHistory(h => h.Remove(id));
    public void ClearHistory(bool pinnedToo = false) => ChangeHistory(h => h.Clear(pinnedToo));

    // MARK: Snippets

    public void ChangeSnippets(Action<Clipboard.SnippetBook> edit)
    {
        edit(Snippets);
        try { Store.Save(Snippets); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Complain(e); }
        Changed?.Invoke();
    }

    public Guid AddFolder(string title)
    {
        var id = Guid.Empty;
        ChangeSnippets(b => id = b.AddFolder(title));
        return id;
    }

    /// <summary>A snippet; a protected one's words go to Credential Manager, never into the book.</summary>
    public Guid AddSnippet(string title, string text, bool isProtected = false, Guid? folder = null)
    {
        var snippet = Clipboard.Snippet.Make(title, text, isProtected);
        if (isProtected) secrets.Set(snippet.SecretAccount, text);
        ChangeSnippets(b => b.Add(snippet, folder));
        return snippet.Id;
    }

    /// <summary>Saves an edit. A protected snippet's words, when given, go to Credential Manager.</summary>
    public void Update(Clipboard.Snippet snippet, string? secret = null)
    {
        if (snippet.Protected && secret is not null) secrets.Set(snippet.SecretAccount, secret);
        ChangeSnippets(b => b.Update(snippet));
    }

    /// <summary>Protected on: the words move into Credential Manager. Off: they come back into the book.</summary>
    public void SetProtected(Guid id, bool isProtected)
    {
        if (Snippets.Find(id) is not { } snippet || snippet.Protected == isProtected) return;
        if (isProtected)
        {
            secrets.Set(snippet.SecretAccount, snippet.Text);
            snippet = snippet with { Protected = true, Text = "" };
        }
        else
        {
            snippet = snippet with { Protected = false, Text = secrets.Get(snippet.SecretAccount) ?? "" };
            secrets.Set(snippet.SecretAccount, null);
        }
        ChangeSnippets(b => b.Update(snippet));
    }

    public void RenameFolder(Guid id, string title) => ChangeSnippets(b => b.RenameFolder(id, title));
    public void Move(Guid id, int step) => ChangeSnippets(b => b.Move(id, step));

    /// <summary>A folder or a snippet goes, and with it the secrets of every protected snippet in it.</summary>
    public void RemoveSnippetOrFolder(Guid id)
    {
        var gone = new List<Clipboard.Snippet>();
        ChangeSnippets(b => gone = b.Remove(id));
        foreach (var s in gone.Where(s => s.Protected)) secrets.Set(s.SecretAccount, null);
    }

    /// <summary>The words to paste: the book's, or Credential Manager's for a protected snippet.</summary>
    public string Words(Clipboard.Snippet snippet) => snippet.Protected ? secrets.Get(snippet.SecretAccount) ?? "" : snippet.Text;

    // MARK: Files

    public int ImportClipy(string file)
    {
        var read = Clipboard.ImportClipy(File.ReadAllText(file));
        ChangeSnippets(b => b.Merge(read));
        return read.All.Count();
    }

    public void ExportClipy(string file) => File.WriteAllText(file, Clipboard.ExportClipy(Snippets), new System.Text.UTF8Encoding(false));

    private static void Complain(Exception e) => Console.Error.WriteLine("Ledgelings clipboard: " + e.Message);
}
