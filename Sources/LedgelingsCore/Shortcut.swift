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

    /// What the shortcut brings up.
    public enum Opens: String, CaseIterable, Sendable {
        /// The Creature Actions sheet; pressed again, it puts the sheet away.
        case actions
        /// The tray menu, under the cursor: everything the hidden icon would have offered.
        case menu

        public var title: String {
            switch self {
            case .actions: tr("Creature Actions")
            case .menu: tr("The whole menu")
            }
        }
    }

    public static let keyCodes = 0...127
    /// Control-Option-L, L for Ledgelings: free in the system and in the common window managers.
    public static let standard = Shortcut(keyCode: 37, modifiers: [.control, .option])

    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// As it was saved, or the standard one when what was saved cannot be a shortcut.
    public init(savedKeyCode: Int?, savedModifiers: Int?) {
        let made = Shortcut(keyCode: savedKeyCode ?? Self.standard.keyCode,
                            modifiers: Modifiers(rawValue: savedModifiers ?? Self.standard.modifiers.rawValue).intersection(.all))
        self = made.isUsable ? made : Self.standard
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
