import AppKit
import QuartzCore
import SwiftUI
import LedgelingsCore

/// The screenshot tool filmed offscreen on two simulated monitors side by side, the
/// left one 2× and the right one 1×: a rectangle with a box, an arrow, a blur over a
/// card number and a freehand blur over a password; a lasso; all monitors at once;
/// then the last rectangle again with no toolbar. A creature carries each shot home.
/// Every step is printed with its time, and every picture is written beside the film.
///
///     Ledgelings --shot-film build/screenshots.mp4
@MainActor
enum ShotFilm {
    static let left = Display(frame: CGRect(x: 0, y: 0, width: 600, height: 400), scale: Promo.scale, id: "film-left", name: "Left 2×")
    static let right = Display(frame: CGRect(x: 600, y: 60, width: 424, height: 280), scale: Promo.scale, id: "film-right", name: "Right 1×")

    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-shot-film-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-shot-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "robot", "frog", "cat"]
        settings.creatureCount = 4
        settings.minSize = 2; settings.maxSize = 2
        settings.brain = .script
        settings.talkEnabled = false
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.playEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch), bonds: BondBook(directory: scratch),
                                stages: [left, right])
        colony.userIdleSeconds = { 0 }
        var t = 0.0
        func log(_ line: String) { print(String(format: "film %5.2f  %@", t, line)) }
        colony.trace = { if $0.hasPrefix("shot") { log($0) } }

        let frames = [ShotFrame(monitor: Shot.Monitor(frame: left.frame, scale: 2), image: desktop(left.frame.size, scale: 2, left: true), name: left.name),
                      ShotFrame(monitor: Shot.Monitor(frame: right.frame, scale: 1), image: desktop(right.frame.size, scale: 1, left: false), name: right.name)]
        let folder = output.deletingPathExtension()
        let stem = folder.lastPathComponent
        func write(_ image: CGImage, _ what: String) {
            let url = folder.deletingLastPathComponent().appendingPathComponent("\(stem)-\(what).png")
            try? ShotRenderer.png(image)?.write(to: url)
            log("wrote \(url.lastPathComponent) \(image.width)×\(image.height) px")
        }

        let stage = Promo.Stage()
        let desk = CALayer()
        desk.frame = CGRect(origin: .zero, size: Promo.size)
        desk.backgroundColor = CGColor(srgbRed: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        stage.root.addSublayer(desk)
        let screens = frames.map { f -> CALayer in
            let layer = CALayer()
            layer.frame = f.monitor.frame
            layer.magnificationFilter = .nearest
            stage.root.addSublayer(layer)
            return layer
        }
        let toolbar = CALayer()
        toolbar.anchorPoint = .zero
        toolbar.magnificationFilter = .nearest
        stage.root.addSublayer(toolbar)
        for overlay in colony.overlays {
            overlay.root.position = overlay.display.frame.origin
            overlay.root.masksToBounds = true
            stage.root.addSublayer(overlay.root)
        }
        let toast = CALayer()
        toast.anchorPoint = .zero
        stage.root.addSublayer(toast)

        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let dt = 1 / Double(Promo.fps)
        var frame = 0
        var session: ShotSession?
        var toolbarKey = ""
        let blocks: [CGImage?] = frames.map { ShotRenderer.blocky($0.image, block: Shot.blurBlock * $0.monitor.scale) }
        var toastUntil = 0.0

        func draw() async throws {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: dt, cursor: CGPoint(x: -500, y: -500), shift: true)
            for (i, f) in frames.enumerated() {
                if let session, session.isUp {
                    screens[i].contents = paint(f, session: session, blocks: blocks[i])
                } else {
                    screens[i].contents = f.image
                }
            }
            if let session, session.isUp {
                let m = session.model
                let key = "\(m.mode)\(m.tool)\(m.colour)\(m.stage)\(m.marks.isEmpty)"
                if key != toolbarKey {
                    toolbarKey = key
                    let image = try await picture(ShotToolbar(model: m))
                    toolbar.contents = image
                }
                toolbar.isHidden = false
            } else {
                toolbar.isHidden = true
            }
            toast.isHidden = t > toastUntil
            // Hidden while the screens are frozen, as in the app.
            let frozen = session?.isUp == true
            for overlay in colony.overlays where overlay.root.isHidden != frozen { overlay.root.isHidden = frozen }
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
            t = Double(frame) * dt
        }
        func wait(_ seconds: Double) async throws { let end = t + seconds; while t < end { try await draw() } }

        /// The toolbar shot: frozen, the toolbar at the top of the left monitor.
        func open() async throws -> ShotSession {
            log("shortcut ⌃⌥S: the screens freeze")
            let made = ShotSession(frames: frames, settings: settings) { outcome in
                guard case .taken(let image, _, _, let spot) = outcome else { return }
                finished(image, spot: spot)
            }
            made.trace = { log($0) }
            let size = try await toolbarSize(made.model)
            // The film's monitors are small: the toolbar shrinks to fit the left one.
            let fit = min(1, (left.frame.width - 16) / size.width)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            toolbar.bounds = CGRect(origin: .zero, size: size)
            toolbar.transform = CATransform3DMakeScale(fit, fit, 1)
            let shown = CGSize(width: size.width * fit, height: size.height * fit)
            made.startOffscreen(cursor: CGPoint(x: left.frame.midX, y: left.frame.midY), toolbar: shown)
            let origin = Shot.toolbarOrigin(cursorX: left.frame.midX, screen: left.frame, size: shown)
            toolbar.position = origin
            toolbarKey = ""
            session = made
            return made
        }
        var shots = 0
        func finished(_ image: CGImage, spot: CGPoint) {
            shots += 1
            write(image, ["rectangle", "lasso", "all", "last-rectangle"][min(shots - 1, 3)])
            let note = Shot.toast(size: CGSize(width: image.width, height: image.height), copied: true, saved: nil)
            log("toast \(note)")
            if let made = try? toastImage(note) {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                defer { CATransaction.commit() }
                toast.contents = made
                toast.bounds = CGRect(x: 0, y: 0, width: CGFloat(made.width) / Promo.scale, height: CGFloat(made.height) / Promo.scale)
                toast.position = CGPoint(x: spot.x - toast.bounds.width / 2, y: spot.y - 90)
                toastUntil = t + 1.6
            }
            colony.shotCarrierCome(to: spot, picture: ShotRenderer.thumbnail(image, size: colony.planeCell))
        }
        func drag(_ s: ShotSession, _ a: CGPoint, _ b: CGPoint, seconds: Double = 0.7, path: ((Double) -> CGPoint)? = nil) async throws {
            s.down(a)
            let steps = Int(seconds * Double(Promo.fps))
            for k in 1...steps {
                let u = Double(k) / Double(steps)
                s.dragged(path?(u) ?? CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u))
                try await draw()
            }
            s.up(path?(1) ?? b)
            try await wait(0.3)
        }
        func waitForCarrier() async throws {
            for _ in 0..<(Promo.fps * 6) where colony.shotCarry != nil { try await draw() }
        }

        try await wait(1)
        // 1. A rectangle on the 2× monitor, marked up.
        var s = try await open()
        try await wait(0.6)
        try await drag(s, CGPoint(x: 70, y: 330), CGPoint(x: 470, y: 70))
        s.act(.tool(.box)); s.act(.colour(0))
        try await drag(s, CGPoint(x: 96, y: 300), CGPoint(x: 300, y: 262))
        s.act(.tool(.arrow)); s.act(.colour(1))
        try await drag(s, CGPoint(x: 440, y: 120), CGPoint(x: 310, y: 270))
        s.act(.tool(.blur))
        try await drag(s, CGPoint(x: 96, y: 228), CGPoint(x: 400, y: 200))
        s.act(.tool(.brush))
        try await drag(s, CGPoint(x: 100, y: 164), CGPoint(x: 380, y: 160), seconds: 0.9) { u in CGPoint(x: 100 + 280 * u, y: 161 + 3 * sin(u * 9)) }
        try await wait(0.6)
        log("⏎: copy")
        s.act(.finish(.enter))
        settings.shotLastRect = Shot.save(CGRect(x: 70, y: 70, width: 400, height: 260))
        try await waitForCarrier()

        // 2. A lasso round the chart on the 1× monitor.
        s = try await open()
        s.act(.mode(.lasso))
        try await wait(0.4)
        let centre = CGPoint(x: right.frame.midX, y: right.frame.midY - 10)
        try await drag(s, CGPoint(x: centre.x + 150, y: centre.y), CGPoint(x: centre.x + 150, y: centre.y), seconds: 1.2) { u in
            CGPoint(x: centre.x + 150 * cos(u * 2 * .pi), y: centre.y + 95 * sin(u * 2 * .pi))
        }
        s.act(.tool(.highlight)); s.act(.colour(2))
        try await drag(s, CGPoint(x: centre.x - 60, y: centre.y + 30), CGPoint(x: centre.x + 40, y: centre.y - 20))
        log("⏎: copy")
        s.act(.finish(.enter))
        try await waitForCarrier()

        // 3. All monitors, stitched at each one's own scale.
        s = try await open()
        try await wait(0.4)
        s.act(.mode(.all))
        try await wait(0.8)
        log("⏎: copy")
        s.act(.finish(.enter))
        try await waitForCarrier()

        // 4. The last rectangle again: no toolbar, straight out.
        log("shortcut ⌘⇧\\: the last rectangle again")
        if let rect = Shot.lastArea(settings.shotLastRect, on: frames.map(\.monitor)), let image = ShotRenderer.render(frames, area: .rect(rect, monitor: 0), marks: []) {
            finished(image, spot: CGPoint(x: rect.midX, y: rect.maxY - 20))
        }
        try await waitForCarrier()
        try await wait(0.5)
        try await recorder.finish()
        print("shot film: \(frame) frames → \(output.path)")
    }

    /// One frozen monitor as the session draws it, at the film's pixel scale.
    private static func paint(_ f: ShotFrame, session: ShotSession, blocks: CGImage?) -> CGImage? {
        let size = f.monitor.frame.size, k = Promo.scale
        guard let c = CGContext(data: nil, width: Int(size.width * k), height: Int(size.height * k), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: k, y: k)
        ShotCanvas.paint(c, frame: f, model: session.model, frames: session.frames, blocks: blocks)
        return c.makeImage()
    }

    private static func toolbarSize(_ model: ShotModel) async throws -> CGSize {
        NSHostingView(rootView: ShotToolbar(model: model)).fittingSize
    }

    /// A SwiftUI view drawn offscreen at the film's scale.
    private static func picture(_ view: some View) async throws -> CGImage {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // SwiftUI draws on the next turns of the run loop, not at once.
        try? await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let image = rep.cgImage else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    private static func toastImage(_ text: String) throws -> CGImage? {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .heavy)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: ScreenOverlay.ink) ?? .black]))
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 28, h: CGFloat = 36, k = Promo.scale
        guard let c = CGContext(data: nil, width: Int(w * k), height: Int(h * k), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: k, y: k)
        ShotCanvas.pixelPlate(CGRect(x: 0, y: 0, width: w, height: h), c)
        c.textPosition = CGPoint(x: 14, y: 13)
        CTLineDraw(line, c)
        return c.makeImage()
    }

    /// A made-up desktop at `scale` pixels per point: on the left, a window with an
    /// invoice, a card number and a password to blur; on the right, a bar chart.
    static func desktop(_ size: CGSize, scale: CGFloat, left: Bool) -> CGImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: scale, y: scale)
        let sky = left ? [CGColor(srgbRed: 0.27, green: 0.55, blue: 0.62, alpha: 1), CGColor(srgbRed: 0.13, green: 0.30, blue: 0.40, alpha: 1)]
                       : [CGColor(srgbRed: 0.45, green: 0.33, blue: 0.62, alpha: 1), CGColor(srgbRed: 0.20, green: 0.14, blue: 0.34, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: sky as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, grey: CGFloat = 0.12) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor(white: grey, alpha: 1)]))
            c.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, c)
        }
        let window = left ? CGRect(x: 80, y: 60, width: 380, height: 280) : CGRect(x: 40, y: 40, width: 344, height: 200)
        c.setFillColor(CGColor(gray: 0, alpha: 0.25))
        c.fill(window.offsetBy(dx: 3, dy: -4))
        c.setFillColor(CGColor(gray: 0.98, alpha: 1))
        c.fill(window)
        c.setFillColor(CGColor(gray: 0.88, alpha: 1))
        c.fill(CGRect(x: window.minX, y: window.maxY - 22, width: window.width, height: 22))
        for (k, colour) in [CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                            CGColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            c.setFillColor(colour)
            c.fillEllipse(in: CGRect(x: window.minX + 9 + CGFloat(k) * 16, y: window.maxY - 16, width: 10, height: 10))
        }
        if left {
            text("Invoice #4821", 100, 276, 22, .bold)
            text("Total due: $1,250.00 by Friday", 100, 246, 14)
            text("Card: 4111 1111 1111 1111", 100, 206, 16, .medium)
            text("Wi-Fi password: moss-garden-42", 100, 156, 14)
            text("Thanks for staying with the Ledgelings.", 100, 100, 12, grey: 0.4)
        } else {
            text("Visitors this week", 56, 210, 13, .semibold)
            let bars: [CGFloat] = [40, 70, 55, 110, 90, 130, 75]
            for (k, b) in bars.enumerated() {
                c.setFillColor(CGColor(srgbRed: 0.25, green: 0.52, blue: 0.91, alpha: 1))
                c.fill(CGRect(x: 70 + CGFloat(k) * 42, y: 56, width: 26, height: b))
            }
        }
        return c.makeImage()!
    }
}
