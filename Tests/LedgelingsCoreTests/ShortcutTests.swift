import Testing
@testable import LedgelingsCore

/// The shortcut from any app (§11): what can be one, and how it reads.
@Suite struct ShortcutTests {
    @Test func aShortcutNeedsCommandControlOrOptionHeld() {
        #expect(Shortcut.standard.isUsable)
        #expect(Shortcut(keyCode: 0, modifiers: [.command]).isUsable)
        #expect(Shortcut(keyCode: 0, modifiers: [.option, .shift]).isUsable)
        #expect(!Shortcut(keyCode: 0, modifiers: []).isUsable)
        #expect(!Shortcut(keyCode: 0, modifiers: [.shift]).isUsable)
        #expect(!Shortcut(keyCode: 128, modifiers: [.command]).isUsable)
        #expect(!Shortcut(keyCode: -1, modifiers: [.command]).isUsable)
    }

    @Test func whatWasSavedIsKeptWhenItCanBeAShortcutElseTheStandardOne() {
        #expect(Shortcut(savedKeyCode: nil, savedModifiers: nil) == .standard)
        #expect(Shortcut(savedKeyCode: 49, savedModifiers: 1 | 2) == Shortcut(keyCode: 49, modifiers: [.command, .shift]))
        #expect(Shortcut(savedKeyCode: 49, savedModifiers: 2) == .standard)
        #expect(Shortcut(savedKeyCode: 400, savedModifiers: 1) == .standard)
        // Bits that are no modifier of ours are dropped, not kept to confuse a later version.
        #expect(Shortcut(savedKeyCode: 49, savedModifiers: 1 | 64).modifiers == [.command])
    }

    @Test func modifiersAreDrawnInTheMacsOrder() {
        #expect(Shortcut.standard.label(key: "L") == "⌃⌥L")
        #expect(Shortcut(keyCode: 0, modifiers: [.command, .shift, .option, .control]).symbols == "⌃⌥⇧⌘")
    }
}
