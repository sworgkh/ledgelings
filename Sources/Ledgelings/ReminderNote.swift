import AppKit
import LedgelingsCore
import SwiftUI

/// Add a Reminder… as the game draws it: a sheet of the letter's pixel paper
/// with a creature peeking over the top edge. You write what to be reminded of,
/// step the day and the time with pixel arrows, pick a repeat, and fold it
/// into a plane. The Reminders tab keeps the list and the delivery settings.
@MainActor
final class ReminderNoteController {
    /// The sheet, in points; the paper is drawn at `pixel` points per paper pixel.
    static let size = CGSize(width: 564, height: 414)
    static let pixel: CGFloat = 3

    private let reminders: ReminderBook
    /// Someone on screen to peek over the paper: a name and an idle frame.
    private let keeper: () -> (name: String, face: CGImage?)?
    private var window: NoteWindow?

    init(reminders: ReminderBook, keeper: @escaping () -> (name: String, face: CGImage?)?) {
        self.reminders = reminders
        self.keeper = keeper
    }

    func show() {
        window?.close()
        let made = NoteWindow(size: Self.size)
        let who = keeper()
        let view = ReminderNoteView(keeper: who?.name, face: who?.face, fold: { [weak self] text, time, repeats in
            self?.reminders.add(text, at: time, repeats: repeats)
            self?.foldAway()
        }, cancel: { [weak self] in self?.dismiss() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        made.contentView = hosting
        // The middle of the screen the cursor is on, where the letters open too.
        let cursor = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main)?.visibleFrame ?? .zero
        made.setFrameOrigin(CGPoint(x: (screen.midX - Self.size.width / 2).rounded(), y: (screen.midY - Self.size.height / 2).rounded()))
        window = made
        NSApp.activate(ignoringOtherApps: true)
        made.makeKeyAndOrderFront(nil)
    }

    /// Folded: the sheet shrinks up and away, as the plane will fly.
    private func foldAway() {
        guard let window else { return }
        self.window = nil
        let from = window.frame
        let to = CGRect(x: from.midX - 20, y: from.maxY + 40, width: 40, height: 30)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            window.animator().setFrame(to, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { window.close() })
    }

    private func dismiss() {
        window?.close()
        window = nil
    }

    /// The sheet as a PNG, drawn by the app itself: `--note --snapshot out.png`.
    func snapshot(to url: URL) throws {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
}

/// A borderless, see-through window that can still take the keyboard, moved by dragging the paper.
final class NoteWindow: NSWindow {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: The sheet

struct ReminderNoteView: View {
    let keeper: String?
    let face: CGImage?
    let fold: (String, Date, Reminders.Repeat) -> Void
    let cancel: () -> Void

    @State private var text = ""
    @State private var time = RemindersSettingsView.nextRoundHour()
    @State private var repeats = Reminders.Repeat.once
    @FocusState private var writing: Bool

    private static let px = ReminderNoteController.pixel
    /// Room above the paper for the creature peeking over it.
    private static let headroom: CGFloat = 54
    private static let ink = Color(cgColor: ScreenOverlay.ink)
    private static let softInk = Color(cgColor: ScreenOverlay.softInk)
    private static let faintInk = Color(cgColor: ScreenOverlay.faintInk)

    private var words: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let size = ReminderNoteController.size
        ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height - Self.headroom)
                .offset(y: Self.headroom)
            if let face { Peeker(face: face, sheetWidth: size.width, headroom: Self.headroom) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    .padding(.bottom, 10)
                field.padding(.bottom, 18)
                when.padding(.bottom, 14)
                repeatRow.padding(.bottom, 18)
                buttons
            }
            .padding(.horizontal, 33)
            .padding(.top, Self.headroom + 27)
            .frame(width: size.width, alignment: .leading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear { writing = true }
        .onExitCommand(perform: cancel)
    }

    private var title: String {
        keeper.map { "A NOTE FOR THE LEDGELINGS · \($0.uppercased()) IS READING OVER THE EDGE" } ?? "A NOTE FOR THE LEDGELINGS"
    }

    // MARK: What

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("REMIND ME TO")
            TextField("", text: $text, prompt: Text("stretch, call mom, stand-up…").foregroundStyle(Self.faintInk))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(Self.ink)
                .focused($writing)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(PixelBox(style: .well))
        }
    }

    // MARK: When

    private var when: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                label("WHEN").frame(width: 62, alignment: .leading)
                stepper(Reminders.day(time, now: Date()), width: 150, back: { shift(days: -1) }, on: { shift(days: 1) })
                stepper(Reminders.clock(time), width: 128, back: { time = Reminders.step(time, by: -15) }, on: { time = Reminders.step(time, by: 15) })
                if time <= Date() {
                    Text("past: it comes\nstraight away").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Self.faintInk)
                }
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 62)
                ForEach([("IN 5 MIN", 5.0), ("IN 30 MIN", 30.0), ("IN 1 HOUR", 60.0)], id: \.0) { title, minutes in
                    PixelButton(title: title, small: true) { time = Date().addingTimeInterval(minutes * 60) }
                }
                PixelButton(title: "TOMORROW 9:00", small: true) { time = Self.tomorrowMorning() }
            }
        }
    }

    private func stepper(_ value: String, width: CGFloat, back: @escaping () -> Void, on: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            PixelButton(title: "◀", small: true, action: back)
            Text(value).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(Self.ink)
                .monospacedDigit()
                .frame(width: width - 60, height: 30)
                .background(PixelBox(style: .well))
            PixelButton(title: "▶", small: true, action: on)
        }
    }

    private func shift(days: Int) {
        time = Calendar.current.date(byAdding: .day, value: days, to: time) ?? time
    }

    private static func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    // MARK: Repeat

    private var repeatRow: some View {
        HStack(spacing: 8) {
            label("REPEAT").frame(width: 62, alignment: .leading)
            ForEach(Reminders.Repeat.allCases, id: \.self) { choice in
                PixelButton(title: choice.title.uppercased(), small: true, chosen: repeats == choice) { repeats = choice }
            }
        }
    }

    // MARK: Fold or not

    private var buttons: some View {
        HStack(alignment: .bottom) {
            Text(words.isEmpty ? "write something first" : "\(Reminders.when(time, now: Date()))" + (repeats == .once ? "" : ", \(repeats.title.lowercased())"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Self.softInk)
            Spacer()
            PixelButton(title: "NEVER MIND", action: cancel)
                .keyboardShortcut(.cancelAction)
            PixelButton(title: "FOLD IT INTO A PLANE", chosen: true, action: send)
                .keyboardShortcut(.defaultAction)
                .disabled(words.isEmpty)
                .opacity(words.isEmpty ? 0.5 : 1)
        }
        // Clear of the paper's folded-down corner.
        .padding(.trailing, 24)
    }

    private func send() {
        guard !words.isEmpty else { return }
        fold(words, time, repeats)
    }

    private func label(_ words: String) -> some View {
        Text(words).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Self.softInk)
    }
}

// MARK: Pixel parts

/// The letter's paper, one image pixel per paper pixel, never smoothed.
struct NotePaper: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let px = ReminderNoteController.pixel
        let image = ScreenOverlay.paperImage(width: Int(width / px), height: Int(height / px))
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.none) }
        }
        .frame(width: width, height: height)
    }
}

/// A creature behind a sheet, its feet hidden by the paper's top edge, eyes over it.
struct Peeker: View {
    let face: CGImage
    let sheetWidth: CGFloat
    /// Room above the paper; the paper's top edge is this far down.
    let headroom: CGFloat

    var body: some View {
        let px = ReminderNoteController.pixel
        let scale: CGFloat = 3, w = CGFloat(face.width) * scale, h = CGFloat(face.height) * scale
        Image(decorative: face, scale: 1).resizable().interpolation(.none)
            .frame(width: w, height: h)
            .mask(alignment: .top) { Rectangle().frame(height: headroom + px * 2) }
            .offset(x: sheetWidth - w - 60, y: headroom + px * 2 - min(h, headroom + 6))
    }
}

/// A box in blocky's rules at the paper's pixel size: a flat fill, a dark rim,
/// a light line top-left and a shade line bottom-right. A well (a field) is lit
/// the other way round, so it reads as pressed into the paper.
struct PixelBox: View {
    enum Style { case raised, pressed, chosen, well }
    var style: Style

    private static let px = ReminderNoteController.pixel
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    static let rim = Color(cgColor: ScreenOverlay.ink)

    private var colours: (fill: Color, topLeft: Color, bottomRight: Color) {
        switch style {
        case .raised: (Self.rgb(250, 248, 240), .white, Self.rgb(196, 192, 206))
        case .pressed: (Self.rgb(226, 222, 212), Self.rgb(196, 192, 206), .white)
        // Blocky's own orange, for the choice made and the button that does it.
        case .chosen: (Self.rgb(255, 138, 61), Self.rgb(255, 178, 122), Self.rgb(214, 98, 32))
        case .well: (Self.rgb(234, 230, 218), Self.rgb(196, 192, 206), Self.rgb(250, 248, 240))
        }
    }

    var body: some View {
        Canvas { context, size in
            let p = Self.px, w = size.width, h = size.height
            let (fill, light, shade) = colours
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Self.rim))
            context.fill(Path(CGRect(x: p, y: p, width: w - 2 * p, height: h - 2 * p)), with: .color(fill))
            context.fill(Path(CGRect(x: p, y: p, width: w - 2 * p, height: p)), with: .color(light))
            context.fill(Path(CGRect(x: p, y: p, width: p, height: h - 2 * p)), with: .color(light))
            context.fill(Path(CGRect(x: p, y: h - 2 * p, width: w - 2 * p, height: p)), with: .color(shade))
            context.fill(Path(CGRect(x: w - 2 * p, y: p, width: p, height: h - 2 * p)), with: .color(shade))
            // Stepped corners: the rim's corner pixels are cut away, never rounded.
            for (x, y) in [(0, 0), (w - p, 0), (0, h - p), (w - p, h - p)] {
                context.blendMode = .clear
                context.fill(Path(CGRect(x: x, y: y, width: p, height: p)), with: .color(.black))
            }
        }
    }
}

/// A button drawn as a `PixelBox` that sinks a pixel while pressed.
struct PixelButton: View {
    var title: String
    var small = false
    var chosen = false
    var action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(PixelButtonStyle(small: small, chosen: chosen))
    }
}

struct PixelButtonStyle: ButtonStyle {
    var small: Bool
    var chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        let px = ReminderNoteController.pixel
        configuration.label
            .font(.system(size: small ? 11 : 13, weight: .heavy, design: .monospaced))
            .foregroundStyle(PixelBox.rim)
            .padding(.horizontal, small ? 9 : 14)
            .frame(minWidth: small ? 30 : 0, minHeight: small ? 30 : 38)
            .background(PixelBox(style: configuration.isPressed ? .pressed : chosen ? .chosen : .raised))
            .offset(y: configuration.isPressed ? px : 0)
            .contentShape(Rectangle())
    }
}
