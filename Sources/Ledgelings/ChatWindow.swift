import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore
import SwiftUI

/// Chat with the creatures (§7.18.1): a pixel-paper window on ⌃⌥C, with a To:
/// row (each creature on screen by its sprite and name, and Everyone), the
/// talk so far and a text box. ⏎ sends, ⇧⏎ makes a new line, ⎋ closes. It opens
/// in a panel that never makes Ledgelings the active app; the creatures stay on
/// their edges and turn to face it while they answer.
@MainActor
final class ChatController {
    static let size = CGSize(width: 760, height: 470)

    private let settings: AppSettings
    private let colony: () -> Colony?
    let model = ChatModel()
    private var panel: ClipPanel?
    private var monitor: Any?
    private var shortcut: GlobalShortcut?
    private var answering: Task<Void, Never>?
    /// Every step, for `--chat` and the film.
    var trace: ((String) -> Void)?
    /// Answers without a model (`LEDGELINGS_FAKE_CHAT`, the film).
    var fake: Colony.ChatFake?
    /// Opens Settings at a page.
    var openSettings: (SettingsPage) -> Void = { _ in }

    init(settings: AppSettings, colony: @escaping () -> Colony?) {
        self.settings = settings
        self.colony = colony
        model.send = { [weak self] in self?.send() }
        model.choose = { [weak self] in self?.choose($0) }
        model.act = { [weak self] in self?.act($0) }
        model.close = { [weak self] in self?.close() }
    }

    var isUp: Bool { panel != nil }
    var isAnswering: Bool { answering != nil }

    func takeShortcut(pressed: @escaping () -> Void = {}) {
        shortcut = GlobalShortcut(settings: settings, enabled: settings.$chatEnabled.combineLatest(settings.$chatShortcutEnabled).map { $0 && $1 },
                                  shortcut: settings.$chatShortcut,
                                  problem: { [weak self] problem in
                                      guard let self, self.settings.chatShortcutProblem != problem else { return }
                                      self.settings.chatShortcutProblem = problem
                                  },
                                  pressed: { [weak self] in pressed(); self?.toggle() })
    }

    // MARK: Opening and closing

    /// The shortcut: up, or away if it is up.
    func toggle() { if isUp { close() } else { show() } }

    /// Up, written to `to` (a name; nil keeps the last choice, Everyone at first).
    func show(to: String? = nil, on given: NSScreen? = nil) {
        refresh()
        if let to { model.chosen = model.targets.contains { $0.name == to } ? to : nil }
        guard panel == nil else { return }
        let (screen, paper) = WindowPlacer.paper(.chat, size: Self.size, screen: given ?? ClipPickerController.screen(caret: nil), settings: settings)
        let made = ClipPanel(frame: screen.visibleFrame)
        model.paper = paper
        model.room = screen.visibleFrame.size
        model.moved = { [settings] in WindowPlacer.paperMoved(.chat, paper: $0, room: screen.visibleFrame, settings: settings) }
        model.unfolded = !settings.clipAnimate
        model.screen = screen.visibleFrame
        let hosting = NSHostingView(rootView: ChatView(model: model))
        hosting.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        made.contentView = hosting
        panel = made
        made.makeKeyAndOrderFront(nil)
        trace?("chat open on \(screen.localizedName), to \(model.chosen ?? "everyone"), \(model.targets.count) on screen")
        if settings.clipAnimate {
            withAnimation(.easeOut(duration: ClipHelper.unfoldSeconds / settings.clipAnimationSpeed)) { model.unfolded = true }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode), flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self?.key(code, flags) ?? false }
            return handled ? nil : event
        }
    }

    /// Who is on screen, and whether anyone can answer.
    func refresh() {
        let targets = colony()?.chatTargets() ?? []
        model.targets = targets.enumerated().map { ChatModel.Target(name: $1.name, portrait: $1.portrait, number: $0 < 9 ? $0 + 1 : nil) }
        if let chosen = model.chosen, !model.targets.contains(where: { $0.name == chosen }) { model.chosen = nil }
        model.hasModel = fake != nil || settings.brain != .script
    }

    /// Gone; answers already asked for still come, on screen and in the log.
    func close() {
        guard let panel else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        self.panel = nil
        model.textView = nil
        trace?("chat close\(isAnswering ? ", still answering" : "")")
    }

    // MARK: Keys

    /// A key pressed on the window; false lets it through to the text box.
    func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let box = model.textView
        switch code {
        case kVK_Escape: close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if shift { return false }
            send()
        case kVK_ANSI_0 where command: choose(nil)
        case kVK_ANSI_Comma where command: act(.settings)
        // A menu-bar app has no Edit menu to send these to the text box: they are sent here.
        case kVK_ANSI_A where command: box?.selectAll(nil)
        case kVK_ANSI_C where command: box?.copy(nil)
        case kVK_ANSI_X where command: box?.cut(nil)
        case kVK_ANSI_V where command: box?.paste(nil)
        case kVK_ANSI_Z where command: shift ? box?.undoManager?.redo() : box?.undoManager?.undo()
        default:
            if command, let n = Self.digits.firstIndex(of: code) {
                guard model.targets.indices.contains(n) else { NSSound.beep(); return true }
                choose(model.targets[n].name)
                return true
            }
            return false
        }
        return true
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func act(_ button: OwnerChat.Button) {
        switch button {
        case .send: send()
        case .everyone: choose(nil)
        case .close: close()
        case .settings:
            close()
            openSettings(model.hasModel ? .chatWithYou : .talk)
        }
    }

    /// Who the next message goes to: a name, or nil for everyone.
    func choose(_ name: String?) {
        model.chosen = name
        trace?("chat to \(name ?? "everyone")")
    }

    // MARK: Sending

    /// ⏎: the text goes to whoever is chosen, and they answer in turn.
    func send(_ given: String? = nil) {
        let text = (given ?? model.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { NSSound.beep(); return }
        guard answering == nil else { model.status = tr("Wait for them to finish answering."); NSSound.beep(); return }
        guard let colony = colony() else { model.status = tr("The creatures are not on screen."); return }
        refresh()
        guard model.hasModel else { model.status = ""; NSSound.beep(); return }
        let to = model.chosen
        model.lines.append(ChatModel.Line(speaker: "", text: text, to: to))
        model.text = ""
        model.textView?.string = ""
        model.status = ""
        trace?("chat sent to \(to ?? "everyone"): \(text)")
        let window = model.paper.isEmpty ? NSEvent.mouseLocation
            : CGPoint(x: model.screen.minX + model.paper.midX, y: model.screen.maxY - model.paper.midY)
        answering = Task { [weak self] in
            await colony.answerOwner(text, to: to, window: window, fake: self?.fake) { event in
                MainActor.assumeIsolated { self?.heard(event) }
            }
            guard let self else { return }
            self.model.thinking = nil
            self.answering = nil
            self.trace?("chat done")
        }
    }

    private func heard(_ event: Colony.ChatEvent) {
        switch event {
        case .thinking(let name): model.thinking = name
        case .answer(let name, let text, let cost):
            model.thinking = nil
            model.lines.append(ChatModel.Line(speaker: name, text: text, cost: cost, portrait: model.targets.first { $0.name == name }?.portrait))
        case .quiet(let name, let why):
            model.thinking = nil
            model.status = why
            trace?("chat \(name) quiet: \(why)")
        case .trouble(let why):
            model.thinking = nil
            model.status = why
            trace?("chat trouble: \(why)")
        }
    }

    /// Wait until every answer to the last message is in and said.
    func finished() async {
        while let task = answering { await task.value; _ = task }
    }

    // MARK: Pictures

    /// The paper as a PNG, for `--chat-window --snapshot`.
    func snapshot(to url: URL) throws {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: model.paper) else { return }
        view.cacheDisplay(in: model.paper, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// MARK: The model

@MainActor
final class ChatModel: ObservableObject {
    struct Target: Identifiable, Equatable {
        var name: String
        var portrait: CGImage?
        /// Its ⌘ number, 1–9.
        var number: Int?
        var id: String { name }
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        /// "" for the owner.
        var speaker: String
        var text: String
        /// The owner's: whom it went to, nil for everyone.
        var to: String? = nil
        var cost: Double? = nil
        var portrait: CGImage? = nil
        var isOwner: Bool { speaker.isEmpty }
    }

    @Published var targets: [Target] = []
    /// Whom the next message goes to; nil is everyone.
    @Published var chosen: String?
    @Published var lines: [Line] = []
    @Published var text = ""
    /// Who is writing an answer now.
    @Published var thinking: String?
    /// Why nothing was sent, or what went wrong.
    @Published var status = ""
    /// A model can answer; without one the window says so, with a way to the settings.
    @Published var hasModel = true
    @Published var unfolded = true
    @Published var paper = CGRect.zero
    /// The panel's screen area, for where the window is on the screen.
    var screen = CGRect.zero
    var room = CGSize.zero
    var moved: (CGRect) -> Void = { _ in }
    weak var textView: NSTextView?

    var send: () -> Void = {}
    var choose: (String?) -> Void = { _ in }
    var act: (OwnerChat.Button) -> Void = { _ in }
    var close: () -> Void = {}
}

// MARK: The window

struct ChatView: View {
    @ObservedObject var model: ChatModel

    static let ink = Color(cgColor: ScreenOverlay.ink)
    static let softInk = Color(cgColor: ScreenOverlay.softInk)
    static let faintInk = Color(cgColor: ScreenOverlay.faintInk)
    static let font = Pixel.Font.typed

    var body: some View {
        let paper = model.paper
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { model.close() }
            sheet
                .frame(width: paper.width, height: paper.height)
                .paperDrag($model.paper, room: model.room, enabled: model.unfolded) { model.moved($0) }
                .scaleEffect(model.unfolded ? 1 : 0.06, anchor: .center)
                .opacity(model.unfolded ? 1 : 0)
                .offset(x: paper.minX, y: paper.minY)
        }
    }

    private var sheet: some View {
        let size = model.paper.size
        return ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(tr("CHAT WITH THE CREATURES")).font(Pixel.Font.title).lineLimit(1).foregroundStyle(Self.faintInk)
                    Spacer()
                    ChatButtonView(button: .settings) { model.act(.settings) }
                    ChatButtonView(button: .close) { model.act(.close) }
                }
                .padding(.bottom, 6)
                toRow.padding(.bottom, 8)
                talk
                    .clipped()
                    .padding(4)
                    .background(PixelBox(style: .well))
                    .frame(maxHeight: .infinity)
                if !model.hasModel { noModel.padding(.top, 8) } else { statusLine.padding(.top, 6) }
                HStack(alignment: .bottom, spacing: 8) {
                    ChatTextBox(model: model)
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(PixelBox(style: .well))
                        .frame(height: 58)
                    ChatButtonView(button: .send, chosen: !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { model.act(.send) }
                        .opacity(model.hasModel ? 1 : 0.45)
                }
                .padding(.top, 6)
                // Clear of the paper's folded corner.
                .padding(.trailing, 46)
                PaperHints(tr("⏎ SEND  ⇧⏎ NEW LINE  ⌘1–9 TO ONE  ⌘0 EVERYONE  ⌘, SETTINGS  ⎋ CLOSE"))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 27)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    /// To: Everyone, then each creature on screen by its sprite and name.
    private var toRow: some View {
        HStack(spacing: 6) {
            Text(tr("TO:")).font(Pixel.Font.label).foregroundStyle(Self.softInk)
            Button { model.choose(nil) } label: {
                HStack(spacing: 5) { PixelIcon(rows: OwnerChat.Button.everyone.icon); Text(tr("EVERYONE")) }
            }
            .buttonStyle(PixelButtonStyle(small: true, chosen: model.chosen == nil))
            .modifier(PixelTag(text: OwnerChat.Button.everyone.tooltip))
            .accessibilityLabel(OwnerChat.Button.everyone.tooltip)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.targets) { target in
                        Button { model.choose(target.name) } label: {
                            HStack(spacing: 4) { Portrait(image: target.portrait, size: 20); Text(target.name.uppercased()).lineLimit(1) }
                        }
                        .buttonStyle(PixelButtonStyle(small: true, chosen: model.chosen == target.name))
                        .modifier(PixelTag(text: OwnerChat.writeTo(target.name, number: target.number)))
                        .accessibilityLabel(OwnerChat.writeTo(target.name, number: target.number))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .zIndex(5)
    }

    /// What has been said, newest at the bottom.
    private var talk: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.lines.isEmpty {
                        Text(model.chosen.map { tr("Write to %@ and press ⏎.", $0) } ?? tr("Write to all of them and press ⏎: a few will answer, one after another."))
                            .foregroundStyle(Self.faintInk)
                    }
                    ForEach(model.lines) { line in row(line).id(line.id) }
                    if let who = model.thinking {
                        HStack(spacing: 6) {
                            Portrait(image: model.targets.first { $0.name == who }?.portrait, size: 22)
                            Text("•••").foregroundStyle(Self.softInk)
                            Text(OwnerChat.thinking(who)).foregroundStyle(Self.softInk)
                        }
                        .id("thinking")
                    }
                }
                .font(Pixel.Font.reading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The newest line stays in sight, also in a still drawn offscreen.
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.lines.count) { withAnimation { reader.scrollTo(model.lines.last?.id, anchor: .bottom) } }
            .onChange(of: model.thinking) { if model.thinking != nil { withAnimation { reader.scrollTo("thinking", anchor: .bottom) } } }
        }
    }

    @ViewBuilder private func row(_ line: ChatModel.Line) -> some View {
        if line.isOwner {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(line.to.map { tr("YOU → %@", $0.uppercased()) } ?? tr("YOU → EVERYONE"))
                        .font(Pixel.Font.hint).foregroundStyle(Self.faintInk)
                    Text(line.text).foregroundStyle(Self.ink).multilineTextAlignment(.leading)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(PixelBox(style: .chosen))
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Portrait(image: line.portrait, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.speaker.uppercased()).font(Pixel.Font.hint).foregroundStyle(Self.faintInk)
                    Text(line.text).foregroundStyle(Self.ink)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(PixelBox(style: .raised))
                }
                Spacer(minLength: 80)
            }
        }
    }

    private var statusLine: some View {
        Text(model.status.isEmpty ? " " : model.status)
            .font(Pixel.Font.label)
            .foregroundStyle(PixelBox.rim)
            .lineLimit(1)
    }

    /// No model, no answers: one line, and the way to the settings.
    private var noModel: some View {
        HStack(spacing: 8) {
            Text(OwnerChat.noModel)
                .font(Pixel.Font.label).foregroundStyle(PixelBox.rim)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button { model.act(.settings) } label: { Text(tr("OPEN SETTINGS")) }
                .buttonStyle(PixelButtonStyle(small: true, chosen: true))
                .modifier(PixelTag(text: OwnerChat.Button.settings.tooltip))
                .fixedSize()
        }
    }
}

/// A creature's sprite at a small size, square pixels kept.
struct Portrait: View {
    let image: CGImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.none) } else { Color.clear }
        }
        .frame(width: size, height: size)
    }
}

/// One of the chat's pixel buttons: its picture, and its name and key on hover.
struct ChatButtonView: View {
    let button: OwnerChat.Button
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

/// What the owner writes: a real text view, so Hebrew runs right to left and the usual keys work.
struct ChatTextBox: NSViewRepresentable {
    @ObservedObject var model: ChatModel

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
        box.font = ChatView.font
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
        let model: ChatModel
        init(model: ChatModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSTextView else { return }
            model.text = box.string
            if !model.status.isEmpty { model.status = "" }
        }
    }
}
