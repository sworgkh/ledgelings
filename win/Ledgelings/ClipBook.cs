using Ledgelings.Core;
using Ledgelings.Native;

namespace Ledgelings;

/// <summary>The clipboard history and the snippets, kept in <c>clipboard.json</c> and <c>snippets.json</c> beside
/// the chats, saved on every change: the Mac's files; a copied picture's bytes in <c>clipboard-images</c> there, deleted
/// when its clip goes. A protected snippet's words are kept in Credential
/// Manager, one generic credential per snippet under <c>Ledgelings Snippets/snippet.&lt;id&gt;</c>; the book keeps a salted
/// fingerprint of them, so a copy of those words in the history is shown masked without reading Credential Manager.</summary>
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
        Store.SweepImages(History);
        FingerprintOldSecrets();
    }

    /// <summary>Protected snippets saved before fingerprints were kept get theirs, once: their words read from Credential Manager.</summary>
    private void FingerprintOldSecrets()
    {
        var old = Snippets.All.Select(x => x.Snippet).Where(s => s.Protected && s.SecretHash is null).ToList();
        if (old.Count == 0) return;
        ChangeSnippets(b => { foreach (var s in old) b.Update(s.Sealed(secrets.Get(s.SecretAccount))); });
    }

    // MARK: History

    public void ChangeHistory(Action<Clipboard.History> edit)
    {
        var pictures = Pictures();
        edit(History);
        try { Store.Save(History); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Complain(e); }
        // A picture pruned, forgotten or cleared takes its files with it.
        var left = Pictures();
        if (!pictures.IsSubsetOf(left))
        {
            Store.SweepImages(History);
            foreach (var id in thumbnails.Keys.Where(id => !left.Contains(id)).ToList()) thumbnails.Remove(id);
        }
        Changed?.Invoke();
    }

    private HashSet<Guid> Pictures() => History.Clips.Where(c => c.Kind == Clipboard.Kind.Image).Select(c => c.Id).ToHashSet();

    /// <summary>A copied picture: its bytes written beside the history (unless the same picture is there already, which
    /// only moves to the top), then the clip, then the limits.</summary>
    public void AddImage(Clipboard.Clip clip, IReadOnlyList<(string Type, byte[] Data)> kinds, int limit, int days)
    {
        if (!History.Clips.Any(c => c.Kind == Clipboard.Kind.Image && c.Picture?.Digest == clip.Picture?.Digest))
        {
            try { Store.SaveImage(clip.Id, kinds); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Complain(e); return; }
        }
        Add(clip, limit, days);
    }

    /// <summary>A picture clip's bytes, in the formats it was copied as.</summary>
    public List<(string Type, byte[] Data)> ImageData(Clipboard.Clip clip) => Store.LoadImage(clip);

    private readonly Dictionary<Guid, System.Windows.Media.Imaging.BitmapSource> thumbnails = new();
    /// <summary>Longest side of a picture's thumbnail, in pixels: drawn twice as big, square pixels.</summary>
    public const int ThumbnailPixels = 20;

    /// <summary>A picture clip's thumbnail, a few pixels across, made once from its best file.</summary>
    public System.Windows.Media.Imaging.BitmapSource? Thumbnail(Clipboard.Clip clip)
    {
        if (clip.Kind != Clipboard.Kind.Image || clip.Picture is not { Types.Count: > 0 } picture) return null;
        if (thumbnails.TryGetValue(clip.Id, out var made)) return made;
        try
        {
            var type = picture.Types[0];
            var bytes = File.ReadAllBytes(Store.ImageFile(clip.Id, type));
            if (type == "DeviceIndependentBitmap") bytes = Clipboard.DibAsBmp(bytes);
            var image = new System.Windows.Media.Imaging.BitmapImage();
            image.BeginInit();
            image.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
            image.StreamSource = new MemoryStream(bytes);
            if (picture.Width >= picture.Height) image.DecodePixelWidth = Math.Min(ThumbnailPixels, Math.Max(picture.Width, 1));
            else image.DecodePixelHeight = Math.Min(ThumbnailPixels, Math.Max(picture.Height, 1));
            image.EndInit();
            image.Freeze();
            return thumbnails[clip.Id] = image;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or NotSupportedException or ArgumentException or InvalidOperationException
                                      or System.IO.FileFormatException)
        {
            return null;
        }
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
        if (isProtected) { secrets.Set(snippet.SecretAccount, text); snippet = snippet.Sealed(text); }
        ChangeSnippets(b => b.Add(snippet, folder));
        return snippet.Id;
    }

    /// <summary>Saves an edit. A protected snippet's words, when given, go to Credential Manager.</summary>
    public void Update(Clipboard.Snippet snippet, string? secret = null)
    {
        if (snippet.Protected && secret is not null) { secrets.Set(snippet.SecretAccount, secret); snippet = snippet.Sealed(secret); }
        ChangeSnippets(b => b.Update(snippet));
    }

    /// <summary>Protected on: the words move into Credential Manager. Off: they come back into the book.</summary>
    public void SetProtected(Guid id, bool isProtected)
    {
        if (Snippets.Find(id) is not { } snippet || snippet.Protected == isProtected) return;
        if (isProtected)
        {
            secrets.Set(snippet.SecretAccount, snippet.Text);
            snippet = snippet.Sealed(snippet.Text) with { Protected = true, Text = "" };
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
