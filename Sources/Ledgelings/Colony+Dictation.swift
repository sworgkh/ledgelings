import AppKit
import LedgelingsCore

/// The creature who holds the microphone (§7.13). When dictation starts it leaps
/// from its edge to the middle of the screen and stands there holding a pixel
/// microphone whose bars follow the voice, the clock in its bubble. Stopped, it
/// thinks (three dots on the microphone) while the model writes the words down,
/// then says "Copied: …the first words…" and hops back to where it was. Trouble
/// (no key, no microphone, no network) it says in plain words, and goes home.
extension Colony {
    struct DictationHelp {
        enum Stage: Equatable {
            case going(ClipHelper.Leap)
            /// In the middle, listening.
            case listening
            /// The model is writing it down.
            case thinking(since: Double)
            /// Saying how it went, until then.
            case telling(until: Double)
            case returning(ClipHelper.Leap)
        }
        var index: Int
        var stage: Stage
        /// Where it stands in the middle of the screen, and where it was on its edge.
        var perch: CGPoint
        var home: CGPoint
        /// The meter, 0 to 1, falling slowly after each word; and the seconds heard.
        var level = 0.0
        var seconds = 0.0
        /// A line to say once it has landed, when it was given one on the way.
        var waiting: (text: String, voiced: Bool)?
    }

    /// Who is holding the microphone, for the film and the demo.
    var dictationHelper: Int? { dictationHelp?.index }

    /// Sends a creature to the middle of the screen under the pointer. False when
    /// nobody can come: all busy, hiding, or none at all.
    @discardableResult
    func dictationCome(to spot: CGPoint? = nil) -> Bool {
        if let help = dictationHelp {
            // Already there or on its way: it stays and listens again.
            if case .returning = help.stage { dictationLand(help.index) } else {
                dictationHelp?.stage = { if case .going = help.stage { return help.stage } else { return .listening } }()
                dictationHelp?.waiting = nil
                bubbles.removeValue(forKey: help.index)
                return true
            }
        }
        guard !hideout.isActive else { return false }
        let free = creatures.indices.filter { i in
            let c = creatures[i]
            return !busy.contains(i) && held?.index != i && grab?.index != i && !isMoving(i) && !c.isPlaying && !c.isChatting
                && !c.isHeld && bubbles[i] == nil && clipHelp?.index != i && shotCarry?.index != i
        }
        let wanted = settings.dictationHelper
        guard let i = free.first(where: { !wanted.isEmpty && character(forCreature: $0).name == wanted }) ?? free.randomElement(using: &rng),
              creatures[i].takeOff(waking: true) else { return false }
        bedTrips.removeValue(forKey: i)
        gardeners.remove(i)
        busy.insert(i)
        let from = creatures[i].position
        let middle = spot ?? Self.middleOfScreen(under: pointerLocation())
        let leap = ClipHelper.Leap(from: from, to: middle, flight: ClipHelper.flight(distance: hypot(middle.x - from.x, middle.y - from.y), speed: 1))
        dictationHelp = DictationHelp(index: i, stage: .going(leap), perch: middle, home: from)
        trace?(String(format: "dictate %@ leaps to (%.0f, %.0f) in %.2f s", character(forCreature: i).name, middle.x, middle.y, leap.duration))
        return true
    }

    /// The middle of the screen the pointer is on, a little below its centre so the bubble has room.
    static func middleOfScreen(under point: CGPoint) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return point }
        return CGPoint(x: frame.midX, y: frame.midY - 40)
    }

    /// What the microphone hears now: the meter and the clock.
    func dictationHear(level: Double, seconds: Double, dt: Double) {
        guard var help = dictationHelp else { return }
        help.level = Dictation.meter(previous: help.level, heard: level, dt: dt)
        help.seconds = seconds
        dictationHelp = help
    }

    /// Stopped: it thinks while the model writes.
    func dictationThink() {
        guard let help = dictationHelp else { return }
        dictationHelp?.level = 0
        if case .going = help.stage { return }
        dictationHelp?.stage = .thinking(since: elapsed)
        trace?("dictate \(character(forCreature: help.index).name) thinks")
    }

    /// It says `text` and then goes home; `voiced`: out loud too, with voice on
    /// (trouble is; a transcript is not read back). On its way, it says it on landing.
    func dictationTell(_ text: String, voiced: Bool) {
        guard let help = dictationHelp else { return }
        if case .going = help.stage { dictationHelp?.waiting = (text, voiced); return }
        let i = help.index
        // Long enough to read, short enough not to keep it standing there.
        let shown = min(Banter.showTime(text, base: settings.bubbleSeconds), voiced ? 7 : 3.5)
        if voiced {
            say(text, from: i, builtIn: true)
        } else {
            bubbleSerial += 1
            bubbles[i] = Bubble(text: text, until: elapsed + shown, serial: bubbleSerial)
        }
        dictationHelp?.stage = .telling(until: elapsed + shown)
        trace?("dictate \(character(forCreature: i).name) says: \(text)")
    }

    /// Let go with nothing said (Esc): straight home.
    func dictationGoHome() {
        guard let help = dictationHelp else { return }
        bubbles.removeValue(forKey: help.index)
        dictationReturn(help)
    }

    private func dictationReturn(_ help: DictationHelp) {
        let i = help.index
        let from = creatures[i].position
        let leap = ClipHelper.Leap(from: from, to: help.home, flight: ClipHelper.flight(distance: hypot(help.home.x - from.x, help.home.y - from.y), speed: 1))
        dictationHelp?.stage = .returning(leap)
        dictationHelp?.waiting = nil
        trace?("dictate \(character(forCreature: i).name) hops home")
    }

    func updateDictationHelp(dt: Double) {
        guard var help = dictationHelp else { return }
        let i = help.index
        guard creatures.indices.contains(i), creatures[i].isPlaying else { dictationHelp = nil; busy.remove(i); return }
        switch help.stage {
        case .going(var leap):
            leap.update(dt: dt)
            creatures[i].carry(to: leap.position, rotation: leap.rotation, pose: leap.pose)
            guard leap.isDone else { help.stage = .going(leap); break }
            help.stage = .listening
            dictationHelp = help
            trace?("dictate \(character(forCreature: i).name) holds the microphone")
            if let waiting = help.waiting {
                dictationHelp?.waiting = nil
                dictationTell(waiting.text, voiced: waiting.voiced)
            }
            return
        case .listening:
            creatures[i].carry(to: help.perch, rotation: 0, pose: "idle")
            // The clock, in a bubble that is never said out loud.
            let clock = "● " + Dictation.clock(help.seconds)
            if bubbles[i]?.text != clock {
                bubbleSerial += 1
                bubbles[i] = Bubble(text: clock, until: elapsed + 2, serial: bubbleSerial)
            } else {
                bubbles[i]?.until = elapsed + 2
            }
        case .thinking:
            creatures[i].carry(to: help.perch, rotation: 0, pose: "idle")
            let writing = Dictation.thinkingBubble
            if bubbles[i]?.text != writing {
                bubbleSerial += 1
                bubbles[i] = Bubble(text: writing, until: elapsed + 120, serial: bubbleSerial)
            }
        case .telling(let until):
            creatures[i].carry(to: help.perch, rotation: 0, pose: "idle")
            if elapsed >= until, !voicedLines.contains(bubbles[i]?.serial ?? -1) {
                bubbles.removeValue(forKey: i)
                dictationHelp = help
                dictationReturn(help)
                return
            }
        case .returning(var leap):
            leap.update(dt: dt)
            creatures[i].carry(to: leap.position, rotation: leap.rotation, pose: leap.pose)
            if leap.isDone {
                dictationLand(i)
                trace?(String(format: "dictate %@ is back at (%.0f, %.0f)", character(forCreature: i).name,
                              creatures[i].position.x, creatures[i].position.y))
                return
            }
            help.stage = .returning(leap)
        }
        dictationHelp = help
    }

    /// Done, or cut short: onto the nearest edge, free again.
    func dictationLand(_ i: Int) {
        dictationHelp = nil
        busy.remove(i)
        guard creatures.indices.contains(i) else { return }
        bubbles.removeValue(forKey: i)
        creatures[i].touchDown()
    }

    /// The microphone creature `i` holds out, its bars or its thinking dots, while it helps.
    func dictationMicrophone(for i: Int) -> CGImage? {
        guard let help = dictationHelp, help.index == i else { return nil }
        var grid: [[Dictation.Ink]]
        switch help.stage {
        case .thinking(let since): grid = Dictation.microphone(bars: 0, thinking: true, tick: Int((elapsed - since) * 4))
        case .listening: grid = Dictation.microphone(bars: Dictation.bars(level: help.level))
        default: grid = Dictation.microphone(bars: 0)
        }
        // Held on its left, the picture turns round: the microphone by the body, the bars outside.
        if creatures[i].isMirrored { grid = grid.map { $0.reversed() } }
        let key = "mic " + grid.map { $0.map { String($0.rawValue) }.joined() }.joined()
        if let made = pixelTexts[key] { return made }
        let made = Self.picture(grid)
        pixelTexts[key] = made
        return made
    }

    /// The colours of the microphone: a dark grey body, the game's ink for the
    /// outline and grille, green bars that light and dim ones that wait.
    static let microphoneInks: [Dictation.Ink: CGColor] = [
        .outline: ScreenOverlay.ink,
        .body: CGColor(srgbRed: 132 / 255, green: 138 / 255, blue: 152 / 255, alpha: 1),
        .light: CGColor(srgbRed: 186 / 255, green: 191 / 255, blue: 202 / 255, alpha: 1),
        .shade: CGColor(srgbRed: 88 / 255, green: 92 / 255, blue: 106 / 255, alpha: 1),
        .grille: ScreenOverlay.ink,
        .lit: CGColor(srgbRed: 92 / 255, green: 206 / 255, blue: 96 / 255, alpha: 1),
        .unlit: CGColor(srgbRed: 150 / 255, green: 146 / 255, blue: 170 / 255, alpha: 0.55),
    ]

    /// A grid of inks as a picture, one pixel each: the overlay scales it up crisp.
    static func picture(_ grid: [[Dictation.Ink]]) -> CGImage? {
        let h = grid.count, w = grid.first?.count ?? 0
        guard w > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (row, line) in grid.enumerated() {
            for (column, ink) in line.enumerated() {
                guard let colour = microphoneInks[ink] else { continue }
                context.setFillColor(colour)
                // Rows run top to bottom; the context counts from the bottom.
                context.fill(CGRect(x: column, y: h - 1 - row, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }
}
