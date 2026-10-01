import AppKit
import LedgelingsCore
import SwiftUI

/// Creature Actions…: everything you can ask of the creatures, on one sheet of
/// the letter's pixel paper. Each action is a tile with its picture cut from the
/// game's own sprites and a letter key; pressing one does it at once. With
/// `actionsStayOpen` the sheet stays up for another go, else it folds away.
@MainActor
final class ActionsController {
    static let size = CGSize(width: 564, height: 506)

    private let settings: AppSettings
    private let colony: () -> Colony?
    private let addReminder: () -> Void
    private let model = ActionsModel()
    private var window: NoteWindow?
    private var timer: Timer?

    init(settings: AppSettings, colony: @escaping () -> Colony?, addReminder: @escaping () -> Void) {
        self.settings = settings
        self.colony = colony
        self.addReminder = addReminder
        model.press = { [weak self] in self?.press($0) }
        model.hide = { [weak self] in self?.hide(minutes: $0) }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let made = NoteWindow(size: Self.size)
        model.keeper = colony()?.noteKeeper()
        model.said = ""
        model.choosingHide = false
        refresh()
        let hosting = NSHostingView(rootView: ActionsSheetView(model: model, done: { [weak self] in self?.dismiss() }))
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        made.contentView = hosting
        // The middle of the screen the cursor is on, where the note opens too.
        let cursor = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main)?.visibleFrame ?? .zero
        made.setFrameOrigin(CGPoint(x: (screen.midX - Self.size.width / 2).rounded(), y: (screen.midY - Self.size.height / 2).rounded()))
        window = made
        made.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// What the tiles need to know, read from the colony twice a second.
    private func refresh() {
        guard let colony = colony() else { return }
        var s = ActionsState()
        s.isNight = colony.isNight
        s.nightOff = settings.nightMinutes == 0
        s.phaseLeft = Int(colony.secondsLeftInPhase.rounded(.up))
        s.teaEnabled = settings.teaPartiesEnabled
        s.teaOn = colony.teaParty != nil || colony.teaInvite != nil
        s.planeInAir = colony.airmail != nil
        s.planted = colony.garden.beds.count
        s.hiding = colony.isHiding
        s.hideLeft = colony.isHiding ? Int(colony.hideout.remaining(at: colony.elapsed).rounded(.up)) : 0
        if s.hiding { model.choosingHide = false }
        if model.state != s { model.state = s }
        if let at = model.saidAt, Date().timeIntervalSince(at) > 5 { model.said = ""; model.saidAt = nil }
    }

    private func press(_ tile: ActionsTile) {
        guard let colony = colony() else { return }
        model.choosingHide = false
        var said: String
        switch tile {
        case .jump:
            colony.startleEveryone()
            said = tr("Everyone jumps.")
        case .talk:
            let before = colony.busy.count
            colony.talkNow()
            said = colony.busy.count > before ? tr("Someone has something to say.") : tr("Nobody talks: %@.", colony.talkStatus)
        case .tea:
            colony.teaNow()
            said = colony.teaParty != nil || colony.teaInvite != nil ? tr("Two of them sit down to tea.") : tr("No tea: %@.", colony.talkStatus)
        case .plane:
            said = colony.sendPlane() ? tr("A paper plane goes up.") : tr("No plane: %@.", colony.talkStatus)
        case .reminder:
            dismiss()
            addReminder()
            return
        case .hide:
            if colony.isHiding {
                colony.bringThemBack()
                said = tr("They come back out.")
            } else {
                model.choosingHide = true
                return
            }
        case .sleep:
            let night = colony.isNight
            colony.skipPhase()
            said = night ? tr("Good morning.") : tr("Good night.")
        case .flowers:
            let pulled = colony.clearGarden()
            said = pulled == 1 ? tr("Pulled up the flower.") : tr("Pulled up %@.", trCount(pulled, "flower", "flowers"))
        }
        after(said)
    }

    private func hide(minutes: Double?) {
        guard let colony = colony() else { return }
        model.choosingHide = false
        colony.hide(for: minutes.map { $0 * 60 } ?? Self.secondsUntilTomorrowMorning())
        after(tr("They run home."))
    }

    private func after(_ said: String) {
        refresh()
        guard settings.actionsStayOpen else { foldAway(); return }
        model.said = said
        model.saidAt = Date()
    }

    /// Seconds until 08:00 tomorrow, local time.
    static func secondsUntilTomorrowMorning() -> Double {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return max(60, eight.timeIntervalSinceNow)
    }

    /// Done: the sheet shrinks up and away, as the note does when folded.
    private func foldAway() {
        guard let window else { return }
        stop()
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
        stop()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        window = nil
    }

    /// The sheet as a PNG, drawn by the app itself: `--actions --snapshot out.png`.
    func snapshot(to url: URL) throws {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
}

// MARK: What the tiles show

/// The colony as the tiles see it.
struct ActionsState: Equatable {
    var isNight = false
    var nightOff = false
    /// Seconds to the next dusk or dawn.
    var phaseLeft = 0
    var teaEnabled = true
    var teaOn = false
    var planeInAir = false
    var planted = 0
    var hiding = false
    /// Seconds until the house opens again.
    var hideLeft = 0
}

/// One tile on the sheet, in the order they are laid out, four to a row.
enum ActionsTile: CaseIterable {
    case jump, talk, tea, plane, reminder, hide, sleep, flowers

    /// The key that presses it while the sheet is up.
    var key: Swift.Character {
        switch self {
        case .jump: "j"
        case .talk: "t"
        case .tea: "e"
        case .plane: "p"
        case .reminder: "r"
        case .hide: "h"
        case .sleep: "s"
        case .flowers: "f"
        }
    }

    func title(in s: ActionsState) -> String {
        switch self {
        case .jump: tr("MAKE THEM JUMP")
        case .talk: tr("MAKE SOMEONE TALK")
        case .tea: s.teaOn ? tr("TEA PARTY ON") : tr("HAVE A TEA PARTY")
        case .plane: tr("SEND A PAPER PLANE")
        case .reminder: tr("ADD A REMINDER")
        case .hide: s.hiding ? tr("BRING THEM BACK") : tr("HIDE THEM FOR A WHILE")
        case .sleep: s.isNight && !s.nightOff ? tr("WAKE THEM UP") : tr("PUT THEM TO SLEEP")
        case .flowers: s.planted == 1 ? tr("CLEAR THE FLOWER") : s.planted == 0 ? tr("CLEAR FLOWERS") : trCount(s.planted, "CLEAR %d FLOWER", "CLEAR %d FLOWERS")
        }
    }

    /// A small line under the title: why it is greyed out, or a clock.
    func detail(in s: ActionsState) -> String? {
        let hidingNote = s.hiding ? tr("they are hiding") : nil
        switch self {
        case .jump, .talk: return hidingNote
        case .tea: return hidingNote ?? (!s.teaEnabled ? tr("off in settings") : s.teaOn ? tr("one at a time") : nil)
        case .plane: return hidingNote ?? (s.planeInAir ? tr("one is in the air") : nil)
        case .reminder: return nil
        case .hide: return s.hiding ? tr("%@ left", Self.clock(s.hideLeft)) : nil
        case .sleep: return s.nightOff ? tr("night is set to 0") : s.isNight ? tr("dawn in %@", Self.clock(s.phaseLeft)) : tr("dusk in %@", Self.clock(s.phaseLeft))
        case .flowers: return s.planted == 0 ? tr("none planted") : nil
        }
    }

    func isEnabled(in s: ActionsState) -> Bool {
        switch self {
        case .jump, .talk: !s.hiding
        case .tea: !s.hiding && s.teaEnabled && !s.teaOn
        case .plane: !s.hiding && !s.planeInAir
        case .reminder, .hide: true
        case .sleep: !s.nightOff
        case .flowers: s.planted > 0
        }
    }

    private static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

@MainActor
final class ActionsModel: ObservableObject {
    @Published var state = ActionsState()
    /// What the last press did, for a few seconds.
    @Published var said = ""
    @Published var choosingHide = false
    var saidAt: Date?
    var keeper: (name: String, face: CGImage?)?
    var press: (ActionsTile) -> Void = { _ in }
    var hide: (Double?) -> Void = { _ in }
}

// MARK: The pictures

/// Each tile's picture, cut from the sprites the creatures already wear, so the
/// sheet is drawn in the same hand as the screen. Talking has no sprite of its
/// own, so its bubble is drawn here in Blocky's rules.
@MainActor
enum ActionIcons {
    static let pictures: [ActionsTile: CGImage] = {
        var made: [ActionsTile: CGImage] = [:]
        let blocky = (try? SpriteAtlas(named: "blocky"))?.frames()
        made[.jump] = blocky?.frame(animation: "jump", time: 0)
        made[.sleep] = compose(blocky?.frame(animation: "sleep", time: 0), with: (try? SpriteAtlas(named: "zzz"))?.frames().frame(animation: "float", time: 0))
        made[.tea] = (try? SpriteAtlas(named: "tea"))?.frames().frame(animation: "steam", time: 0)
        let plane = (try? SpriteAtlas(named: "plane"))?.frames()
        made[.plane] = plane?.frame(animation: "fly", time: 0)
        made[.reminder] = plane?.frame(animation: "letter", time: 0)
        made[.hide] = (try? SpriteAtlas(named: "house"))?.frames().frame(animation: "house", time: 0)
        made[.flowers] = (try? SpriteAtlas(named: "flowers"))?.frames().frame(animation: "poppy", time: 0)
        made[.talk] = glyph(bubble)
        return made.compactMapValues { trimmed($0) }
    }()

    /// The picture cut down to its painted pixels: a sprite cell has room to move in.
    static func trimmed(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX else { return image }
        // The bitmap's rows run top to bottom, the same as CGImage cropping.
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
    }

    /// A speech bubble with three dots: o rim, l light, w fill, s shade, k ink.
    static let bubble = [
        ".oooooooooooooo.",
        "ollllllllllllllo",
        "olwwwwwwwwwwwwso",
        "olwwwwwwwwwwwwso",
        "olwkkwwkkwwkkwso",
        "olwkkwwkkwwkkwso",
        "olwwwwwwwwwwwwso",
        "olwwwwwwwwwwwwso",
        "osssssssssssssso",
        ".ooooowsooooooo.",
        ".....owso.......",
        ".....oso........",
        ".....oo.........",
    ]

    private static let inks: [Swift.Character: (UInt8, UInt8, UInt8)] = [
        "o": (40, 34, 58), "l": (255, 255, 255), "w": (244, 241, 230), "s": (196, 192, 206), "k": (40, 34, 58),
    ]

    /// Rows of characters as an image, one pixel each; `.` is see-through.
    static func glyph(_ rows: [String]) -> CGImage? {
        let h = rows.count, w = rows.map(\.count).max() ?? 0
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = inks[ch] else { continue }
                let i = (y * w + x) * 4
                bytes[i] = c.0; bytes[i + 1] = c.1; bytes[i + 2] = c.2; bytes[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// A sleeper with a Z rising over its head, top right.
    private static func compose(_ base: CGImage?, with z: CGImage?) -> CGImage? {
        guard let base else { return nil }
        guard let z else { return base }
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CG is y-up: the Z sits against the top-right corner.
        ctx.draw(z, in: CGRect(x: w - z.width, y: h - z.height, width: z.width, height: z.height))
        return ctx.makeImage()
    }
}

// MARK: The sheet

struct ActionsSheetView: View {
    @ObservedObject var model: ActionsModel
    let done: () -> Void

    private static let px = ReminderNoteController.pixel
    private static let headroom: CGFloat = 54
    private static let tile = CGSize(width: 114, height: 126)
    private static let gap: CGFloat = 10
    private static let softInk = Color(cgColor: ScreenOverlay.softInk)
    private static let faintInk = Color(cgColor: ScreenOverlay.faintInk)
    /// What the hide row offers, in minutes; nil means "until tomorrow at eight".
    static var hideChoices: [(String, Double?)] {
        [(tr("5 MIN"), 5), (tr("15 MIN"), 15), (tr("30 MIN"), 30), (tr("1 H"), 60), (tr("2 H"), 120), (tr("4 H"), 240), (tr("TILL 8:00"), nil)]
    }

    var body: some View {
        let size = ActionsController.size
        ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height - Self.headroom)
                .offset(y: Self.headroom)
            if let face = model.keeper?.face { Peeker(face: face, sheetWidth: size.width, headroom: Self.headroom) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    .padding(.bottom, 14)
                grid.padding(.bottom, 14)
                line.frame(height: 30, alignment: .leading).padding(.bottom, 12)
                footer
            }
            .padding(.horizontal, 33)
            .padding(.top, Self.headroom + 27)
            .frame(width: size.width, alignment: .leading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onExitCommand(perform: done)
    }

    private var title: String {
        model.keeper.map { tr("WHAT SHOULD THEY DO? · %@ IS WAITING", $0.name.uppercased()) } ?? tr("WHAT SHOULD THEY DO?")
    }

    private var grid: some View {
        let rows = stride(from: 0, to: ActionsTile.allCases.count, by: 4).map { Array(ActionsTile.allCases[$0..<min($0 + 4, ActionsTile.allCases.count)]) }
        return VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: Self.gap) {
                    ForEach(rows[r], id: \.self) { tileView($0) }
                }
            }
        }
    }

    private func tileView(_ tile: ActionsTile) -> some View {
        let s = model.state, enabled = tile.isEnabled(in: s)
        return Button { model.press(tile) } label: {
            VStack(spacing: 5) {
                picture(ActionIcons.pictures[tile]).frame(width: 76, height: 62)
                Text(tile.title(in: s)).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(PixelBox.rim)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.tile.width - 16)
                Text(tile.detail(in: s) ?? " ").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Self.softInk).monospacedDigit().lineLimit(1)
            }
            .frame(width: Self.tile.width, height: Self.tile.height)
            .overlay(alignment: .topTrailing) {
                Text(String(tile.key).uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Self.faintInk).padding(.top, 8).padding(.trailing, 9)
            }
        }
        .buttonStyle(PixelTileStyle(chosen: tile == .hide && (model.choosingHide || s.hiding)))
        .keyboardShortcut(KeyEquivalent(tile.key), modifiers: [])
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    /// A sprite at the largest whole-pixel scale that fits, never smoothed.
    @ViewBuilder private func picture(_ image: CGImage?) -> some View {
        if let image {
            let scale = max(1, min(76 / CGFloat(image.width), 62 / CGFloat(image.height)).rounded(.down))
            Image(decorative: image, scale: 1).resizable().interpolation(.none)
                .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        }
    }

    /// Under the tiles: how long to hide, or what the last press did.
    @ViewBuilder private var line: some View {
        if model.choosingHide {
            HStack(spacing: 6) {
                Text(tr("HIDE FOR")).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Self.softInk)
                    .padding(.trailing, 2)
                ForEach(Self.hideChoices, id: \.0) { title, minutes in
                    PixelButton(title: title, small: true, chosen: minutes == 30) { model.hide(minutes) }
                }
            }
        } else {
            Text(model.said.isEmpty ? tr("click a picture, or press its letter") : model.said)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.said.isEmpty ? Self.faintInk : Self.softInk)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            PixelButton(title: tr("DONE"), action: done)
                .keyboardShortcut(.cancelAction)
        }
        // Clear of the paper's folded-down corner.
        .padding(.trailing, 24)
    }
}

/// A tile drawn as a `PixelBox` that sinks a pixel while pressed.
struct PixelTileStyle: ButtonStyle {
    var chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(PixelBox(style: configuration.isPressed ? .pressed : chosen ? .chosen : .raised))
            .offset(y: configuration.isPressed ? ReminderNoteController.pixel : 0)
            .contentShape(Rectangle())
    }
}
