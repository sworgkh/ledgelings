import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore
import SwiftUI

/// The Read aloud sheet (§7.16.1): the clipboard picker's pixel paper, the text
/// to read, the presets as chips, and the controls of the reading under it. It
/// opens in a panel that never makes Ledgelings the active app. A creature
/// brings it and reads beside it, nodding over the page.
@MainActor
final class ReadAloudSheetController {
    static let size = CGSize(width: 760, height: 470)

    private let settings: AppSettings
    let player: ReadAloudPlayer
    private let clips: ClipBook
    private let watcher: () -> ClipWatcher?
    private let helper: () -> ClipHelping?
    private var helped = false
    let model = ReadAloudSheetModel()
    private var panel: ClipPanel?
    private var monitor: Any?
    private var watching: Set<AnyCancellable> = []
    /// Everyone who can read, by name, every species' cast; the narrator is "".
    var readers: () -> [String] = { [] }
    /// Every step, for `--read-sheet` and the film.
    var trace: ((String) -> Void)?

    init(settings: AppSettings, player: ReadAloudPlayer, clips: ClipBook, watcher: @escaping () -> ClipWatcher?,
         helper: @escaping () -> ClipHelping? = { nil }) {
        self.settings = settings
        self.player = player
        self.clips = clips
        self.watcher = watcher
        self.helper = helper
        model.act = { [weak self] in self?.act($0) }
        model.choose = { [weak self] in self?.choosePreset($0) }
        model.close = { [weak self] in self?.close() }
        model.edited = { [weak self] in self?.edited() }
        player.changed = { [weak self] in self?.phaseChanged($0) }
        settings.$readAloudPresets.sink { [weak self] presets in
            guard let self else { return }
            self.model.presets = presets
            if !presets.contains(where: { $0.id == self.model.presetID }) { self.model.presetID = presets.first?.id }
        }.store(in: &watching)
    }

    var isUp: Bool { panel != nil }

    // MARK: Opening and closing

    /// The shortcut: up with the clipboard's text (and reading it, as the settings say); pressed again while up, it closes.
    func toggle() {
        if isUp { close(); return }
        if player.isActive { show(text: nil, start: false); return }
        let copied = settings.readAloudFromClipboard ? NSPasteboard.general.string(forType: .string) : nil
        if let copied, ReadAloud.refusal(copied, snippets: clips.snippets) == .protected {
            show(text: "", start: false)
            model.tell(ReadAloud.Refusal.protected.line, trouble: true)
            return
        }
        show(text: copied ?? "", start: settings.readAloudStartAtOnce && copied != nil)
    }

    /// Up holding `text` (nil: what is being read now); `start` reads it at once.
    func show(text: String?, start: Bool, preset: ReadAloud.Preset? = nil, on given: NSScreen? = nil) {
        model.presets = settings.readAloudPresets
        if let text {
            model.text = text
            model.textView?.string = text
            let chosen = preset ?? settings.readAloudDefault
            model.presetID = chosen.id
            // A preset handed in as it is (a script's `--engine`), not looked up again by its id.
            model.given = preset
            model.reader = chosen.character
            model.speed = chosen.speed
            model.note = ""
            model.waitingForEnter = false
            if player.phase == .finished || player.phase == .trouble || player.phase == .idle { model.fresh = true }
        } else {
            model.text = player.text
            model.textView?.string = player.text
            model.fresh = false
        }
        model.readers = [""] + readers()
        guard panel == nil else { if start { readNow() }; return }
        let screen = given ?? ClipPickerController.screen(caret: ClipPaster.caret())
        let made = ClipPanel(frame: screen.visibleFrame)
        let paper = CGRect(x: (screen.visibleFrame.width - Self.size.width) / 2, y: (screen.visibleFrame.height - Self.size.height) / 2,
                           width: Self.size.width, height: Self.size.height).integral
        model.paper = paper
        model.unfolded = !settings.clipAnimate
        let hosting = NSHostingView(rootView: ReadAloudSheetView(model: model, player: player))
        hosting.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        made.contentView = hosting
        panel = made
        made.makeKeyAndOrderFront(nil)
        trace?("read sheet open on \(screen.localizedName), \(model.text.count) characters")
        let frame = screen.visibleFrame
        let wait = settings.readAloudHelperEnabled
            ? helper()?.clipHelperCome(paper: paper.offsetBy(dx: frame.minX, dy: frame.maxY - paper.maxY - paper.minY),
                                       centre: CGPoint(x: frame.midX, y: frame.midY), wanted: settings.readAloudHelper) : nil
        helped = wait != nil
        model.anchor = helped ? .topLeading : .center
        if settings.clipAnimate {
            let unfold = { [weak self] in
                guard let self, self.isUp else { return }
                withAnimation(.easeOut(duration: ClipHelper.unfoldSeconds / self.settings.clipAnimationSpeed)) { self.model.unfolded = true }
            }
            if let wait { Task { @MainActor in try? await Task.sleep(for: .seconds(wait)); unfold() } } else { unfold() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode), flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self?.key(code, flags) ?? false }
            return handled ? nil : event
        }
        phaseChanged(player.phase)
        if start { readNow() }
    }

    /// Gone; the reading goes on if the settings say so (the menu's Stop Reading ends it), else it stops.
    func close() {
        guard let panel else { return }
        if !settings.readAloudKeepReading || player.phase == .paused { player.stop() }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        self.panel = nil
        model.textView = nil
        if helped {
            helper()?.clipHelperMood(.calm)
            helper()?.clipHelperGoHome(after: 0)
        }
        helped = false
        trace?("read sheet close\(player.isActive ? ", still reading" : "")")
    }

    // MARK: Keys

    /// A key pressed on the sheet; false lets it through to the text box.
    func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let box = model.textView
        switch code {
        case kVK_Escape: close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if shift { return false }
            act(.play)
        case kVK_ANSI_Period where command: act(.stop)
        case kVK_ANSI_S where command: act(.save)
        case kVK_ANSI_C where command && shift: act(.copy)
        case kVK_ANSI_Minus where command: act(.slower)
        case kVK_ANSI_Equal where command: act(.faster)
        case kVK_ANSI_R where command: act(.reader)
        case kVK_Delete where command: clear()
        // A menu-bar app has no Edit menu to send these to the text box: they are sent here.
        case kVK_ANSI_A where command: box?.selectAll(nil)
        case kVK_ANSI_C where command: box?.copy(nil)
        case kVK_ANSI_X where command: box?.cut(nil)
        case kVK_ANSI_V where command: box?.paste(nil)
        case kVK_ANSI_Z where command: shift ? box?.undoManager?.redo() : box?.undoManager?.undo()
        default:
            if command, let n = Self.digits.firstIndex(of: code) { choosePreset(n); return true }
            return false
        }
        return true
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func act(_ button: ReadAloud.Button) {
        switch button {
        case .play, .pause:
            switch player.phase {
            case .playing: player.pause()
            case .paused: player.resume()
            case .preparing: player.stop()
            default: readNow(confirmed: model.waitingForEnter)
            }
        case .stop: player.stop()
        case .save: save()
        case .copy: copy()
        case .slower: pace(by: -1)
        case .faster: pace(by: 1)
        case .reader: nextReader()
        case .readRow: break
        }
    }

    /// ⌘1…: that preset, its reader and pace with it.
    func choosePreset(_ n: Int) {
        guard model.presets.indices.contains(n) else { NSSound.beep(); return }
        let preset = model.presets[n]
        model.presetID = preset.id
        model.given = nil
        model.reader = preset.character
        model.speed = preset.speed
        model.waitingForEnter = false
        model.note = ""
        trace?("read preset \(preset.name)")
        if player.isActive { player.setPace(model.speed) }
    }

    private func pace(by steps: Int) {
        model.speed = ReadAloud.step(model.speed, by: steps)
        if player.isActive { player.setPace(model.speed) }
        trace?("read pace \(ReadAloud.speedLabel(model.speed))")
    }

    /// ⌘R: the next reader, the narrator first, then every character of every species; for the next reading.
    private func nextReader() {
        let all = model.readers.isEmpty ? [""] : model.readers
        let at = all.firstIndex(of: model.reader) ?? -1
        model.reader = all[(at + 1) % all.count]
        model.waitingForEnter = false
        trace?("read reader \(model.reader.isEmpty ? "narrator" : model.reader)")
    }

    private func clear() {
        model.text = ""
        model.textView?.string = ""
        edited()
    }

    /// Typing changes what ⏎ will read; a long text asks again.
    func edited() {
        model.waitingForEnter = false
        model.note = ""
        model.fresh = true
    }

    // MARK: Reading

    /// ⏎: read the text with the chosen preset. Above the long-text limit a paid
    /// reading first shows its parts and price, and reads on the next ⏎.
    func readNow(confirmed: Bool = false) {
        let text = model.text
        if let refusal = ReadAloud.refusal(text, snippets: clips.snippets) {
            model.tell(refusal.line, trouble: true)
            NSSound.beep()
            trace?("read refused: \(refusal.line)")
            return
        }
        let preset = model.preset
        if !confirmed, text.count > settings.readAloudLongLimit, player.plan(preset).engine.isPaid {
            let parts = ReadAloud.parts(text, forced: preset.forcedLanguage).count
            model.waitingForEnter = true
            model.tell(player.estimate(text, preset).map {
                tr("%@ · %@ · about %@ · ⏎ reads", grouped(text.count), trCount(parts, "part", "parts"), Spend.label($0))
            } ?? tr("%@ · %@ · ⏎ reads", grouped(text.count), trCount(parts, "part", "parts")), trouble: false)
            trace?("read waits for ⏎: \(model.note)")
            return
        }
        model.waitingForEnter = false
        model.note = ""
        model.fresh = false
        player.read(text, preset: preset)
    }

    private func grouped(_ n: Int) -> String { trCount(n, "character", "characters") }

    private func phaseChanged(_ phase: ReadAloudPlayer.Phase) {
        guard helped else { return }
        switch phase {
        case .preparing: helper()?.clipHelperMood(.thinking)
        case .playing: helper()?.clipHelperMood(.reading)
        case .trouble: helper()?.clipHelperMood(.puzzled)
        case .idle, .paused, .finished: helper()?.clipHelperMood(.calm)
        }
    }

    // MARK: The sound out

    /// ⌘S: the reading as one file in the save folder, named by its time and first words.
    func save() {
        guard player.hasSound else { model.tell(tr("Nothing read yet: ⏎ reads it first"), trouble: true); NSSound.beep(); return }
        let folder = settings.readAloudFolderURL
        let url = folder.appendingPathComponent(ReadAloud.fileName(for: player.text, at: Date(), format: settings.readAloudFormat))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try player.write(to: url, format: settings.readAloudFormat)
            model.tell(player.isComplete ? tr("Saved: %@", url.lastPathComponent) : tr("Saved what is read so far: %@", url.lastPathComponent), trouble: false)
            model.savedURL = url
            trace?("read saved \(url.path)")
        } catch {
            model.tell(tr("Could not save in %@: %@", folder.path, error.localizedDescription), trouble: true)
            trace?("read save trouble: \(error)")
        }
    }

    /// ⌘⇧C: the reading as a file on the clipboard, to drop into a chat or a mail.
    func copy() {
        guard player.hasSound else { model.tell(tr("Nothing read yet: ⏎ reads it first"), trouble: true); NSSound.beep(); return }
        let folder = ReadAloudPlayer.copyFolder
        try? FileManager.default.removeItem(at: folder)
        let url = folder.appendingPathComponent(ReadAloud.fileName(for: player.text, at: Date(), format: settings.readAloudFormat))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try player.write(to: url, format: settings.readAloudFormat)
            let board = NSPasteboard.general
            board.clearContents()
            board.writeObjects([url as NSURL])
            watcher()?.ownWrite()
            model.tell(tr("The sound file is on the clipboard: ⌘V drops it into a chat or a mail"), trouble: false)
            trace?("read copied \(url.lastPathComponent)")
        } catch {
            model.tell(tr("Could not copy the sound: %@", error.localizedDescription), trouble: true)
        }
    }

    // MARK: Pictures

    /// The paper as a PNG, for `--read-sheet --snapshot`.
    func snapshot(to url: URL) throws {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: model.paper) else { return }
        view.cacheDisplay(in: model.paper, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: The model

@MainActor
final class ReadAloudSheetModel: ObservableObject {
    @Published var text = ""
    @Published var presets: [ReadAloud.Preset] = ReadAloud.defaultPresets
    @Published var presetID: UUID?
    /// The preset as it was handed to the sheet, when it was; wins over the saved one of the same id.
    var given: ReadAloud.Preset?
    /// The character reading, chosen on the sheet; "" is the narrator.
    @Published var reader = ""
    @Published var readers: [String] = [""]
    /// The pace, chosen on the sheet: the preset's to begin with.
    @Published var speed = 1.0
    /// A long paid text shows its price and waits for a second ⏎.
    @Published var waitingForEnter = false
    /// Why nothing is read, or what happened to the file; over the player's own status.
    @Published var note = ""
    /// The note is trouble (drawn in the rim's dark ink), not news.
    @Published var noteIsTrouble = false
    /// The text was changed since the reading on show: ⏎ reads it afresh.
    @Published var fresh = true
    @Published var savedURL: URL?

    func tell(_ line: String, trouble: Bool) {
        note = line
        noteIsTrouble = trouble
    }
    @Published var unfolded = true
    @Published var anchor = UnitPoint.center
    @Published var paper = CGRect.zero
    weak var textView: NSTextView?

    var act: (ReadAloud.Button) -> Void = { _ in }
    var choose: (Int) -> Void = { _ in }
    var close: () -> Void = {}
    var edited: () -> Void = {}

    /// The preset chosen, with the reader and pace chosen on the sheet.
    var preset: ReadAloud.Preset {
        var p = given.flatMap { $0.id == presetID ? $0 : nil } ?? presets.first { $0.id == presetID } ?? presets.first ?? ReadAloud.defaultPresets[0]
        if p.character != reader {
            // Another reader than the preset's: its voice is cast for that reader, not the preset's own.
            p.character = reader
            p.voice = ""
        }
        p.speed = speed
        return p
    }

    var readerTitle: String { reader.isEmpty ? tr("NARRATOR") : reader.uppercased() }
}

// MARK: The sheet

struct ReadAloudSheetView: View {
    @ObservedObject var model: ReadAloudSheetModel
    @ObservedObject var player: ReadAloudPlayer

    static let ink = Color(cgColor: ScreenOverlay.ink)
    static let softInk = Color(cgColor: ScreenOverlay.softInk)
    static let faintInk = Color(cgColor: ScreenOverlay.faintInk)
    static let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)

    var body: some View {
        let paper = model.paper
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { model.close() }
            sheet
                .frame(width: paper.width, height: paper.height)
                .scaleEffect(model.unfolded ? 1 : 0.06, anchor: model.anchor)
                .opacity(model.unfolded ? 1 : 0)
                .offset(x: paper.minX, y: paper.minY)
        }
    }

    private var sheet: some View {
        let size = model.paper.size
        return ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(tr("READ ALOUD")).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    Spacer()
                }
                .padding(.bottom, 8)
                presets.padding(.bottom, 8)
                ReadTextBox(model: model)
                    .padding(.horizontal, 6).padding(.vertical, 6)
                    .background(PixelBox(style: .well))
                    .frame(height: 210)
                controls.padding(.top, 10)
                progress.padding(.top, 10)
                statusLine.padding(.top, 8)
                Spacer(minLength: 0)
                Text(tr("⏎ READ · PAUSE  ⇧⏎ NEW LINE  ⌘. STOP  ⌘− ⌘= PACE  ⌘1–9 PRESET  ⌘R READER  ⌘S SAVE  ⌘⇧C COPY  ⎋ CLOSE"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Self.faintInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.trailing, 60)
            }
            .padding(.horizontal, 27)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.presets.enumerated()), id: \.element.id) { i, preset in
                Button { model.choose(i) } label: { Text(preset.title.uppercased()) }
                    .buttonStyle(PixelButtonStyle(small: true, chosen: model.presetID == preset.id))
                    .modifier(PixelTag(text: Self.tag(preset, number: i + 1)))
            }
            Spacer(minLength: 0)
        }
    }

    /// "Bedtime: Zed, 0.8× (⌘3)".
    static func tag(_ preset: ReadAloud.Preset, number: Int) -> String {
        let who = preset.character.isEmpty ? (preset.voice.isEmpty ? tr("a narrator") : preset.voice) : preset.character
        return tr("%@: %@, %@ (⌘%d)", preset.title, who, ReadAloud.speedLabel(preset.speed), number)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            ReadAloudButtonView(button: player.phase == .playing ? .pause : .play, chosen: player.phase == .playing) { model.act(.play) }
            ReadAloudButtonView(button: .stop) { model.act(.stop) }.opacity(player.isActive ? 1 : 0.45)
            Spacer().frame(width: 14)
            ReadAloudButtonView(button: .slower) { model.act(.slower) }
            Text(ReadAloud.speedLabel(model.speed))
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(Self.ink)
                .frame(width: 48)
            ReadAloudButtonView(button: .faster) { model.act(.faster) }
            Spacer().frame(width: 14)
            ReadAloudButtonView(button: .reader) { model.act(.reader) }
            Text(model.readerTitle)
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(Self.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            ReadAloudButtonView(button: .save) { model.act(.save) }.opacity(player.hasSound ? 1 : 0.45)
            ReadAloudButtonView(button: .copy) { model.act(.copy) }.opacity(player.hasSound ? 1 : 0.45)
        }
    }

    private var progress: some View {
        let rate = max(player.rate, 0.01)
        let shown = player.length > 0 ? min(player.played / player.length, 1) : 0
        let ready = player.partsTotal > 0 ? Double(player.partsReady) / Double(player.partsTotal) : 0
        return HStack(spacing: 10) {
            GeometryReader { g in
                let inner = max(g.size.width - 8, 0)
                ZStack(alignment: .leading) {
                    PixelBox(style: .well)
                    Rectangle().fill(Self.faintInk.opacity(0.35)).frame(width: inner * ready, height: 10).offset(x: 4)
                    Rectangle().fill(Color(red: 1, green: 138 / 255, blue: 61 / 255)).frame(width: inner * shown, height: 10).offset(x: 4)
                }
            }
            .frame(height: 18)
            Text(player.partsTotal == 0 ? "0:00 / 0:00"
                 : "\(ReadAloud.clock(player.played / rate)) / \(player.isComplete ? "" : "~")\(ReadAloud.clock(player.length / rate))")
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Self.softInk)
                .frame(width: 104, alignment: .trailing)
        }
    }

    private var statusLine: some View {
        let trouble = model.note.isEmpty ? player.phase == .trouble : model.noteIsTrouble
        let line = !model.note.isEmpty ? model.note
            : !player.status.isEmpty ? player.status
            : tr("Paste or type, choose a preset, and ⏎ reads it.")
        return HStack(spacing: 8) {
            if player.phase == .preparing { Text("•••").foregroundStyle(Self.softInk) }
            Text(line)
                .foregroundStyle(trouble ? PixelBox.rim : Self.softInk)
                .lineLimit(2)
            Spacer()
        }
        .font(.system(size: 11, weight: .heavy, design: .monospaced))
    }
}

/// One of Read aloud's pixel buttons: its picture, and its name and key on hover.
struct ReadAloudButtonView: View {
    let button: ReadAloud.Button
    var chosen = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { PixelIcon(rows: button.icon) }
            .buttonStyle(PixelButtonStyle(small: true, chosen: chosen, square: true))
            .modifier(PixelTag(text: button.tooltip))
            .accessibilityLabel(button.tooltip)
    }
}

// MARK: The text box

/// The text to read: a real text view, so Hebrew runs right to left and the
/// usual keys work; what is typed is what ⏎ reads.
struct ReadTextBox: NSViewRepresentable {
    @ObservedObject var model: ReadAloudSheetModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let box = NSTextView()
        box.isRichText = false
        box.allowsUndo = true
        box.drawsBackground = false
        box.font = ReadAloudSheetView.font
        box.textColor = NSColor(cgColor: ScreenOverlay.ink)
        box.insertionPointColor = NSColor(cgColor: ScreenOverlay.ink) ?? .black
        box.alignment = .natural
        box.baseWritingDirection = .natural
        box.isAutomaticQuoteSubstitutionEnabled = false
        box.isAutomaticDashSubstitutionEnabled = false
        box.isAutomaticTextReplacementEnabled = false
        box.isVerticallyResizable = true
        box.autoresizingMask = [.width]
        box.textContainer?.widthTracksTextView = true
        box.delegate = context.coordinator
        box.string = model.text
        scroll.documentView = box
        model.textView = box
        DispatchQueue.main.async { box.window?.makeFirstResponder(box) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let box = scroll.documentView as? NSTextView else { return }
        if box.string != model.text { box.string = model.text }
        model.textView = box
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: ReadAloudSheetModel
        init(model: ReadAloudSheetModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSTextView else { return }
            model.text = box.string
            model.edited()
        }
    }
}
