import AppKit
import QuartzCore
import SwiftUI
import LedgelingsCore

/// The chat window written to an .mp4 frame by frame, offscreen: a message to
/// one creature (it thinks, turns to the window, answers in a bubble), then one
/// to Everyone (three answer in turn, each after the one before). The talks run
/// through the real colony first, with stand-in answers (no model, no key), so
/// the memory and the Chats log are the real ones; each step's still is written
/// beside the film (`-open.png`, `-thinking.png`, `-answer.png`, `-everyone.png`,
/// `-everyone-done.png`, `-no-model.png`).
///
///     Ledgelings --chat-film build/chat.mp4
@MainActor
enum ChatFilm {
    static let one = "Good morning! I'm off to the dentist at ten, wish me luck."
    static let all = "Who wants to hear a joke about the cursor?"

    static func run(output: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-chat-film-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let name = "ledgelings-chat-film"
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
        let history = ChatHistory(directory: scratch.appendingPathComponent("chats"))
        let colony = try Colony(settings: settings, history: history,
                                library: SpriteLibrary(directory: scratch.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: scratch),
                                stage: Display(frame: CGRect(origin: .zero, size: Promo.size), scale: Promo.scale))
        colony.userIdleSeconds = { 0 }
        colony.ownerChats = OwnerChatBook(directory: scratch)
        var t = 0.0
        func log(_ line: String) { print(String(format: "film %5.2f  %@", t, line)) }

        // The talks, through the colony itself: who answers, in what order, what they remember.
        let targets = colony.chatTargets()
        guard let first = targets.first?.name else { throw CocoaError(.validationMissingMandatoryProperty) }
        colony.trace = { line in if line.hasPrefix("chat") { log(line) } }
        settings.chatBubbles = false; settings.chatSpeak = false
        var oneAnswer = "", allAnswers: [(String, String)] = []
        await colony.answerOwner(one, to: first, window: CGPoint(x: Promo.size.width / 2, y: Promo.size.height / 2), fake: ChatDemo.fake) { e in
            if case .answer(_, let text, _) = e { oneAnswer = text }
        }
        await colony.answerOwner(all, to: nil, window: CGPoint(x: Promo.size.width / 2, y: Promo.size.height / 2), fake: ChatDemo.fake) { e in
            if case .answer(let who, let text, _) = e { allAnswers.append((who, text)) }
        }
        settings.chatBubbles = true
        for line in colony.ownerChatDump() { log(line) }
        let logged = history.exchanges(on: ChatLog.day(of: Date()))
        log("chats tab: \(logged.count) talks, \(logged.map { $0.lines.count }.reduce(0, +)) lines")
        guard !oneAnswer.isEmpty, allAnswers.count == min(settings.chatEveryone, targets.count) else {
            throw CocoaError(.validationMultipleErrors, userInfo: [NSLocalizedDescriptionKey: "the chat went wrong: \(allAnswers.count) answered everyone"])
        }

        // The window's stills, drawn by its own view.
        let model = ChatModel()
        let size = ChatController.size
        model.paper = CGRect(origin: .zero, size: size)
        model.targets = targets.enumerated().map { ChatModel.Target(name: $1.name, portrait: $1.portrait, number: $0 + 1) }
        func portrait(_ who: String) -> CGImage? { targets.first { $0.name == who }?.portrait }
        func still(_ step: String, _ set: (ChatModel) -> Void) async throws -> CGImage {
            set(model)
            let image = try await TranslateFilm.picture(ChatView(model: model), size: size)
            try write(image, to: output, step)
            return image
        }
        let open = try await still("open") { m in m.chosen = first }
        let thinking = try await still("thinking") { m in
            m.lines = [.init(speaker: "", text: one, to: first)]; m.thinking = first
        }
        let answered = try await still("answer") { m in
            m.thinking = nil; m.lines.append(.init(speaker: first, text: oneAnswer, portrait: portrait(first)))
        }
        var shown: [CGImage] = []
        for k in 0..<allAnswers.count {
            let image = try await still(k == 0 ? "everyone" : k == allAnswers.count - 1 ? "everyone-done" : "everyone-\(k + 1)") { m in
                m.chosen = nil
                if k == 0 { m.lines.append(.init(speaker: "", text: all, to: nil)) }
                m.lines.append(.init(speaker: allAnswers[k].0, text: allAnswers[k].1, portrait: portrait(allAnswers[k].0)))
                m.thinking = k + 1 < allAnswers.count ? allAnswers[k + 1].0 : nil
            }
            shown.append(image)
        }
        _ = try await still("no-model") { m in m.hasModel = false; m.thinking = nil; m.lines = []; m.chosen = first }

        // The film: the window over the stage, the creatures answering on their edges.
        let stage = Promo.Stage()
        let base: CGFloat = 0.6
        let paperOnStage = CGRect(x: (Promo.size.width - size.width * base) / 2, y: (Promo.size.height - size.height * base) / 2 + 20,
                                  width: size.width * base, height: size.height * base)
        let paper = CALayer()
        paper.contents = open
        paper.magnificationFilter = .nearest
        paper.bounds = CGRect(origin: .zero, size: size)
        paper.anchorPoint = CGPoint(x: 0, y: 1)
        paper.position = CGPoint(x: paperOnStage.minX, y: paperOnStage.maxY)
        paper.transform = CATransform3DMakeScale(base, base, 1)
        paper.opacity = 0
        stage.root.addSublayer(paper)
        stage.root.addSublayer(colony.overlays[0].root)
        let centre = CGPoint(x: paperOnStage.midX, y: paperOnStage.midY)
        func index(_ who: String) -> Int { colony.creatureIndex(named: who) ?? 0 }

        // What happens from when: the sheet's picture, and a creature thinking or answering.
        enum Beat { case think(String), say(String, String), done }
        var script: [(at: Double, image: CGImage?, beat: Beat?, line: String)] = [
            (0.5, open, nil, "⌃⌥C: the chat opens, to \(first)"),
            (2.0, thinking, .think(first), "⏎: \"\(one)\""),
            (4.0, answered, .say(first, oneAnswer), "\(first) answers"),
            (9.0, nil, .done, ""),
        ]
        var at = 10.0
        for (k, (who, text)) in allAnswers.enumerated() {
            script.append((at, k == 0 ? answered : shown[k - 1], .think(who), k == 0 ? "⌘0 and ⏎: \"\(all)\"" : "\(who) heard the others"))
            script.append((at + 1.6, shown[k], .say(who, text), "\(who) answers"))
            at += 5.5
        }
        script.append((at, nil, .done, "everyone has answered"))
        let end = at + 2

        let recorder = try Promo.Recorder(url: output, layer: stage.canvas,
                                          size: CGSize(width: Promo.size.width * Promo.scale, height: Promo.size.height * Promo.scale), fps: Promo.fps)
        let away = CGPoint(x: -500, y: -500), dt = 1 / Double(Promo.fps)
        var frame = 0, next = 0
        while t < end + 1.5 {
            t = Double(frame) * dt
            CATransaction.begin(); CATransaction.setDisableActions(true)
            colony.advance(dt: dt, cursor: away, shift: false)
            let unfold = min(max((t - 0.3) / ClipHelper.unfoldSeconds, 0), 1), eased = 1 - (1 - unfold) * (1 - unfold)
            let fold = t > end ? min((t - end) / ClipHelper.collapseSeconds, 1) : 0
            paper.opacity = Float(eased * (1 - fold))
            let k = base * (0.06 + 0.94 * eased) * (1 - 0.98 * fold * fold)
            paper.transform = CATransform3DMakeScale(k, k, 1)
            while next < script.count, script[next].at <= t {
                let step = script[next]
                if let image = step.image { paper.contents = image }
                switch step.beat {
                case .think(let who): colony.startChatTurn(index(who), facing: centre)
                case .say(let who, let text):
                    colony.endChatThinking(index(who))
                    colony.say(text, from: index(who), voiced: false)
                case .done: colony.endChatTurns(); colony.bubbles.removeAll()
                case nil: break
                }
                if !step.line.isEmpty { log(step.line) }
                next += 1
            }
            CATransaction.commit()
            try await recorder.append(frame: frame, at: t)
            frame += 1
        }
        try await recorder.finish()
        print("chat film: \(frame) frames → \(output.path)")
    }

    /// `out.mp4` → `out-<step>.png`.
    private static func write(_ image: CGImage, to film: URL, _ step: String) throws {
        let png = film.deletingLastPathComponent().appendingPathComponent(film.deletingPathExtension().lastPathComponent + "-\(step).png")
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: png)
    }
}
