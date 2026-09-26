import AppKit
import Combine
import LedgelingsCore

/// The user's reminders, kept in `reminders.json` beside the chats and the
/// spend file, saved on every change.
@MainActor
final class ReminderBook: ObservableObject {
    let store: Reminders.Store
    @Published private(set) var book: Reminders.Book

    init(directory: URL = SpendLedger.defaultDirectory) {
        store = Reminders.Store(directory: directory)
        book = store.load()
    }

    var file: URL { store.file }

    func change(_ edit: (inout Reminders.Book) -> Void) {
        edit(&book)
        do { try store.save(book) } catch {
            FileHandle.standardError.write(Data("Ledgelings reminders: \(error)\n".utf8))
        }
    }

    func add(_ text: String, at time: Date, repeats: Reminders.Repeat) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        change { $0.add(Reminders.Reminder(text: words, time: time, repeats: repeats)) }
    }

    func remove(_ id: UUID) { change { $0.remove(id) } }
    func clearFinished() { change { $0.clearFinished() } }
    func markSent(_ id: UUID, at now: Date) { change { $0.markSent(id, at: now) } }
}
