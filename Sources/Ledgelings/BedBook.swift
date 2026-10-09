import Combine
import Foundation
import LedgelingsCore

/// Where each character likes to sleep, as the app sees it: `beds.json` next to
/// the chats, loaded once, saved on every change, and published so the Beds tab
/// can follow along.
@MainActor
final class BedBook: ObservableObject {
    let store: Beds.Store
    @Published private(set) var book: Beds.Book

    init(directory: URL = SpendLedger.defaultDirectory) {
        store = Beds.Store(directory: directory)
        book = store.load()
    }

    var file: URL { store.file }

    func spot(of name: String) -> Beds.Spot? { book.spots[name] }

    /// `name` slept the night at `point` (`Beds.Book.slept`).
    func slept(_ name: String, at point: CGPoint) { change { $0.slept(name, at: point) } }

    /// The user put `name`'s bed down at `point`.
    func moved(_ name: String, to point: CGPoint) { change { $0.moved(name, to: point) } }

    func forget(_ name: String? = nil) { change { $0.forget(name) } }

    private func change(_ edit: (inout Beds.Book) -> Void) {
        edit(&book)
        do { try store.save(book) } catch {
            FileHandle.standardError.write(Data("Ledgelings beds: \(error)\n".utf8))
        }
    }
}
