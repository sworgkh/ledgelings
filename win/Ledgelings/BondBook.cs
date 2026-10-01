using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The bonds as the app sees it: <c>bonds.json</c> next to the spend file, loaded once,
/// saved whenever it changes, and announced so the Bonds tab can follow along.</summary>
public sealed class BondBook
{
    public Bonds.Store Store { get; }
    public Bonds.Book Book { get; private set; }
    public event Action? Changed;

    public BondBook(string? directory = null)
    {
        Store = new Bonds.Store(directory ?? AppFolders.Root);
        Book = Store.Load();
    }

    public string File => Store.File;

    public Bonds.Bond? Bond(string a, string b) => Book.Bond(a, b);

    public void Change(Action<Bonds.Book> edit)
    {
        edit(Book);
        try { Store.Save(Book); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings bonds: " + e.Message); }
        Changed?.Invoke();
    }

    public void Forget(string key) => Change(b => b.Forget(key));
    public void ForgetAll() => Change(b => b.Bonds.Clear());

    public void RevealInExplorer()
    {
        if (System.IO.File.Exists(File)) Shell.RevealFile(File);
        else { Directory.CreateDirectory(Store.Directory); Shell.OpenFolder(Store.Directory); }
    }
}
