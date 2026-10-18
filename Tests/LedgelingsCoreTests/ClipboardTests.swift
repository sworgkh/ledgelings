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

    // MARK: Pictures

    func picture(_ digest: String, _ w: Int = 1280, _ h: Int = 720) -> Clipboard.Picture {
        Clipboard.Picture(width: w, height: h, bytes: 10, digest: digest, types: ["public.png"])
    }

    @Test func aPictureIsLabelledBySizeAndTheSamePictureMovesUp() {
        var h = history(["a"])
        h.add(.image(picture("one"), copiedAt: t0.addingTimeInterval(1), app: "Preview"))
        h.add(.image(picture("two"), copiedAt: t0.addingTimeInterval(2)))
        #expect(h.clips.count == 3, "two different pictures of the same size are two clips")
        #expect(h.clips[1].text == "Image 1280×720" && h.clips[1].kind == .image)
        let first = h.clips[1].id
        h.togglePin(first)
        var again = picture("one")
        again.types = ["public.png", "public.tiff"]
        h.add(.image(again, copiedAt: t0.addingTimeInterval(3)))
        #expect(h.clips.count == 3)
        #expect(h.clips[0].id == first && h.clips[0].pinned, "the same bytes: the same clip, its pin kept")
        #expect(h.clips[0].picture?.types == ["public.png"], "its files are the ones first kept")
    }

    @Test func aPictureIsFoundByImageAndByItsApp() {
        var h = history(["a picture of a cat"])
        h.add(.image(picture("p", 64, 40), copiedAt: t0.addingTimeInterval(1), app: "Preview"))
        Language.$override.withValue(.english) {
            #expect(Clipboard.search("image", history: h, snippets: .init()).clips.map(\.text) == ["Image 64×40"])
            #expect(Clipboard.search("preview 64", history: h, snippets: .init()).clips.count == 1)
            #expect(h.clips[0].preview() == "Image 64×40")
        }
        Language.$override.withValue(.russian) {
            #expect(h.clips[0].preview() == "Картинка 64×40")
            #expect(Clipboard.search("картинка", history: h, snippets: .init()).clips.count == 1)
            #expect(Clipboard.search("image", history: h, snippets: .init()).clips.count == 1, "the English word still finds it")
        }
    }

    @Test func picturesCountInTheLimit() {
        var h = history(["a", "b"])
        h.add(.image(picture("p"), copiedAt: t0.addingTimeInterval(5)))
        h.prune(limit: 2, days: 0, now: t0)
        #expect(h.clips.map(\.text) == ["Image 1280×720", "b"])
    }

    @Test func theTypesKeptFitTheCapBestFirst() {
        let found = ["public.png": 3_000_000, "public.tiff": 40_000_000, "public.jpeg": 1_000_000]
        #expect(Clipboard.keptImageTypes(found, cap: 20_000_000) == ["public.png", "public.jpeg"])
        #expect(Clipboard.keptImageTypes(found, cap: 50_000_000) == ["public.png", "public.jpeg", "public.tiff"])
        #expect(Clipboard.keptImageTypes(found, cap: 1_500_000) == ["public.jpeg"])
        #expect(Clipboard.keptImageTypes(found, cap: 500_000).isEmpty)
    }

    @Test func theDigestTellsBytesApart() {
        #expect(Clipboard.digest(Data([1, 2, 3])) == Clipboard.digest(Data([1, 2, 3])))
        #expect(Clipboard.digest(Data([1, 2, 3])) != Clipboard.digest(Data([1, 2, 4])))
    }

    @Test func picturesAreFilesBesideTheHistoryAndGoWithTheirClip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clip-images-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Clipboard.Store(directory: dir)
        var h = Clipboard.History()
        let clip = Clip.image(Clipboard.Picture(width: 2, height: 2, bytes: 6, digest: "d", types: ["public.png", "public.tiff"]), copiedAt: t0)
        h.add(clip)
        try store.saveImage(clip.id, [("public.png", Data([1, 2])), ("public.tiff", Data([3, 4, 5, 6]))])
        try store.save(h)
        let read = store.loadImage(store.loadHistory().clips[0])
        #expect(read.map(\.type) == ["public.png", "public.tiff"] && read.map(\.data) == [Data([1, 2]), Data([3, 4, 5, 6])])
        #expect(!(try String(contentsOf: store.historyFile, encoding: .utf8)).contains("AQI="), "no bytes in the JSON")
        store.sweepImages(keeping: h)
        #expect(store.loadImage(clip).count == 2, "a kept clip keeps its files")
        h.remove(clip.id)
        store.sweepImages(keeping: h)
        #expect(store.loadImage(clip).isEmpty)
        #expect((try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectory.path)).isEmpty)
    }

    @Test func anOldHistoryWithNoPicturesStillReads() throws {
        let json = #"{"clips":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"text","text":"hi","copiedAt":"2027-01-01T00:00:00Z","pinned":false}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let h = try decoder.decode(Clipboard.History.self, from: Data(json.utf8))
        #expect(h.clips[0].text == "hi" && h.clips[0].picture == nil)
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
