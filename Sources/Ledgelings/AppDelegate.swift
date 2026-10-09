import AppKit
import Combine
import LedgelingsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let history = ChatHistory()
    private let library = SpriteLibrary()
    private let spend = SpendLedger()
    private let bonds = BondBook()
    private let reminders = ReminderBook()
    private let hunts = HuntBook()
    private let beds = BedBook()
    private lazy var voice = Voice(settings: settings, spend: spend, history: history)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, history: history, library: library, spend: spend, bonds: bonds, reminders: reminders, hunts: hunts, beds: beds, voice: voice,
        send: { [weak self] in self?.colony?.deliverNow($0) },
        clearGarden: { [weak self] in self?.colony?.clearGarden() ?? 0 })
    private lazy var note = ReminderNoteController(reminders: reminders, keeper: { [weak self] in self?.colony?.noteKeeper() })
    private lazy var actions = ActionsController(settings: settings, colony: { [weak self] in self?.colony },
                                                 addReminder: { [weak self] in self?.openReminders() },
                                                 open: { [weak self] in self?.follow($0) })
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?
    private var shortcutShown: AnyCancellable?
    private var colony: Colony?
    private let phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let talkStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let spendItem = NSMenuItem(title: "", action: #selector(openSpend), keyEquivalent: "")
    private let voiceItem = NSMenuItem(title: "", action: #selector(toggleVoice), keyEquivalent: "v")
    private let revengeItem = NSMenuItem(title: "", action: #selector(toggleRevenge), keyEquivalent: "")
    private let pointer = SystemPointer()
    private let nextReminderItem = NSMenuItem(title: "", action: #selector(openReminderList), keyEquivalent: "")

    private var speaking: AnyCancellable?
    private var minding: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything is drawn or said: the language everything looks its words up in.
        Language.choose(settings.language)
        speaking = settings.$language.sink { Language.choose($0) }
        CursorMood.choose(settings.cursorMood)
        minding = settings.$cursorMood.sink { CursorMood.choose($0) }
        if let at = CommandLine.arguments.firstIndex(of: "--promo") {
            let out = CommandLine.arguments.indices.contains(at + 1) ? CommandLine.arguments[at + 1] : "build/promo.mp4"
            Task { @MainActor in
                do { try await Promo.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings promo: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--reminder-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/reminder.mp4"
            let text = args.indices.contains(at + 2) ? args[at + 2] : "Stretch your back and drink some water"
            Task { @MainActor in
                do { try await ReminderFilm.run(output: URL(fileURLWithPath: out), text: text) }
                catch { FileHandle.standardError.write(Data("Ledgelings reminder film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--garden-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/garden.mp4"
            Task { @MainActor in
                do { try await GardenFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings garden film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--bed-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/beds.mp4"
            Task { @MainActor in
                do { try await BedFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings bed film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--tea-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/tea.mp4"
            Task { @MainActor in
                do { try await TeaFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings tea film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        do {
            colony = try Colony(settings: settings, history: history, library: library, spend: spend, bonds: bonds, reminders: reminders, hunts: hunts, beds: beds)
            colony?.voice = voice
            colony?.pointer = pointer
            freeTheCursorWhenTheScreenGoes()
        } catch {
            FileHandle.standardError.write(Data("Ledgelings: \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }
        installStatusItem()
        shortcut = GlobalShortcut(settings: settings) { [weak self] in self?.shortcutPressed() }
        shortcutShown = Publishers.CombineLatest(settings.$shortcutEnabled, settings.$shortcut)
            .sink { [weak self] enabled, shortcut in self?.showShortcutInMenu(enabled ? shortcut : nil) }
        // `--shortcut`: says on stderr whether the system took the shortcut, then each press; quits after the first.
        if CommandLine.arguments.contains("--shortcut") {
            let label = GlobalShortcut.label(settings.shortcut)
            let state = !settings.shortcutEnabled ? "off" : settings.shortcutProblem.isEmpty ? "registered" : "refused: \(settings.shortcutProblem)"
            FileHandle.standardError.write(Data("shortcut \(label) \(state)\n".utf8))
            Task { @MainActor in try? await Task.sleep(for: .seconds(30)); FileHandle.standardError.write(Data("shortcut: not pressed\n".utf8)); exit(2) }
        }
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
                for _ in 0..<900 where !colony.busy.isEmpty || !colony.chats.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
                colony.trace?("pair let go")
                exit(0)
            }
        }
        // `--grab`: the first creature grabs the cursor now; every step on stderr
        // with the time since, then quit once it has let go.
        if CommandLine.arguments.contains("--grab"), let colony {
            let start = Date()
            colony.trace = { line in
                FileHandle.standardError.write(Data(String(format: "grab %6.2f  %@\n", Date().timeIntervalSince(start), line).utf8))
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                colony.grabCursor(0)
                while colony.grab != nil { try? await Task.sleep(for: .seconds(0.1)) }
                try? await Task.sleep(for: .seconds(2))
                exit(0)
            }
        }
        // `--tea`: a tea party now, every line and voice cue on stderr with the
        // time since it started, then quit once the pair has walked on.
        if CommandLine.arguments.contains("--tea"), let colony {
            let start = Date()
            colony.trace = { line in
                FileHandle.standardError.write(Data(String(format: "tea %7.2f  %@\n", Date().timeIntervalSince(start), line).utf8))
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                colony.teaNow()
                try? await Task.sleep(for: .seconds(1))
                guard colony.teaParty != nil || colony.teaInvite != nil else { colony.trace?("no party: \(colony.talkStatus)"); exit(1) }
                while colony.teaParty != nil || colony.teaInvite != nil || !colony.chats.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
                colony.trace?("pair walks on")
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
        // `--remind "text"`: a reminder delivered now, on the real screen, without saving it.
        if let at = CommandLine.arguments.firstIndex(of: "--remind"), CommandLine.arguments.indices.contains(at + 1), let colony {
            let text = CommandLine.arguments[at + 1]
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                colony.deliverNow(Reminders.Reminder(text: text, time: Date()))
            }
        }
        // `--note`: the paper note of Add a Reminder…; `--snapshot <file.png>` with it writes it to a file and quits.
        if CommandLine.arguments.contains("--note") {
            let note = note
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                note.show()
                guard let shot = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(shot + 1) else { return }
                try? await Task.sleep(for: .seconds(1))
                do { try note.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[shot + 1])) } catch { FileHandle.standardError.write(Data("Ledgelings snapshot: \(error)\n".utf8)) }
                exit(0)
            }
        }
        // `--actions`: the Creature Actions sheet; `--snapshot <file.png>` with it writes it to a file and quits.
        if CommandLine.arguments.contains("--actions") {
            let actions = actions
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                actions.show()
                guard let shot = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(shot + 1) else { return }
                try? await Task.sleep(for: .seconds(1))
                do { try actions.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[shot + 1])) } catch { FileHandle.standardError.write(Data("Ledgelings snapshot: \(error)\n".utf8)) }
                exit(0)
            }
        }
        // `--settings [creatures|actions|chases|beds|sprites|talk|bonds|calendar|reminders|voice|costs|chats]`: open the window at launch, for looking at it from a script.
        if let at = CommandLine.arguments.firstIndex(of: "--settings") {
            let tabs: [String: SettingsTab] = ["creatures": .creatures, "actions": .actions, "chases": .chases, "beds": .beds, "sprites": .sprites, "talk": .talk, "flowers": .flowers, "bonds": .bonds, "calendar": .calendar, "reminders": .reminders, "voice": .voice, "costs": .costs, "chats": .chats]
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

    private let actionsItem = NSMenuItem(title: "", action: #selector(openActions), keyEquivalent: "a")
    private let chatsItem = NSMenuItem(title: "", action: #selector(openChats), keyEquivalent: "h")
    private let settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
    private let languageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let cursorMoodItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image()
        let menu = NSMenu()
        menu.delegate = self
        phaseItem.isEnabled = false
        menu.addItem(phaseItem)
        menu.addItem(.separator())
        actionsItem.target = self
        menu.addItem(actionsItem)
        nextReminderItem.target = self
        menu.addItem(nextReminderItem)
        voiceItem.target = self
        menu.addItem(voiceItem)
        revengeItem.target = self
        menu.addItem(revengeItem)
        talkStatusItem.isEnabled = false
        menu.addItem(talkStatusItem)
        chatsItem.target = self
        menu.addItem(chatsItem)
        spendItem.target = self
        menu.addItem(spendItem)
        // Each language under its own name, so whoever cannot read the current one still finds theirs.
        let languages = NSMenu()
        for language in Language.allCases {
            let choice = NSMenuItem(title: language.title, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = language.rawValue
            languages.addItem(choice)
        }
        languageItem.submenu = languages
        menu.addItem(languageItem)
        let moods = NSMenu()
        for mood in CursorMood.allCases {
            let choice = NSMenuItem(title: "", action: #selector(chooseCursorMood(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = mood.rawValue
            moods.addItem(choice)
        }
        cursorMoodItem.submenu = moods
        menu.addItem(cursorMoodItem)
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        retitleMenu()
    }

    /// The fixed titles, in the current language.
    private func retitleMenu() {
        actionsItem.title = tr("Creature Actions…")
        voiceItem.title = tr("Hear Them Talk")
        revengeItem.title = tr("Cursor Revenge")
        chatsItem.title = tr("Chat History…")
        settingsItem.title = tr("Settings…")
        languageItem.title = tr("Language")
        quitItem.title = tr("Quit Ledgelings")
        for choice in languageItem.submenu?.items ?? [] {
            choice.state = choice.representedObject as? String == settings.language.rawValue ? .on : .off
        }
        cursorMoodItem.title = tr("The Cursor Is")
        for choice in cursorMoodItem.submenu?.items ?? [] {
            let mood = (choice.representedObject as? String).flatMap(CursorMood.init(rawValue:))
            choice.title = mood?.title ?? ""
            choice.state = mood == settings.cursorMood ? .on : .off
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        retitleMenu()
        guard let colony else { return }
        let left = Int(colony.secondsLeftInPhase.rounded(.up))
        let clock = String(format: "%d:%02d", left / 60, left % 60)
        phaseItem.title = colony.isNight ? tr("Night — they wake in %@", clock) : tr("Day — they sleep in %@", clock)
        if settings.nightMinutes == 0 { phaseItem.title = tr("Always day — night is set to 0") }
        voiceItem.state = settings.voiceEnabled ? .on : .off
        revengeItem.state = settings.revengeEnabled ? .on : .off
        if let next = reminders.book.upcoming {
            nextReminderItem.title = "   " + tr("Next: %@, %@", String(next.text.prefix(40)), Reminders.when(next.time, now: Date()))
                + (settings.remindersEnabled ? "" : " " + tr("(off)"))
            nextReminderItem.isHidden = false
        } else {
            nextReminderItem.isHidden = true
        }
        talkStatusItem.title = "   " + String(colony.talkStatus.prefix(70))
        let s = spend.summary
        spendItem.title = tr("Spent: %@ today, %@ this month", Spend.label(s.today.cost), Spend.label(s.month.cost))
        spendItem.isHidden = s.allTime.calls == 0
        if colony.isHiding {
            let back = Int(colony.hideout.remaining(at: colony.elapsed).rounded(.up))
            phaseItem.title = back > 0 ? tr("Hiding in the house — out in %@", String(format: "%d:%02d", back / 60, back % 60)) : tr("Coming home…")
        }
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, let language = Language(rawValue: code) else { return }
        settings.language = language
        retitleMenu()
    }

    @objc private func chooseCursorMood(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mood = CursorMood(rawValue: raw) else { return }
        settings.cursorMood = mood
        retitleMenu()
    }

    @objc private func openActions() { actions.show() }

    /// The shortcut from any app: the sheet comes up, or goes away if it is up.
    private func shortcutPressed() {
        actions.toggle()
        if CommandLine.arguments.contains("--shortcut") {
            FileHandle.standardError.write(Data("shortcut pressed: sheet \(actions.isUp ? "up" : "away")\n".utf8))
            Task { @MainActor in try? await Task.sleep(for: .seconds(2)); exit(0) }
        }
    }

    /// Creature Actions… in the menu wears the shortcut from any app, so it can be
    /// learnt there; ⌘A, which only works with the menu open, while there is none.
    private func showShortcutInMenu(_ shortcut: Shortcut?) {
        let key = shortcut.map { GlobalShortcut.keyName($0.keyCode).lowercased() } ?? ""
        guard let shortcut, key.count == 1 else {
            actionsItem.keyEquivalent = "a"
            actionsItem.keyEquivalentModifierMask = .command
            return
        }
        actionsItem.keyEquivalent = key
        actionsItem.keyEquivalentModifierMask = GlobalShortcut.flags(shortcut.modifiers)
    }

    /// Opened again while running: with the icon hidden, the way in that needs no shortcut.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        actions.reopened()
        return false
    }

    private func follow(_ link: ActionsLink) {
        switch link {
        case .settings: openSettings()
        case .chats: openChats()
        case .quit: NSApp.terminate(nil)
        }
    }
    @objc private func toggleVoice() { settings.voiceEnabled.toggle() }
    @objc private func toggleRevenge() { settings.revengeEnabled.toggle() }

    /// A creature holding the cursor lets go the moment the screen sleeps or locks,
    /// the user switches away, or the app quits.
    private func freeTheCursorWhenTheScreenGoes() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(freeTheCursor), name: name, object: nil)
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(freeTheCursor),
                                                            name: .init("com.apple.screenIsLocked"), object: nil)
    }

    @objc private func freeTheCursor() { colony?.letGoOfCursor(.escape) }

    func applicationWillTerminate(_ notification: Notification) { colony?.letGoOfCursor(.escape) }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openChats() { settingsWindow.show(tab: .chats) }
    @objc private func openReminders() { settings.reminderPaperNote ? note.show() : settingsWindow.show(tab: .reminders) }
    @objc private func openReminderList() { settingsWindow.show(tab: .reminders) }
    @objc private func openSpend() { settingsWindow.show(tab: .costs) }
}
