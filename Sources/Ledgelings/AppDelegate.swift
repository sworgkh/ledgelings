import AppKit
import LedgelingsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let history = ChatHistory()
    private let library = SpriteLibrary()
    private let spend = SpendLedger()
    private lazy var settingsWindow = SettingsWindowController(settings: settings, history: history, library: library, spend: spend)
    private var statusItem: NSStatusItem?
    private var colony: Colony?
    private let phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let skipItem = NSMenuItem(title: "", action: #selector(skipPhase), keyEquivalent: "")
    private let talkStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let spendItem = NSMenuItem(title: "", action: #selector(openSpend), keyEquivalent: "")
    private let hideItem = NSMenuItem(title: "Hide Them for a While…", action: #selector(hideThem), keyEquivalent: "")
    /// What the dialog offers, in minutes; nil means "until tomorrow at eight".
    private static let hideChoices: [(String, Double?)] = [
        ("5 minutes", 5), ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240),
        ("Until tomorrow morning", nil),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let at = CommandLine.arguments.firstIndex(of: "--promo") {
            let out = CommandLine.arguments.indices.contains(at + 1) ? CommandLine.arguments[at + 1] : "build/promo.mp4"
            Task { @MainActor in
                do { try await Promo.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings promo: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        do {
            colony = try Colony(settings: settings, history: history, library: library, spend: spend)
        } catch {
            FileHandle.standardError.write(Data("Ledgelings: \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }
        installStatusItem()
        // `--settings [creatures|sprites|talk|chats]`: open the window at launch, for looking at it from a script.
        if let at = CommandLine.arguments.firstIndex(of: "--settings") {
            let tabs: [String: SettingsTab] = ["creatures": .creatures, "sprites": .sprites, "talk": .talk, "chats": .chats]
            settingsWindow.show(tab: CommandLine.arguments.indices.contains(at + 1) ? tabs[CommandLine.arguments[at + 1]] : nil)
            // `--snapshot <file.png>` with it: write the window to a file two seconds later and quit.
            if let shot = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(shot + 1) {
                let out = URL(fileURLWithPath: CommandLine.arguments[shot + 1])
                Task { @MainActor [settingsWindow] in
                    try? await Task.sleep(for: .seconds(2))
                    do { try settingsWindow.snapshot(to: out) } catch { FileHandle.standardError.write(Data("Ledgelings snapshot: \(error)\n".utf8)) }
                    exit(0)
                }
            }
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image()
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
        spendItem.target = self
        menu.addItem(spendItem)
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
        let s = spend.summary
        spendItem.title = "Spent: \(Spend.label(s.today.cost)) today, \(Spend.label(s.month.cost)) this month"
        spendItem.isHidden = s.allTime.calls == 0
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
    @objc private func openSpend() { settingsWindow.show(tab: .talk) }
}
