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
        #expect(s.clipHistoryShortcutEnabled && s.clipHistoryShortcut == .clipHistory)
        #expect(s.clipSnippetsShortcutEnabled && s.clipSnippetsShortcut == .clipSnippets)
        #expect(s.clipExcludedApps == Clipboard.defaultExcludedMacApps)
        s.clipboardEnabled = false; s.clipHistoryEnabled = false; s.clipKeepFormatting = false; s.clipKeepFiles = false
        s.clipAutoPaste = false; s.clipPlainText = true; s.clipAnimate = false
        s.clipSnippetShortcutsEnabled = false; s.clipHistoryShortcutEnabled = false; s.clipSnippetsShortcutEnabled = false
        s.clipHistoryLimit = 50; s.clipKeepDays = 0; s.clipAnimationSpeed = 2
        s.clipHistoryShortcut = Shortcut(keyCode: 9, modifiers: [.command, .shift])
        s.clipSnippetsShortcut = Shortcut(keyCode: 1, modifiers: [.control])
        s.clipExcludedApps = ["com.example.vault"]
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.clipboardEnabled && !again.clipHistoryEnabled && !again.clipKeepFormatting && !again.clipKeepFiles)
        #expect(!again.clipAutoPaste && again.clipPlainText && !again.clipAnimate)
        #expect(!again.clipSnippetShortcutsEnabled && !again.clipHistoryShortcutEnabled && !again.clipSnippetsShortcutEnabled)
        #expect(again.clipHistoryLimit == 50 && again.clipKeepDays == 0 && again.clipAnimationSpeed == 2)
        #expect(again.clipHistoryShortcut == Shortcut(keyCode: 9, modifiers: [.command, .shift]))
        #expect(again.clipSnippetsShortcut == Shortcut(keyCode: 1, modifiers: [.control]))
        #expect(again.clipExcludedApps == ["com.example.vault"])
        defaults.set(5, forKey: "clipHistoryLimit"); defaults.set(9999, forKey: "clipKeepDays"); defaults.set(10.0, forKey: "clipAnimationSpeed")
        defaults.set(Shortcut.Modifiers.shift.rawValue, forKey: "clipHistoryShortcutModifiers")
        let clamped = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(clamped.clipHistoryLimit == 10 && clamped.clipKeepDays == 365 && clamped.clipAnimationSpeed == 3, "clamped on load")
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
