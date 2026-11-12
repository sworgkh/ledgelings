import AppKit
import QuartzCore
import LedgelingsCore

/// Every effect filmed offscreen (SPEC §7.19): each of the five styles on two creatures at once (Blocky and
/// Boo), then each of the twenty moments, one after another, the ambient ones along the bottom edge. Every
/// step is printed with its time (`fx 3.20 Smitten on Boo`, `fx 9.10 moment goal Blocky`), and a contact
/// sheet of every effect at its height is written beside the film (`…-contact.png`), each cell captioned.
///
///     Ledgelings --effects-film build/effects.mp4
@MainActor
enum EffectsFilm {
    struct Cell { let label: String; let image: CGImage }

    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-effects-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-effects-film"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        settings.species = ["blocky", "ghost", "robot", "frog"]
        settings.creatureCount = 4
        settings.minSize = 2; settings.maxSize = 2
        settings.brain = .script
        settings.talkEnabled = false
        settings.planesEnabled = false
        settings.teaPartiesEnabled = false
        settings.playEnabled = false
        settings.dayMinutes = 600; settings.nightMinutes = 0
        settings.effectStyleSeconds = 5
        // Nothing comes by itself in the film: only what it plays.
        settings.effectsAmbientEveryMinutes = 120; settings.effectsAmbientSeconds = 10
        settings.effectsFrequency = .rarely
        settings.effectsReduceMotion = .off
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch), bonds: BondBook(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.meetings = Meetings(gap: -1e6)
        colony.nextPlayAt = .infinity
        colony.elapsed = 1e4            // well past any ambient spell's start, so none comes by itself
        let start = colony.elapsed
        var t = 0.0
        func log(_ line: String) { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
        colony.fx.trace = { line in
            // "fx 10003.20 …" on the colony's clock: the film's own time instead.
            let parts = line.split(separator: " ", maxSplits: 2)
            if parts.count == 3, parts[0] == "fx", Double(parts[1]) != nil { log(String(format: "fx %.2f %@", t, String(parts[2]))) } else { log(line) }
        }

        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let dt = 1 / Double(Promo.fps), away = CGPoint(x: -500, y: -500)

        // Who wears what: Blocky and Boo, standing still on the floor a little apart.
        let names = colony.creatures.indices.map { colony.character(forCreature: $0).name }
        guard let blocky = names.firstIndex(of: "Blocky"), let boo = names.firstIndex(of: "Boo") else {
            throw NSError(domain: "effects film", code: 1, userInfo: [NSLocalizedDescriptionKey: "no Blocky and Boo: \(names)"])
        }
        func stand() {
            for (k, i) in [blocky, boo].enumerated() {
                let world = colony.world(forSize: colony.sizes[i])
                guard let floor = world.segments.first(where: { world.loops[$0.loop].inward(ofSegment: $0.segment).dy > 0.9 }) else { continue }
                let tAt = world.loops[floor.loop].t(onSegment: floor.segment, fraction: k == 0 ? 0.42 : 0.56)
                colony.creatures[i] = Creature(world: world, spot: .init(loop: floor.loop, t: tAt), facingForwards: k == 0,
                                               config: colony.creatures[i].config)
                colony.creatures[i].pause(for: 1e4)
            }
            for i in colony.creatures.indices where i != blocky && i != boo { colony.creatures[i].pause(for: 1e4) }
        }
        stand()

        // The plan: each step starts something and lasts a while; a still is taken partway in.
        enum What { case style(Effects.Style), moment(Effects.Moment) }
        var plan: [(what: What, seconds: Double)] = Effects.Style.allCases.map { (.style($0), settings.effectStyleSeconds + 0.6) }
        for m in Effects.Moment.allCases {
            let d = FXCatalog.all[m.effect]?.meta.duration ?? 2
            plan.append((.moment(m), m.ambient ? 7 : max(1.6, min(d, 3.6)) + 0.4))
        }
        var cells: [Cell] = []
        var k = -1, stepEnds = 1.0, captureAt = Double.infinity, capture: (label: String, rect: CGRect)?
        var pendingRestore = false
        var frame = 0
        while true {
            t = Double(frame) * dt
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if t >= stepEnds {
                if pendingRestore { settings.creatureCount = 4; colony.applySettings(); stand(); pendingRestore = false }
                k += 1
                guard k < plan.count else { CATransaction.commit(); break }
                let step = plan[k]
                stepEnds = t + step.seconds
                switch step.what {
                case .style(let s):
                    colony.wear(s, on: blocky, byHand: true); colony.wear(s, on: boo, byHand: true)
                    captureAt = t + 2.4
                    capture = (s.title, cropRect(around: [blocky, boo], colony, meta: FXCatalog.all[s.effect]?.meta))
                case .moment(let m):
                    let d = FXCatalog.all[m.effect]?.meta.duration ?? 2
                    if m == .poof {
                        // Poof is a creature going: one is taken away, and comes back after.
                        let last = colony.creatures.count - 1
                        capture = ("\(m.title) · \(m.feature.title)", cropRect(around: [last], colony, meta: FXCatalog.all[m.effect]?.meta))
                        settings.creatureCount = 3; colony.applySettings()
                        pendingRestore = true
                    } else if m.ambient {
                        colony.play(m, on: blocky)
                        capture = ("\(m.title) · \(m.feature.title)", CGRect(x: 0, y: 0, width: 760, height: 360))
                    } else {
                        colony.play(m, on: blocky)
                        capture = ("\(m.title) · \(m.feature.title)", cropRect(around: [blocky], colony, meta: FXCatalog.all[m.effect]?.meta))
                    }
                    captureAt = t + (m.ambient ? 5 : min(d * 0.5, 2.2))
                    if m == .newArrival { captureAt = t + 2.3 }
                    if m == .copied || m == .hardLanding { captureAt = t + 0.35 }
                }
            }
            colony.advance(dt: dt, cursor: away, shift: false)
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            if t >= captureAt, let c = capture, let whole = recorder.lastFrame(), let image = crop(whole, c.rect) {
                cells.append(Cell(label: c.label, image: image))
                captureAt = .infinity
                // The first style's still has both wearers in it: the stills of a style show two creatures.
            }
            frame += 1
            if frame > Promo.fps * 400 { break }
        }
        try await recorder.finish()
        _ = start
        let sheet = output.deletingLastPathComponent().appendingPathComponent(output.deletingPathExtension().lastPathComponent + "-contact.png")
        if let made = contactSheet(cells), let png = ShotRenderer.png(made) { try png.write(to: sheet) }
        log("contact sheet: \(cells.count) effects → \(sheet.path)")
        print("effects film: \(Effects.Style.allCases.count) styles, \(Effects.Moment.allCases.count) moments → \(output.path)")
    }

    /// The box round some creatures and their effect, in stage points (y up).
    static func cropRect(around who: [Int], _ colony: Colony, meta: FXMeta?) -> CGRect {
        let points = who.map { colony.creatures[$0].position }
        let w = CGFloat(meta?.size.w ?? 100) * 2, h = CGFloat(meta?.size.h ?? 100) * 2
        let minX = (points.map(\.x).min() ?? 0) - min(w, 420) / 2, maxX = (points.map(\.x).max() ?? 0) + min(w, 420) / 2
        let floor = (points.map(\.y).min() ?? 0) - 40
        return CGRect(x: minX, y: floor, width: maxX - minX, height: min(h, 380))
    }

    /// A part of the film's frame, given in stage points (y up).
    static func crop(_ image: CGImage, _ r: CGRect) -> CGImage? {
        let s = Promo.scale
        let px = CGRect(x: r.minX * s, y: (Promo.size.height - r.maxY) * s, width: r.width * s, height: r.height * s)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return px.isEmpty ? nil : image.cropping(to: px.integral)
    }

    /// Every still in a grid, six across, each fitted into its cell and captioned under it.
    static func contactSheet(_ cells: [Cell]) -> CGImage? {
        guard !cells.isEmpty else { return nil }
        let cw = 380, ch = 250, caption = 26, across = 6
        let rows = (cells.count + across - 1) / across
        let W = cw * across, H = (ch + caption) * rows
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.08, blue: 0.14, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .none
        for (n, cell) in cells.enumerated() {
            let col = n % across, row = n / across
            let x = col * cw, top = H - row * (ch + caption)
            let k = min(CGFloat(cw - 8) / CGFloat(cell.image.width), CGFloat(ch - 8) / CGFloat(cell.image.height))
            let w = CGFloat(cell.image.width) * k, h = CGFloat(cell.image.height) * k
            ctx.draw(cell.image, in: CGRect(x: CGFloat(x) + (CGFloat(cw) - w) / 2, y: CGFloat(top - ch) + (CGFloat(ch) - h) / 2, width: w, height: h))
            let label = NSAttributedString(string: cell.label, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
                                                                            .foregroundColor: NSColor.white])
            let line = CTLineCreateWithAttributedString(label)
            ctx.textPosition = CGPoint(x: CGFloat(x + 10), y: CGFloat(top - ch - caption + 8))
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }
}
