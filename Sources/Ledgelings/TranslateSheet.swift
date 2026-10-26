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

    init(settings: AppSettings, translator: Translator, clips: ClipBook, watcher: @escaping () -> ClipWatcher?,
         helper: @escaping () -> ClipHelping? = { nil }) {
        self.settings = settings
        self.translator = translator
        self.clips = clips
        self.watcher = watcher
        self.helper = helper
        model.edited = { [weak self] in self?.edited() }
        model.act = { [weak self] in self?.act($0) }
        model.close = { [weak self] in self?.close() }
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
        guard panel == nil else { edited(now: true); return }
        let screen = given ?? ClipPickerController.screen(caret: caret)
        let made = ClipPanel(frame: screen.visibleFrame)
        let paper = CGRect(x: (screen.visibleFrame.width - Self.size.width) / 2, y: (screen.visibleFrame.height - Self.size.height) / 2,
                           width: Self.size.width, height: Self.size.height).integral
        model.paper = paper
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
        let box = model.textView
        switch code {
        case kVK_Escape: close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if shift { return false }
            act(command ? .paste : .copy)
        case kVK_Tab:
            if model.guess.isEmpty { return !shift && !option ? true : false }
            takeGuess()
        case kVK_ANSI_S where command: act(.swap)
        case kVK_Delete where command: act(.clear)
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
        case .translate, .openSheet: break
        }
    }

    // MARK: Typing

    /// The text changed (or a language did): the guess kept if the new letters
    /// are its start, else dropped; the translation asked for after the wait.
    func edited(now: Bool = false) {
        working?.cancel()
        guessing?.cancel()
        let text = model.text
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

    /// The paper as a PNG, for `--translate-film` and `--translate --snapshot`.
    func snapshot(to url: URL) throws {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: model.paper) else { return }
        view.cacheDisplay(in: model.paper, to: rep)
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
    /// The text box, for the keys a menu-bar app has no Edit menu for.
    weak var textView: NSTextView?
    var cursorAtEnd = true

    var edited: () -> Void = {}
    var act: (Translate.Button) -> Void = { _ in }
    var close: () -> Void = {}

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
                HStack {
                    Text(tr("TRANSLATE")).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    Spacer()
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
                Text(tr("⏎ COPY  ⌘⏎ PASTE  ⇧⏎ NEW LINE  ⇥ GUESS  ⌘S SWAP  ⌘1–4 FROM  ⌥1–3 INTO  ⌘⌫ CLEAR  ⎋ CLOSE"))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) { PixelIcon(rows: button.icon) }
            .buttonStyle(PixelButtonStyle(small: true, chosen: false, square: true))
            .modifier(PixelTag(text: button.tooltip(app: app)))
            .accessibilityLabel(button.tooltip(app: app))
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
