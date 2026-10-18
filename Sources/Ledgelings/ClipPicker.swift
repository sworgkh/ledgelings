import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore
import SwiftUI

/// The clipboard picker: a sheet of the letter's pixel paper with one search
/// field over the recent copies and the snippets at once, run from the keyboard.
/// Type to filter, ↑↓ to choose, ⏎ to paste (⌥⏎ the other way round: plain or
/// formatted), ⌘1–9 for the first nine, ⇥ to jump between the two groups, ⌘P to
/// pin, ⌫ (or ⌘⌫ while searching) to forget a copy, ⎋ to close. The mouse works too.
///
/// The sheet opens in a see-through panel over the whole screen that never makes
/// Ledgelings the active app, so the app you were typing in stays in front and
/// gets the paste. Once something is chosen the panel goes at once, ⌘V is pressed
/// a moment later, and a picture of the sheet collapses into the text cursor on
/// its own, so the paste never waits for the animation.
@MainActor
final class ClipPickerController {
    static let size = CGSize(width: 600, height: 484)
    /// Milliseconds between the panel going and ⌘V: the app in front needs its keyboard back first.
    static let pasteDelay = 40

    private let settings: AppSettings
    private let book: ClipBook
    private let watcher: () -> ClipWatcher?
    private let editSnippets: () -> Void
    let model = ClipPickerModel()
    private var panel: ClipPanel?
    private var monitor: Any?
    /// The app in front when the picker was called, which gets the paste.
    private var previous: NSRunningApplication?
    /// Where its text cursor was, if it said.
    private(set) var caret: CGRect?
    /// Every step, for `--clip-demo`.
    var trace: ((String) -> Void)?
    /// Off in `--clip-demo`, which must not press ⌘V into whatever app is in front.
    var pressKeys = true
    /// Off in `--clip-demo` too: a script cannot press Touch ID.
    var askOwner = true

    init(settings: AppSettings, book: ClipBook, watcher: @escaping () -> ClipWatcher?, editSnippets: @escaping () -> Void) {
        self.settings = settings
        self.book = book
        self.watcher = watcher
        self.editSnippets = editSnippets
        model.source = { [weak book] in (book?.history ?? .init(), book?.snippets ?? .init()) }
        model.choose = { [weak self] row, other in self?.choose(row, otherWay: other) }
        model.close = { [weak self] in self?.close() }
        model.askTrust = { ClipPaster.askForTrust() }
        model.edit = { [weak self] in self?.close(); self?.editSnippets() }
    }

    var isUp: Bool { panel != nil }

    /// Up with `first` on top and chosen; pressed again while up, it switches to that group, or closes when already there.
    func toggle(_ first: ClipPickerModel.Group) {
        if isUp {
            if model.first == first { close() } else { model.first = first; model.refresh(selectFirst: true) }
            return
        }
        show(first)
    }

    func show(_ first: ClipPickerModel.Group) {
        previous = NSWorkspace.shared.frontmostApplication
        if previous?.bundleIdentifier == Bundle.main.bundleIdentifier { previous = nil }
        caret = ClipPaster.caret()
        let screen = Self.screen(caret: caret)
        model.first = first
        model.query = ""
        model.needsTrust = settings.clipAutoPaste && !ClipPaster.trusted
        model.plainFirst = settings.clipPlainText
        model.refresh(selectFirst: true)
        model.unfolded = !settings.clipAnimate
        let made = ClipPanel(frame: screen.visibleFrame)
        let paper = CGRect(x: (screen.visibleFrame.width - Self.size.width) / 2, y: (screen.visibleFrame.height - Self.size.height) / 2,
                           width: Self.size.width, height: Self.size.height).integral
        model.paper = paper
        let hosting = NSHostingView(rootView: ClipPickerView(model: model))
        hosting.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        made.contentView = hosting
        panel = made
        made.makeKeyAndOrderFront(nil)
        trace?("open \(first == .recent ? "history" : "snippets") on \(screen.localizedName), \(model.rows.count) rows, caret \(caret.map { "at \(Int($0.midX)),\(Int($0.midY))" } ?? "unknown")")
        if settings.clipAnimate {
            withAnimation(.easeOut(duration: 0.14 / settings.clipAnimationSpeed)) { model.unfolded = true }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode), flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self?.key(code, flags) ?? false }
            return handled ? nil : event
        }
    }

    /// The screen with the text cursor, else with the front window, else with the pointer.
    static func screen(caret: CGRect?) -> NSScreen {
        let screens = NSScreen.screens
        if let caret, let s = screens.first(where: { $0.frame.contains(CGPoint(x: caret.midX, y: caret.midY)) }) { return s }
        if let window = frontWindow(), let s = screens.max(by: { $0.frame.intersection(window).area < $1.frame.intersection(window).area }),
           s.frame.intersects(window) { return s }
        let pointer = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? screens[0]
    }

    /// The front app's front window, in AppKit's screen points, from the window list (no permission needed).
    static func frontWindow() -> CGRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = info[kCGWindowBounds as String] as? [String: CGFloat], let w = b["Width"], let h = b["Height"],
                  let x = b["X"], let y = b["Y"] else { continue }
            return CGRect(x: x, y: top - y - h, width: w, height: h)
        }
        return nil
    }

    // MARK: Keys

    /// Handles a key pressed on the picker; false lets it through to the search field.
    func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let command = flags.contains(.command), option = flags.contains(.option), control = flags.contains(.control)
        switch code {
        case kVK_Escape: close()
        case kVK_DownArrow: model.step(1)
        case kVK_UpArrow: model.step(-1)
        case kVK_PageDown: model.step(8)
        case kVK_PageUp: model.step(-8)
        case kVK_ANSI_N where control: model.step(1)
        case kVK_ANSI_P where control: model.step(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let row = model.selectedRow { choose(row, otherWay: option) }
        case kVK_Tab: model.jumpGroup()
        case kVK_ANSI_P where command: model.selectedRow.map(pin)
        case kVK_ANSI_E where command: model.edit()
        case kVK_Delete where command || model.query.isEmpty, kVK_ForwardDelete where model.query.isEmpty:
            model.selectedRow.map(forget)
        default:
            if command, let n = Self.digits.firstIndex(of: code), let row = model.numbered(n + 1) {
                choose(row, otherWay: option)
                return true
            }
            return false
        }
        return true
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func pin(_ row: ClipPickerModel.Row) {
        guard row.group == .recent else { NSSound.beep(); return }
        book.togglePin(row.id)
        model.refresh()
        trace?("pin \(row.text)")
    }

    /// A copy is forgotten; a snippet is edited in the Snippets window, never deleted from here by a stray key.
    func forget(_ row: ClipPickerModel.Row) {
        guard row.group == .recent else { NSSound.beep(); return }
        book.remove(row.id)
        model.refresh(keeping: model.rows.firstIndex { $0.id == row.id })
        trace?("forget \(row.text)")
    }

    // MARK: Choosing

    /// Pastes `row`: written to the pasteboard, the panel gone, ⌘V pressed for the app
    /// that was in front. `otherWay` swaps plain text and formatting for this once.
    func choose(_ row: ClipPickerModel.Row, otherWay: Bool = false) {
        let plain = settings.clipPlainText != otherWay
        switch row.group {
        case .recent:
            guard let clip = book.history.clips.first(where: { $0.id == row.id }) else { return }
            paste(ClipPaster.Item(text: clip.text, rtf: clip.rtf, files: clip.paths), plain: plain, from: row)
            book.bump(clip.id)
        case .snippets:
            guard let snippet = book.snippets.snippet(row.id) else { return }
            guard snippet.protected else {
                paste(ClipPaster.Item(text: snippet.text), plain: true, from: row)
                return
            }
            guard settings.clipProtectedNeedsAuth, askOwner else {
                paste(ClipPaster.Item(text: book.words(of: snippet), secret: true), plain: true, from: row)
                return
            }
            // Touch ID's sheet comes up over the paper; the paste waits for it, the picker stays.
            model.checking = true
            // From the picker, closing it meanwhile cancels; from the snippet's own shortcut there is none.
            let fromPicker = isUp
            Task { @MainActor in
                let ok = await OwnerCheck.confirm(tr("paste the protected snippet “%@”", snippet.title))
                model.checking = false
                guard ok, isUp == fromPicker else { trace?("protected \(snippet.title): not confirmed"); return }
                paste(ClipPaster.Item(text: book.words(of: snippet), secret: true), plain: true, from: row)
            }
        }
    }

    /// Pastes a snippet straight from its own shortcut, with no picker.
    func pasteNow(_ snippet: Clipboard.Snippet) {
        previous = NSWorkspace.shared.frontmostApplication
        caret = ClipPaster.caret()
        let row = ClipPickerModel.Row(id: snippet.id, group: .snippets, text: snippet.preview(), detail: "", title: snippet.title,
                                      pinned: false, protected: snippet.protected)
        choose(row)
    }

    private func paste(_ item: ClipPaster.Item, plain: Bool, from row: ClipPickerModel.Row) {
        let before = item.secret ? ClipPaster.saved() : []
        ClipPaster.put(item, plain: plain)
        watcher()?.ownWrite()
        let started = Date()
        collapse()
        guard settings.clipAutoPaste else { trace?("copied \(row.title ?? row.text)"); return }
        guard ClipPaster.trusted || !pressKeys else {
            trace?("copied \(row.title ?? row.text): no Accessibility, press ⌘V")
            ClipToast.show(tr("Copied. Press ⌘V to paste."), near: caret)
            return
        }
        // The front app has its keyboard back once the panel is gone; give it a beat to notice.
        if pressKeys, let previous, !previous.isActive { previous.activate() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Self.pasteDelay))
            if pressKeys { ClipPaster.pressPaste() }
            trace?(String(format: "%@ %@ after %.0f ms%@", pressKeys ? "paste" : "would paste", row.title ?? row.text, Date().timeIntervalSince(started) * 1000,
                          item.secret ? ", concealed" : ""))
            guard item.secret else { return }
            // The secret leaves the pasteboard again, and what was there before comes back.
            try? await Task.sleep(for: .seconds(1))
            ClipPaster.restore(before)
            watcher()?.ownWrite()
            trace?("pasteboard put back")
        }
    }

    /// Closes with nothing pasted: the sheet folds back to the middle and is gone.
    func close() {
        guard isUp else { return }
        trace?("close")
        collapse(toCaret: false)
    }

    /// The panel goes now; a picture of the paper shrinks into the text cursor (or the middle) on its own.
    private func collapse(toCaret: Bool = true) {
        guard let panel else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let to = toCaret ? caret : nil
        let paper = model.paper.offsetBy(dx: panel.frame.minX, dy: 0)
        let onScreen = CGRect(x: paper.minX, y: panel.frame.maxY - paper.maxY, width: paper.width, height: paper.height)
        let picture = settings.clipAnimate ? snapshotImage() : nil
        panel.orderOut(nil)
        self.panel = nil
        guard let picture else { return }
        ClipGhost.fly(picture, from: onScreen, to: to, seconds: 0.18 / settings.clipAnimationSpeed)
        trace?(to.map { "collapse into the caret at \(Int($0.midX)),\(Int($0.midY))" } ?? "collapse to the middle")
    }

    /// The paper as it looks now.
    private func snapshotImage() -> NSImage? {
        guard let view = panel?.contentView else { return nil }
        let rect = model.paper
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    /// The paper as a PNG: `--clip-demo --snapshot out.png`.
    func snapshot(to url: URL) throws {
        guard let image = snapshotImage(), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// A borderless, see-through panel over the screen that takes the keyboard
/// without making Ledgelings the active app.
final class ClipPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A picture of the paper flying into a point and fading, in a window that never takes the keyboard.
@MainActor
enum ClipGhost {
    static func fly(_ image: NSImage, from: CGRect, to target: CGRect?, seconds: Double) {
        let window = NSWindow(contentRect: from, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSImageView(frame: CGRect(origin: .zero, size: from.size))
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        view.layer?.magnificationFilter = .nearest
        view.layer?.minificationFilter = .nearest
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFrontRegardless()
        let point = target.map { CGPoint(x: $0.minX, y: $0.midY) } ?? CGPoint(x: from.midX, y: from.midY)
        let end = CGRect(x: point.x - 6, y: point.y - 4, width: 12, height: 9)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = seconds
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(end, display: true)
            window.animator().alphaValue = 0.2
        }, completionHandler: { window.close() })
    }
}

/// A one-line note on the paper's pixel box, near the text cursor, gone in two seconds.
@MainActor
enum ClipToast {
    private static var window: NSWindow?

    static func show(_ text: String, near caret: CGRect?) {
        window?.close()
        let label = Text(text).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(PixelBox.rim)
            .padding(.horizontal, 14).padding(.vertical, 10).background(PixelBox(style: .raised)).fixedSize()
        let hosting = NSHostingView(rootView: label)
        let size = hosting.fittingSize
        let screen = ClipPickerController.screen(caret: caret).visibleFrame
        let origin = caret.map { CGPoint(x: $0.minX, y: $0.minY - size.height - 6) }
            ?? CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        let made = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        made.isOpaque = false
        made.backgroundColor = .clear
        made.ignoresMouseEvents = true
        made.isReleasedWhenClosed = false
        made.level = .popUpMenu
        made.contentView = hosting
        made.orderFrontRegardless()
        window = made
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if window === made { made.close(); window = nil }
        }
    }
}

// MARK: The model

@MainActor
final class ClipPickerModel: ObservableObject {
    enum Group { case recent, snippets }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let group: Group
        /// The words, folded to one line, or dots for a protected snippet.
        let text: String
        /// Where it came from and when, or the snippet's folder.
        let detail: String
        /// A snippet's title.
        let title: String?
        let pinned: Bool
        let protected: Bool
    }

    @Published var query = "" { didSet { if query != oldValue { refresh(selectFirst: true) } } }
    @Published private(set) var rows: [Row] = []
    @Published var selected: UUID?
    @Published var first: Group = .recent
    /// Paste would only copy: no Accessibility permission yet.
    @Published var needsTrust = false
    @Published var plainFirst = false
    /// Waiting for Touch ID.
    @Published var checking = false
    /// The sheet is open all the way; false while it unfolds.
    @Published var unfolded = true
    /// Where the paper sits in the panel, in the panel's points from its top-left.
    @Published var paper = CGRect.zero
    @Published private(set) var counts = (recent: 0, snippets: 0)

    var source: () -> (Clipboard.History, Clipboard.SnippetBook) = { (.init(), .init()) }
    var choose: (Row, Bool) -> Void = { _, _ in }
    var close: () -> Void = {}
    var askTrust: () -> Void = {}
    var edit: () -> Void = {}

    var selectedRow: Row? { rows.first { $0.id == selected } }

    /// The rows again, after a search or a change: the first chosen, or the same one kept,
    /// or the one now at `keeping`'s place when that row went.
    func refresh(selectFirst: Bool = false, keeping index: Int? = nil) {
        let (history, snippets) = source()
        let found = Clipboard.search(query, history: history, snippets: snippets)
        let now = Date()
        let recent = found.clips.map { clip in
            Row(id: clip.id, group: .recent, text: clip.preview(90), detail: Self.detail(clip, now: now), title: nil,
                pinned: clip.pinned, protected: false)
        }
        let saved = found.snippets.map { snippet in
            Row(id: snippet.id, group: .snippets, text: snippet.preview(90), detail: snippets.folder(of: snippet.id)?.title ?? "",
                title: snippet.title, pinned: false, protected: snippet.protected)
        }
        rows = first == .recent ? recent + saved : saved + recent
        counts = (recent.count, saved.count)
        if let index, !rows.isEmpty, selectedRow == nil {
            selected = rows[min(index, rows.count - 1)].id
        } else if selectFirst || selectedRow == nil {
            selected = rows.first(where: { $0.group == first })?.id ?? rows.first?.id
        }
    }

    func step(_ by: Int) {
        guard !rows.isEmpty else { return }
        let at = rows.firstIndex { $0.id == selected } ?? 0
        selected = rows[min(max(at + by, 0), rows.count - 1)].id
    }

    /// ⇥: to the first row of the other group.
    func jumpGroup() {
        let current = selectedRow?.group ?? first
        if let row = rows.first(where: { $0.group != current }) { selected = row.id }
    }

    /// The row wearing number `n` (1–9): the first nine rows.
    func numbered(_ n: Int) -> Row? { rows.indices.contains(n - 1) ? rows[n - 1] : nil }

    /// "Safari · 5 min", "PINNED · Notes · 2 d", "FILES · Finder · now".
    static func detail(_ clip: Clipboard.Clip, now: Date) -> String {
        var parts: [String] = []
        if clip.kind == .files { parts.append(tr("FILES")) }
        if let app = clip.app, !app.isEmpty { parts.append(app) }
        parts.append(ago(clip.copiedAt, now: now))
        return parts.joined(separator: " · ")
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return tr("now")
        case ..<3600: return tr("%d min", Int(seconds / 60))
        case ..<86_400: return tr("%d h", Int(seconds / 3600))
        default: return tr("%d d", Int(seconds / 86_400))
        }
    }
}

// MARK: The sheet

struct ClipPickerView: View {
    @ObservedObject var model: ClipPickerModel
    @FocusState private var typing: Bool

    private static let ink = Color(cgColor: ScreenOverlay.ink)
    private static let softInk = Color(cgColor: ScreenOverlay.softInk)
    private static let faintInk = Color(cgColor: ScreenOverlay.faintInk)
    private static let rowHeight: CGFloat = 36

    var body: some View {
        let paper = model.paper
        ZStack(alignment: .topLeading) {
            // Nearly clear, so a click anywhere off the paper reaches the panel and closes it.
            Color.black.opacity(0.001).onTapGesture { model.close() }
            sheet
                .frame(width: paper.width, height: paper.height)
                .scaleEffect(model.unfolded ? 1 : 0.06, anchor: .center)
                .opacity(model.unfolded ? 1 : 0)
                .offset(x: paper.minX, y: paper.minY)
        }
        .onAppear { typing = true }
    }

    private var sheet: some View {
        let size = model.paper.size
        return ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tr("CLIPBOARD")).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    Spacer()
                    Text(tr("%d RECENT · %d SNIPPETS", model.counts.recent, model.counts.snippets))
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                }
                .padding(.bottom, 8)
                field.padding(.bottom, 10)
                list
                footer.padding(.top, 8)
            }
            .padding(.horizontal, 27)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var field: some View {
        // The hint is drawn by hand: a prompt in a panel of an app that is not active
        // came out white and cut off at the top.
        TextField("", text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .heavy, design: .monospaced))
            .foregroundStyle(Self.ink)
            .focused($typing)
            .background(alignment: .leading) {
                if model.query.isEmpty {
                    Text(tr("search copies and snippets…")).font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Self.faintInk).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(PixelBox(style: .well))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.rows.isEmpty {
                        Text(model.query.isEmpty ? tr("Nothing yet: copy something, or add a snippet (⌘E).") : tr("Nothing matches."))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Self.softInk)
                            .padding(.top, 20).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index == 0 || model.rows[index - 1].group != row.group { header(row.group) }
                        line(row, number: index < 9 ? index + 1 : nil).id(row.id)
                    }
                }
                .padding(.trailing, 6)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selected) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func header(_ group: ClipPickerModel.Group) -> some View {
        Text(group == .recent ? tr("RECENT") : tr("SNIPPETS"))
            .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(Self.softInk)
            .padding(.top, 6).padding(.bottom, 2)
    }

    private func line(_ row: ClipPickerModel.Row, number: Int?) -> some View {
        let chosen = row.id == model.selected
        return HStack(spacing: 8) {
            Text(number.map { "\($0)" } ?? " ")
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(chosen ? PixelBox.rim : Self.faintInk)
                .frame(width: 12)
            if row.pinned { Text("▲").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(PixelBox.rim) }
            if let title = row.title {
                Text(title).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(PixelBox.rim).lineLimit(1)
                    .layoutPriority(1)
            }
            Text(row.text).font(.system(size: 12, weight: row.title == nil ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(row.title == nil ? PixelBox.rim : Self.softInk).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            Text(row.protected ? tr("LOCKED · %@", row.detail) : row.detail)
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(chosen ? PixelBox.rim : Self.faintInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: Self.rowHeight)
        .background { if chosen { PixelBox(style: .chosen) } }
        .contentShape(Rectangle())
        .onHover { if $0 { model.selected = row.id } }
        .onTapGesture { model.choose(row, NSEvent.modifierFlags.contains(.option)) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.needsTrust {
                HStack(spacing: 8) {
                    Text(tr("To paste for you, Ledgelings needs Accessibility (System Settings › Privacy & Security). Until then it copies; you press ⌘V."))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Self.softInk)
                        .fixedSize(horizontal: false, vertical: true)
                    PixelButton(title: tr("ALLOW…"), small: true, action: model.askTrust)
                }
            }
            Text(model.checking ? tr("Waiting for Touch ID or your password…")
                 : tr("⏎ PASTE  ⌥⏎ %@  ⌘1–9 PICK  ⇥ GROUP  ⌘P PIN  ⌫ FORGET  ⌘E EDIT  ⎋ CLOSE", model.plainFirst ? tr("FORMATTED") : tr("PLAIN")))
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Self.faintInk)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        // Clear of the paper's folded-down corner.
        .padding(.trailing, 60)
    }
}
