import AppKit
import LedgelingsCore
import SwiftUI

/// Creature Actions…: everything you can ask of the creatures, on one sheet of
/// the letter's pixel paper. Each action is a tile with its picture cut from the
/// game's own sprites and a letter key; pressing one does it at once. With
/// `actionsStayOpen` the sheet stays up for another go, else it folds away.
@MainActor
final class ActionsController {
    static let size = CGSize(width: 564, height: 548)

    private let settings: AppSettings
    private let colony: () -> Colony?
    private let addReminder: () -> Void
    private let open: (ActionsLink) -> Void
    private let model = ActionsModel()
    private var window: NoteWindow?
    private var timer: Timer?

    init(settings: AppSettings, colony: @escaping () -> Colony?, addReminder: @escaping () -> Void,
         open: @escaping (ActionsLink) -> Void = { _ in }) {
        self.settings = settings
        self.colony = colony
        self.addReminder = addReminder
        self.open = open
        model.press = { [weak self] in self?.press($0) }
        model.flip = { [weak self] in self?.flip($0) }
        model.open = { [weak self] in self?.follow($0) }
        model.hide = { [weak self] in self?.hide(minutes: $0) }
        model.play = { [weak self] in self?.play($0) }
        model.chooseScreen = { [weak self] in self?.chooseScreen() }
    }

    /// Which page is showing.
    var page: ActionsPage { model.page }

    /// Whether the sheet is on screen.
    var isUp: Bool { window != nil }

    /// `page`: the sheet, or straight to its Activities page (the menu's Activities…).
    func show(page: ActionsPage = .main) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.page = page
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

    /// The shortcut from any app: up if it is away, away if it is up.
    func toggle() {
        if isUp { foldAway() } else { show() }
    }

    /// The app was opened again while running (Spotlight, Finder, the Dock): with
    /// no icon in the menu bar that is the other way in, so the sheet comes up.
    func reopened() {
        if settings.reopenShowsActions { show() }
    }

    /// What the tiles need to know, read from the colony twice a second.
    private func refresh() {
        var s = ActionsState()
        s.talkOn = settings.talkEnabled
        s.voiceOn = settings.voiceEnabled
        s.revengeOn = settings.revengeEnabled
        s.playOn = settings.playEnabled
        s.playsOff = Set(Plays.Kind.allCases.filter { !settings.playEnabled || !settings.enabledPlays.contains($0) })
        s.mood = settings.cursorMood
        s.language = settings.language
        s.screen = ScreenChoice.isOffered ? Self.screenTitle(settings) : nil
        model.shortcut = settings.shortcutEnabled ? GlobalShortcut.label(settings.shortcut) : ""
        guard let colony = colony() else {
            if model.state != s { model.state = s }
            return
        }
        s.isNight = colony.isNight
        s.nightOff = settings.nightMinutes == 0
        s.phaseLeft = Int(colony.secondsLeftInPhase.rounded(.up))
        s.teaEnabled = settings.teaPartiesEnabled
        s.teaOn = colony.teaParty != nil || colony.teaInvite != nil
        s.planeInAir = colony.airmail != nil
        s.playing = colony.play != nil
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

    /// A switch from the menu bar menu, flipped here. The sheet stays up whatever
    /// `actionsStayOpen` says: its new state is the answer, and there may be another to flip.
    private func flip(_ flipped: ActionsSwitch) {
        model.choosingHide = false
        switch flipped {
        case .talk: settings.talkEnabled.toggle()
        case .voice: settings.voiceEnabled.toggle()
        case .revenge: settings.revengeEnabled.toggle()
        case .play: settings.playEnabled.toggle()
        case .cursor: settings.cursorMood = Self.next(after: settings.cursorMood)
        case .language: settings.language = Self.next(after: settings.language)
        }
        refresh()
        model.said = flipped.said(in: model.state)
        model.saidAt = Date()
    }

    /// The sheet's screen button: which monitor they live on, short enough for the row.
    static func screenTitle(_ settings: AppSettings) -> String {
        guard settings.homeScreen != HomeScreen.all, !ScreenChoice.isAway(settings) else { return tr("SCREEN: ALL") }
        let name = ScreenChoice.current(settings)
        // "Built-in Retina Display" is the laptop's own: that is all it needs to say.
        let short = name.lowercased().hasPrefix("built-in") ? tr("BUILT-IN") : name.uppercased()
        return tr("SCREEN: %@", short)
    }

    /// The screen button: the monitors, as the menu bar menu has them, under the pointer.
    private func chooseScreen() {
        model.choosingHide = false
        let menu = ScreenChoice.menu(settings) { [weak self] monitor in
            guard let self else { return }
            settings.liveOn(monitor)
            refresh()
            model.said = ScreenChoice.said(settings)
            model.saidAt = Date()
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    static func next<T: CaseIterable & Equatable>(after value: T) -> T {
        let all = Array(T.allCases)
        return all[((all.firstIndex(of: value) ?? -1) + 1) % all.count]
    }

    /// Settings, the chats, or out: the sheet is put away first.
    private func follow(_ link: ActionsLink) {
        dismiss()
        open(link)
    }

    /// Play now, from the Activities page: the game starts, or the line says why not.
    private func play(_ kind: Plays.Kind) {
        guard let colony = colony() else { return }
        after(colony.startPlay(kind) ? tr("Off they go: %@.", kind.title) : tr("No game: %@.", colony.talkStatus))
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
    var talkOn = true
    var voiceOn = false
    var revengeOn = true
    var playOn = true
    /// Games switched off in settings (all of them while play is off).
    var playsOff: Set<Plays.Kind> = []
    var playing = false
    var mood = CursorMood.bad
    var language = Language.english
    /// The screen button's words; nil with one monitor, when there is nothing to choose.
    var screen: String?
}

/// The switches under the tiles: what the menu bar menu offers besides the
/// actions, here too, so that nothing is lost when the icon is hidden.
enum ActionsSwitch: CaseIterable {
    case talk, voice, revenge, cursor, language, play

    /// Its words say how it stands now.
    func title(in s: ActionsState) -> String {
        switch self {
        case .talk: s.talkOn ? tr("TALK ON") : tr("TALK OFF")
        case .voice: s.voiceOn ? tr("VOICE ON") : tr("VOICE OFF")
        case .revenge: s.revengeOn ? tr("REVENGE ON") : tr("REVENGE OFF")
        case .play: s.playOn ? tr("PLAY ON") : tr("PLAY OFF")
        case .cursor: tr("CURSOR: %@", s.mood.title.uppercased())
        // Under its own name, as in the menu, so whoever cannot read the current one still finds theirs.
        case .language: s.language.title.uppercased()
        }
    }

    /// Drawn pressed in while it is on.
    func isOn(in s: ActionsState) -> Bool {
        switch self {
        case .talk: s.talkOn
        case .voice: s.voiceOn
        case .revenge: s.revengeOn
        case .play: s.playOn
        case .cursor, .language: false
        }
    }

    /// The line under the tiles after a press.
    func said(in s: ActionsState) -> String {
        switch self {
        case .talk: s.talkOn ? tr("They talk again.") : tr("They keep quiet.")
        case .voice: s.voiceOn ? tr("You hear them talk.") : tr("They talk in bubbles only.")
        case .revenge: s.revengeOn ? tr("They may grab the cursor.") : tr("They leave the cursor alone.")
        case .play: s.playOn ? tr("They play now and then.") : tr("No more games.")
        case .cursor: tr("The cursor is: %@.", s.mood.title)
        case .language: tr("They speak %@ now.", s.language.title)
        }
    }
}

/// Where the sheet can send you, as the menu did.
enum ActionsLink: CaseIterable {
    case settings, chats, quit

    var title: String {
        switch self {
        case .settings: tr("SETTINGS")
        case .chats: tr("CHATS")
        case .quit: tr("QUIT")
        }
    }
}

/// The sheet has one inner page: the games, listed (`Plays`).
enum ActionsPage { case main, activities }

/// A game as a row of the Activities page: what it is called, a line on what
/// happens, and the key that plays it.
extension Plays.Kind {
    var activityTitle: String {
        switch self {
        case .tag: tr("CATCH ME IF YOU CAN")
        case .rope: tr("NINJA ROPE")
        case .parachute: tr("PARACHUTE")
        case .basketball: tr("BASKETBALL")
        case .soccer: tr("SOCCER")
        case .baseball: tr("BASEBALL")
        }
    }

    var activityLine: String {
        switch self {
        case .tag: tr("Two friends chase each other round the edges. A touch, and the other one is it.")
        case .rope: tr("A hook into the ceiling, a big swing over the floor, a somersault down.")
        case .parachute: tr("Up to the ceiling, then down slowly under a little parachute.")
        case .basketball: tr("A hoop on the wall and a few throws; two friends take turns.")
        case .soccer: tr("Everyone free, on the widest floor: alone, one-on-one, one goal for three, teams of friends.")
        case .baseball: tr("Bases on the screen's edges, hit, catch and run by hopping edge to edge.")
        }
    }

    var activityKey: Swift.Character {
        switch self {
        case .tag: "c"
        case .rope: "w"
        case .parachute: "u"
        case .basketball: "b"
        case .soccer: "g"
        case .baseball: "i"
        }
    }

    /// Why Play Now is greyed, or nil when it is not.
    func activityDetail(in s: ActionsState) -> String? {
        if s.hiding { return tr("they are hiding") }
        if s.playsOff.contains(self) { return tr("off in settings") }
        if s.playing { return tr("one at a time") }
        return nil
    }
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
    /// The shortcut from any app as drawn ("⌃⌥L"), empty while it is off.
    @Published var shortcut = ""
    var press: (ActionsTile) -> Void = { _ in }
    var hide: (Double?) -> Void = { _ in }
    var flip: (ActionsSwitch) -> Void = { _ in }
    var open: (ActionsLink) -> Void = { _ in }
    /// The main sheet, or its Activities page.
    @Published var page = ActionsPage.main
    var play: (Plays.Kind) -> Void = { _ in }
    var chooseScreen: () -> Void = {}
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

    /// Each game's picture on the Activities page: Blocky running, the hook, the parachute, the hoop, the net, the bat.
    static let games: [Plays.Kind: CGImage] = {
        var made: [Plays.Kind: CGImage] = [:]
        let props = (try? SpriteAtlas(named: "play"))?.frames()
        made[.tag] = (try? SpriteAtlas(named: "blocky"))?.frames().frame(animation: "walk", time: 0)
        made[.rope] = props?.frame(animation: "hook", time: 0)
        made[.parachute] = props?.frame(animation: "chute", time: 0)
        made[.basketball] = props?.frame(animation: "hoop", time: 0)
        made[.soccer] = props?.frame(animation: "net", time: 0)
        made[.baseball] = props?.frame(animation: "bat", time: 0)
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
                if model.page == .activities {
                    Text(tr("ACTIVITIES · WHAT SHOULD THEY PLAY?")).font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.faintInk).padding(.bottom, 10)
                    activities.padding(.bottom, 8)
                    line.frame(height: 30, alignment: .leading).padding(.bottom, 6)
                    activitiesFooter
                } else {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        // With two monitors or more: which one they live on, chosen from a menu of their names.
                        // Up here, small: the switches' row has no room left in Russian.
                        if let screen = model.state.screen {
                            Button { model.chooseScreen() } label: { Text(screen + " ▾").lineLimit(1).truncationMode(.middle) }
                                .buttonStyle(TinyPixelButtonStyle())
                                .frame(maxWidth: 220, alignment: .trailing)
                        }
                    }
                    .frame(height: 22)
                    .padding(.trailing, 2)
                    .padding(.bottom, 6)            // 28 in all, as the title alone was
                    grid.padding(.bottom, 14)
                    line.frame(height: 30, alignment: .leading).padding(.bottom, 12)
                    switches.padding(.bottom, 12)
                    footer
                }
            }
            .padding(.horizontal, 33)
            .padding(.top, Self.headroom + 27)
            .frame(width: size.width, alignment: .leading)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // Esc on the inner page goes back; on the sheet it puts the sheet away.
        .onExitCommand { if model.page == .activities { model.page = .main } else { done() } }
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
            Text(model.said.isEmpty ? hint : model.said)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.said.isEmpty ? Self.faintInk : Self.softInk)
                .lineLimit(1)
        }
    }

    private var hint: String {
        model.shortcut.isEmpty ? tr("click a picture, or press its letter")
            : tr("click a picture, or press its letter · %@ opens and closes this", model.shortcut)
    }

    /// The menu's quick switches, each saying how it stands; the language sits with the links below.
    private var switches: some View {
        HStack(spacing: 6) {
            ForEach(ActionsSwitch.allCases.filter { $0 != .language && $0 != .play }, id: \.self) { flipped in
                PixelButton(title: flipped.title(in: model.state), small: true, chosen: flipped.isOn(in: model.state)) { model.flip(flipped) }
                    .lineLimit(1).fixedSize()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            PixelButton(title: tr("ACTIVITIES…"), small: true) { model.page = .activities }
                .keyboardShortcut("a", modifiers: [])
            PixelButton(title: ActionsSwitch.language.title(in: model.state), small: true) { model.flip(.language) }
            PixelButton(title: ActionsLink.settings.title, small: true) { model.open(.settings) }
                .keyboardShortcut(",", modifiers: .command)
            PixelButton(title: ActionsLink.chats.title, small: true) { model.open(.chats) }
            PixelButton(title: ActionsLink.quit.title, small: true) { model.open(.quit) }
                .keyboardShortcut("q", modifiers: .command)
            Spacer()
            PixelButton(title: tr("DONE"), action: done)
                .keyboardShortcut(.cancelAction)
        }
        // Clear of the paper's folded-down corner.
        .padding(.trailing, 24)
    }
}

extension ActionsSheetView {
    /// The Activities page: a row per game, its picture, name and what happens, and Play Now.
    var activities: some View {
        // Six rows still leave room for the line and the buttons under them.
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Plays.Kind.allCases, id: \.self) { activityRow($0) }
        }
    }

    private func activityRow(_ kind: Plays.Kind) -> some View {
        let s = model.state, why = kind.activityDetail(in: s)
        return Button { model.play(kind) } label: {
            HStack(spacing: 12) {
                activityPicture(ActionIcons.games[kind]).frame(width: 64, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.activityTitle).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(PixelBox.rim)
                    Text(kind.activityLine).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(cgColor: ScreenOverlay.softInk)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(tr("PLAY NOW")).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(PixelBox.rim)
                    Text(why ?? String(kind.activityKey).uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(cgColor: ScreenOverlay.faintInk)).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: ActionsController.size.width - 66, height: 52, alignment: .leading)
        }
        .buttonStyle(PixelTileStyle(chosen: false))
        .keyboardShortcut(KeyEquivalent(kind.activityKey), modifiers: [])
        .disabled(why != nil)
        .opacity(why == nil ? 1 : 0.45)
    }

    @ViewBuilder private func activityPicture(_ image: CGImage?) -> some View {
        if let image {
            let scale = max(1, min(64 / CGFloat(image.width), 40 / CGFloat(image.height)).rounded(.down))
            Image(decorative: image, scale: 1).resizable().interpolation(.none)
                .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        }
    }

    /// Back to the sheet, games on or off, and Done.
    var activitiesFooter: some View {
        HStack(spacing: 6) {
            PixelButton(title: tr("BACK"), small: true) { model.page = .main }
                .keyboardShortcut(.leftArrow, modifiers: [])
            PixelButton(title: ActionsSwitch.play.title(in: model.state), small: true, chosen: ActionsSwitch.play.isOn(in: model.state)) { model.flip(.play) }
                .lineLimit(1).fixedSize()
            Spacer()
            PixelButton(title: tr("DONE"), action: done)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.top, 40)
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

/// A pixel button smaller than the switches', for the title line: the screen choice.
struct TinyPixelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(PixelBox.rim)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(PixelBox(style: configuration.isPressed ? .pressed : .raised))
            .offset(y: configuration.isPressed ? ReminderNoteController.pixel : 0)
            .contentShape(Rectangle())
    }
}
