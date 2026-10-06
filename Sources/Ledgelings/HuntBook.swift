import Combine
import Foundation
import LedgelingsCore

/// The cursor's hunts as the app sees it: `hunts.json` next to the chats,
/// loaded once, saved on every count, and published so the Chases tab can
/// follow along.
@MainActor
final class HuntBook: ObservableObject {
    let store: Hunts.Store
    @Published private(set) var book: Hunts.Book
    /// The user's wall clock and calendar; tests set them.
    var now: () -> Date = Date.init
    var calendar = Calendar.current

    init(directory: URL = SpendLedger.defaultDirectory) {
        store = Hunts.Store(directory: directory)
        book = store.load()
    }

    var file: URL { store.file }

    /// One more hunt of `name`; its numbers afterwards.
    @discardableResult
    func count(_ name: String) -> Hunts.Numbers {
        change { $0.count(name, at: now(), calendar: calendar) }
        return numbers(of: name)
    }

    func numbers(of name: String) -> Hunts.Numbers { book.numbers(of: name, at: now(), calendar: calendar) }
    var total: Hunts.Numbers { book.total(at: now(), calendar: calendar) }

    func reset(_ name: String? = nil) { change { $0.reset(name) } }

    private func change(_ edit: (inout Hunts.Book) -> Void) {
        edit(&book)
        do { try store.save(book) } catch {
            FileHandle.standardError.write(Data("Ledgelings hunts: \(error)\n".utf8))
        }
    }
}
