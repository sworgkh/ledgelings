import AppKit
import Combine
import LedgelingsCore

/// The bonds as the app sees it: `bonds.json` next to the chats, loaded once,
/// saved whenever it changes, and published so the Bonds tab can follow along.
@MainActor
final class BondBook: ObservableObject {
    let store: Bonds.Store
    @Published private(set) var book: Bonds.Book

    init(directory: URL = SpendLedger.defaultDirectory) {
        store = Bonds.Store(directory: directory)
        book = store.load()
    }

    var file: URL { store.file }

    func bond(_ a: String, _ b: String) -> Bonds.Bond? { book.bond(a, b) }

    func change(_ edit: (inout Bonds.Book) -> Void) {
        edit(&book)
        do { try store.save(book) } catch {
            FileHandle.standardError.write(Data("Ledgelings bonds: \(error)\n".utf8))
        }
    }

    func forget(_ key: String) { change { $0.forget(key) } }
    func forgetAll() { change { $0 = Bonds.Book() } }

    func revealInFinder() {
        if FileManager.default.fileExists(atPath: file.path) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        else { try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true); NSWorkspace.shared.open(store.directory) }
    }
}
