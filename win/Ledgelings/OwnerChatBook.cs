using Ledgelings.Core;

namespace Ledgelings;

/// <summary>What the creatures remember of chatting with the owner (SPEC §7.18), as the app sees it:
/// <c>owner-chats.json</c> beside the bonds, loaded once, saved whenever it changes, announced so the page can follow.</summary>
public sealed class OwnerChatBook
{
    public OwnerChat.Store Store { get; }
    public OwnerChat.Book Book { get; private set; }
    public event Action? Changed;

    public OwnerChatBook(string? directory = null)
    {
        Store = new OwnerChat.Store(directory ?? AppFolders.Root);
        Book = Store.Load();
    }

    public string File => Store.File;

    public OwnerChat.Memory? MemoryOf(string name) => Book.MemoryOf(name);

    public void Change(Action<OwnerChat.Book> edit)
    {
        edit(Book);
        try { Store.Save(Book); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings owner chats: " + e.Message); }
        Changed?.Invoke();
    }

    public void Forget(string name) => Change(b => b.Forget(name));
    public void ForgetAll() => Change(b => b.ForgetAll());
}
