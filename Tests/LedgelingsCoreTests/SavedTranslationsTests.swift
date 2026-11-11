import Foundation
import Testing
@testable import LedgelingsCore

/// Saved translations (§7.14.2): the star's rules, the drawer's search and order,
/// the file, and which side the drawer opens on.
@Suite struct SavedTranslationsTests {
    typealias T = Translate
    let day0 = Date(timeIntervalSince1970: 1_800_000_000)

    func entry(_ text: String, _ translation: String = "x", from: String = "en", to: String = "ru", at minutes: Double = 0, app: String? = nil) -> T.Saved {
        T.Saved(text: text, from: from, translation: translation, to: to, savedAt: day0.addingTimeInterval(minutes * 60), app: app)
    }

    @Test func savingAndUnsaving() {
        var book = T.SavedBook()
        let on = book.toggle(entry("Good morning", "Доброе утро"), limit: 500)
        #expect(on)
        #expect(book.count == 1 && book.find(text: "Good morning", from: "en", to: "ru")?.translation == "Доброе утро")
        let again = book.toggle(entry("Good morning", "Доброе утро", at: 1), limit: 500)
        #expect(!again, "pressed again: removed")
        #expect(book.isEmpty)
    }

    @Test func theSameTextAndPairIsSavedOnce() {
        var book = T.SavedBook()
        book.save(entry("Good morning", "Доброе утро", app: "Notes"), limit: 500)
        let id = book.entries[0].id
        book.save(entry("  Good morning\n", "С добрым утром", at: 5), limit: 500)
        #expect(book.count == 1, "the edges of the text do not count")
        #expect(book.entries[0].id == id && book.entries[0].translation == "С добрым утром" && book.entries[0].app == "Notes")
        #expect(book.entries[0].savedAt == day0.addingTimeInterval(300), "it moves to the top with its new date")
        book.save(entry("Good morning", "בוקר טוב", to: "he", at: 6), limit: 500)
        book.save(entry("good morning", "Доброе утро", at: 7), limit: 500)
        #expect(book.count == 3, "another target, or other capitals, is another entry")
    }

    @Test func theOldestBeyondTheCapAreDropped() {
        var book = T.SavedBook()
        for i in 0..<60 { book.save(entry("text \(i)", at: Double(i)), limit: 50) }
        #expect(book.count == 50)
        #expect(book.entries.first?.text == "text 59" && book.entries.last?.text == "text 10")
        book.prune(limit: 20)
        #expect(book.count == 20 && book.entries.last?.text == "text 40")
    }

    @Test func newestFirst() {
        let book = T.SavedBook(entries: [entry("b", at: 2), entry("a", at: 1), entry("c", at: 3)])
        #expect(book.entries.map(\.text) == ["c", "b", "a"])
        var more = book
        more.save(entry("d", at: 0), limit: 500)
        #expect(more.entries.first?.text == "d", "the one saved last goes on top")
    }

    @Test func searchLooksInBothTexts() {
        var book = T.SavedBook()
        book.save(entry("Can you send me the report?", "Можешь прислать мне отчёт?", at: 1), limit: 500)
        book.save(entry("אני אגיע מאוחר היום", "I'll be late today", from: "he", to: "en", at: 2), limit: 500)
        book.save(entry("Ещё раз", "Once again", from: "ru", to: "en", at: 3), limit: 500)
        #expect(book.search("REPORT").map(\.text) == ["Can you send me the report?"], "the text, in any case")
        #expect(book.search("отчет").count == 1, "the translation, ё as е")
        #expect(book.search("late").first?.from == "he")
        #expect(book.search("мне send").count == 1, "every word, in either text")
        #expect(book.search("nothing like it").isEmpty)
        #expect(book.search("  ").count == 3, "blank: all of them, newest first")
        #expect(book.search("").map(\.text).first == "Ещё раз")
    }

    @Test func theFileSurvivesAReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("saved-translations-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = T.SavedStore(directory: dir)
        #expect(store.load().isEmpty, "no file yet")
        var book = T.SavedBook()
        book.save(entry("Good morning", "Доброе утро", at: 1, app: "Safari"), limit: 500)
        book.save(entry("שלום", "Hello", from: "he", to: "en", at: 2), limit: 500)
        try store.save(book)
        #expect(store.file.lastPathComponent == "translations.json")
        let again = store.load()
        #expect(again == book)
        #expect(again.entries.first?.text == "שלום" && again.entries.last?.app == "Safari")
        try Data("not json".utf8).write(to: store.file)
        #expect(store.load().isEmpty, "an unreadable file is an empty book, not a crash")
    }

    @Test func theDrawerOpensOnTheRightUnlessThereIsNoRoom() {
        #expect(T.DrawerSide.side(paperMinX: 400, paperWidth: 760, drawerWidth: 350, room: 1728) == .right)
        #expect(T.DrawerSide.side(paperMinX: 900, paperWidth: 760, drawerWidth: 350, room: 1728) == .left, "the right edge of the monitor is near")
        #expect(T.DrawerSide.side(paperMinX: 100, paperWidth: 760, drawerWidth: 350, room: 1000) == .right, "no room either side: the right")
    }

    @Test func aPairTagAndADate() {
        #expect(entry("x", from: "he", to: "en").pair == "HE → EN")
        Language.$override.withValue(.english) {
            #expect(T.savedDate(day0, now: day0) == "15 Jan")
            #expect(T.savedDate(day0, now: day0.addingTimeInterval(400 * 86_400)) == "15 Jan 2027")
        }
    }

    @Test func theLimitsAreChosen() {
        #expect(T.defaultSavedLimit == 500 && T.savedLimitRange == 50...5_000)
    }
}
