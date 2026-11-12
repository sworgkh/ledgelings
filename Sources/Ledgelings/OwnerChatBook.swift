import AppKit
import Combine
import LedgelingsCore

/// What the creatures remember of chatting with the owner (§7.18.2), as the app
/// sees it: `owner-chats.json` beside the bonds, loaded once, saved whenever it
/// changes, published so the settings page can follow along.
@MainActor
final class OwnerChatBook: ObservableObject {
    let store: OwnerChat.Store
    @Published private(set) var book: OwnerChat.Book

    init(directory: URL = SpendLedger.defaultDirectory) {
        store = OwnerChat.Store(directory: directory)
        book = store.load()
    }

    var file: URL { store.file }

    func memory(of name: String) -> OwnerChat.Memory? { book.memory(of: name) }

    @discardableResult
    func change<T>(_ edit: (inout OwnerChat.Book) -> T) -> T {
        let out = edit(&book)
        do { try store.save(book) } catch {
            FileHandle.standardError.write(Data("Ledgelings owner chats: \(error)\n".utf8))
        }
        return out
    }

    func forget(_ name: String) { change { $0.forget(name) } }
    func forgetAll() { change { $0.forgetAll() } }
}
