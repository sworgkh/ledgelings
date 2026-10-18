import AppKit
import LedgelingsCore

/// `--paste-check`: does a picked clip really land, not only on the pasteboard? Opens a
/// small window with a text field, puts a line on the pasteboard the way the picker
/// does, presses ⌘V the way the picker does and reads the field. Prints whether
/// Accessibility is granted to this very build, then what landed; puts the pasteboard back.
@MainActor
enum PasteCheck {
    static func run() async -> Bool {
        func log(_ line: String) { FileHandle.standardError.write(Data("paste \(line)\n".utf8)) }
        let trusted = ClipPaster.trusted
        log("accessibility \(trusted ? "granted" : "NOT granted to this build: picking only copies")")
        let before = ClipPaster.saved()
        defer { ClipPaster.restore(before) }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: CGRect(x: 10, y: 15, width: 340, height: 28))
        window.contentView?.addSubview(field)
        window.center()
        // ⌘V reaches a text field through the Edit menu's Paste; a menu-bar app has none of its own.
        let menu = NSMenu(), edit = NSMenuItem(), items = NSMenu(title: "Edit")
        items.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu = items
        menu.addItem(edit)
        let mainMenu = NSApp.mainMenu
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = mainMenu }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        for _ in 0..<20 where !NSApp.isActive { try? await Task.sleep(for: .milliseconds(100)) }
        log("in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"), this app active \(NSApp.isActive), field key \(window.isKeyWindow)")
        let line = "Ledgelings paste check \(Int.random(in: 1000...9999))"
        ClipPaster.put(ClipPaster.Item(text: line), plain: true)
        let started = Date()
        let pressed = ClipPaster.pressPaste()
        try? await Task.sleep(for: .milliseconds(300))
        let landed = field.stringValue
        log(String(format: "⌘V %@, field now \"%@\" after %.0f ms", pressed ? "pressed" : "not pressed", landed, Date().timeIntervalSince(started) * 1000))
        window.orderOut(nil)
        let ok = landed == line
        log(ok ? "pasted for real" : "NOT pasted")
        return ok
    }
}
