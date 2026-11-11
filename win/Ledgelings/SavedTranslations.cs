using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The saved translations (SPEC §7.14.3), the Mac's <c>SavedTranslations.swift</c>: kept in
/// <c>translations.json</c> beside the clipboard history and saved on every change.</summary>
public sealed class SavedTranslations
{
    public Translate.SavedStore Store { get; }
    public Translate.SavedBook Book { get; }
    /// <summary>Saved, removed or cleared.</summary>
    public event Action? Changed;

    public SavedTranslations(string? directory = null)
    {
        Store = new Translate.SavedStore(directory ?? AppFolders.Root);
        Book = Store.Load();
    }

    public void Change(Action<Translate.SavedBook> edit)
    {
        edit(Book);
        try { Store.Save(Book); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings: saved translations not saved: " + e.Message); }
        Changed?.Invoke();
    }

    /// <summary>The star: saved when it was not, removed when it was. True when it is saved now.</summary>
    public bool Toggle(Translate.Saved entry, int limit)
    {
        var now = false;
        Change(b => now = b.Toggle(entry, limit));
        return now;
    }

    public void Remove(Guid id) => Change(b => b.Remove(id));
    public void Clear() => Change(b => b.Clear());

    public void Prune(int limit)
    {
        if (Book.Count > limit) Change(b => b.Prune(limit));
    }
}
