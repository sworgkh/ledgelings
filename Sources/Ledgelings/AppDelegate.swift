import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var statusItem: NSStatusItem?
    private var colony: Colony?
    private let phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let skipItem = NSMenuItem(title: "", action: #selector(skipPhase), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            colony = try Colony(settings: settings)
        } catch {
            FileHandle.standardError.write(Data("Ledgelings: \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.fill", accessibilityDescription: "Ledgelings")
        let menu = NSMenu()
        menu.delegate = self
        phaseItem.isEnabled = false
        skipItem.target = self
        menu.addItem(phaseItem)
        menu.addItem(skipItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Make Them Jump", action: #selector(makeThemJump), keyEquivalent: "j").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ledgelings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let colony else { return }
        let left = Int(colony.secondsLeftInPhase.rounded(.up))
        let clock = String(format: "%d:%02d", left / 60, left % 60)
        phaseItem.title = colony.isNight ? "Night — they wake in \(clock)" : "Day — they sleep in \(clock)"
        skipItem.title = colony.isNight ? "Wake Them Up Now" : "Put Them to Sleep Now"
        skipItem.isHidden = settings.nightMinutes == 0
        if settings.nightMinutes == 0 { phaseItem.title = "Always day — night is set to 0" }
    }

    @objc private func makeThemJump() { colony?.startleEveryone() }
    @objc private func skipPhase() { colony?.skipPhase() }
    @objc private func openSettings() { settingsWindow.show() }
}
