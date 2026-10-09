using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Where each character likes to sleep, as the app sees it: <c>beds.json</c> next to the spend
/// file, loaded once, saved on every change, and announced so the Beds tab can follow along.</summary>
public sealed class BedBook
{
    public Beds.Store Store { get; }
    public Beds.Book Book { get; private set; }
    public event Action? Changed;

    public BedBook(string? directory = null)
    {
        Store = new Beds.Store(directory ?? AppFolders.Root);
        Book = Store.Load();
    }

    public string File => Store.File;

    public Beds.Spot? SpotOf(string name) => Book.Spots.GetValueOrDefault(name);

    /// <summary><paramref name="name"/> slept the night at <paramref name="point"/> (<see cref="Beds.Book.Slept"/>).</summary>
    public void Slept(string name, Pt point) => Change(b => b.Slept(name, point));

    /// <summary>The user put <paramref name="name"/>'s bed down at <paramref name="point"/>.</summary>
    public void Moved(string name, Pt point) => Change(b => b.Moved(name, point));

    public void Forget(string? name = null) => Change(b => b.Forget(name));

    private void Change(Action<Beds.Book> edit)
    {
        edit(Book);
        try { Store.Save(Book); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings beds: " + e.Message); }
        Changed?.Invoke();
    }

    public void RevealInExplorer()
    {
        if (System.IO.File.Exists(File)) Shell.RevealFile(File);
        else { Directory.CreateDirectory(Store.Directory); Shell.OpenFolder(Store.Directory); }
    }
}
