import AppKit
import Carbon.HIToolbox
import QuartzCore
import SwiftUI
import LedgelingsCore

/// The Translate sheet brought by a creature, written to an .mp4 frame by frame,
/// offscreen: the leap to the corner, the sheet unfolding, a phrase typed with
/// its guess in grey, the translation into Russian (thinking dots meanwhile), the
/// swap that checks it backwards, a Hebrew answer running right to left; then the
/// saved translations (⌘D on two of them, ⌘L for the drawer beside the sheet, a
/// search, one loaded back, one deleted: the sheet's own logic, offscreen); then the
/// clipboard picker with a row translated under it. Each step's still is written
/// beside the film (`-typing.png`, `-guess.png`, `-russian.png`, `-swap.png`,
/// `-hebrew.png`, `-saved.png`, `-drawer.png`, `-drawer-search.png`, `-loaded.png`,
/// `-deleted.png`, `-picker.png`). Hand-written answers, no model, no key.
///
///     Ledgelings --translate-film build/translate.mp4
@MainActor
enum TranslateFilm {
    static let phrase = "Can you send me the report before Friday's meeting?"

    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-translate-film-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-translate-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.creatureCount = 4
        settings.species = ["blocky", "cat", "frog", "robot"]
        settings.minSize = 2.5; settings.maxSize = 2.5
        settings.brain = .script
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.playEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.userIdleSeconds = { 0 }
        var t = 0.0
        func log(_ line: String) { print(String(format: "film %5.2f  %@", t, line)) }
        colony.trace = { line in if line.hasPrefix("clip") { log(line) } }

        // The sheet's stills, drawn by its own view.
        let model = TranslateSheetModel()
        model.paper = CGRect(origin: .zero, size: TranslateSheetController.size)
        model.languages = Translate.languages
        func still(_ step: String, _ set: (TranslateSheetModel) -> Void) async throws -> CGImage {
            set(model)
            let image = try await picture(TranslateSheetView(model: model), size: TranslateSheetController.size)
            try write(image, to: output, step)
            return image
        }
        let typing = try await still("typing") { m in
            m.text = "Can you send me"; m.detected = Translate.english; m.guess = ""; m.result = ""; m.state = .waiting
            m.status = tr("%@ → %@ · translating…", Translate.english.title.uppercased(), Translate.russian.title.uppercased())
        }
        let guess = try await still("guess") { m in m.guess = " the report before Friday" }
        let russian = try await still("russian") { m in
            m.text = phrase; m.guess = ""; m.state = .done; m.resultLanguage = Translate.russian
            m.result = TranslateDemo.known["en>ru|\(phrase)"] ?? ""
            m.status = Translate.status(from: Translate.english, to: Translate.russian, seconds: 0.6)
        }
        let swapped = try await still("swap") { m in
            m.sourceChoice = Translate.russian; m.targetChoice = Translate.english; m.text = m.result; m.detected = Translate.russian
            m.resultLanguage = Translate.english; m.result = TranslateDemo.known["ru>en|\(m.text)"] ?? ""
            m.status = Translate.status(from: Translate.russian, to: Translate.english, seconds: 0.5)
        }
        let hebrew = try await still("hebrew") { m in
            m.sourceChoice = nil; m.targetChoice = Translate.hebrew; m.text = phrase; m.detected = Translate.english
            m.resultLanguage = Translate.hebrew; m.result = TranslateDemo.known["en>he|\(phrase)"] ?? ""
            m.status = Translate.status(from: Translate.english, to: Translate.hebrew, seconds: 0.7)
        }
        let book = ClipBook(directory: scratch.appendingPathComponent("clips"), secrets: Keychain(service: name))

        // Saved translations, through a real sheet's keys with a stand-in model.
        settings.translateAutocomplete = false
        settings.translateDelayMs = 200
        let translator = Translator(settings: settings, spend: SpendLedger(directory: scratch))
        translator.fake = TranslateDemo.fake
        let savedBook = SavedTranslations(directory: scratch.appendingPathComponent("saved"))
        let sheet = TranslateSheetController(settings: settings, translator: translator, clips: book, saved: savedBook, watcher: { nil })
        sheet.trace = { log("sheet \($0)") }
        let m = sheet.model
        m.languages = Translate.languages; m.hasModel = true; m.savedOn = true; m.appName = "Mail"
        m.paper = CGRect(origin: .zero, size: TranslateSheetController.size)
        let wide = CGSize(width: TranslateSheetController.size.width + TranslateSheetModel.drawerWidth - TranslateSheetModel.drawerTuck,
                          height: TranslateSheetController.size.height)
        m.room = wide
        func type(_ text: String) async {
            m.typed(text, cursorAtEnd: true)
            for _ in 0..<100 where m.state != .done { try? await Task.sleep(for: .milliseconds(50)) }
            log("typed and translated: \(m.result)")
        }
        func shot(_ step: String, drawer: Bool) async throws -> CGImage {
            let image = try await picture(TranslateSheetView(model: m), size: drawer ? wide : TranslateSheetController.size)
            try write(image, to: output, step)
            return image
        }
        func press(_ code: Int, _ flags: NSEvent.ModifierFlags = [], _ name: String) {
            let took = sheet.key(code, flags)
            log("\(name)\(took ? "" : " (not taken)")")
        }
        await type(phrase)
        press(kVK_ANSI_D, .command, "⌘D")
        let savedImage = try await shot("saved", drawer: false)
        await type("Не забудь купить молоко и хлеб по дороге домой.")
        press(kVK_ANSI_D, .command, "⌘D")
        log("\(savedBook.book.count) saved: \(savedBook.book.entries.map { $0.text.prefix(24) }.joined(separator: " | "))")
        press(kVK_ANSI_L, .command, "⌘L")
        let drawerImage = try await shot("drawer", drawer: true)
        m.query = "report"
        log("search \"report\": \(m.shownSaved.count) of \(m.saved.count)")
        let searchImage = try await shot("drawer-search", drawer: true)
        press(kVK_Return, [], "⏎ loads the first entry")
        let loadedImage = try await shot("loaded", drawer: true)
        m.query = ""
        press(kVK_UpArrow, [], "↑")
        press(kVK_Delete, [], "⌫")
        let deletedImage = try await shot("deleted", drawer: true)
        press(kVK_Escape, [], "⎋ closes the drawer")
        if savedBook.book.count != 1 || m.drawerOpen || m.text != phrase {
            throw CocoaError(.validationMultipleErrors, userInfo: [NSLocalizedDescriptionKey: "saved translations went wrong: \(savedBook.book.count) saved"])
        }

        // The picker, a row translated under it.
        let now = Date()
        for (i, text) in ["Не забудь купить молоко и хлеб по дороге домой.", "https://ledgelings.app/beds", "אני אגיע מאוחר היום, תתחילו בלעדיי."].enumerated() {
            book.add(Clipboard.Clip(text: text, copiedAt: now.addingTimeInterval(Double(i) * 60 - 600), app: ["Telegram", "Safari", "WhatsApp"][i]), limit: 100, days: 0)
        }
        let picker = ClipPickerModel()
        picker.source = { (book.history, book.snippets) }
        picker.paper = CGRect(origin: .zero, size: ClipPickerController.size)
        picker.translateOn = true
        picker.refresh(selectFirst: true)
        if let row = picker.rows.first(where: { $0.text.hasPrefix("אני") }) {
            picker.selected = row.id
            picker.translation = .init(id: row.id, target: Translate.english, state: .done(TranslateDemo.known["he>en|\(book.history.clips.first { $0.id == row.id }!.text)"] ?? ""))
        }
        let pickerImage = try await picture(ClipPickerView(model: picker), size: ClipPickerController.size)
        try write(pickerImage, to: output, "picker")

        let stage = Promo.Stage()
        let size = TranslateSheetController.size
        let base: CGFloat = 0.62
        let paperOnStage = CGRect(x: (Promo.size.width - size.width * base) / 2 + 50, y: 30, width: size.width * base, height: size.height * base)
        let paper = CALayer()
        paper.contents = typing
        paper.magnificationFilter = .nearest
        paper.bounds = CGRect(origin: .zero, size: size)
        paper.anchorPoint = CGPoint(x: 0, y: 1)
        paper.position = CGPoint(x: paperOnStage.minX, y: paperOnStage.maxY)
        paper.transform = CATransform3DMakeScale(base, base, 1)
        paper.opacity = 0
        stage.root.addSublayer(paper)
        stage.root.addSublayer(colony.overlays[0].root)

        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500), dt = 1 / Double(Promo.fps)
        let centre = CGPoint(x: Promo.size.width / 2, y: Promo.size.height / 2)
        // What the sheet shows from when, after it has unfolded, and how the creature holds it meanwhile.
        let script: [(at: Double, image: CGImage, mood: ClipHelperMood, line: String)] = [
            (0, typing, .thinking, "typed \"Can you send me\""),
            (1.2, guess, .calm, "guess: the report before Friday"),
            (2.8, russian, .calm, "⇥ takes it: English → Russian"),
            (5.0, swapped, .calm, "⌘S: back from Russian"),
            (7.0, hebrew, .calm, "⌥3: into Hebrew, right to left"),
            (9.4, savedImage, .calm, "⌘D: the star, filled: saved"),
            (11.0, drawerImage, .calm, "⌘L: the drawer of saved ones"),
            (12.8, searchImage, .calm, "a search: report"),
            (14.4, loadedImage, .calm, "⏎: loaded back, no call"),
            (16.0, deletedImage, .calm, "⌫: one deleted"),
            (17.6, pickerImage, .calm, "the clipboard picker: ⌘T under a row"),
        ]
        enum Phase { case before, coming(until: Double), unfolding(since: Double), open(since: Double), closing(since: Double), after(until: Double) }
        var phase = Phase.before, frame = 0, done = false, shown = -1
        while !done && frame < Promo.fps * 30 {
            t = Double(frame) * dt
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: dt, cursor: away, shift: false)
            switch phase {
            case .before where t >= 1:
                log("⌃⌥T")
                phase = .coming(until: t + (colony.clipHelperCome(paper: paperOnStage, centre: centre, wanted: "") ?? 0))
            case .coming(let until) where t >= until:
                phase = .unfolding(since: t)
            case .unfolding(let since):
                let s = min((t - since) / ClipHelper.unfoldSeconds, 1), eased = 1 - (1 - s) * (1 - s)
                paper.opacity = Float(eased)
                paper.transform = CATransform3DMakeScale(base * (0.06 + 0.94 * eased), base * (0.06 + 0.94 * eased), 1)
                if s >= 1 { phase = .open(since: t); log("sheet open") }
            case .open(let since):
                let at = t - since
                if let i = script.lastIndex(where: { $0.at <= at }), i != shown {
                    shown = i
                    let step = script[i]
                    paper.contents = step.image
                    // The picker, or the sheet with its drawer: their own size, same corner.
                    let k = CGFloat(typing.width) / size.width
                    paper.bounds = CGRect(origin: .zero, size: CGSize(width: CGFloat(step.image.width) / k, height: CGFloat(step.image.height) / k))
                    colony.clipHelperMood(step.mood)
                    log(step.line)
                }
                if at >= 20.6 { phase = .closing(since: t); log("⎋") }
            case .closing(let since):
                let s = min((t - since) / ClipHelper.collapseSeconds, 1), k = base * (1 - 0.98 * s * s)
                paper.transform = CATransform3DMakeScale(k, k, 1)
                paper.opacity = Float(1 - s)
                if s >= 1 { colony.clipHelperGoHome(after: 0); phase = .after(until: t + 1.5) }
            case .after(let until) where t >= until && colony.clipHelp == nil:
                done = true
            default: break
            }
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
        }
        try await recorder.finish()
        print("translate film: \(frame) frames → \(output.path)")
    }

    /// A view drawn offscreen, as a picture.
    static func picture(_ view: some View, size: CGSize) async throws -> CGImage {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        try? await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        hosting.needsDisplay = true
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let image = rep.cgImage else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    /// `out.mp4` → `out-<step>.png`.
    private static func write(_ image: CGImage, to film: URL, _ step: String) throws {
        let url = film.deletingPathExtension().appendingPathExtension("").deletingPathExtension()
        let png = film.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-\(step).png")
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: png)
    }
}
