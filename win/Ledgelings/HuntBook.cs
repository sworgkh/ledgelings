using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The cursor's hunts as the app sees it: <c>hunts.json</c> next to the spend file, loaded once,
/// saved on every count, and announced so the Chases tab can follow along.</summary>
public sealed class HuntBook
{
    public Hunts.Store Store { get; }
    public Hunts.Book Book { get; private set; }
    public event Action? Changed;
    /// <summary>The user's wall clock, time zone and first day of the week; tests set them.</summary>
    public Func<DateTimeOffset> Now { get; set; } = () => DateTimeOffset.Now;
    public Hunts.Clock Clock { get; set; } = Hunts.Clock.Local;

    public HuntBook(string? directory = null)
    {
        Store = new Hunts.Store(directory ?? AppFolders.Root);
        Book = Store.Load();
    }

    public string File => Store.File;

    /// <summary>One more hunt of <paramref name="name"/>; its numbers afterwards.</summary>
    public Hunts.Numbers Count(string name)
    {
        Change(b => b.Count(name, Now(), Clock));
        return NumbersOf(name);
    }

    public Hunts.Numbers NumbersOf(string name) => Book.NumbersOf(name, Now(), Clock);
    public Hunts.Numbers Total => Book.Total(Now(), Clock);

    public void Reset(string? name = null) => Change(b => b.Reset(name));

    private void Change(Action<Hunts.Book> edit)
    {
        edit(Book);
        try { Store.Save(Book); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings hunts: " + e.Message); }
        Changed?.Invoke();
    }

    public void RevealInExplorer()
    {
        if (System.IO.File.Exists(File)) Shell.RevealFile(File);
        else { Directory.CreateDirectory(Store.Directory); Shell.OpenFolder(Store.Directory); }
    }
}
