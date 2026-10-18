import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import LedgelingsCore

/// Watches the Mac's pasteboard for copies and keeps them in the history.
///
/// macOS tells nobody when something is copied, so the pasteboard's change count
/// is read twice a second, as every clipboard manager does; reading a number
/// costs nothing. A copy marked concealed or transient (nspasteboard.org's
/// markers, written by password managers), one made in an excluded app, and
/// the app's own writes are left out. Images are not kept: one screenshot is
/// megabytes, the history is one JSON file read at launch, and the picker shows
/// words; files are kept as their paths.
@MainActor
final class ClipWatcher {
    static let every: TimeInterval = 0.5

    private let settings: AppSettings
    private let book: ClipBook
    private let pasteboard: NSPasteboard
    private var seen: Int
    private var timer: Timer?
    private var following: AnyCancellable?
    /// What the watcher did with each copy, for `--clip-demo`.
    var trace: ((String) -> Void)?

    init(settings: AppSettings, book: ClipBook, pasteboard: NSPasteboard = .general) {
        self.settings = settings
        self.book = book
        self.pasteboard = pasteboard
        seen = pasteboard.changeCount
        following = Publishers.CombineLatest(settings.$clipboardEnabled, settings.$clipHistoryEnabled)
            .sink { [weak self] on, history in self?.watch(on && history) }
    }

    /// The app wrote to the pasteboard itself: that change is not a copy.
    func ownWrite() { seen = pasteboard.changeCount }

    private func watch(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        seen = pasteboard.changeCount
        guard on else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.every, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
    }

    /// Reads the pasteboard when it changed since the last look.
    func look(now: Date = Date()) {
        let count = pasteboard.changeCount
        guard count != seen else { return }
        seen = count
        let front = NSWorkspace.shared.frontmostApplication
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !types.contains(ClipPaster.ownType.rawValue) else { return }
        guard Clipboard.shouldKeep(types: types, app: front?.bundleIdentifier, excluded: settings.clipExcludedApps) else {
            trace?("skip \(front?.bundleIdentifier ?? "?"): concealed, passing or excluded")
            return
        }
        guard let clip = Self.read(pasteboard, at: now, app: front?.localizedName, settings: settings) else {
            trace?("skip: no text")
            return
        }
        book.add(clip, limit: settings.clipHistoryLimit, days: settings.clipKeepDays)
        trace?("keep \(clip.kind.rawValue) \"\(clip.preview(40))\" from \(clip.app ?? "?")")
    }

    /// The copy as a clip: files (as paths), else text with its RTF beside it, else nothing.
    static func read(_ pasteboard: NSPasteboard, at now: Date, app: String?, settings: AppSettings) -> Clipboard.Clip? {
        if settings.clipKeepFiles,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return Clipboard.Clip(kind: .files, text: urls.map(\.path).joined(separator: "\n"), copiedAt: now, app: app)
        }
        guard let text = pasteboard.string(forType: .string) else { return nil }
        let rtf = settings.clipKeepFormatting ? pasteboard.data(forType: .rtf) : nil
        return Clipboard.Clip(kind: rtf == nil ? .text : .rich, text: text, rtf: rtf, copiedAt: now, app: app)
    }
}

/// Puts a chosen item on the pasteboard and pastes it into the app that was in
/// front, by pressing ⌘V for the user. Pressing keys for another app needs the
/// Accessibility permission; without it the item is only copied and the user
/// presses ⌘V.
@MainActor
enum ClipPaster {
    /// Marks our own writes, so other clipboard managers know where they came from.
    static let ownType = NSPasteboard.PasteboardType("com.alterman.ledgelings.paste")
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// What to put on the pasteboard.
    struct Item {
        var text: String
        var rtf: Data?
        var files: [String] = []
        /// A protected snippet's words: marked concealed, so no clipboard manager keeps them,
        /// and taken off the pasteboard again once pasted.
        var secret = false
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Asks for the Accessibility permission: macOS shows its own dialog with a way to System Settings.
    static func askForTrust() {
        // kAXTrustedCheckOptionPrompt's own value; the constant is a global Swift 6 will not read.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Writes `item`; `plain` leaves its formatting off.
    static func put(_ item: Item, plain: Bool, on pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if !item.files.isEmpty {
            pasteboard.writeObjects(item.files.map { URL(fileURLWithPath: $0) as NSURL })
        }
        let entry = NSPasteboardItem()
        entry.setString(item.text, forType: .string)
        if !plain, let rtf = item.rtf { entry.setData(rtf, forType: .rtf) }
        entry.setString("", forType: ownType)
        if item.secret { entry.setString("", forType: concealed) }
        if item.files.isEmpty { pasteboard.writeObjects([entry]) }
    }

    /// Everything on the pasteboard now, to put back after a secret was pasted.
    static func saved(_ pasteboard: NSPasteboard = .general) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], on pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let made = items.map { kinds in
            let item = NSPasteboardItem()
            for (type, data) in kinds { item.setData(data, forType: type) }
            return item
        }
        if !made.isEmpty { pasteboard.writeObjects(made) }
    }

    /// Presses ⌘V for the app in front. False, and nothing pressed, without the permission.
    @discardableResult
    static func pressPaste() -> Bool {
        guard trusted else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(keyCode(for: "v") ?? kVK_ANSI_V)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        return true
    }

    /// The key that types `letter` in the keyboard's Latin layout: V is not on the same key in Dvorak.
    static func keyCode(for letter: String) -> Int? {
        (0..<128).first { GlobalShortcut.keyName($0).lowercased() == letter }
    }

    /// Where the text cursor is in the app in front, in AppKit's screen points (y up),
    /// when the app tells Accessibility; nil when it does not or there is no permission.
    static func caret() -> CGRect? {
        guard trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let field = element as! AXUIElement
        var range: AnyObject?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(field, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
        // Accessibility measures from the top of the main screen, downwards.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let flipped = CGRect(x: rect.minX, y: top - rect.maxY, width: max(rect.width, 1), height: max(rect.height, 1))
        return NSScreen.screens.contains { $0.frame.intersects(flipped) } ? flipped : nil
    }
}
