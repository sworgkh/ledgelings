import AppKit
import Carbon.HIToolbox
import LedgelingsCore
import SwiftUI

/// The Translate sheet (§7.14.1): the clipboard picker's pixel paper, the text
/// you type on the left and its translation on the right, live, the rest of the
/// phrase guessed in grey. It opens in a panel that never makes Ledgelings the
/// active app, so ⌘⏎ pastes back into the app you were in. A creature brings it.
@MainActor
final class TranslateSheetController {
    static let size = CGSize(width: 760, height: 470)

    private let settings: AppSettings
    private let translator: Translator
    private let clips: ClipBook
    /// The saved translations, behind the star (⌘D) and in the drawer (⌘L).
    let saved: SavedTranslations
    private let watcher: () -> ClipWatcher?
    private let helper: () -> ClipHelping?
    private var helped = false
    let model = TranslateSheetModel()
    private var panel: ClipPanel?
    private var monitor: Any?
    private var previous: NSRunningApplication?
    private var caret: CGRect?
    /// The translation in flight, and the guess: a newer keystroke cancels both.
    private var working: Task<Void, Never>?
    private var guessing: Task<Void, Never>?
    /// Every step, for the film and the demo.
    var trace: ((String) -> Void)?
    /// Off in the film and the demo: never press ⌘V into whatever app is in front.
    var pressKeys = true
    /// Opens Settings › Translate.
    var openSettings: () -> Void = {}

    init(settings: AppSettings, translator: Translator, clips: ClipBook, saved: SavedTranslations, watcher: @escaping () -> ClipWatcher?,
         helper: @escaping () -> ClipHelping? = { nil }) {
        self.settings = settings
        self.translator = translator
        self.clips = clips
        self.saved = saved
        self.watcher = watcher
        self.helper = helper
        model.edited = { [weak self] in self?.edited() }
        model.act = { [weak self] in self?.act($0) }
        model.close = { [weak self] in self?.close() }
        model.load = { [weak self] in self?.load($0) }
        model.copySaved = { [weak self] in self?.copySaved($0) }
        model.removeSaved = { [weak self] in self?.removeSaved($0) }
    }

    var isUp: Bool { panel != nil }

    // MARK: Opening and closing

    /// Up, empty or holding `text`, which is translated at once. Pressed again while up, it closes.
    func toggle(text: String? = nil) {
        if isUp, text == nil { close(); return }
        show(text: text)
    }

    func show(text: String? = nil, into target: Translate.Language? = nil, on given: NSScreen? = nil) {
        translator.refresh()
        if !isUp {
            previous = NSWorkspace.shared.frontmostApplication
            if previous?.bundleIdentifier == Bundle.main.bundleIdentifier { previous = nil }
            caret = ClipPaster.caret()
        }
        model.languages = settings.translateLanguagesOn
        model.targets = settings.translateTargets
        model.sourceChoice = nil
        model.targetChoice = target
        model.appName = previous?.localizedName
        model.hasModel = translator.hasModel
        model.text = text ?? ""
        model.result = ""
        model.guess = ""
        model.state = .idle
        model.status = ""
        model.savedOn = settings.translateSavedEnabled
        saved.prune(limit: settings.translateSavedLimit)
        refreshSaved()
        if !isUp {
            model.query = ""
            model.drawerOpen = model.savedOn && settings.translateSavedOpenDrawer
            model.drawerHasKeys = false
        }
        guard panel == nil else { edited(now: true); return }
        let (screen, paper) = WindowPlacer.paper(.translate, size: Self.size, screen: given ?? ClipPickerController.screen(caret: caret), settings: settings)
        let made = ClipPanel(frame: screen.visibleFrame)
        model.paper = paper
        model.room = screen.visibleFrame.size
        model.moved = { [settings] in WindowPlacer.paperMoved(.translate, paper: $0, room: screen.visibleFrame, settings: settings) }
        model.unfolded = !settings.clipAnimate
        let hosting = NSHostingView(rootView: TranslateSheetView(model: model))
        hosting.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        made.contentView = hosting
        panel = made
        made.makeKeyAndOrderFront(nil)
        trace?("translate open on \(screen.localizedName)\(text.map { ", \($0.count) characters" } ?? "")")
        let frame = screen.visibleFrame
        let wait = settings.translateHelperEnabled
            ? helper()?.clipHelperCome(paper: paper.offsetBy(dx: frame.minX, dy: frame.maxY - paper.maxY - paper.minY),
                                       centre: CGPoint(x: frame.midX, y: frame.midY), wanted: settings.translateHelper) : nil
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
        if text != nil { edited(now: true) }
        if model.drawerOpen { trace?("drawer open with the sheet on the \(model.drawerSide), \(saved.book.count) saved") }
    }

    func close() {
        guard let panel else { return }
        working?.cancel()
        guessing?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        self.panel = nil
        model.textView = nil
        model.drawerOpen = false
        model.drawerHasKeys = false
        if helped {
            helper()?.clipHelperMood(.calm)
            helper()?.clipHelperGoHome(after: 0)
        }
        helped = false
        trace?("translate close")
    }

    // MARK: Keys

    /// A key pressed on the sheet; false lets it through to the text box.
    func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let command = flags.contains(.command), option = flags.contains(.option), shift = flags.contains(.shift)
        let inDrawer = drawerHasKeys
        if inDrawer, drawerKey(code, flags) { return true }
        // In the drawer the editing keys go to its search box, not the text.
        let box = inDrawer ? panel?.firstResponder as? NSTextView : model.textView
        switch code {
        // The drawer closes first, the sheet after.
        case kVK_Escape: model.drawerOpen ? toggleDrawer() : close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if shift { return false }
            act(command ? .paste : .copy)
        case kVK_Tab:
            if model.guess.isEmpty { return !shift && !option ? true : false }
            takeGuess()
        case kVK_ANSI_S where command: act(.swap)
        case kVK_Delete where command: act(.clear)
        case kVK_ANSI_D where command: act(.save)
        case kVK_ANSI_L where command: act(.savedList)
        // A menu-bar app has no Edit menu to send these to the text box: they are sent here.
        case kVK_ANSI_A where command: box?.selectAll(nil)
        case kVK_ANSI_C where command: box?.copy(nil)
        case kVK_ANSI_X where command: box?.cut(nil)
        case kVK_ANSI_V where command: box?.paste(nil)
        case kVK_ANSI_Z where command: shift ? box?.undoManager?.redo() : box?.undoManager?.undo()
        default:
            if let n = Self.digits.firstIndex(of: code) {
                if command, !option { chooseSource(n); return true }
                if option, !command { chooseTarget(n); return true }
            }
            return false
        }
        return true
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]

    /// The drawer holds the keys while its search box does (or, with no panel, while it is open).
    private var drawerHasKeys: Bool {
        guard model.drawerOpen else { return false }
        guard let panel, let box = model.textView else { return model.drawerHasKeys }
        return panel.firstResponder !== box
    }

    /// ↑↓ move, ⏎ loads, ⌫ deletes (⌘⌫ even while searching), ⌘C copies the row unless words in the search box are selected.
    private func drawerKey(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let command = flags.contains(.command)
        let field = panel?.firstResponder as? NSTextView
        switch code {
        case kVK_DownArrow: model.step(1)
        case kVK_UpArrow: model.step(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter: if let row = model.selectedEntry { load(row) } else { NSSound.beep() }
        case kVK_Delete where command || model.query.isEmpty, kVK_ForwardDelete where model.query.isEmpty: act(.deleteSaved)
        case kVK_ANSI_C where command && (field?.selectedRange().length ?? 0) == 0: act(.copySaved)
        default: return false
        }
        return true
    }

    /// ⌘1 Detect, ⌘2… each language on.
    func chooseSource(_ n: Int) {
        guard n <= model.languages.count else { NSSound.beep(); return }
        model.sourceChoice = n == 0 ? nil : model.languages[n - 1]
        edited(now: true)
    }

    /// ⌥1… each language on.
    func chooseTarget(_ n: Int) {
        guard model.languages.indices.contains(n) else { NSSound.beep(); return }
        model.targetChoice = model.languages[n]
        edited(now: true)
    }

    func act(_ button: Translate.Button) {
        switch button {
        case .copy:
            // ⏎ on a long text, or after trouble, translates; with a translation, it copies.
            if model.state == .waitingForEnter || model.state == .trouble { translateNow(); return }
            guard !model.result.isEmpty, model.state == .done else { NSSound.beep(); return }
            deliver(paste: false)
        case .paste:
            guard !model.result.isEmpty, model.state == .done else { NSSound.beep(); return }
            deliver(paste: true)
        case .swap: swap()
        case .clear:
            model.text = ""
            model.textView?.string = ""
            edited(now: true)
        case .save: toggleSave()
        case .savedList: toggleDrawer()
        case .copySaved: if let row = model.selectedEntry { copySaved(row) } else { NSSound.beep() }
        case .deleteSaved: if let row = model.selectedEntry { removeSaved(row) } else { NSSound.beep() }
        case .translate, .openSheet: break
        }
    }

    // MARK: Saved translations

    /// The star: the translation on show is saved, or no longer. Only a finished one; else a beep, as copy does.
    func toggleSave() {
        guard model.savedOn, model.state == .done, !model.result.isEmpty, let source = model.source else { NSSound.beep(); return }
        let target = model.resultLanguage ?? model.target
        let entry = Translate.Saved(text: model.text, from: source.code, translation: model.result, to: target.code, savedAt: Date(), app: model.appName)
        let now = saved.toggle(entry, limit: settings.translateSavedLimit)
        refreshSaved()
        trace?("\(now ? "saved" : "unsaved") \(source.code)→\(target.code): \(model.text.prefix(60)) (\(saved.book.count) saved)")
    }

    /// The drawer of saved translations slides out of the sheet's side, or back in.
    func toggleDrawer() {
        guard model.savedOn else { NSSound.beep(); return }
        let open = !model.drawerOpen
        withAnimation(.easeOut(duration: 0.22)) { model.drawerOpen = open }
        model.drawerHasKeys = open
        if open {
            model.query = ""
            refreshSaved()
            model.selectedSaved = model.shownSaved.first?.id
            trace?("drawer open on the \(model.drawerSide), \(saved.book.count) saved")
        } else {
            if let box = model.textView { box.window?.makeFirstResponder(box) }
            trace?("drawer closed")
        }
    }

    /// A saved translation back in the sheet: its text, languages and translation, from the saved copy; no call.
    func load(_ entry: Translate.Saved) {
        guard let from = Translate.language(entry.from), let to = Translate.language(entry.to) else { NSSound.beep(); return }
        working?.cancel()
        guessing?.cancel()
        model.text = entry.text
        model.textView?.string = entry.text
        model.detected = Translate.detect(Translate.protect(entry.text).text, among: model.languages)
        model.sourceChoice = model.detected == from ? nil : from
        model.targetChoice = to
        model.guess = ""
        model.result = entry.translation
        model.resultLanguage = to
        model.state = .done
        model.status = tr("%@ → %@ · saved %@", from.title, to.title, Translate.savedDate(entry.savedAt)).uppercased()
        model.selectedSaved = entry.id
        refreshSaved()
        trace?("loaded saved \(from.code)→\(to.code): \(entry.text.prefix(60))")
    }

    /// A row's translation on the clipboard; the sheet stays.
    func copySaved(_ entry: Translate.Saved) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(entry.translation, forType: .string)
        watcher()?.ownWrite()
        keepInHistory(entry.translation, clips: clips, settings: settings)
        model.status = tr("Copied the translation")
        trace?("copied saved: \(entry.translation.prefix(60))")
    }

    /// A row deleted; the one below it is chosen next.
    func removeSaved(_ entry: Translate.Saved) {
        let at = model.shownSaved.firstIndex { $0.id == entry.id } ?? 0
        saved.remove(entry.id)
        refreshSaved()
        let left = model.shownSaved
        model.selectedSaved = left.isEmpty ? nil : left[min(at, left.count - 1)].id
        trace?("deleted saved: \(entry.text.prefix(60)) (\(saved.book.count) left)")
    }

    /// The model's copy of the book, and whether the translation on show is in it.
    func refreshSaved() {
        model.saved = saved.book
        if let source = model.source, model.state == .done {
            model.isSaved = saved.book.find(text: model.text, from: source.code, to: (model.resultLanguage ?? model.target).code) != nil
        } else {
            model.isSaved = false
        }
        if let id = model.selectedSaved, !model.shownSaved.contains(where: { $0.id == id }) { model.selectedSaved = model.shownSaved.first?.id }
    }

    // MARK: Typing

    /// The text changed (or a language did): the guess kept if the new letters
    /// are its start, else dropped; the translation asked for after the wait.
    func edited(now: Bool = false) {
        working?.cancel()
        guessing?.cancel()
        let text = model.text
        model.isSaved = false
        model.detected = Translate.detect(Translate.protect(text).text, among: model.languages)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.result = ""
            model.state = .idle
            model.status = ""
            helper()?.clipHelperMood(.calm)
            return
        }
        if let refusal = Translate.refusal(text, snippets: clips.snippets) {
            model.result = ""
            model.state = .refused
            model.status = refusal.line
            return
        }
        guard model.hasModel else {
            model.state = .trouble
            model.status = Translator.Trouble.noModel.line
            return
        }
        if text.count > settings.translateLiveLimit && !now {
            let parts = Translate.parts(text).count
            model.state = .waitingForEnter
            model.status = settings.translateModel == Translate.defaultModel
                ? tr("%@ · about %@ · ⏎ translates", trCount(parts, "part", "parts"),
                     Spend.label(Translate.estimate(characters: text.count, parts: parts, promptPerToken: 0.0000001, completionPerToken: 0.0000004)))
                : tr("%@ · ⏎ translates", trCount(parts, "part", "parts"))
            return
        }
        let delay = now ? 0 : settings.translateDelayMs
        // The translation on show is of the old text now: faded, and ⏎ will not copy it.
        model.state = .waiting
        working = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.translate(text)
        }
        if settings.translateAutocomplete, model.cursorAtEnd, !(model.source?.rightToLeft ?? false), !text.hasSuffix("\n"), text.count < 2_000 {
            guessing = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                await self?.guess(text)
            }
        }
    }

    private func translateNow() {
        working?.cancel()
        let text = model.text
        working = Task { @MainActor [weak self] in await self?.translate(text) }
    }

    private func translate(_ text: String) async {
        guard let source = model.source else {
            model.state = .refused
            model.status = Translate.Refusal.nothingToTranslate.line
            return
        }
        let target = model.target
        model.state = .waiting
        model.status = tr("%@ → %@ · translating…", source.title.uppercased(), target.title.uppercased())
        helper()?.clipHelperMood(.thinking)
        let result = await translator.translate(text, from: source, to: target)
        guard !Task.isCancelled, model.text == text else { return }
        switch result {
        case .success(let done):
            model.result = done.text
            model.resultLanguage = target
            model.state = .done
            var status = Translate.status(from: source, to: target, seconds: done.seconds)
            if model.sourceChoice == nil, model.targetChoice == source { status += " · " + tr("already in %@", source.title) }
            if done.markersLost { status += " · " + tr("links may be changed") }
            model.status = status
            refreshSaved()
            helper()?.clipHelperMood(.calm)
            trace?("translated \(source.code)→\(target.code): \(done.text.prefix(80))")
        case .failure(.cancelled):
            return
        case .failure(let trouble):
            model.state = .trouble
            model.status = trouble.line
            helper()?.clipHelperMood(.puzzled)
            trace?("translate trouble: \(trouble.line)")
        }
    }

    private func guess(_ text: String) async {
        guard let source = model.source else { return }
        let guess = await translator.guess(after: text, in: source)
        // Only for the text and cursor it was asked about.
        guard !Task.isCancelled, model.text == text, model.cursorAtEnd, !guess.isEmpty else { return }
        model.guess = guess
        trace?("guess: \(guess)")
    }

    /// ⇥: the grey words become typed ones.
    func takeGuess() {
        guard !model.guess.isEmpty else { return }
        let taken = model.guess
        model.guess = ""
        model.text += taken
        if let box = model.textView {
            box.string = model.text
            box.setSelectedRange(NSRange(location: (model.text as NSString).length, length: 0))
        }
        trace?("took the guess: \(taken)")
        edited()
    }

    /// The languages change places, and the translation becomes the text, to check it backwards.
    func swap() {
        guard let source = model.source else { NSSound.beep(); return }
        let target = model.target
        let back = model.state == .done ? model.result : model.text
        model.sourceChoice = target
        model.targetChoice = source
        model.text = back
        model.textView?.string = back
        model.result = ""
        trace?("swap: \(target.code)→\(source.code)")
        edited(now: true)
    }

    // MARK: Delivering

    private func deliver(paste: Bool) {
        let text = model.result
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        watcher()?.ownWrite()
        keepInHistory(text, clips: clips, settings: settings)
        let caret = caret, previous = previous
        close()
        guard paste else {
            ClipToast.show(tr("Copied the translation"), near: caret)
            trace?("copied the translation")
            return
        }
        guard ClipPaster.trusted || !pressKeys else {
            ClipToast.show(tr("Copied. Press ⌘V to paste."), near: caret)
            return
        }
        if pressKeys, let previous, !previous.isActive { previous.activate() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ClipPickerController.pasteDelay))
            if pressKeys { ClipPaster.pressPaste() }
            trace?("\(pressKeys ? "pasted" : "would paste") the translation into \(previous?.localizedName ?? "the app in front")")
        }
    }

    // MARK: Pictures

    /// The paper as a PNG, with the drawer when it is open, for `--translate-film` and `--translate-sheet --snapshot`.
    func snapshot(to url: URL) throws {
        let area = model.drawerOpen ? model.paper.union(model.drawerFrame) : model.paper
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: area) else { return }
        view.cacheDisplay(in: area, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// A translation copied or pasted goes into the clipboard history from "Translate",
/// when the history is on and the setting says so; the watcher skips the app's own
/// writes, so it is added here on purpose.
@MainActor
func keepInHistory(_ text: String, clips: ClipBook, settings: AppSettings) {
    guard settings.translateKeepInHistory, settings.clipboardEnabled, settings.clipHistoryEnabled else { return }
    clips.add(Clipboard.Clip(text: text, copiedAt: Date(), app: tr("Translate")), limit: settings.clipHistoryLimit, days: settings.clipKeepDays)
}

// MARK: The model

@MainActor
final class TranslateSheetModel: ObservableObject {
    enum State { case idle, waiting, done, waitingForEnter, trouble, refused }

    @Published var text = ""
    /// The grey words after the cursor; never translated until taken.
    @Published var guess = ""
    @Published var result = ""
    @Published var resultLanguage: Translate.Language?
    @Published var state = State.idle
    @Published var status = ""
    @Published var languages: [Translate.Language] = Translate.languages
    /// Picked by hand; nil: detected.
    @Published var sourceChoice: Translate.Language?
    /// Picked by hand; nil: the source's "goes into" rule.
    @Published var targetChoice: Translate.Language?
    @Published var detected: Translate.Language?
    @Published var appName: String?
    @Published var hasModel = true
    @Published var unfolded = true
    @Published var anchor = UnitPoint.center
    @Published var paper = CGRect.zero
    /// The panel the paper is drawn in, and where the owner let go of it after a drag.
    var room = CGSize.zero
    var moved: (CGRect) -> Void = { _ in }
    /// The text box, for the keys a menu-bar app has no Edit menu for.
    weak var textView: NSTextView?
    var cursorAtEnd = true

    var edited: () -> Void = {}
    var act: (Translate.Button) -> Void = { _ in }
    var close: () -> Void = {}
    var load: (Translate.Saved) -> Void = { _ in }
    var copySaved: (Translate.Saved) -> Void = { _ in }
    var removeSaved: (Translate.Saved) -> Void = { _ in }

    // MARK: Saved translations

    /// Off in the settings: no star, no drawer.
    @Published var savedOn = true
    @Published var saved = Translate.SavedBook()
    /// The translation on show is saved: the star is filled.
    @Published var isSaved = false
    @Published var drawerOpen = false
    /// Its search box has the keys; set by the box, or by ⌘L where there is no window.
    var drawerHasKeys = false
    @Published var query = "" {
        didSet { if query != oldValue { selectedSaved = shownSaved.first?.id } }
    }
    @Published var selectedSaved: UUID?

    var shownSaved: [Translate.Saved] { saved.search(query) }
    var selectedEntry: Translate.Saved? { selectedSaved.flatMap { id in saved.entries.first { $0.id == id } } }

    func step(_ by: Int) {
        let rows = shownSaved
        guard !rows.isEmpty else { NSSound.beep(); return }
        let at = rows.firstIndex { $0.id == selectedSaved }.map { $0 + by } ?? (by > 0 ? 0 : rows.count - 1)
        selectedSaved = rows[min(max(at, 0), rows.count - 1)].id
    }

    static let drawerWidth: CGFloat = 360
    /// How far the drawer stays tucked under the paper, so it seems to come out of its edge.
    static let drawerTuck: CGFloat = 10

    /// The side the drawer opens on: the right, unless that monitor has no room for it there.
    var drawerSide: Translate.DrawerSide {
        Translate.DrawerSide.side(paperMinX: paper.minX, paperWidth: paper.width, drawerWidth: Self.drawerWidth - Self.drawerTuck,
                                  room: room.width > 0 ? room.width : .greatestFiniteMagnitude)
    }

    /// Where the drawer stands in the panel: beside the paper, a little shorter than it.
    var drawerFrame: CGRect {
        let x = drawerSide == .right ? paper.maxX - Self.drawerTuck : paper.minX - Self.drawerWidth + Self.drawerTuck
        return CGRect(x: x, y: paper.minY + 16, width: Self.drawerWidth, height: max(paper.height - 32, 0))
    }

    var source: Translate.Language? { sourceChoice ?? detected }

    /// What each language goes into, from the settings.
    @Published var targets = Translate.defaultTargets

    var target: Translate.Language {
        guard let source else { return targetChoice ?? languages.first ?? Translate.english }
        return Translate.target(for: source, chosen: targetChoice, targets: targets, on: languages)
    }

    /// What the text box reports as you type.
    func typed(_ new: String, cursorAtEnd: Bool) {
        let old = text
        self.cursorAtEnd = cursorAtEnd
        // Typing the guess's own next letters keeps the rest of it.
        if new.count > old.count, new.hasPrefix(old), cursorAtEnd {
            let added = String(new.dropFirst(old.count))
            guess = guess.hasPrefix(added) ? String(guess.dropFirst(added.count)) : ""
        } else {
            guess = ""
        }
        text = new
        edited()
    }
}

// MARK: The sheet

struct TranslateSheetView: View {
    @ObservedObject var model: TranslateSheetModel

    static let ink = Color(cgColor: ScreenOverlay.ink)
    static let softInk = Color(cgColor: ScreenOverlay.softInk)
    static let faintInk = Color(cgColor: ScreenOverlay.faintInk)
    static let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)

    var body: some View {
        let paper = model.paper
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { model.close() }
            if model.savedOn && model.unfolded {
                let frame = model.drawerFrame
                ZStack(alignment: .topLeading) {
                    if model.drawerOpen {
                        TranslateDrawerView(model: model)
                            .transition(.move(edge: model.drawerSide == .right ? .leading : .trailing))
                    }
                }
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipped()
                .offset(x: frame.minX, y: frame.minY)
            }
            sheet
                .frame(width: paper.width, height: paper.height)
                .paperDrag($model.paper, room: model.room, enabled: model.unfolded) { model.moved($0) }
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
                HStack {
                    Text(tr("TRANSLATE")).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    Spacer()
                    if model.savedOn {
                        TranslateButtonView(button: .savedList, on: model.drawerOpen) { model.act(.savedList) }
                    }
                }
                .padding(.bottom, 8)
                chips.padding(.bottom, 8)
                HStack(alignment: .top, spacing: 14) {
                    TranslateTextBox(model: model)
                        .padding(.horizontal, 6).padding(.vertical, 6)
                        .background(PixelBox(style: .well))
                    result
                }
                .frame(height: 300)
                statusLine.padding(.top, 8)
                Spacer(minLength: 0)
                Text(model.savedOn ? tr("⏎ COPY  ⌘⏎ PASTE  ⇧⏎ NEW LINE  ⇥ GUESS  ⌘S SWAP  ⌘1–4 FROM  ⌥1–3 INTO  ⌘D SAVE  ⌘L SAVED  ⌘⌫ CLEAR  ⎋ CLOSE")
                     : tr("⏎ COPY  ⌘⏎ PASTE  ⇧⏎ NEW LINE  ⇥ GUESS  ⌘S SWAP  ⌘1–4 FROM  ⌥1–3 INTO  ⌘⌫ CLEAR  ⎋ CLOSE"))
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

    private var chips: some View {
        HStack(spacing: 6) {
            chip(model.sourceChoice == nil ? (model.detected.map { tr("DETECT · %@", $0.title.uppercased()) } ?? tr("DETECT")) : tr("DETECT"),
                 chosen: model.sourceChoice == nil, tip: tr("Tell the language by its letters (⌘1)")) { model.sourceChoice = nil; model.edited() }
            ForEach(Array(model.languages.enumerated()), id: \.element.code) { i, language in
                chip(language.title.uppercased(), chosen: model.sourceChoice == language, tip: tr("From %@ (⌘%d)", language.title, i + 2)) {
                    model.sourceChoice = language; model.edited()
                }
            }
            Spacer(minLength: 8)
            TranslateButtonView(button: .swap) { model.act(.swap) }
            Spacer(minLength: 8)
            let target = model.target
            ForEach(Array(model.languages.enumerated()), id: \.element.code) { i, language in
                chip(language.title.uppercased(), chosen: target == language && model.source != nil, tip: tr("Into %@ (⌥%d)", language.title, i + 1)) {
                    model.targetChoice = language; model.edited()
                }
            }
        }
    }

    private func chip(_ title: String, chosen: Bool, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(PixelButtonStyle(small: true, chosen: chosen))
            .modifier(PixelTag(text: tip))
    }

    private var result: some View {
        let rtl = model.resultLanguage?.rightToLeft ?? false
        return VStack(alignment: .trailing, spacing: 6) {
            ScrollView {
                Text(model.result.isEmpty ? " " : model.result)
                    .font(Font(Self.font))
                    .foregroundStyle(model.state == .done ? Self.ink : Self.softInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                    .multilineTextAlignment(rtl ? .trailing : .leading)
            }
            .scrollIndicators(.never)
            HStack(spacing: 6) {
                if model.savedOn {
                    TranslateButtonView(button: .save, on: model.isSaved) { model.act(.save) }
                }
                TranslateButtonView(button: .copy) { model.act(.copy) }
                TranslateButtonView(button: .paste, app: model.appName) { model.act(.paste) }
            }
            .opacity(model.state == .done ? 1 : 0.45)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelBox(style: .raised))
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if model.state == .waiting { Text("•••").foregroundStyle(Self.softInk) }
            Text(model.status.isEmpty ? tr("Type, or paste, in any language that is on.") : model.status)
                .foregroundStyle(model.state == .trouble || model.state == .refused ? PixelBox.rim : Self.softInk)
                .lineLimit(2)
            Spacer()
        }
        .font(.system(size: 11, weight: .heavy, design: .monospaced))
    }
}

/// One of the translator's pixel buttons: its picture, and its name and key on hover.
struct TranslateButtonView: View {
    let button: Translate.Button
    var app: String? = nil
    /// Saved already (the star, filled), or the drawer open.
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { PixelIcon(rows: button.icon(on: on)) }
            .buttonStyle(PixelButtonStyle(small: true, chosen: false, square: true))
            .modifier(PixelTag(text: button.tooltip(app: app, on: on)))
            .accessibilityLabel(button.tooltip(app: app, on: on))
    }
}

// MARK: The drawer

/// The saved translations, on a strip of the same paper sliding out of the
/// sheet's side: a search over both texts, newest first, each row loading back
/// into the sheet on a click, with its copy and its bin.
struct TranslateDrawerView: View {
    @ObservedObject var model: TranslateSheetModel
    @FocusState private var typing: Bool

    private static let ink = TranslateSheetView.ink
    private static let softInk = TranslateSheetView.softInk
    private static let faintInk = TranslateSheetView.faintInk

    var body: some View {
        let size = model.drawerFrame.size
        let rows = model.shownSaved
        ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tr("SAVED")).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    Spacer()
                    Text(model.query.isEmpty ? "\(model.saved.count)" : "\(rows.count) / \(model.saved.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                }
                .padding(.bottom, 8)
                field.padding(.bottom, 8)
                list(rows)
                Text(tr("↑↓ MOVE  ⏎ LOAD  ⌘C COPY  ⌫ DELETE  ⎋ CLOSE"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Self.faintInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 6)
                    .padding(.trailing, 40)
            }
            // The side under the paper is tucked away: the words keep clear of it.
            .padding(.leading, model.drawerSide == .right ? 18 + TranslateSheetModel.drawerTuck : 18)
            .padding(.trailing, model.drawerSide == .left ? 18 + TranslateSheetModel.drawerTuck : 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear { typing = true }
        // Only taking the keys is heard: on screen the panel's first responder says who has them,
        // and an offscreen still losing its window must not hand them back to the text.
        .onChange(of: typing) { _, now in if now { model.drawerHasKeys = true } }
    }

    private var field: some View {
        // The hint is drawn by hand, as in the clipboard picker.
        TextField("", text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .heavy, design: .monospaced))
            .foregroundStyle(Self.ink)
            .focused($typing)
            .background(alignment: .leading) {
                if model.query.isEmpty {
                    Text(tr("search saved…")).font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Self.faintInk).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PixelBox(style: .well))
    }

    private func list(_ rows: [Translate.Saved]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if rows.isEmpty {
                        Text(model.saved.isEmpty ? tr("Nothing saved yet: ⌘D saves a translation.") : tr("Nothing matches."))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Self.softInk)
                            .padding(.top, 16).frame(maxWidth: .infinity)
                    }
                    ForEach(rows) { row in line(row).id(row.id) }
                }
                .padding(.trailing, 4)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedSaved) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func line(_ row: Translate.Saved) -> some View {
        let chosen = row.id == model.selectedSaved
        return VStack(alignment: .leading, spacing: 3) {
            words(row.text, in: row.from, ink: chosen ? PixelBox.rim : Self.softInk, weight: .semibold)
            words(row.translation, in: row.to, ink: PixelBox.rim, weight: .heavy)
            HStack(spacing: 6) {
                Text(row.pair)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(PixelBox.rim)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(PixelBox(style: .raised))
                Text(Translate.savedDate(row.savedAt))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(chosen ? PixelBox.rim : Self.faintInk)
                Spacer(minLength: 4)
                icon(.copySaved) { model.copySaved(row) }
                icon(.deleteSaved) { model.removeSaved(row) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background { if chosen { PixelBox(style: .chosen) } }
        .contentShape(Rectangle())
        .onHover { if $0 { model.selectedSaved = row.id } }
        .onTapGesture { model.load(row) }
    }

    /// One line of a row, right to left for Hebrew.
    private func words(_ text: String, in code: String, ink: Color, weight: Font.Weight) -> some View {
        let rtl = Translate.language(code)?.rightToLeft ?? false
        return Text(text.split(whereSeparator: \.isNewline).joined(separator: " "))
            .font(.system(size: 12, weight: weight, design: .monospaced)).foregroundStyle(ink)
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }

    private func icon(_ button: Translate.Button, action: @escaping () -> Void) -> some View {
        Button(action: action) { PixelIcon(rows: button.icon) }
            .buttonStyle(.plain)
            .modifier(PixelTag(text: button.tooltip()))
            .accessibilityLabel(button.tooltip())
    }
}

/// A tag drawn in the sheet itself on hover: the panel sits above where the
/// system's tooltips open, so `.help` would show underneath.
struct PixelTag: ViewModifier {
    let text: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) {
                if hovering {
                    Text(text)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(PixelBox.rim)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(PixelBox(style: .raised))
                        .fixedSize()
                        .offset(y: 30)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .zIndex(hovering ? 10 : 0)
    }
}

// MARK: The text box

/// The left box: a real text view, so a Hebrew line runs right to left and an
/// English one left to right in the same box (each paragraph takes the direction
/// of its first strong letter), with the guess drawn in grey after the cursor.
struct TranslateTextBox: NSViewRepresentable {
    @ObservedObject var model: TranslateSheetModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        let box = GuessTextView()
        box.isRichText = false
        box.allowsUndo = true
        box.drawsBackground = false
        box.font = TranslateSheetView.font
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
        guard let box = scroll.documentView as? GuessTextView else { return }
        if box.string != model.text { box.string = model.text }
        if box.guess != model.guess { box.guess = model.guess; box.needsDisplay = true }
        model.textView = box
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: TranslateSheetModel
        init(model: TranslateSheetModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSTextView else { return }
            model.typed(box.string, cursorAtEnd: box.selectedRange().location == (box.string as NSString).length)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let box = notification.object as? NSTextView else { return }
            let atEnd = box.selectedRange().location == (box.string as NSString).length && box.selectedRange().length == 0
            model.cursorAtEnd = atEnd
            if !atEnd, !model.guess.isEmpty { model.guess = "" }
        }
    }
}

/// A text view that draws `guess` in faint ink straight after its last letter.
final class GuessTextView: NSTextView {
    var guess = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !guess.isEmpty, let layout = layoutManager, let container = textContainer else { return }
        let length = (string as NSString).length
        guard length > 0, !string.hasSuffix("\n") else { return }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: length - 1, length: 1), actualCharacterRange: nil)
        let last = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? TranslateSheetView.font, .foregroundColor: NSColor(cgColor: ScreenOverlay.faintInk) ?? .gray]
        // As many of its words as fit on the line; the rest would only be cut off at the edge.
        let room = container.size.width - container.lineFragmentPadding + textContainerOrigin.x - last.maxX
        var shown = guess
        while !shown.isEmpty, (shown as NSString).size(withAttributes: attributes).width > room {
            let words = shown.trimmingCharacters(in: .whitespaces)
            guard let space = words.lastIndex(of: " ") else { shown = ""; break }
            shown = String(shown.prefix { $0 == " " }) + String(words[..<space])
        }
        (shown as NSString).draw(at: CGPoint(x: last.maxX, y: last.minY), withAttributes: attributes)
    }
}
