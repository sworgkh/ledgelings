import AppKit
import Foundation
import LedgelingsCore
import LocalAuthentication
import Testing
@testable import Ledgelings

/// Productivity tools › Clipboard: its settings, the book keeping protected words
/// in the secret store only, the watcher leaving secrets and our own writes out,
/// and the picker's keys.
@MainActor
@Suite(.serialized) struct ClipboardSettingsTests {
    let name = "ledgelings-clipboard-settings-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        var items: [String: String] = [:]
        func get(_ account: String) -> String? { items[account] }
        func set(_ value: String?, for account: String) { items[account] = value?.isEmpty == false ? value : nil }
    }

    func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString)") }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.clipboardEnabled && s.clipHistoryEnabled && s.clipKeepFormatting && s.clipKeepFiles && s.clipAutoPaste)
        #expect(!s.clipPlainText && s.clipAnimate && s.clipSnippetShortcutsEnabled)
        #expect(s.clipHistoryLimit == 200 && s.clipKeepDays == 30 && s.clipAnimationSpeed == 1)
        #expect(s.clipKeepImages && s.clipLargestImageMB == 20)
        #expect(s.clipHistoryShortcutEnabled && s.clipHistoryShortcut == .clipHistory)
        #expect(s.clipSnippetsShortcutEnabled && s.clipSnippetsShortcut == .clipSnippets)
        #expect(s.clipExcludedApps == Clipboard.defaultExcludedMacApps)
        s.clipboardEnabled = false; s.clipHistoryEnabled = false; s.clipKeepFormatting = false; s.clipKeepFiles = false
        s.clipAutoPaste = false; s.clipPlainText = true; s.clipAnimate = false
        s.clipSnippetShortcutsEnabled = false; s.clipHistoryShortcutEnabled = false; s.clipSnippetsShortcutEnabled = false
        s.clipHistoryLimit = 50; s.clipKeepDays = 0; s.clipAnimationSpeed = 2
        s.clipKeepImages = false; s.clipLargestImageMB = 5
        s.clipHistoryShortcut = Shortcut(keyCode: 9, modifiers: [.command, .shift])
        s.clipSnippetsShortcut = Shortcut(keyCode: 1, modifiers: [.control])
        s.clipExcludedApps = ["com.example.vault"]
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.clipboardEnabled && !again.clipHistoryEnabled && !again.clipKeepFormatting && !again.clipKeepFiles)
        #expect(!again.clipAutoPaste && again.clipPlainText && !again.clipAnimate)
        #expect(!again.clipSnippetShortcutsEnabled && !again.clipHistoryShortcutEnabled && !again.clipSnippetsShortcutEnabled)
        #expect(again.clipHistoryLimit == 50 && again.clipKeepDays == 0 && again.clipAnimationSpeed == 2)
        #expect(!again.clipKeepImages && again.clipLargestImageMB == 5)
        #expect(again.clipHistoryShortcut == Shortcut(keyCode: 9, modifiers: [.command, .shift]))
        #expect(again.clipSnippetsShortcut == Shortcut(keyCode: 1, modifiers: [.control]))
        #expect(again.clipExcludedApps == ["com.example.vault"])
        defaults.set(5, forKey: "clipHistoryLimit"); defaults.set(9999, forKey: "clipKeepDays"); defaults.set(10.0, forKey: "clipAnimationSpeed")
        defaults.set(500, forKey: "clipLargestImageMB")
        defaults.set(Shortcut.Modifiers.shift.rawValue, forKey: "clipHistoryShortcutModifiers")
        let clamped = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(clamped.clipHistoryLimit == 10 && clamped.clipKeepDays == 365 && clamped.clipAnimationSpeed == 3, "clamped on load")
        #expect(clamped.clipLargestImageMB == 100, "clamped on load")
        #expect(clamped.clipHistoryShortcut == .clipHistory, "a shortcut with no Command, Control or Option is the standard one")
    }

    @Test func theOldTouchIDSwitchIsForgottenAndAProtectedPasteAlwaysAsks() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "clipProtectedNeedsAuth")
        _ = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(defaults.object(forKey: "clipProtectedNeedsAuth") == nil, "the old key is removed on load")
        Language.$override.withValue(.english) {
            #expect(OwnerCheck.why(LAError.Code.biometryNotAvailable.rawValue).contains("not available"))
            #expect(OwnerCheck.why(LAError.Code.biometryNotEnrolled.rawValue).contains("No fingerprint"))
            #expect(OwnerCheck.why(LAError.Code.biometryLockout.rawValue).contains("unlock it with your password"))
            #expect(OwnerCheck.why(nil).contains("not available"))
        }
    }

    @Test func aProtectedSnippetsWordsGoToTheSecretStoreOnly() throws {
        let dir = folder(), secrets = Secrets()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = ClipBook(directory: dir, secrets: secrets)
        let id = book.addSnippet(title: "Wi-Fi", text: "pixel-perfect-42", protected: true)
        let account = try #require(book.snippets.snippet(id)).secretAccount
        #expect(secrets.items[account] == "pixel-perfect-42")
        #expect(!(try String(contentsOf: book.store.snippetsFile, encoding: .utf8)).contains("pixel-perfect-42"))
        #expect(book.words(of: try #require(book.snippets.snippet(id))) == "pixel-perfect-42")
        book.setProtected(id, false)
        #expect(secrets.items[account] == nil && book.snippets.snippet(id)?.text == "pixel-perfect-42", "unprotected: back in the book")
        book.setProtected(id, true)
        #expect(secrets.items[account] == "pixel-perfect-42" && book.snippets.snippet(id)?.text == "")
        book.removeSnippetOrFolder(id)
        #expect(secrets.items.isEmpty, "a deleted snippet takes its secret with it")
        let again = ClipBook(directory: dir, secrets: secrets)
        #expect(again.snippets.all.isEmpty)
    }

    @Test func theHistorySurvivesARelaunchWithItsLimits() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = ClipBook(directory: dir, secrets: Secrets())
        let now = Date()
        for i in 0..<5 { book.add(Clipboard.Clip(text: "copy \(i)", copiedAt: now.addingTimeInterval(Double(i))), limit: 3, days: 30) }
        #expect(book.history.clips.map(\.text) == ["copy 4", "copy 3", "copy 2"])
        book.togglePin(book.history.clips[2].id)
        book.bump(book.history.clips[2].id, at: now.addingTimeInterval(10))
        let again = ClipBook(directory: dir, secrets: Secrets())
        #expect(again.history.clips.map(\.text) == ["copy 2", "copy 4", "copy 3"] && again.history.clips[0].pinned)
        again.clearHistory()
        #expect(again.history.clips.map(\.text) == ["copy 2"])
    }

    @Test func theWatcherKeepsCopiesButNotSecretsOrItsOwnWrites() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = AppSettings(defaults: defaults, keychain: Secrets())
        let book = ClipBook(directory: dir, secrets: Secrets())
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let watcher = ClipWatcher(settings: settings, book: book, pasteboard: board)
        func write(_ text: String, _ extra: NSPasteboard.PasteboardType? = nil) {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            if let extra { item.setString("", forType: extra) }
            board.writeObjects([item])
        }
        write("first"); watcher.look()
        write("hunter2", ClipPaster.concealed); watcher.look()
        write("ours", ClipPaster.ownType); watcher.look()
        ClipPaster.put(ClipPaster.Item(text: "pasted"), plain: true, on: board); watcher.ownWrite(); watcher.look()
        write("second"); watcher.look()
        #expect(book.history.clips.map(\.text) == ["second", "first"])
    }

    @Test func aCopiedPictureIsKeptAsFilesThumbnailedPastedBackAndForgotten() throws {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = AppSettings(defaults: defaults, keychain: Secrets())
        let book = ClipBook(directory: dir, secrets: Secrets())
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let watcher = ClipWatcher(settings: settings, book: book, pasteboard: board)
        let (png, tiff) = ClipDemo.picture()
        func copy(words: String? = nil) {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            item.setData(tiff, forType: .tiff)
            if let words { item.setString(words, forType: .string) }
            board.writeObjects([item])
            watcher.look()
        }
        copy()
        let clip = try #require(book.history.clips.first)
        #expect(clip.kind == .image && clip.text == "Image 48×30" && clip.picture?.types == ["public.png", "public.tiff"])
        #expect(book.imageData(of: clip).map(\.data) == [png, tiff])
        let thumbnail = try #require(book.thumbnail(of: clip))
        #expect(max(thumbnail.size.width, thumbnail.size.height) == CGFloat(ClipBook.thumbnailPixels))
        copy()
        #expect(book.history.clips.count == 1, "the same picture again is the same clip")

        ClipPaster.put(ClipPaster.Item(text: clip.text, images: book.imageData(of: clip)), plain: false, on: board)
        watcher.ownWrite()
        #expect(board.data(forType: .png) == png && board.data(forType: .tiff) == tiff && board.string(forType: .string) == nil)

        copy(words: "a table from Numbers")
        #expect(book.history.clips.first?.kind == .text, "words with a picture of them are words")
        settings.clipLargestImageMB = 1
        let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        board.clearContents()
        board.setData(big.tiffRepresentation!, forType: .tiff)
        watcher.look()
        #expect(book.history.clips.count == 2, "a TIFF over the cap is left out")
        settings.clipKeepImages = false
        settings.clipLargestImageMB = 20
        board.clearContents()
        board.setData(big.tiffRepresentation!, forType: .tiff)
        watcher.look()
        #expect(book.history.clips.count == 2, "pictures off: none kept")

        book.remove(clip.id)
        #expect(book.imageData(of: clip).isEmpty, "a forgotten picture's files go")
    }

    @Test func protectedWordsAreFingerprintedNeverWrittenAndOldOnesGetTheirsOnLoad() throws {
        let dir = folder(), secrets = Secrets()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = ClipBook(directory: dir, secrets: secrets)
        let id = book.addSnippet(title: "Wi-Fi", text: "pixel-perfect-42", protected: true)
        #expect(book.snippets.mask(for: Clipboard.Clip(text: "pixel-perfect-42", copiedAt: Date())) == "PWD:Wi-Fi: [16] chars")
        let plain = book.addSnippet(title: "Door", text: "1234")
        book.setProtected(plain, true)
        #expect(book.snippets.secret(matching: "1234")?.id == plain)
        book.update(try #require(book.snippets.snippet(id)), secret: "new-password")
        #expect(book.snippets.secret(matching: "pixel-perfect-42") == nil && book.snippets.secret(matching: "new-password")?.id == id)
        #expect(!(try String(contentsOf: book.store.snippetsFile, encoding: .utf8)).contains("new-password"))

        // A book saved before fingerprints: the first load reads the keychain once and fingerprints it.
        var old = book.snippets
        for (_, s) in old.all { var s = s; s.secretSalt = nil; s.secretHash = nil; old.update(s) }
        try book.store.save(old)
        let again = ClipBook(directory: dir, secrets: secrets)
        #expect(again.snippets.secret(matching: "new-password")?.id == id && again.snippets.secret(matching: "1234")?.id == plain)
    }

    @Test func thePickerShowsAMaskedRowAndPastesItsRealWords() throws {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = ClipBook(directory: dir, secrets: Secrets())
        book.addSnippet(title: "Wi-Fi", text: "pixel-perfect-42", protected: true)
        book.add(Clipboard.Clip(text: "pixel-perfect-42", copiedAt: Date()), limit: 10, days: 0)
        book.add(Clipboard.Clip(text: "lunch", copiedAt: Date()), limit: 10, days: 0)
        let picker = ClipPickerController(settings: AppSettings(defaults: defaults, keychain: Secrets()), book: book, watcher: { nil }, editSnippets: {})
        picker.model.refresh(selectFirst: true)
        let rows = picker.model.rows.filter { $0.group == .recent }
        #expect(rows.map(\.text) == ["lunch", "PWD:Wi-Fi: [16] chars"])
        #expect(rows.map(\.masked) == [false, true])
    }

    @Test func aSecretIsWrittenConcealedAndPlainTextDropsTheFormatting() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let rtf = Data("{\\rtf1 hi}".utf8)
        ClipPaster.put(ClipPaster.Item(text: "hi", rtf: rtf), plain: false, on: board)
        #expect(board.data(forType: .rtf) == rtf && board.string(forType: .string) == "hi")
        ClipPaster.put(ClipPaster.Item(text: "hi", rtf: rtf), plain: true, on: board)
        #expect(board.data(forType: .rtf) == nil)
        let before = ClipPaster.saved(board)
        ClipPaster.put(ClipPaster.Item(text: "s3cret", secret: true), plain: true, on: board)
        #expect(board.types?.contains(ClipPaster.concealed) == true)
        ClipPaster.restore(before, on: board)
        #expect(board.string(forType: .string) == "hi")
    }

    @Test func thePickersKeysMoveJumpAndNumber() {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let book = ClipBook(directory: dir, secrets: Secrets())
        let now = Date()
        for i in 0..<3 { book.add(Clipboard.Clip(text: "copy \(i)", copiedAt: now.addingTimeInterval(Double(i))), limit: 100, days: 0) }
        book.addSnippet(title: "Sig", text: "Best regards")
        let picker = ClipPickerController(settings: AppSettings(defaults: defaults, keychain: Secrets()), book: book, watcher: { nil }, editSnippets: {})
        let model = picker.model
        model.source = { (book.history, book.snippets) }
        model.refresh(selectFirst: true)
        #expect(model.rows.map(\.text) == ["copy 2", "copy 1", "copy 0", "Best regards"])
        #expect(model.selectedRow?.text == "copy 2")
        _ = picker.key(125, [])
        #expect(model.selectedRow?.text == "copy 1")
        _ = picker.key(48, [])
        #expect(model.selectedRow?.title == "Sig", "⇥ jumps to the snippets")
        _ = picker.key(48, [])
        #expect(model.selectedRow?.text == "copy 2", "and back")
        #expect(model.numbered(4)?.title == "Sig" && model.numbered(5) == nil)
        model.query = "regards"
        #expect(model.rows.map(\.title) == ["Sig"] && model.selectedRow?.title == "Sig")
        model.first = .snippets
        model.query = ""
        #expect(model.rows.first?.title == "Sig", "the snippets shortcut puts them first")
        _ = picker.key(125, [])
        _ = picker.key(51, [])           // ⌫ with nothing typed forgets the copy
        #expect(book.history.clips.map(\.text) == ["copy 1", "copy 0"])
        #expect(!picker.key(0, []), "a letter goes to the search field")
    }
}
