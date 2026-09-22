import AppKit
import AVFoundation
import LedgelingsCore
import Metal
import QuartzCore

/// The promo video: the colony on a clean wallpaper, directed through every
/// feature and written to an .mp4, frame by frame, offscreen. Nothing on the
/// user's screen is recorded, and no permission is needed.
///
///     Ledgelings --promo build/promo.mp4
@MainActor
enum Promo {
    /// 1024×576 points at 2.5× is 2560×1440 pixels: creatures and bubbles read at a glance.
    static let size = CGSize(width: 1024, height: 576)
    static let scale: CGFloat = 2.5
    static let fps = 30
    static let port = 17777

    /// What the captions say, and when (seconds into the video).
    struct Caption { let from: Double; let to: Double; let text: String }

    static func run(output: URL) async throws {
        let brain = try startBrain()
        defer { brain.terminate() }
        try await waitForBrain()

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-promo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let settings = try promoSettings()
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: size), scale: scale))
        colony.meetings = Meetings(gap: 12, cooldown: 60, giftEvery: 1)   // the first meeting brings the flower

        let stage = Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        stage.root.addSublayer(stage.captionPlate)
        stage.root.addSublayer(stage.card)

        let recorder = try Recorder(url: output, layer: stage.canvas, size: CGSize(width: size.width * scale, height: size.height * scale), fps: fps)
        let director = Director(colony: colony)
        var frame = 0
        while !director.finished {
            let t = Double(frame) / Double(fps)
            director.direct(at: t)
            colony.advance(dt: 1 / Double(fps), cursor: director.cursor, shift: false)
            stage.show(at: t, director: director)
            try await recorder.append(frame: frame, at: t)
            frame += 1
            if frame % 2 == 0 { try await Task.sleep(for: .milliseconds(1)) }   // let the brain's replies land
        }
        try await recorder.finish()
        print("promo: \(frame) frames, \(String(format: "%.1f", Double(frame) / Double(fps))) s → \(output.path)")
    }

    // MARK: The pieces

    /// Six creatures, big enough to read at 720p, talking to the canned brain.
    private static func promoSettings() throws -> AppSettings {
        let name = "ledgelings-promo"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        s.creatureCount = 6
        s.species = ["blocky", "frog", "cat", "ghost", "mushroom", "triangle"]
        s.minSize = 2.5; s.maxSize = 2.5
        s.brain = .lmStudio
        s.talkServer = "http://127.0.0.1:\(port)"
        s.talkModel = "promo"
        s.talkEnabled = true
        s.followGiver = true
        s.bubbleSeconds = 4
        s.flowerMinutes = 30
        s.dayMinutes = 30; s.nightMinutes = 30
        return s
    }

    /// The server is up when it lists its one model. Up to five seconds.
    private static func waitForBrain() async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/v1/models")!
        for _ in 0..<50 {
            if let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "Promo", code: 7, userInfo: [NSLocalizedDescriptionKey: "the promo brain did not start on port \(port)"])
    }

    private static func startBrain() throws -> Process {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let binary = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: cwd).standardizedFileURL.deletingLastPathComponent()
        let candidates = [
            cwd.appendingPathComponent("scripts/promo-brain.py"),
            binary.appendingPathComponent("../../scripts/promo-brain.py"),
            binary.appendingPathComponent("../../../scripts/promo-brain.py"),
        ].map(\.standardizedFileURL)
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw NSError(domain: "Promo", code: 1, userInfo: [NSLocalizedDescriptionKey: "scripts/promo-brain.py not found"])
        }
        let process = Process()
        let system = "/usr/bin/python3"
        if FileManager.default.isExecutableFile(atPath: system) {
            process.executableURL = URL(fileURLWithPath: system)
            process.arguments = [path.path, "\(port)"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", path.path, "\(port)"]
        }
        try process.run()
        return process
    }

    /// The script: what happens when. Times are seconds into the video; the
    /// house scene waits for the creatures rather than the clock.
    @MainActor final class Director {
        let colony: Colony
        var cursor = CGPoint(x: -400, y: -400)
        var finished = false
        private var done: Set<String> = []
        private var houseHiddenAt: Double?
        private var endAt: Double?
        var captions: [Caption] = []
        var card: (title: String, lines: [String], from: Double, to: Double)?

        init(colony: Colony) { self.colony = colony }

        private func once(_ key: String, _ body: () -> Void) {
            guard !done.contains(key) else { return }
            done.insert(key); body()
        }

        func direct(at t: Double) {
            let c = colony
            if ProcessInfo.processInfo.environment["LEDGELINGS_PROMO_TRACE"] != nil, Int((t * 30).rounded()) % 30 == 0 {
                let modes = c.creatures.map { "\($0.animation)@\(Int($0.position.x)),\(Int($0.position.y))" }.joined(separator: " ")
                print(String(format: "t=%.0f", t), c.hideout.phase, c.isNight ? "night" : "day", "bubbles=\(c.bubbles.count)", modes)
            }
            once("title") {
                card = ("Ledgelings", ["Pixel creatures that live on the edges of your screen."], 0, 4.5)
                // Spread them round the edge, all walking the same way, so nobody meets before the script says.
                let along: [CGFloat] = [0.02, 0.18, 0.34, 0.50, 0.66, 0.82]
                for (i, f) in along.enumerated() where i < c.creatures.count {
                    let world = c.world(forSize: c.sizes[i])
                    let loop = world.loops[0]
                    c.creatures[i].config.walkSpeed = 52                    // in step, so nobody catches anybody up
                    c.creatures[i].emerge(at: EdgeWorld.Spot(loop: 0, t: loop.wrap(loop.length * f)), facing: 1, using: &c.rng)
                }
            }
            if t >= 4.5 { once("walk") { captions.append(Caption(from: 4.5, to: 9.5, text: "They crawl along the edges of your monitors.")) } }

            // The cursor swoops at the third creature: it jumps away.
            if t >= 8, t < 11, c.creatures.count > 2 {
                once("flee-caption") { captions.append(Caption(from: 8, to: 12, text: "They flee your cursor.")) }
                let target = c.creatures[2].position
                let p = min(1, (t - 8) / 1.6)
                cursor = CGPoint(x: -100 + (target.x + 100) * p, y: size.height + 100 - (size.height + 100 - target.y) * p)
            } else { cursor = CGPoint(x: -400, y: -400) }

            // Two are put on the bottom edge, walking at each other.
            if t >= 12 { once("meet") {
                captions.append(Caption(from: 12, to: 18.5, text: "When two bump into each other, they stop and talk."))
                let bottomLeft = c.world(forSize: c.sizes[0]).nearest(to: CGPoint(x: 400, y: 0))
                let bottomRight = c.world(forSize: c.sizes[1]).nearest(to: CGPoint(x: 880, y: 0))
                c.creatures[0].emerge(at: bottomLeft, facing: 1, using: &c.rng)
                c.creatures[1].emerge(at: bottomRight, facing: -1, using: &c.rng)
            } }
            if t >= 18.5 { once("flower") {
                captions.append(Caption(from: 18.5, to: 21.5, text: "Every third meeting brings a flower."))
                captions.append(Caption(from: 21.5, to: 25.5, text: "The one wearing it follows the giver."))
            } }

            if t >= 24 { once("quiet") { c.settings.talkEnabled = false } }   // no new chats into the night
            if t >= 26 { once("night") {
                captions.append(Caption(from: 26, to: 31.5, text: "At night they sleep."))
                c.releaseChat()                                             // a talker never dozes off
                c.skipPhase()
            } }
            if t >= 26, t < 33.5 { c.bubbles.removeAll() }                   // a reply still in flight stays quiet
            if t >= 32 { once("day") { c.skipPhase() } }

            if t >= 34 { once("hide") {
                captions.append(Caption(from: 34, to: 40, text: "Hide them for a while: they run home."))
                c.hide(for: 600)
            } }
            if t >= 34, c.hideout.phase == .hidden, houseHiddenAt == nil { houseHiddenAt = t }
            if let hid = houseHiddenAt, t >= hid + 1.5 { once("back") {
                captions.append(Caption(from: t, to: t + 6, text: "…and come back when it is time."))
                c.bringThemBack()
            } }
            if done.contains("back"), c.hideout.phase == .away, endAt == nil { endAt = t + 3 }
            if t >= 60, endAt == nil { endAt = t }                      // never wait forever
            if let end = endAt, t >= end {
                once("end") {
                    card = ("Ledgelings", ["Free and open source · macOS and Windows", "github.com/sworgkh/ledgelings"], end, end + 6)
                }
                if t >= end + 6 { finished = true }
            }
        }
    }

    /// The layers around the colony: captions along the bottom, a card for the title and the end.
    @MainActor final class Stage {
        /// Pixel-sized: what the renderer draws. `root` sits inside it, scaled up.
        let canvas = CALayer()
        let root = CALayer()
        let wallpaper = CAGradientLayer()
        let captionPlate = CALayer()
        let captionText = CATextLayer()
        let card = CALayer()
        let cardTitle = CATextLayer()
        let cardLines = CATextLayer()

        init() {
            canvas.bounds = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            canvas.anchorPoint = .zero; canvas.position = .zero
            canvas.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
            root.bounds = CGRect(origin: .zero, size: size); root.anchorPoint = .zero; root.position = .zero
            canvas.addSublayer(root)
            // A quiet desktop: a soft dark-blue gradient, nothing else.
            wallpaper.frame = root.bounds
            wallpaper.colors = [CGColor(srgbRed: 0.16, green: 0.24, blue: 0.45, alpha: 1), CGColor(srgbRed: 0.07, green: 0.09, blue: 0.20, alpha: 1)]
            wallpaper.startPoint = CGPoint(x: 0, y: 1); wallpaper.endPoint = CGPoint(x: 0.3, y: 0)
            root.addSublayer(wallpaper)
            captionPlate.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
            captionPlate.cornerRadius = 10
            captionPlate.opacity = 0
            captionText.contentsScale = scale
            captionText.alignmentMode = .center
            captionText.isWrapped = true
            captionText.truncationMode = .none
            captionPlate.addSublayer(captionText)

            card.bounds = root.bounds; card.anchorPoint = .zero; card.position = .zero
            card.backgroundColor = CGColor(srgbRed: 0.09, green: 0.08, blue: 0.14, alpha: 1)
            card.opacity = 0
            for layer in [cardTitle, cardLines] {
                layer.contentsScale = scale; layer.alignmentMode = .center; layer.isWrapped = true
                card.addSublayer(layer)
            }
            cardTitle.string = NSAttributedString(string: "Ledgelings", attributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: NSColor.white])
            cardTitle.frame = CGRect(x: 0, y: size.height / 2 - 10, width: size.width, height: 90)
            cardLines.frame = CGRect(x: 80, y: size.height / 2 - 120, width: size.width - 160, height: 100)
        }

        func show(at t: Double, director: Director) {
            CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
            if let cap = director.captions.last(where: { $0.from <= t && t < $0.to }) {
                let fade = min(1, min(t - cap.from, cap.to - t) / 0.35)
                let text = NSAttributedString(string: cap.text, attributes: [
                    .font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white])
                if (captionText.string as? NSAttributedString)?.string != cap.text {
                    // Measure the way CATextLayer lays out: Core Text, wrapped at the same width.
                    let setter = CTFramesetterCreateWithAttributedString(text)
                    let measured = CTFramesetterSuggestFrameSizeWithConstraints(
                        setter, CFRange(location: 0, length: text.length), nil, CGSize(width: size.width - 200, height: 400), nil)
                    let w = ceil(measured.width) + 48, h = ceil(measured.height) + 24
                    captionPlate.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                    captionPlate.position = CGPoint(x: size.width / 2, y: size.height * 0.33)
                    captionText.frame = CGRect(x: 24, y: 12, width: w - 48, height: h - 24)
                    captionText.string = text
                    captionText.displayIfNeeded()          // a reused text layer otherwise shows the old string a while
                }
                captionPlate.opacity = Float(max(0, fade))
            } else {
                captionPlate.opacity = 0
            }
            if let c = director.card, c.from <= t, t < c.to {
                let fade = min(1, min(t - c.from, c.to - t) / 0.6)
                card.opacity = Float(max(0, fade))
                let lines = c.lines.joined(separator: "\n")
                if (cardLines.string as? NSAttributedString)?.string != lines {
                    cardLines.string = NSAttributedString(string: lines, attributes: [
                        .font: NSFont.systemFont(ofSize: 26, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.85)])
                    cardLines.displayIfNeeded()
                }
            } else {
                card.opacity = 0
            }
        }

    }

    /// H.264 .mp4, one frame at a time. Core Animation's own offscreen renderer
    /// (CARenderer, on Metal) draws the layer tree exactly as a window would: cropped
    /// sprite frames, nearest-neighbour scaling, transforms, text.
    @MainActor final class Recorder {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let renderer: CARenderer
        private let texture: MTLTexture
        private let queue: MTLCommandQueue
        private let readback: MTLBuffer
        private let size: CGSize
        private let fps: Int
        private let bytesPerRow: Int

        init(url: URL, layer: CALayer, size: CGSize, fps: Int) throws {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.size = size; self.fps = fps
            let w = Int(size.width), h = Int(size.height)
            bytesPerRow = w * 4
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                throw NSError(domain: "Promo", code: 8, userInfo: [NSLocalizedDescriptionKey: "no Metal device"])
            }
            let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            description.usage = [.renderTarget, .shaderRead]
            description.storageMode = .private
            guard let texture = device.makeTexture(descriptor: description),
                  let readback = device.makeBuffer(length: bytesPerRow * h, options: .storageModeShared) else {
                throw NSError(domain: "Promo", code: 9, userInfo: [NSLocalizedDescriptionKey: "could not make the render target"])
            }
            self.texture = texture; self.queue = queue; self.readback = readback
            renderer = CARenderer(mtlTexture: texture, options: [kCARendererColorSpace as String: CGColorSpace(name: CGColorSpace.sRGB)!])
            renderer.layer = layer
            renderer.bounds = CGRect(x: 0, y: 0, width: w, height: h)

            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w, AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            ])
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Promo", code: 2) }
            writer.startSession(atSourceTime: .zero)
        }

        func append(frame: Int, at seconds: Double) async throws {
            // Draw the tree into the texture, then pull the pixels back.
            renderer.beginFrame(atTime: seconds, timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
            guard let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else {
                throw NSError(domain: "Promo", code: 10)
            }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: Int(size.width), height: Int(size.height), depth: 1),
                      to: readback, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * Int(size.height))
            blit.endEncoding()
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                commands.addCompletedHandler { _ in done.resume() }
                commands.commit()
            }

            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "Promo", code: 3) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw NSError(domain: "Promo", code: 4) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let h = Int(size.height), stride = CVPixelBufferGetBytesPerRow(buffer)
            let base = CVPixelBufferGetBaseAddress(buffer)!
            let src = readback.contents()
            // Core Animation draws y-up; video rows run top-down.
            for row in 0..<h {
                memcpy(base + row * stride, src + (h - 1 - row) * bytesPerRow, bytesPerRow)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))) else {
                throw writer.error ?? NSError(domain: "Promo", code: 6)
            }
        }

        func finish() async throws {
            input.markAsFinished()
            await writer.finishWriting()
            if let error = writer.error { throw error }
        }
    }
}
