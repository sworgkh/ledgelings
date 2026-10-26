import Foundation

/// The system-wide keyboard shortcut: a key and the modifier keys held with it.
/// It is how the owner reaches the creatures when the tray has no room for the
/// icon. The key is the platform's own key number (a Mac virtual key code); the
/// modifiers are kept in bits of our own, so a saved shortcut means the same
/// thing whichever toolkit registers it.
public struct Shortcut: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
        static let all: Modifiers = [.command, .shift, .option, .control]
    }

    public static let keyCodes = 0...127
    /// Control-Option-L, L for Ledgelings: free in the system and in the common window managers.
    public static let standard = Shortcut(keyCode: 37, modifiers: [.control, .option])
    /// The clipboard history picker: Control-Option-V. Not ⌘⇧V, which Chrome, Slack and
    /// Google Docs use to paste without formatting, nor ⌥⇧⌘V, the Mac's own Paste and Match Style.
    public static let clipHistory = Shortcut(keyCode: 9, modifiers: [.control, .option])
    /// The snippets picker: Control-Option-B, beside V on the keyboard, as Clipy has ⌘⇧B beside ⌘⇧V.
    public static let clipSnippets = Shortcut(keyCode: 11, modifiers: [.control, .option])
    /// A screenshot with the toolbar: Control-Option-S, beside the others.
    public static let shotCapture = Shortcut(keyCode: 1, modifiers: [.control, .option])
    /// The full screen at once: Command-Shift-8, the * key, beside the Mac's own ⌘⇧3–5.
    public static let shotFull = Shortcut(keyCode: 28, modifiers: [.command, .shift])
    /// The last rectangle again: Command-Shift-\.
    public static let shotLast = Shortcut(keyCode: 42, modifiers: [.command, .shift])
    /// Dictation: Control-Option-D, D for dictate, beside the others.
    public static let dictation = Shortcut(keyCode: 2, modifiers: [.control, .option])

    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// As it was saved, or the standard one when what was saved cannot be a shortcut.
    public init(savedKeyCode: Int?, savedModifiers: Int?, standard: Shortcut = Self.standard) {
        let made = Shortcut(keyCode: savedKeyCode ?? standard.keyCode,
                            modifiers: Modifiers(rawValue: savedModifiers ?? standard.modifiers.rawValue).intersection(.all))
        self = made.isUsable ? made : standard
    }

    /// A shortcut taken from every app must not be a key someone types: it needs
    /// Command, Control or Option held. Shift alone is a capital letter.
    public var isUsable: Bool {
        Self.keyCodes.contains(keyCode) && !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// The modifiers as the Mac draws them, in the Mac's order: ⌃⌥⇧⌘.
    public var symbols: String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
    }

    /// The whole shortcut for a label, given the key's name: "⌃⌥L".
    public func label(key: String) -> String { symbols + key }
}
