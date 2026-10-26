import AVFoundation
import AppKit
import QuartzCore
import LedgelingsCore

/// Dictation's creature written to an .mp4 frame by frame, offscreen: the leap to
/// the middle with the microphone, the bars following a real voice (a line the
/// Mac says into a file, measured as the microphone would be), the clock, the
/// thinking dots, "Copied: …" and the hop back; then a second round where there
/// is no key and it says so. Nothing is recorded and no model is called. A still
/// of each moment is written beside the film (`…-listening.png`, `…-thinking.png`, `…-copied.png`).
///
///     Ledgelings --dictate-film build/dictation.mp4
@MainActor
enum DictationFilm {
    static let line = "Remind me to water the ferns on Friday, and to call Mortimer about the cracked monitor."

    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-dictate-film-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-dictate-film"
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
        settings.talkEnabled = false
        settings.dayMinutes = 30; settings.nightMinutes = 30
        settings.dictationHelper = "Blocky"
        let colony = try Colony(settings: settings, history: ChatHistory(directory: scratch.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.userIdleSeconds = { 0 }
        var t = 0.0
        func log(_ line: String) { print(String(format: "film %5.2f  %@", t, line)) }
        colony.trace = { line in if line.hasPrefix("dictate") { log(line) } }

        // The voice: a line said into a file, its loudness every frame, as the meter would hear it.
        let voice = try loudness(of: line, in: scratch, fps: Promo.fps)
        log(String(format: "voice: %.1f s of \"%@\"", Double(voice.count) / Double(Promo.fps), line))

        let stage = Promo.Stage()
        stage.root.addSublayer(colony.overlays[0].root)
        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500), dt = 1 / Double(Promo.fps)
        let middle = CGPoint(x: Promo.size.width / 2, y: Promo.size.height / 2 - 40)
        enum Phase { case before, coming, listening(since: Double, frame: Int), thinking(until: Double), telling, before2, coming2, after }
        var phase = Phase.before, frame = 0, done = false
        var stills: [String: CGImage] = [:]
        func still(_ what: String) {
            guard stills[what] == nil, let image = recorder.lastFrame() else { return }
            stills[what] = image
            let stem = output.deletingPathExtension().lastPathComponent
            let url = output.deletingLastPathComponent().appendingPathComponent("\(stem)-\(what).png")
            try? ShotRenderer.png(image)?.write(to: url)
            log("still \(url.lastPathComponent)")
        }
        while !done && frame < Promo.fps * 40 {
            t = Double(frame) * dt
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: dt, cursor: away, shift: false)
            var snap: String?
            switch phase {
            case .before where t >= 1:
                log("shortcut ⌃⌥D: listening")
                colony.dictationCome(to: middle)
                phase = .coming
            case .coming:
                if case .listening? = colony.dictationHelp?.stage { phase = .listening(since: t, frame: 0) }
            case .listening(let since, let k):
                // A breath before the first word, and one after the last.
                let heard = k >= 8 && k - 8 < voice.count ? voice[k - 8] : 0
                colony.dictationHear(level: heard, seconds: t - since, dt: dt)
                if k == 8 + voice.count / 3 { snap = "listening" }
                if k >= voice.count + 20 {
                    log(String(format: "⌃⌥D again: stop after %.1f s, sent", t - since))
                    colony.dictationThink()
                    phase = .thinking(until: t + 1.6)
                } else {
                    phase = .listening(since: since, frame: k + 1)
                }
            case .thinking(let until):
                if t >= until - 0.6 { snap = "thinking" }
                if t >= until {
                    colony.dictationTell(Dictation.copiedBubble(line), voiced: false)
                    phase = .telling
                }
            case .telling:
                if case .telling(let until)? = colony.dictationHelp?.stage, t >= until - 1 { snap = "copied" }
                if colony.dictationHelp == nil { phase = .before2 }
            case .before2:
                log("shortcut ⌃⌥D with no OpenRouter key")
                colony.dictationCome(to: middle)
                colony.dictationTell(Dictation.Trouble.noKey.line, voiced: false)
                phase = .coming2
            case .coming2:
                if colony.dictationHelp == nil { phase = .after; done = true }
            default: break
            }
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            if let snap { still(snap) }
            frame += 1
        }
        try await recorder.finish()
        print("dictate film: \(frame) frames → \(output.path)")
    }

    /// The Mac says `text` into a file; its loudness, 0 to 1, for each frame of the film.
    static func loudness(of text: String, in folder: URL, fps: Int) throws -> [Double] {
        let file = folder.appendingPathComponent("line.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", file.path, text]
        try say.run()
        say.waitUntilExit()
        let audio = try AVAudioFile(forReading: file)
        let format = audio.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.length)) else { return [] }
        try audio.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let all = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let step = Int(format.sampleRate) / fps
        return stride(from: 0, to: all.count, by: step).map { start in
            Dictation.level(rms: Dictation.rms(all[start..<min(start + step, all.count)]))
        }
    }
}
