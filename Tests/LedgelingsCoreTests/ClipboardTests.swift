import Foundation
import Testing
@testable import LedgelingsCore

/// SPEC §2.12: the clipboard history, the snippets, the search across both, what
/// is never kept, and Clipy's XML.
@Suite struct ClipboardTests {
    typealias Clip = Clipboard.Clip
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func history(_ texts: [String]) -> Clipboard.History {
        var h = Clipboard.History()
        for (i, text) in texts.enumerated() { h.add(Clip(text: text, copiedAt: t0.addingTimeInterval(Double(i)))) }
        return h
    }

    // MARK: History

    @Test func newestComesFirst() {
        #expect(history(["a", "b", "c"]).clips.map(\.text) == ["c", "b", "a"])
    }

    @Test func copyingTheSameTextAgainMovesItUpAndKeepsItsPin() {
        var h = history(["a", "b"])
        let a = h.clips[1].id
        h.togglePin(a)
        h.add(Clip(text: "a", copiedAt: t0.addingTimeInterval(10)))
        #expect(h.clips.map(\.text) == ["a", "b"])
        #expect(h.clips[0].id == a)
        #expect(h.clips[0].pinned)
        #expect(h.clips[0].copiedAt == t0.addingTimeInterval(10))
    }

    @Test func blankCopiesAreNotKept() {
        var h = Clipboard.History()
        let added = h.add(Clip(text: "  \n\t", copiedAt: t0))
        #expect(!added)
        #expect(h.clips.isEmpty)
    }

    @Test func aHugeCopyIsCutAndHugeFormattingDropped() {
        var h = Clipboard.History()
        h.add(Clip(kind: .rich, text: String(repeating: "x", count: Clipboard.longestClip + 5),
                   rtf: Data(count: Clipboard.largestRTF + 1), copiedAt: t0))
        #expect(h.clips[0].text.count == Clipboard.longestClip)
        #expect(h.clips[0].rtf == nil)
        #expect(h.clips[0].kind == .text)
    }

    @Test func pruneKeepsTheNewestAndEveryPin() {
        var h = history(["1", "2", "3", "4", "5"])
        h.togglePin(h.clips[4].id)           // "1", the oldest
        h.prune(limit: 2, days: 0, now: t0)
        #expect(h.clips.map(\.text) == ["5", "4", "1"])
    }

    @Test func pruneForgetsClipsOlderThanTheDaysToKeep() {
        var h = Clipboard.History()
        h.add(Clip(text: "old", copiedAt: t0))
        h.add(Clip(text: "new", copiedAt: t0.addingTimeInterval(9 * 86_400)))
        h.prune(limit: 100, days: 7, now: t0.addingTimeInterval(10 * 86_400))
        #expect(h.clips.map(\.text) == ["new"])
        h.add(Clip(text: "older still", copiedAt: t0.addingTimeInterval(-86_400 * 300)))
        h.prune(limit: 100, days: 0, now: t0.addingTimeInterval(10 * 86_400))
        #expect(h.clips.count == 2)
    }

    @Test func clearAllKeepsPinsUnlessAskedNotTo() {
        var h = history(["a", "b", "c"])
        h.togglePin(h.clips[1].id)
        h.clear()
        #expect(h.clips.map(\.text) == ["b"])
        h.clear(pinnedToo: true)
        #expect(h.clips.isEmpty)
    }

    @Test func removeTakesOneClip() {
        var h = history(["a", "b"])
        h.remove(h.clips[0].id)
        #expect(h.clips.map(\.text) == ["a"])
    }

    @Test func previewFoldsWhitespaceAndCuts() {
        #expect(Clip(text: "  hello\n\n  world\t!", copiedAt: t0).preview() == "hello world !")
        #expect(Clip(text: "abcdefghij", copiedAt: t0).preview(5) == "abcd…")
        #expect(Clip(kind: .files, text: "/Users/me/a.txt\n/Users/me/b.png", copiedAt: t0).preview() == "a.txt, b.png")
    }

    // MARK: Snippets

    @Test func aProtectedSnippetNeverHoldsItsWords() {
        let s = Clipboard.Snippet(title: "Bank", text: "hunter2", protected: true)
        #expect(s.text.isEmpty)
        #expect(s.preview() == Clipboard.mask)
        var book = Clipboard.SnippetBook()
        let id = book.add(Clipboard.Snippet(title: "Bank", text: "x"))
        book.update(Clipboard.Snippet(id: id, title: "Bank", text: "hunter2", protected: true))
        #expect(book.snippet(id)?.text == "")
        #expect(book.snippet(id)?.secretAccount == "snippet.\(id.uuidString)")
    }

    @Test func addingToAnEmptyBookMakesAFolder() {
        var book = Clipboard.SnippetBook()
        book.add(Clipboard.Snippet(title: "Hi", text: "Hello!"))
        #expect(book.folders.count == 1)
        #expect(book.all.map(\.snippet.title) == ["Hi"])
    }

    @Test func snippetsMoveWithinAndAcrossFolders() {
        var book = Clipboard.SnippetBook()
        let f1 = book.addFolder("One"), f2 = book.addFolder("Two")
        let a = book.add(Clipboard.Snippet(title: "a"), to: f1)
        book.add(Clipboard.Snippet(title: "b"), to: f1)
        book.add(Clipboard.Snippet(title: "c"), to: f2)
        book.move(a, by: 1)
        #expect(book.folders[0].snippets.map(\.title) == ["b", "a"])
        book.move(a, by: 1)                    // past the end: first in the next folder
        #expect(book.folders[0].snippets.map(\.title) == ["b"])
        #expect(book.folders[1].snippets.map(\.title) == ["a", "c"])
        book.move(f2, by: -1)
        #expect(book.folders.map(\.title) == ["Two", "One"])
        book.renameFolder(f1, to: "Uno")
        #expect(book.folders[1].title == "Uno")
    }

    @Test func removingAFolderHandsBackItsSnippets() {
        var book = Clipboard.SnippetBook()
        let f = book.addFolder("F")
        book.add(Clipboard.Snippet(title: "a"), to: f)
        book.add(Clipboard.Snippet(title: "p", protected: true), to: f)
        let gone = book.remove(f)
        #expect(gone.map(\.title) == ["a", "p"])
        #expect(book.folders.isEmpty)
    }

    @Test func aSnippetShortcutMustBeUsable() {
        var s = Clipboard.Snippet(title: "a")
        #expect(s.shortcut == nil)
        s.shortcut = Shortcut(keyCode: 0, modifiers: [.control, .option])
        #expect(s.shortcut == Shortcut(keyCode: 0, modifiers: [.control, .option]))
        s.modifiers = Shortcut.Modifiers.shift.rawValue
        #expect(s.shortcut == nil)
    }

    // MARK: Search

    func book() -> Clipboard.SnippetBook {
        var book = Clipboard.SnippetBook()
        let work = book.addFolder("Work")
        book.add(Clipboard.Snippet(title: "Signature", text: "Best regards, Evgeny"), to: work)
        book.add(Clipboard.Snippet(title: "Bank PIN", text: "4321", protected: true), to: work)
        let home = book.addFolder("Home")
        book.add(Clipboard.Snippet(title: "Address", text: "12 Café Street"), to: home)
        return book
    }

    @Test func searchFindsAcrossHistoryAndSnippetsAtOnce() {
        var h = history(["meeting at the café", "invoice 42"])
        h.clips[1].app = "Mail"
        let found = Clipboard.search("cafe", history: h, snippets: book())
        #expect(found.clips.map(\.text) == ["meeting at the café"])
        #expect(found.snippets.map(\.title) == ["Address"])
    }

    @Test func everyWordMustMatchInAnyOrderAndCase() {
        let h = history(["Quarterly REPORT draft", "report final"])
        #expect(Clipboard.search("draft report", history: h, snippets: .init()).clips.map(\.text) == ["Quarterly REPORT draft"])
        #expect(Clipboard.search("mail", history: h, snippets: .init()).isEmpty)
    }

    @Test func aClipIsFoundByItsApp() {
        var h = history(["x"])
        h.clips[0].app = "Safari"
        #expect(Clipboard.search("safari", history: h, snippets: .init()).clips.count == 1)
    }

    @Test func snippetsMatchTitleFolderAndWordsButAProtectedOneOnlyItsTitle() {
        #expect(Clipboard.search("regards", history: .init(), snippets: book()).snippets.map(\.title) == ["Signature"])
        #expect(Clipboard.search("home", history: .init(), snippets: book()).snippets.map(\.title) == ["Address"])
        #expect(Clipboard.search("pin", history: .init(), snippets: book()).snippets.map(\.title) == ["Bank PIN"])
        #expect(Clipboard.search("4321", history: .init(), snippets: book()).snippets.isEmpty)
    }

    @Test func anEmptyQueryFindsEverythingPinnedFirst() {
        var h = history(["a", "b", "c"])
        h.togglePin(h.clips[2].id)
        let found = Clipboard.search("  ", history: h, snippets: book())
        #expect(found.clips.map(\.text) == ["a", "c", "b"])
        #expect(found.snippets.count == 3)
    }

    // MARK: What is never kept

    @Test func concealedAndTransientCopiesAreNotKept() {
        #expect(!Clipboard.shouldKeep(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], app: nil, excluded: []))
        #expect(!Clipboard.shouldKeep(types: ["org.nspasteboard.TransientType"], app: nil, excluded: []))
        #expect(!Clipboard.shouldKeep(types: ["ExcludeClipboardContentFromMonitorProcessing"], app: nil, excluded: []))
        #expect(Clipboard.shouldKeep(types: ["public.utf8-plain-text"], app: nil, excluded: []))
    }

    @Test func copiesInAnExcludedAppAreNotKept() {
        #expect(!Clipboard.shouldKeep(types: [], app: "com.1password.1password", excluded: Clipboard.defaultExcludedMacApps))
        #expect(!Clipboard.shouldKeep(types: [], app: "KEEPASSXC.EXE", excluded: Clipboard.defaultExcludedWindowsApps))
        #expect(Clipboard.shouldKeep(types: [], app: "com.apple.Safari", excluded: Clipboard.defaultExcludedMacApps))
    }

    // MARK: Files

    @Test func historyAndSnippetsSurviveARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Clipboard.Store(directory: dir)
        var h = history(["a", "b"])
        h.clips[0].rtf = Data("{\\rtf1 b}".utf8)
        h.clips[0].kind = .rich
        try store.save(h)
        let b = book()
        try store.save(b)
        #expect(store.loadHistory() == h)
        #expect(store.loadSnippets() == b)
        let json = try String(contentsOf: store.snippetsFile, encoding: .utf8)
        #expect(!json.contains("4321"))
    }

    @Test func aMissingOrBrokenFileIsAnEmptyHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Clipboard.Store(directory: dir)
        #expect(store.loadHistory().clips.isEmpty)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: store.historyFile)
        #expect(store.loadHistory().clips.isEmpty)
    }

    // MARK: Clipy

    static let clipyXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <folders>
      <folder>
        <title>Mail</title>
        <snippets>
          <snippet><title>Thanks</title><content>Thank you &amp; best,
    Evgeny</content></snippet>
          <snippet><title>Code</title><content><![CDATA[<b>bold</b>]]></content></snippet>
        </snippets>
      </folder>
      <folder><title>Empty</title><snippets/></folder>
    </folders>
    """

    @Test func clipyXMLComesIn() throws {
        let book = try Clipboard.importClipy(Data(Self.clipyXML.utf8))
        #expect(book.folders.map(\.title) == ["Mail", "Empty"])
        #expect(book.folders[0].snippets.map(\.title) == ["Thanks", "Code"])
        #expect(book.folders[0].snippets[0].text == "Thank you & best,\nEvgeny")
        #expect(book.folders[0].snippets[1].text == "<b>bold</b>")
    }

    @Test func somethingElseIsNotClipyXML() {
        #expect(throws: Clipboard.ClipyError.notClipyXML) { try Clipboard.importClipy(Data("<plist/>".utf8)) }
        #expect(throws: Clipboard.ClipyError.notClipyXML) { try Clipboard.importClipy(Data("not xml".utf8)) }
    }

    @Test func anExportReadsBackAndKeepsNoSecret() throws {
        var b = book()
        b.folders[0].snippets[0].text = "a < b & \"c\""
        let data = Clipboard.exportClipy(b)
        #expect(!String(decoding: data, as: UTF8.self).contains("4321"))
        let back = try Clipboard.importClipy(data)
        #expect(back.folders.map(\.title) == b.folders.map(\.title))
        #expect(back.all.map(\.snippet.title) == b.all.map(\.snippet.title))
        #expect(back.folders[0].snippets[0].text == "a < b & \"c\"")
        #expect(back.folders[0].snippets[1].text == "")
    }
}
