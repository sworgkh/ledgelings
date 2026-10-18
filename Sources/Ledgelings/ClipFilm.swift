import AppKit
import QuartzCore
import SwiftUI
import LedgelingsCore

/// The clipboard picker brought by a creature, written to an .mp4 frame by frame,
/// offscreen: the leap to the corner, the sheet unfolding out of it, a search,
/// the collapse into a text cursor and the leap home; then a second round with
/// no cursor known, collapsing into the creature, which leaps back with it.
/// Its own history and snippets, nothing pasted, built-in lines.
///
///     Ledgelings --clip-film build/clipboard.mp4
@MainActor
enum ClipFilm {
    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-clip-film-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-clip-film"
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
        colony.trace = { line in if line.hasPrefix("clip") || line.hasPrefix("say") { print(String(format: "film %5.2f  %@", t, line)) } }

        // The sheet, as the picker draws it, from a book of its own.
        let book = ClipBook(directory: scratch.appendingPathComponent("clips"), secrets: Keychain(service: name))
        let now = Date()
        for (i, text) in ["Meeting notes: ship the clipboard on Friday", "invoice #4821 for the café", "https://ledgelings.app/beds",
                          "Stand-up at 10:30, room Moss"].enumerated() {
            book.add(Clipboard.Clip(text: text, copiedAt: now.addingTimeInterval(Double(i) * 60 - 600), app: ["Notes", "Mail", "Safari", "Calendar"][i]),
                     limit: 100, days: 0)
        }
        let work = book.addFolder("Work")
        book.addSnippet(title: "Signature", text: "Best regards,\nThe Ledgelings", to: work)
        book.addSnippet(title: "Wi-Fi password", text: "", protected: false, to: work)
        let size = ClipPickerController.size
        // The film is smaller than a screen: the sheet at 80 %, low enough for the creature on its corner to show.
        let base: CGFloat = 0.8
        let paperOnStage = CGRect(x: (Promo.size.width - size.width * base) / 2 + 60, y: 40,
                                  width: size.width * base, height: size.height * base)
        let model = ClipPickerModel()
        model.source = { (book.history, book.snippets) }
        model.paper = CGRect(origin: .zero, size: size)
        model.refresh(selectFirst: true)
        let all = try await picture(model)
        model.query = "invoice"
        let found = try await picture(model)

        let stage = Promo.Stage()
        let paper = CALayer()
        paper.contents = all
        paper.magnificationFilter = .nearest
        paper.bounds = CGRect(origin: .zero, size: size)
        paper.anchorPoint = CGPoint(x: 0, y: 1)          // its top-left corner, where the creature holds it
        paper.position = CGPoint(x: paperOnStage.minX, y: paperOnStage.maxY)
        paper.opacity = 0
        stage.root.addSublayer(paper)
        stage.root.addSublayer(colony.overlays[0].root)  // the creatures over the sheet, as on screen
        // A text field in a window to the left: the cursor the sheet collapses into.
        let field = CALayer()
        field.frame = CGRect(x: 60, y: 120, width: 170, height: 34)
        field.backgroundColor = CGColor(gray: 0.97, alpha: 1)
        field.borderColor = CGColor(gray: 0.2, alpha: 1); field.borderWidth = 2
        let caret = CALayer()
        caret.frame = CGRect(x: 72, y: 126, width: 2, height: 22)
        caret.backgroundColor = CGColor(gray: 0, alpha: 1)
        stage.root.insertSublayer(field, below: paper)
        stage.root.insertSublayer(caret, below: paper)

        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500), dt = 1 / Double(Promo.fps)
        enum Phase { case before, coming(until: Double), unfolding(since: Double), open(until: Double), collapsing(since: Double, into: CGPoint), after(until: Double) }
        var phase = Phase.before, round = 1, frame = 0, done = false
        let unfold = ClipHelper.unfoldSeconds, collapse = ClipHelper.collapseSeconds
        let centre = CGPoint(x: Promo.size.width / 2, y: Promo.size.height / 2)
        func log(_ line: String) { print(String(format: "film %5.2f  %@", t, line)) }
        while !done && frame < Promo.fps * 30 {
            t = Double(frame) * dt
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: dt, cursor: away, shift: false)
            caret.opacity = Int(t * 2) % 2 == 0 ? 1 : 0
            switch phase {
            case .before where t >= 1:
                paper.contents = all
                log("shortcut: round \(round)")
                phase = .coming(until: t + (colony.clipHelperCome(paper: paperOnStage, centre: centre) ?? 0))
            case .coming(let until) where t >= until:
                phase = .unfolding(since: t)
            case .unfolding(let since):
                let s = min((t - since) / unfold, 1), eased = 1 - (1 - s) * (1 - s)
                paper.opacity = Float(eased)
                paper.transform = CATransform3DMakeScale(base * (0.06 + 0.94 * eased), base * (0.06 + 0.94 * eased), 1)
                if s >= 1 { phase = .open(until: t + 2.5); log("sheet open") }
            case .open(let until):
                if round == 1, t >= until - 1.4, (paper.contents as! CGImage) !== found { paper.contents = found; log("typed \"invoice\"") }
                if t >= until {
                    // Round one has a text cursor; round two does not, and goes into the creature's grip.
                    let into = round == 1 ? CGPoint(x: caret.frame.minX, y: caret.frame.midY) : CGPoint(x: paperOnStage.minX, y: paperOnStage.maxY)
                    log("⏎: collapse into \(round == 1 ? "the text cursor" : "the creature")")
                    phase = .collapsing(since: t, into: into)
                }
            case .collapsing(let since, let into):
                let s = min((t - since) / collapse, 1), eased = s * s, k = base * (1 - 0.98 * eased)
                paper.transform = CATransform3DMakeScale(k, k, 1)
                // The corner travels to the point; at the end the whole sheet is a speck there.
                paper.position = CGPoint(x: paperOnStage.minX + (into.x - paperOnStage.minX) * eased,
                                         y: paperOnStage.maxY + (into.y - paperOnStage.maxY) * eased)
                paper.opacity = Float(1 - 0.8 * eased)
                if s >= 1 {
                    paper.opacity = 0
                    paper.transform = CATransform3DMakeScale(base, base, 1)
                    paper.position = CGPoint(x: paperOnStage.minX, y: paperOnStage.maxY)
                    colony.clipHelperGoHome(after: 0)
                    phase = .after(until: t + 1.5)
                }
            case .after(let until) where t >= until && colony.clipHelp == nil:
                if round == 2 { done = true } else { round = 2; phase = .before }
            default: break
            }
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
        }
        try await recorder.finish()
        print("clip film: \(frame) frames → \(output.path)")
    }

    /// The sheet drawn by the picker's own view, offscreen, as a picture.
    private static func picture(_ model: ClipPickerModel) async throws -> CGImage {
        let size = ClipPickerController.size
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: ClipPickerView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        try? await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let image = rep.cgImage else { throw CocoaError(.fileWriteUnknown) }
        return image
    }
}
