import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore
import SwiftUI

/// The shortcut that works in every app: the way to the creatures when the menu
/// bar has no room for the icon, which on a notched Mac is often. Registered
/// with Carbon's hot keys, the one system-wide way that asks for no permission.
/// It follows the settings: off, changed, or let go while a new one is recorded.
@MainActor
final class GlobalShortcut {
    private let settings: AppSettings
    private let pressed: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var following: AnyCancellable?

    init(settings: AppSettings, pressed: @escaping () -> Void) {
        self.settings = settings
        self.pressed = pressed
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let me = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            // Carbon calls on the main thread, in the middle of its own event; what
            // the press opens (a menu tracks in its own loop) waits until it is done.
            DispatchQueue.main.async { me.pressed() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        following = Publishers.CombineLatest3(settings.$shortcutEnabled, settings.$shortcut, settings.$recordingShortcut)
            .sink { [weak self] enabled, shortcut, recording in self?.hold(enabled && !recording ? shortcut : nil) }
    }

    /// Lets go of the old shortcut and takes the new one, or none.
    private func hold(_ shortcut: Shortcut?) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        var problem = ""
        if let shortcut {
            // "LDGL", so the system can tell our hot key from another app's.
            let id = EventHotKeyID(signature: 0x4C44_474C, id: 1)
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbon(shortcut.modifiers), id,
                                             GetApplicationEventTarget(), 0, &hotKey)
            if status != noErr {
                hotKey = nil
                problem = tr("macOS would not take %@: it is already taken. Record another.", Self.label(shortcut))
            }
        }
        if settings.shortcutProblem != problem { settings.shortcutProblem = problem }
    }

    static func carbon(_ modifiers: Shortcut.Modifiers) -> UInt32 {
        UInt32((modifiers.contains(.command) ? cmdKey : 0) | (modifiers.contains(.shift) ? shiftKey : 0)
            | (modifiers.contains(.option) ? optionKey : 0) | (modifiers.contains(.control) ? controlKey : 0))
    }

    static func flags(_ modifiers: Shortcut.Modifiers) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { f.insert(.command) }
        if modifiers.contains(.shift) { f.insert(.shift) }
        if modifiers.contains(.option) { f.insert(.option) }
        if modifiers.contains(.control) { f.insert(.control) }
        return f
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Shortcut.Modifiers {
        var m: Shortcut.Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }

    /// Keys that print nothing, or nothing you could read on a button.
    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// What is printed on the key: by the keyboard's Latin layout, so the label
    /// reads the same whichever language is being typed.
    static func keyName(_ keyCode: Int) -> String {
        if let name = named[keyCode] { return name }
        let fallback = tr("key %d", keyCode)
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0, length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, characters.count, &length, &characters)
        }
        let name = String(utf16CodeUnits: characters, count: length).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return status == noErr && !name.isEmpty ? name : fallback
    }

    static func label(_ shortcut: Shortcut) -> String { shortcut.label(key: keyName(shortcut.keyCode)) }
}

/// The shortcut as a button: click it and the next keys pressed become the
/// shortcut. Escape, or a second click, keeps the old one. A key with no
/// Command, Control or Option held is refused with a beep.
struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    @State private var monitor: Any?

    var body: some View {
        Button(settings.recordingShortcut ? tr("Press the keys…") : GlobalShortcut.label(settings.shortcut)) {
            settings.recordingShortcut ? stop() : start()
        }
        .monospacedDigit()
        .onDisappear(perform: stop)
    }

    private func start() {
        settings.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let made = Shortcut(keyCode: Int(event.keyCode), modifiers: GlobalShortcut.modifiers(event.modifierFlags))
            if made.keyCode == kVK_Escape, made.modifiers.isEmpty {
                stop()
            } else if made.isUsable {
                settings.shortcut = made
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if settings.recordingShortcut { settings.recordingShortcut = false }
    }
}
