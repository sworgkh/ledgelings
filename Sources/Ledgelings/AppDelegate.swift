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
        settings: settings, history: history, library: library, spend: spend, bonds: bonds, reminders: reminders, hunts: hunts, beds: beds, voice: voice, clips: clips,
        send: { [weak self] in self?.colony?.deliverNow($0) },
        clearGarden: { [weak self] in self?.colony?.clearGarden() ?? 0 },
        editSnippets: { [weak self] in self?.snippetsWindow.show() },
        openRelationships: { [weak self] in self?.relationshipsWindow.show() },
        seedMemory: { [weak self] dryRun in await self?.seedMemory(dryRun: dryRun) ?? "" })
    private lazy var relationshipsWindow = RelationshipsWindowController(settings: settings, bonds: bonds)
    private lazy var note = ReminderNoteController(reminders: reminders, keeper: { [weak self] in self?.colony?.noteKeeper() })
    private lazy var actions = ActionsController(settings: settings, colony: { [weak self] in self?.colony },
                                                 addReminder: { [weak self] in self?.openReminders() },
                                                 open: { [weak self] in self?.follow($0) })
    private let clips = ClipBook()
    private var clipWatcher: ClipWatcher?
    private var clipShortcuts: ClipShortcuts?
    private lazy var picker = ClipPickerController(settings: settings, book: clips, watcher: { [weak self] in self?.clipWatcher },
                                                   editSnippets: { [weak self] in self?.snippetsWindow.show() },
                                                   helper: { [weak self] in self?.colony })
    private lazy var snippetsWindow = SnippetsWindowController(settings: settings, book: clips)
    private lazy var shots = ShotController(settings: settings, colony: { [weak self] in self?.colony })
    private lazy var dictation = DictationController(settings: settings, spend: spend, clips: clips, colony: { [weak self] in self?.colony },
                                                     watcher: { [weak self] in self?.clipWatcher })
    private(set) lazy var translate = TranslateController(settings: settings, spend: spend, clips: clips, watcher: { [weak self] in self?.clipWatcher },
                                                          helper: { [weak self] in self?.colony })
    private lazy var toolsScreen = ToolsScreenController(settings: settings)
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?
    private var shortcutShown: AnyCancellable?
    private var colony: Colony?
    private let phaseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let talkStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let spendItem = NSMenuItem(title: "", action: #selector(openSpend), keyEquivalent: "")
    private let voiceItem = NSMenuItem(title: "", action: #selector(toggleVoice), keyEquivalent: "v")
    private let revengeItem = NSMenuItem(title: "", action: #selector(toggleRevenge), keyEquivalent: "")
    private let activitiesItem = NSMenuItem(title: "", action: #selector(openActivities), keyEquivalent: "")
    private let deedsItem = NSMenuItem(title: "", action: #selector(toggleDeeds), keyEquivalent: "")
    private let relationshipsItem = NSMenuItem(title: "", action: #selector(openRelationships), keyEquivalent: "")
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
        if let at = CommandLine.arguments.firstIndex(of: "--kit-images") {
            // The sprite kit's attachments and its prompt (from the saved form), written to a folder.
            let args = CommandLine.arguments
            let folder = URL(fileURLWithPath: args.indices.contains(at + 1) ? args[at + 1] : "build/sprite-kit")
            do {
                for file in try library.saveKitImages(to: folder) { print("kit \(file.path)") }
                let prompt = folder.appendingPathComponent("prompt.txt")
                try library.prompt(settings.spriteKitForm).write(to: prompt, atomically: true, encoding: .utf8)
                print("kit \(prompt.path)")
                exit(0)
            } catch { FileHandle.standardError.write(Data("Ledgelings kit: \(error)\n".utf8)); exit(1) }
        }
        if let at = CommandLine.arguments.firstIndex(of: "--kit-import"), CommandLine.arguments.indices.contains(at + 1) {
            // Import one picture with the saved form, as Import… does, and print what was read: name, colour, idle pose.
            do {
                let name = try library.importFile(URL(fileURLWithPath: CommandLine.arguments[at + 1]), form: settings.spriteKitForm)
                if !settings.species.contains(name) { settings.species.append(name) }
                let atlas = library.atlas(named: name)
                print("imported \(name) colour \(atlas?.meta.colour ?? "none") kind \(atlas?.meta.kind ?? "none")")
                if let image = try? atlas?.image() { for row in SpriteText.describe(image, pose: "idle", palette: .blocky) { print(row) } }
                exit(0)
            } catch { FileHandle.standardError.write(Data("Ledgelings kit: \(error)\n".utf8)); exit(1) }
        }
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
        if let at = CommandLine.arguments.firstIndex(of: "--invite-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/invite.mp4"
            let offer = args.indices.contains(at + 2) ? Deeds.Offer(word: args[at + 2]) : nil
            Task { @MainActor in
                do { try await InviteFilm.run(output: URL(fileURLWithPath: out), offer: offer ?? .game(.soccer)); exit(0) }
                catch { FileHandle.standardError.write(Data("invite film: \(error)\n".utf8)); exit(1) }
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--play-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/play.mp4"
            let only = args.indices.contains(at + 2) ? Plays.Kind(rawValue: args[at + 2]) : nil
            Task { @MainActor in
                do { try await PlayFilm.run(output: URL(fileURLWithPath: out), only: only) }
                catch { FileHandle.standardError.write(Data("Ledgelings play film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--screens-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/screens.mp4"
            Task { @MainActor in
                do { try await ScreensFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings screens film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--clip-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/clipboard.mp4"
            Task { @MainActor in
                do { try await ClipFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings clip film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--shot-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/screenshots.mp4"
            Task { @MainActor in
                do { try await ShotFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings shot film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--dictate-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/dictation.mp4"
            Task { @MainActor in
                do { try await DictationFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings dictate film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if let at = CommandLine.arguments.firstIndex(of: "--translate-film") {
            let args = CommandLine.arguments
            let out = args.indices.contains(at + 1) ? args[at + 1] : "build/translate.mp4"
            Task { @MainActor in
                do { try await TranslateFilm.run(output: URL(fileURLWithPath: out)) }
                catch { FileHandle.standardError.write(Data("Ledgelings translate film: \(error)\n".utf8)); exit(1) }
                exit(0)
            }
            return
        }
        if CommandLine.arguments.contains("--mic-check") {
            Task { @MainActor in exit(await DictationDemo.check() ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--shot-check") {
            Task { @MainActor in exit(await ShotDemo.check() ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--paste-check") {
            Task { @MainActor in exit(await PasteCheck.run() ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--clip-demo") {
            let shot = CommandLine.arguments.firstIndex(of: "--snapshot").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
            Task { @MainActor in
                exit(await ClipDemo.run(settings: settings, snapshot: shot.map { URL(fileURLWithPath: $0) }) ? 0 : 1)
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
        clipWatcher = ClipWatcher(settings: settings, book: clips)
        clipShortcuts = ClipShortcuts(settings: settings, book: clips, open: { [weak self] in self?.clipShortcutPressed($0) },
                                      paste: { [weak self] in self?.picker.pasteNow($0) })
        shortcut = GlobalShortcut(settings: settings) { [weak self] in self?.shortcutPressed() }
        shots.takeShortcuts { [weak self] in self?.shotShortcutPressed($0) }
        dictation.takeShortcut { [weak self] in self?.dictationShortcutPressed() }
        translate.takeShortcuts { [weak self] in self?.translateShortcutPressed($0) }
        setUpToolsScreen()
        translate.sheet.openSettings = { [weak self] in self?.settingsWindow.show(.translate) }
        picker.translateRow = { [weak self] text, after in
            guard let self else { return (nil, .failure(.cancelled)) }
            return await self.translate.translateRow(text, after: after)
        }
        picker.openInSheet = { [weak self] in self?.translate.sheet.show(text: $0) }
        shortcutShown = Publishers.CombineLatest(settings.$shortcutEnabled, settings.$shortcut)
            .sink { [weak self] enabled, shortcut in self?.showShortcutInMenu(enabled ? shortcut : nil) }
        // `--shortcut`: says on stderr whether the system took the shortcut, then each press; quits after the first.
        if CommandLine.arguments.contains("--shortcut") {
            let label = GlobalShortcut.label(settings.shortcut)
            let state = !settings.shortcutEnabled ? "off" : settings.shortcutProblem.isEmpty ? "registered" : "refused: \(settings.shortcutProblem)"
            FileHandle.standardError.write(Data("shortcut \(label) \(state)\n".utf8))
            for (name, on, key) in [("history", settings.clipHistoryShortcutEnabled, settings.clipHistoryShortcut),
                                    ("snippets", settings.clipSnippetsShortcutEnabled, settings.clipSnippetsShortcut)] {
                let clipState = !settings.clipboardEnabled || !on ? "off" : settings.clipShortcutProblem.isEmpty ? "registered" : "refused: \(settings.clipShortcutProblem)"
                FileHandle.standardError.write(Data("shortcut \(GlobalShortcut.label(key)) \(name) \(clipState)\n".utf8))
            }
            for (name, on, key) in [("screenshot", settings.shotCaptureShortcutEnabled, settings.shotCaptureShortcut),
                                    ("full screen", settings.shotFullShortcutEnabled, settings.shotFullShortcut),
                                    ("last rectangle", settings.shotLastShortcutEnabled, settings.shotLastShortcut)] {
                let problem = settings.shotShortcutProblem.contains(GlobalShortcut.label(key)) ? settings.shotShortcutProblem : ""
                let shotState = !settings.shotEnabled || !on ? "off" : problem.isEmpty ? "registered" : "refused: \(problem)"
                FileHandle.standardError.write(Data("shortcut \(GlobalShortcut.label(key)) \(name) \(shotState)\n".utf8))
            }
            let dictationState = !settings.dictationEnabled || !settings.dictationShortcutEnabled ? "off"
                : settings.dictationShortcutProblem.isEmpty ? "registered" : "refused: \(settings.dictationShortcutProblem)"
            FileHandle.standardError.write(Data("shortcut \(GlobalShortcut.label(settings.dictationShortcut)) dictation \(dictationState)\n".utf8))
            let toolsState = !settings.toolsScreenEnabled || !settings.toolsScreenShortcutEnabled ? "off"
                : settings.toolsScreenShortcutProblem.isEmpty ? "registered" : "refused: \(settings.toolsScreenShortcutProblem)"
            FileHandle.standardError.write(Data("shortcut \(GlobalShortcut.label(settings.toolsScreenShortcut)) tools \(toolsState)\n".utf8))
            for (name, on, key) in [("translate", settings.translateShortcutEnabled, settings.translateShortcut),
                                    ("translate last copy", settings.translateClipShortcutEnabled, settings.translateClipShortcut)] {
                let problem = settings.translateShortcutProblem.contains(GlobalShortcut.label(key)) ? settings.translateShortcutProblem : ""
                let translateState = !settings.translateEnabled || !on ? "off" : problem.isEmpty ? "registered" : "refused: \(problem)"
                FileHandle.standardError.write(Data("shortcut \(GlobalShortcut.label(key)) \(name) \(translateState)\n".utf8))
            }
            Task { @MainActor in try? await Task.sleep(for: .seconds(30)); FileHandle.standardError.write(Data("shortcut: not pressed\n".utf8)); exit(2) }
        }
        // `--shot-demo [--snapshot out.png]`: a shot of the real screen with marks, the clipboard put back after.
        if CommandLine.arguments.contains("--shot-demo") {
            let shot = CommandLine.arguments.firstIndex(of: "--snapshot").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
            let shots = shots
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                exit(await ShotDemo.run(settings: settings, controller: shots, snapshot: shot.map { URL(fileURLWithPath: $0) }) ? 0 : 1)
            }
        }
        // `--translate "text" [--to he] [--model id]`, `--translate-bench [--runs 10]`,
        // `--translate-sheet "text" [--snapshot out.png]`: the translator from a terminal, through the real call.
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        if ProcessInfo.processInfo.environment["LEDGELINGS_FAKE_TRANSLATE"] != nil { translate.translator.fake = TranslateDemo.fake }
        if let text = value("--translate") {
            let translate = translate, spend = spend
            Task { @MainActor in
                translate.trace = { FileHandle.standardError.write(Data("  \($0)\n".utf8)) }
                exit(await TranslateDemo.once(text, to: value("--to"), model: value("--model"), controller: translate, settings: settings, spend: spend) ? 0 : 1)
            }
        }
        if args.contains("--translate-bench") {
            let translate = translate, spend = spend
            Task { @MainActor in
                exit(await TranslateDemo.bench(runs: value("--runs").flatMap(Int.init) ?? 10, controller: translate, settings: settings, spend: spend) ? 0 : 1)
            }
        }
        // `--tools [--snapshot out.png]`: the Tools screen on the real screen, written to a PNG, then closed.
        if args.contains("--tools") {
            let toolsScreen = toolsScreen
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                toolsScreen.trace = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
                toolsScreen.show()
                for tile in toolsScreen.model.tiles {
                    FileHandle.standardError.write(Data("tools \(tile.number) \(tile.tool.rawValue)\(tile.on ? "" : " (off)"): \(tile.tooltip)\n".utf8))
                }
                try? await Task.sleep(for: .seconds(1))
                if let out = value("--snapshot") { try? toolsScreen.snapshot(to: URL(fileURLWithPath: out)) }
                toolsScreen.close()
                exit(0)
            }
        }
        if let text = value("--translate-sheet") {
            let translate = translate
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                translate.trace = { FileHandle.standardError.write(Data("  \($0)\n".utf8)) }
                exit(await TranslateDemo.sheet(text, into: value("--to").flatMap(Translate.language), snapshot: value("--snapshot").map { URL(fileURLWithPath: $0) }, controller: translate) ? 0 : 1)
            }
        }
        // `--dictate-demo [--model id]`: a line the Mac says, through the real call, onto the clipboard; put back after.
        if CommandLine.arguments.contains("--dictate-demo") {
            let args = CommandLine.arguments
            let model = args.firstIndex(of: "--model").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
            let dictation = dictation, clips = clips
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                exit(await DictationDemo.run(settings: settings, controller: dictation, clips: clips, model: model) ? 0 : 1)
            }
        }
        // `--converse`: one conversation, every line and voice cue on stderr with
        // the time since it started, then quit once the pair is let go.
        // `--invite soccer|tag|basketball|baseball|tea`: it opens with that
        // invitation, and runs on until what was agreed has started (or lapsed).
        if CommandLine.arguments.contains("--converse"), let colony {
            let start = Date(), args = CommandLine.arguments
            colony.trace = { line in
                FileHandle.standardError.write(Data(String(format: "converse %6.2f  %@\n", Date().timeIntervalSince(start), line).utf8))
            }
            let invite = args.firstIndex(of: "--invite").flatMap { args.indices.contains($0 + 1) ? Deeds.Offer(word: args[$0 + 1]) : nil }
            colony.forcedOffer = invite
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                colony.talkNow()
                try? await Task.sleep(for: .seconds(1))
                for _ in 0..<900 where !colony.busy.isEmpty || !colony.chats.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
                colony.trace?("pair let go")
                if invite != nil {
                    for _ in 0..<1800 where !colony.agreed.isEmpty || colony.play != nil || colony.teaParty != nil || colony.teaInvite != nil {
                        try? await Task.sleep(for: .seconds(0.1))
                    }
                    colony.trace?("deeds done")
                }
                exit(0)
            }
        }
        // `--memory [name]`: every pair's memory (or those with `name`), as the
        // Relationships window and a prompt see it, on stderr; then quit.
        if let at = CommandLine.arguments.firstIndex(of: "--memory"), let colony {
            let args = CommandLine.arguments
            let only = args.indices.contains(at + 1) && !args[at + 1].hasPrefix("--") ? args[at + 1] : nil
            colony.memoryDump(only: only).forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            exit(0)
        }
        // `--memory-seed [--dry-run]`: read the last `seedDays` days of the chat log
        // into the pairs' memory, every step on stderr; the dry run sends and changes nothing.
        if CommandLine.arguments.contains("--memory-seed"), let colony {
            let dry = CommandLine.arguments.contains("--dry-run")
            Task { @MainActor in
                let report = await colony.seedMemory(dryRun: dry) { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
                if !dry { colony.memoryDump().forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) } }
                exit(report.pairs.isEmpty ? 1 : 0)
            }
        }
        // `--diary`: every pair with something new gets its diary now, whatever the
        // hour; what the model wrote on stderr, then quit.
        if CommandLine.arguments.contains("--diary"), let colony {
            colony.trace = { if $0.hasPrefix("memory") { FileHandle.standardError.write(Data(($0 + "\n").utf8)) } }
            Task { @MainActor in
                let n = colony.writeDiaries(force: true)
                colony.trace?("memory: \(n) pairs asked")
                for _ in 0..<1200 where !colony.writingMemory.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
                exit(n == 0 ? 1 : 0)
            }
        }
        // `--screens [all|N]`: every monitor, the choice and where each creature is, on stderr.
        // With `all` or a monitor's number (left to right, from 1) the choice is made live
        // (saved, as the menu would), every step of the move is printed, and it all again once they have landed.
        if let at = CommandLine.arguments.firstIndex(of: "--screens"), let colony {
            let args = CommandLine.arguments, start = Date()
            func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "screens %6.2f  %@\n", Date().timeIntervalSince(start), line).utf8)) }
            colony.trace = { if $0.hasPrefix("move") || $0.hasPrefix("screens") || $0.hasPrefix("let go") { log($0) } }
            let pick = args.indices.contains(at + 1) ? args[at + 1] : nil
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                colony.describeScreens().forEach(log)
                guard let pick else { exit(0) }
                let choices = ScreenChoice.attached
                if pick == "all" { settings.liveOn(nil) }
                else if let n = Int(pick), choices.indices.contains(n - 1) { settings.liveOn(choices[n - 1]) }
                else { log("no screen \(pick): all, or 1 to \(choices.count)"); exit(2) }
                try? await Task.sleep(for: .seconds(0.5))
                for _ in 0..<300 where !colony.moves.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
                try? await Task.sleep(for: .seconds(1))
                colony.describeScreens().forEach(log)
                exit(colony.creatures.allSatisfy { colony.isHome($0.position, slack: 1) } ? 0 : 1)
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
        // however long they have lived together; bond, story, their story so far
        // and prompt text on stderr, then quit.
        if CommandLine.arguments.contains("--plot"), let colony {
            let start = Date()
            colony.trace = { FileHandle.standardError.write(Data(String(format: "plot %6.2f  %@\n", Date().timeIntervalSince(start), $0).utf8)) }
            Task { @MainActor in
                guard colony.creatures.count >= 2 else { colony.trace?("needs two creatures"); exit(1) }
                let a = colony.character(forCreature: 0).name, b = colony.character(forCreature: 1).name
                colony.writePlotIfDue(a, b, now: true)
                // The built-in lines write it at once; a model in the background.
                guard colony.plotting.contains(Bonds.key(a, b)) || colony.bonds.bond(a, b)?.plot != nil else {
                    colony.trace?("not asked: \(colony.settings.brainProblem)"); exit(1)
                }
                while colony.plotting.contains(Bonds.key(a, b)) { try? await Task.sleep(for: .seconds(0.1)) }
                colony.trace?("story so far: \(colony.bonds.bond(a, b)?.chronicle ?? "-")")
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
        // `--actions [--activities]`: the Creature Actions sheet (on its Activities page); `--snapshot <file.png>` with it writes it to a file and quits.
        // `--relationships [--snapshot out.png]`: the Relationships window, written to a PNG.
        if CommandLine.arguments.contains("--relationships") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                relationshipsWindow.show()
                guard let shot = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(shot + 1) else { return }
                try? await Task.sleep(for: .seconds(2))
                do { try relationshipsWindow.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[shot + 1])) } catch { FileHandle.standardError.write(Data("Ledgelings snapshot: \(error)\n".utf8)) }
                exit(0)
            }
        }
        if CommandLine.arguments.contains("--actions") {
            let actions = actions
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                actions.show(page: CommandLine.arguments.contains("--activities") ? .activities : .main)
                guard let shot = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(shot + 1) else { return }
                try? await Task.sleep(for: .seconds(1))
                do { try actions.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[shot + 1])) } catch { FileHandle.standardError.write(Data("Ledgelings snapshot: \(error)\n".utf8)) }
                exit(0)
            }
        }
        // `--settings <page>` (any `SettingsPage`, or the old `productivity`): open the window at launch, for
        // looking at it from a script. `--settings-search <words>` opens it with them in the search box.
        let search = CommandLine.arguments.firstIndex(of: "--settings-search").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
        if let at = CommandLine.arguments.firstIndex(of: "--settings") ?? CommandLine.arguments.firstIndex(of: "--settings-search") {
            let name = CommandLine.arguments[at] == "--settings" && CommandLine.arguments.indices.contains(at + 1) ? CommandLine.arguments[at + 1] : ""
            settingsWindow.show(SettingsPage.named(name), search: search)
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
    /// Which monitor they live on; only with two or more attached.
    private let screenItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let clipHistoryItem = NSMenuItem(title: "", action: #selector(openClipHistory), keyEquivalent: "")
    private let clipSnippetsItem = NSMenuItem(title: "", action: #selector(openClipSnippets), keyEquivalent: "")
    private let editSnippetsItem = NSMenuItem(title: "", action: #selector(openSnippetsEditor), keyEquivalent: "")
    private let shotItem = NSMenuItem(title: "", action: #selector(takeShot), keyEquivalent: "")
    private let shotFullItem = NSMenuItem(title: "", action: #selector(takeFullShot), keyEquivalent: "")
    private let shotLastItem = NSMenuItem(title: "", action: #selector(takeLastShot), keyEquivalent: "")
    private let dictationItem = NSMenuItem(title: "", action: #selector(dictate), keyEquivalent: "")
    private let translateItem = NSMenuItem(title: "", action: #selector(openTranslate), keyEquivalent: "")
    private let toolsItem = NSMenuItem(title: "", action: #selector(openToolsScreen), keyEquivalent: "")
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
        activitiesItem.target = self
        menu.addItem(activitiesItem)
        nextReminderItem.target = self
        menu.addItem(nextReminderItem)
        for item in [toolsItem, clipHistoryItem, clipSnippetsItem, editSnippetsItem, shotItem, shotFullItem, shotLastItem, dictationItem, translateItem] {
            item.target = self
            menu.addItem(item)
        }
        voiceItem.target = self
        menu.addItem(voiceItem)
        revengeItem.target = self
        menu.addItem(revengeItem)
        deedsItem.target = self
        menu.addItem(deedsItem)

        talkStatusItem.isEnabled = false
        menu.addItem(talkStatusItem)
        chatsItem.target = self
        menu.addItem(chatsItem)
        relationshipsItem.target = self
        menu.addItem(relationshipsItem)
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
        menu.addItem(screenItem)
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
        activitiesItem.title = tr("Activities…")
        chatsItem.title = tr("Chat History…")
        deedsItem.title = tr("Deeds from Talk")
        relationshipsItem.title = tr("Relationships…")
        settingsItem.title = tr("Settings…")
        languageItem.title = tr("Language")
        quitItem.title = tr("Quit Ledgelings")
        clipHistoryItem.title = tr("Clipboard History…")
        clipSnippetsItem.title = tr("Paste a Snippet…")
        editSnippetsItem.title = tr("Edit Snippets…")
        for (item, shortcut, on) in [(clipHistoryItem, settings.clipHistoryShortcut, settings.clipHistoryShortcutEnabled),
                                     (clipSnippetsItem, settings.clipSnippetsShortcut, settings.clipSnippetsShortcutEnabled)] {
            item.isHidden = !settings.clipboardEnabled
            let key = GlobalShortcut.keyName(shortcut.keyCode).lowercased()
            item.keyEquivalent = on && key.count == 1 ? key : ""
            item.keyEquivalentModifierMask = GlobalShortcut.flags(shortcut.modifiers)
        }
        editSnippetsItem.isHidden = !settings.clipboardEnabled
        shotItem.title = tr("Take a Screenshot…")
        shotFullItem.title = tr("Screenshot the Full Screen")
        shotLastItem.title = tr("Screenshot the Last Rectangle")
        for (item, shortcut, on) in [(shotItem, settings.shotCaptureShortcut, settings.shotCaptureShortcutEnabled),
                                     (shotFullItem, settings.shotFullShortcut, settings.shotFullShortcutEnabled),
                                     (shotLastItem, settings.shotLastShortcut, settings.shotLastShortcutEnabled)] {
            item.isHidden = !settings.shotEnabled
            let key = GlobalShortcut.keyName(shortcut.keyCode).lowercased()
            item.keyEquivalent = on && key.count == 1 ? key : ""
            item.keyEquivalentModifierMask = GlobalShortcut.flags(shortcut.modifiers)
        }
        dictationItem.title = dictation.isRecording ? tr("Stop Dictating") : tr("Dictate")
        dictationItem.isHidden = !settings.dictationEnabled
        let dictationKey = GlobalShortcut.keyName(settings.dictationShortcut.keyCode).lowercased()
        dictationItem.keyEquivalent = settings.dictationShortcutEnabled && dictationKey.count == 1 ? dictationKey : ""
        dictationItem.keyEquivalentModifierMask = GlobalShortcut.flags(settings.dictationShortcut.modifiers)
        translateItem.title = tr("Translate…")
        translateItem.isHidden = !settings.translateEnabled
        let translateKey = GlobalShortcut.keyName(settings.translateShortcut.keyCode).lowercased()
        translateItem.keyEquivalent = settings.translateShortcutEnabled && translateKey.count == 1 ? translateKey : ""
        translateItem.keyEquivalentModifierMask = GlobalShortcut.flags(settings.translateShortcut.modifiers)
        toolsItem.title = tr("Tools…")
        toolsItem.isHidden = !settings.toolsScreenEnabled
        let toolsKey = GlobalShortcut.keyName(settings.toolsScreenShortcut.keyCode).lowercased()
        toolsItem.keyEquivalent = settings.toolsScreenShortcutEnabled && toolsKey.count == 1 ? toolsKey : ""
        toolsItem.keyEquivalentModifierMask = GlobalShortcut.flags(settings.toolsScreenShortcut.modifiers)
        for choice in languageItem.submenu?.items ?? [] {
            choice.state = choice.representedObject as? String == settings.language.rawValue ? .on : .off
        }
        cursorMoodItem.title = tr("The Cursor Is")
        screenItem.title = tr("Screen")
        screenItem.isHidden = !ScreenChoice.isOffered
        if ScreenChoice.isOffered {
            screenItem.submenu = ScreenChoice.menu(settings) { [weak self] in self?.settings.liveOn($0) }
        }
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
        deedsItem.state = settings.deedsEnabled ? .on : .off
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
    @objc private func toggleDeeds() { settings.deedsEnabled.toggle() }
    @objc private func openRelationships() { relationshipsWindow.show() }

    /// The seed, from the Relationships tab: its log in a line for the tab.
    private func seedMemory(dryRun: Bool) async -> String {
        guard let colony else { return tr("The creatures are not on screen.") }
        let report = await colony.seedMemory(dryRun: dryRun) { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        return dryRun ? tr("%@ to read, about %@ tokens to send. Nothing was sent.", trCount(report.pairs.count, "pair", "pairs"), "\(report.tokens)")
                      : tr("%@ read in. See them in Relationships….", trCount(report.pairs.count, "pair", "pairs"))
    }
    @objc private func openClipHistory() { picker.show(.recent) }
    @objc private func openClipSnippets() { picker.show(.snippets) }
    @objc private func openSnippetsEditor() { snippetsWindow.show() }
    // From the menu: once it has closed, so it is not in the picture.
    @objc private func takeShot() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); shots.withToolbar() } }
    @objc private func takeFullShot() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); shots.fullScreen() } }
    @objc private func takeLastShot() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); shots.lastRectangle() } }

    // From the menu: once it has closed, so the app in front is the one dictated into.
    @objc private func dictate() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); dictation.press() } }

    // From the menu: once it has closed, so the sheet knows the app that was in front.
    @objc private func openToolsScreen() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); toolsScreen.show() } }
    @objc private func openTranslate() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); translate.sheet.show() } }

    /// A translate shortcut from any app, for `--shortcut`: said, then quit once the sheet is closed.
    private func translateShortcutPressed(_ which: String) {
        guard CommandLine.arguments.contains("--shortcut") else { return }
        FileHandle.standardError.write(Data("shortcut pressed: \(which == "type" ? "translate" : "translate last copy")\n".utf8))
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); while translate.sheet.isUp { try? await Task.sleep(for: .seconds(0.2)) }; exit(0) }
    }

    /// The dictation shortcut from any app, for `--shortcut`: said, then quit once it has listened and written.
    private func dictationShortcutPressed() {
        guard CommandLine.arguments.contains("--shortcut") else { return }
        FileHandle.standardError.write(Data("shortcut pressed: dictation \(dictation.isRecording ? "stops" : "starts")\n".utf8))
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); while dictation.isBusy { try? await Task.sleep(for: .seconds(0.2)) }; exit(0) }
    }

    /// A screenshot shortcut from any app, for `--shortcut`: said, then quit once the shot is done with.
    private func shotShortcutPressed(_ name: String) {
        guard CommandLine.arguments.contains("--shortcut") else { return }
        FileHandle.standardError.write(Data("shortcut pressed: \(name)\n".utf8))
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); while shots.isUp { try? await Task.sleep(for: .seconds(0.2)) }; exit(0) }
    }

    /// A clipboard shortcut from any app: its picker up, or switched, or away.
    private func clipShortcutPressed(_ group: ClipPickerModel.Group) {
        picker.toggle(group)
        if CommandLine.arguments.contains("--shortcut") {
            FileHandle.standardError.write(Data("shortcut pressed: \(group == .recent ? "history" : "snippets") picker \(picker.isUp ? "up" : "away")\n".utf8))
            Task { @MainActor in try? await Task.sleep(for: .seconds(2)); exit(0) }
        }
    }

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
        case .tools:
            // The Actions sheet made Ledgelings the active app: give the keyboard back
            // first, so a tool that pastes pastes into the app you were in.
            NSApp.deactivate()
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); toolsScreen.show() }
        }
    }

    /// What each tile of the Tools screen starts, whether it is on, its shortcut, and its shortcut from any app.
    private func setUpToolsScreen() {
        toolsScreen.start = { [weak self] tool in
            guard let self else { return }
            switch tool {
            case .translate: translate.sheet.show()
            case .dictation: dictation.press()
            case .screenshot: shots.withToolbar()
            case .fullScreen: shots.fullScreen()
            case .lastRectangle: shots.lastRectangle()
            case .clipHistory: picker.show(.recent)
            case .snippets: picker.show(.snippets)
            case .reminder: openReminders()
            }
        }
        toolsScreen.isOn = { [weak self] tool in
            guard let s = self?.settings else { return false }
            switch tool {
            case .translate: return s.translateEnabled
            case .dictation: return s.dictationEnabled
            case .screenshot, .fullScreen, .lastRectangle: return s.shotEnabled
            case .clipHistory, .snippets: return s.clipboardEnabled
            case .reminder: return s.remindersEnabled
            }
        }
        toolsScreen.shortcutLabel = { [weak self] tool in
            guard let s = self?.settings else { return nil }
            let pair: (Bool, Shortcut)? = switch tool {
            case .translate: (s.translateShortcutEnabled, s.translateShortcut)
            case .dictation: (s.dictationShortcutEnabled, s.dictationShortcut)
            case .screenshot: (s.shotCaptureShortcutEnabled, s.shotCaptureShortcut)
            case .fullScreen: (s.shotFullShortcutEnabled, s.shotFullShortcut)
            case .lastRectangle: (s.shotLastShortcutEnabled, s.shotLastShortcut)
            case .clipHistory: (s.clipHistoryShortcutEnabled, s.clipHistoryShortcut)
            case .snippets: (s.clipSnippetsShortcutEnabled, s.clipSnippetsShortcut)
            case .reminder: nil
            }
            return pair.flatMap { $0.0 ? GlobalShortcut.label($0.1) : nil }
        }
        toolsScreen.openSettings = { [weak self] in self?.settingsWindow.show($0) }
        toolsScreen.takeShortcut { [weak self] in self?.toolsShortcutPressed() }
    }

    /// The Tools screen's shortcut from any app, for `--shortcut`: said, then quit once the screen is closed.
    private func toolsShortcutPressed() {
        guard CommandLine.arguments.contains("--shortcut") else { return }
        FileHandle.standardError.write(Data("shortcut pressed: tools\n".utf8))
        Task { @MainActor in try? await Task.sleep(for: .seconds(2)); while toolsScreen.isUp { try? await Task.sleep(for: .seconds(0.2)) }; exit(0) }
    }
    @objc private func toggleVoice() { settings.voiceEnabled.toggle() }
    @objc private func toggleRevenge() { settings.revengeEnabled.toggle() }
    /// The games, on the Actions sheet's inner page: Play Now for each, and games on or off.
    @objc private func openActivities() { actions.show(page: .activities) }

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
    @objc private func openChats() { settingsWindow.show(.chats) }
    @objc private func openReminders() { settings.reminderPaperNote ? note.show() : settingsWindow.show(.reminders) }
    @objc private func openReminderList() { settingsWindow.show(.reminders) }
    @objc private func openSpend() { settingsWindow.show(.costs) }
}
