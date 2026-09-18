import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let history = ChatHistory()
    private lazy var settingsWindow = SettingsWindowController(settings: settings, history: history)
    private var statusItem: NSStatusItem?
    private var colony: Colony?
    private let phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let skipItem = NSMenuItem(title: "", action: #selector(skipPhase), keyEquivalent: "")
    private let talkStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let hideItem = NSMenuItem(title: "Hide Them for a While…", action: #selector(hideThem), keyEquivalent: "")
    /// What the dialog offers, in minutes; nil means "until tomorrow at eight".
    private static let hideChoices: [(String, Double?)] = [
        ("5 minutes", 5), ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
        ("Until tomorrow morning", nil),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            colony = try Colony(settings: settings, history: history)
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
        hideItem.target = self
        menu.addItem(hideItem)
        menu.addItem(withTitle: "Make Someone Talk", action: #selector(makeSomeoneTalk), keyEquivalent: "t").target = self
        talkStatusItem.isEnabled = false
        menu.addItem(talkStatusItem)
        menu.addItem(withTitle: "Chat History…", action: #selector(openChats), keyEquivalent: "h").target = self
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
        talkStatusItem.title = "   " + String(colony.talkStatus.prefix(70))
        if colony.isHiding {
            let back = Int(colony.hideout.remaining(at: colony.elapsed).rounded(.up))
            hideItem.title = back > 0 ? String(format: "Bring Them Back Now (%d:%02d left)", back / 60, back % 60) : "Coming home…"
        } else {
            hideItem.title = "Hide Them for a While…"
        }
    }

    /// A small sheet: how long should they stay in the house?
    @objc private func hideThem() {
        guard let colony else { return }
        if colony.isHiding { colony.bringThemBack(); return }
        let alert = NSAlert()
        alert.messageText = "Hide the creatures for a while"
        alert.informativeText = "They run home, the house packs itself away, and when the time is up it comes back and they walk out."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        popup.addItems(withTitles: Self.hideChoices.map(\.0))
        popup.selectItem(at: 2)
        alert.accessoryView = popup
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let minutes = Self.hideChoices[max(0, popup.indexOfSelectedItem)].1
        colony.hide(for: minutes.map { $0 * 60 } ?? Self.secondsUntilTomorrowMorning())
    }

    /// Seconds until 08:00 tomorrow, local time.
    private static func secondsUntilTomorrowMorning() -> Double {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return max(60, eight.timeIntervalSinceNow)
    }

    @objc private func makeThemJump() { colony?.startleEveryone() }
    @objc private func skipPhase() { colony?.skipPhase() }
    @objc private func makeSomeoneTalk() { colony?.talkNow() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openChats() { settingsWindow.show(tab: .chats) }
}
