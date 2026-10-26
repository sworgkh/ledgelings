import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore
import SwiftUI

/// Every shortcut the app takes from all apps, under one Carbon handler: the
/// Creature Actions shortcut, the clipboard pickers', each snippet's own. Each is
/// told apart by its hot key id, so a press reaches only its own action.
@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var handler: EventHandlerRef?
    private var held: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    /// What letting go of a key does, for the few that care (dictation's hold to talk).
    private var releases: [UInt32: () -> Void] = [:]
    private var lastID: UInt32 = 0

    private init() {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return noErr }
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            // Carbon calls on the main thread, in the middle of its own event; what
            // the press opens (a menu tracks in its own loop) waits until it is done.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { (released ? HotKeys.shared.releases[id.id] : HotKeys.shared.actions[id.id])?() }
            }
            return noErr
        }, 2, &specs, nil, &handler)
    }

    /// A number of its own for a new shortcut.
    func newID() -> UInt32 {
        lastID += 1
        return lastID
    }

    /// Lets go of what `id` held and takes `shortcut`, or nothing. False when the
    /// system refused it: another app, or another of ours, has it already.
    @discardableResult
    func hold(_ id: UInt32, _ shortcut: Shortcut?, pressed: @escaping () -> Void, released: (() -> Void)? = nil) -> Bool {
        if let old = held.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        actions[id] = pressed
        releases[id] = released
        guard let shortcut else { return true }
        var ref: EventHotKeyRef?
        // "LDGL", so the system can tell our hot keys from another app's.
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), GlobalShortcut.carbon(shortcut.modifiers),
                                         EventHotKeyID(signature: 0x4C44_474C, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        held[id] = ref
        return true
    }

    func release(_ id: UInt32) {
        if let old = held.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        actions[id] = nil
        releases[id] = nil
    }
}

/// One shortcut that works in every app, following the settings: off, changed, or
/// let go while any shortcut is being recorded. The Creature Actions one is the
/// way to the creatures when the menu bar has no room for the icon, which on a
/// notched Mac is often. Carbon's hot keys are the one system-wide way that asks
/// for no permission.
@MainActor
final class GlobalShortcut {
    private let id = HotKeys.shared.newID()
    private var following: AnyCancellable?

    /// Creature Actions' shortcut: `shortcutEnabled` and `shortcut`, its trouble in `shortcutProblem`.
    convenience init(settings: AppSettings, pressed: @escaping () -> Void) {
        self.init(settings: settings, enabled: settings.$shortcutEnabled, shortcut: settings.$shortcut,
                  problem: { [weak settings] in if settings?.shortcutProblem != $0 { settings?.shortcutProblem = $0 } }, pressed: pressed)
    }

    init(settings: AppSettings, enabled: some Publisher<Bool, Never>, shortcut: some Publisher<Shortcut, Never>,
         problem: @escaping (String) -> Void, pressed: @escaping () -> Void, released: (() -> Void)? = nil) {
        following = Publishers.CombineLatest3(enabled, shortcut, settings.$recordingShortcut)
            .sink { [id] enabled, shortcut, recording in
                let wanted = enabled && !recording ? shortcut : nil
                let taken = HotKeys.shared.hold(id, wanted, pressed: pressed, released: released)
                problem(taken ? "" : tr("macOS would not take %@: it is already taken. Record another.", Self.label(shortcut)))
            }
    }

    deinit {
        let id = id
        MainActor.assumeIsolated { HotKeys.shared.release(id) }
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

/// A shortcut as a button: click it and the next keys pressed become the
/// shortcut. Escape, or a second click, keeps the old one. A key with no
/// Command, Control or Option held is refused with a beep. Every shortcut is let
/// go while one is recorded, so the keys reach the recorder.
struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    /// Which shortcut it records; Creature Actions' when not given.
    var shortcut: Binding<Shortcut>?
    /// Or one that may be none at all, as a snippet's own.
    var optional: Binding<Shortcut?>?
    @State private var monitor: Any?
    @State private var recording = false

    private var current: Shortcut? { optional.map(\.wrappedValue) ?? shortcut?.wrappedValue ?? settings.shortcut }

    var body: some View {
        Button(recording ? tr("Press the keys…") : current.map(GlobalShortcut.label) ?? tr("Record Shortcut")) {
            recording ? stop() : start()
        }
        .monospacedDigit()
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        settings.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let made = Shortcut(keyCode: Int(event.keyCode), modifiers: GlobalShortcut.modifiers(event.modifierFlags))
            if made.keyCode == kVK_Escape, made.modifiers.isEmpty {
                stop()
            } else if made.isUsable {
                if let optional { optional.wrappedValue = made } else if let shortcut { shortcut.wrappedValue = made } else { settings.shortcut = made }
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
        recording = false
        if settings.recordingShortcut { settings.recordingShortcut = false }
    }
}
