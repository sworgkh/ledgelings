import Combine
import Foundation
import LedgelingsCore

/// The saved translations (§7.14.3), kept in `translations.json` beside the
/// clipboard history and saved on every change.
@MainActor
final class SavedTranslations: ObservableObject {
    let store: Translate.SavedStore
    @Published private(set) var book: Translate.SavedBook

    init(directory: URL = SpendLedger.defaultDirectory) {
        store = Translate.SavedStore(directory: directory)
        book = store.load()
    }

    func change(_ edit: (inout Translate.SavedBook) -> Void) {
        edit(&book)
        do { try store.save(book) } catch { NSLog("Ledgelings: saved translations not saved: \(error)") }
    }

    /// The star: saved when it was not, removed when it was. True when it is saved now.
    @discardableResult
    func toggle(_ entry: Translate.Saved, limit: Int) -> Bool {
        var now = false
        change { now = $0.toggle(entry, limit: limit) }
        return now
    }

    func remove(_ id: UUID) { change { $0.remove(id) } }
    func clear() { change { $0.clear() } }
    func prune(limit: Int) {
        guard book.count > limit else { return }
        change { $0.prune(limit: limit) }
    }
}
