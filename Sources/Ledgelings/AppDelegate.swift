import AppKit
import LedgelingsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let history = ChatHistory()
    private let library = SpriteLibrary()
    private let spend = SpendLedger()
    private let bonds = BondBook()
    private lazy var voice = Voice(settings: settings, spend: spend, history: history)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, history: history, library: library, spend: spend, bonds: bonds, voice: voice)
    private var statusItem: NSStatusItem?
    private var colony: Colony?
    private let phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let skipItem = NSMenuItem(title: "", action: #selector(skipPhase), keyEquivalent: "")
    private let talkStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let spendItem = NSMenuItem(title: "", action: #selector(openSpend), keyEquivalent: "")
    private let voiceItem = NSMenuItem(title: "Hear Them Talk", action: #selector(toggleVoice), keyEquivalent: "v")
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
            colony = try Colony(settings: settings, history: history, library: library, spend: spend, bonds: bonds)
            colony?.voice = voice
        } catch {
            FileHandle.standardError.write(Data("Ledgelings: \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }
        installStatusItem()
        // `--converse`: one conversation, every line and voice cue on stderr with
        // the time since it started, then quit once the pair is let go.
        if CommandLine.arguments.contains("--converse"), let colony {
            let start = Date()
            colony.trace = { line in
                FileHandle.standardError.write(Data(String(format: "converse %6.2f  %@\n", Date().timeIntervalSince(start), line).utf8))
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                colony.talkNow()
                try? await Task.sleep(for: .seconds(1))
                for _ in 0..<600 where !colony.busy.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
                colony.trace?("pair let go")
                exit(0)
            }
        }
        // `--plot`: the first two creatures on screen get their next story now,
        // however long they have lived together; bond, story and prompt text on stderr, then quit.
        if CommandLine.arguments.contains("--plot"), let colony {
            let start = Date()
            colony.trace = { FileHandle.standardError.write(Data(String(format: "plot %6.2f  %@\n", Date().timeIntervalSince(start), $0).utf8)) }
            Task { @MainActor in
                guard colony.creatures.count >= 2 else { colony.trace?("needs two creatures"); exit(1) }
                let a = colony.character(forCreature: 0).name, b = colony.character(forCreature: 1).name
                colony.writePlotIfDue(a, b, now: true)
                guard colony.plotting.contains(Bonds.key(a, b)) else { colony.trace?("not asked: \(colony.settings.brainProblem)"); exit(1) }
                while colony.plotting.contains(Bonds.key(a, b)) { try? await Task.sleep(for: .seconds(0.1)) }
                colony.trace?("\(a) hears: \(colony.relationship(of: 0, with: 1))")
                colony.trace?("\(b) hears: \(colony.relationship(of: 1, with: 0))")
                exit(colony.bonds.bond(a, b)?.plot == nil ? 1 : 0)
            }
        }
        // `--cast`: the brain model casts everyone on screen, one line each on stderr, then quit.
        if CommandLine.arguments.contains("--cast") {
            let voice = voice
            Task { @MainActor in
                var seen: [String] = []
                for name in voice.cast() where !seen.contains(name) {
                    seen.append(name)
                    do { FileHandle.standardError.write(Data("cast: \(name) → \(try await voice.castWithModel(name))\n".utf8)) }
                    catch { FileHandle.standardError.write(Data("cast: \(name) failed: \(error)\n".utf8)) }
                }
                exit(0)
            }
        }
        // `--say "text"`: one line in the current voice settings, its cues on stderr, then quit.
        if let at = CommandLine.arguments.firstIndex(of: "--say"), CommandLine.arguments.indices.contains(at + 1) {
            let text = CommandLine.arguments[at + 1], name = voice.cast().first ?? "Blocky"
            let voice = voice
            func log(_ s: String) { FileHandle.standardError.write(Data("say: \(s)\n".utf8)) }
            let started = voice.sayOnce(text, as: name) { cue in
                log("\(cue) · \(voice.status)")
                if cue == .done || cue == .dropped { exit(cue == .done ? 0 : 1) }
            }
            if !started { log("not said: \(voice.status)"); exit(1) }
            Task { @MainActor in try? await Task.sleep(for: .seconds(60)); log("timed out"); exit(2) }
        }
        // `--settings [creatures|sprites|talk|bonds|voice|costs|chats]`: open the window at launch, for looking at it from a script.
        if let at = CommandLine.arguments.firstIndex(of: "--settings") {
            let tabs: [String: SettingsTab] = ["creatures": .creatures, "sprites": .sprites, "talk": .talk, "bonds": .bonds, "calendar": .calendar, "voice": .voice, "costs": .costs, "chats": .chats]
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
        menu.addItem(withTitle: "Send a Paper Plane", action: #selector(sendPaperPlane), keyEquivalent: "p").target = self
        voiceItem.target = self
        menu.addItem(voiceItem)
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
        voiceItem.state = settings.voiceEnabled ? .on : .off
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
    @objc private func sendPaperPlane() { colony?.sendPlane() }
    @objc private func toggleVoice() { settings.voiceEnabled.toggle() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openChats() { settingsWindow.show(tab: .chats) }
    @objc private func openSpend() { settingsWindow.show(tab: .costs) }
}
