using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The user's reminders, kept in <c>reminders.json</c> beside the chats and the
/// spend file, saved on every change. Same file as the Mac's.</summary>
public sealed class ReminderBook
{
    public Reminders.Store Store { get; }
    public Reminders.Book Book { get; private set; }
    /// <summary>The book changed: a reminder added, removed, sent or cleared.</summary>
    public event Action? Changed;

    public ReminderBook(string? directory = null)
    {
        Store = new Reminders.Store(directory ?? AppFolders.Root);
        Book = Store.Load();
    }

    public string File => Store.File;

    public void Change(Action<Reminders.Book> edit)
    {
        edit(Book);
        try { Store.Save(Book); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Ledgelings reminders: " + e.Message);
        }
        Changed?.Invoke();
    }

    public void Add(string text, DateTimeOffset time, Reminders.Repeat repeats)
    {
        var words = text.Trim();
        if (words.Length == 0) return;
        Change(b => b.Add(new Reminders.Reminder(words, time, repeats)));
    }

    public void Remove(Guid id) => Change(b => b.Remove(id));
    public void ClearFinished() => Change(b => b.ClearFinished());
    public void MarkSent(Guid id, DateTimeOffset now) => Change(b => b.MarkSent(id, now));

    public void RevealInExplorer()
    {
        Directory.CreateDirectory(Store.Directory);
        if (System.IO.File.Exists(File)) Shell.RevealFile(File); else Shell.OpenFolder(Store.Directory);
    }
}
