import AppKit
import LedgelingsCore

/// The creature who brings the clipboard picker (§7.11.1). On the shortcut it
/// leaps from its edge to the paper's top-left corner and holds it while the
/// picker is open; the picker unfolds out of it once it lands. When the picker
/// goes, it leaps back to where it was and walks on.
extension Colony: ClipHelping {
    struct ClipHelp {
        enum Stage {
            case going(ClipHelper.Leap)
            /// At the corner, with the picker open.
            case holding(CGPoint)
            case returning(ClipHelper.Leap)
        }
        var index: Int
        var stage: Stage
        /// Where it was on its edge before it came.
        var home: CGPoint
        /// How it holds the sheet: calm, thinking while a model answers, puzzled at trouble.
        var mood = ClipHelperMood.calm
        var moodSince = 0.0
    }

    /// Where it holds the paper, while it is on its way there or holding it.
    var clipHelperPerch: CGPoint? {
        switch clipHelp?.stage {
        case .going(let leap): leap.to
        case .holding(let perch): perch
        default: nil
        }
    }

    /// Sends a creature to hold `paper` (global points). Seconds until it lands
    /// there, or nil when nobody can come: all busy, hiding, or nobody at all.
    func clipHelperCome(paper: CGRect, centre: CGPoint) -> Double? {
        clipHelperCome(paper: paper, centre: centre, wanted: settings.clipHelper)
    }

    /// The same, `wanted` coming if free (empty: whoever is nearest the middle).
    func clipHelperCome(paper: CGRect, centre: CGPoint, wanted: String) -> Double? {
        if let help = clipHelp { clipHelperLand(help.index) }
        guard !hideout.isActive else { return nil }
        let candidates = creatures.indices.map { i in
            let c = creatures[i]
            return ClipHelper.Candidate(name: character(forCreature: i).name, position: c.position, asleep: c.looksAsleep,
                                        free: !busy.contains(i) && held?.index != i && grab?.index != i && !isMoving(i)
                                            && !c.isPlaying && !c.isChatting && !c.isHeld && bubbles[i] == nil)
        }
        guard let i = ClipHelper.choose(candidates, centre: centre, wanted: wanted),
              creatures[i].takeOff(waking: true) else { return nil }
        bedTrips.removeValue(forKey: i)
        gardeners.remove(i)
        busy.insert(i)
        let from = creatures[i].position
        let perch = ClipHelper.perch(paper: paper, half: atlas.bodyHalfSize * CGFloat(sizes[i]))
        let leap = ClipHelper.Leap(from: from, to: perch,
                                   flight: ClipHelper.flight(distance: hypot(perch.x - from.x, perch.y - from.y), speed: settings.clipAnimationSpeed))
        clipHelp = ClipHelp(index: i, stage: .going(leap), home: from)
        trace?(String(format: "clip %@ leaps to (%.0f, %.0f) in %.2f s", character(forCreature: i).name, perch.x, perch.y, leap.duration))
        return leap.duration
    }

    /// The picker is gone: back to its edge, `after` seconds from now (the collapse first).
    func clipHelperGoHome(after: Double) {
        guard let help = clipHelp else { return }
        let i = help.index
        Task { @MainActor [weak self] in
            if after > 0 { try? await Task.sleep(for: .seconds(after)) }
            guard let self, let now = self.clipHelp, now.index == i, self.creatures.indices.contains(i) else { return }
            if case .returning = now.stage { return }
            let from = self.creatures[i].position
            let leap = ClipHelper.Leap(from: from, to: now.home,
                                       flight: ClipHelper.flight(distance: hypot(now.home.x - from.x, now.home.y - from.y),
                                                                 speed: self.settings.clipAnimationSpeed))
            self.clipHelp?.stage = .returning(leap)
            self.trace?("clip \(self.character(forCreature: i).name) leaps home")
        }
    }

    /// Thinking dots over it while a model answers; a "?" and a little hop at trouble.
    func clipHelperMood(_ mood: ClipHelperMood) {
        guard let help = clipHelp, help.mood != mood else { return }
        clipHelp?.mood = mood
        clipHelp?.moodSince = elapsed
        if mood == .calm { bubbles.removeValue(forKey: help.index) }
        trace?("clip \(character(forCreature: help.index).name) is \(mood)")
    }

    func updateClipHelp(dt: Double) {
        guard var help = clipHelp else { return }
        let i = help.index
        guard creatures.indices.contains(i), creatures[i].isPlaying else { clipHelp = nil; busy.remove(i); return }
        switch help.stage {
        case .going(var leap):
            leap.update(dt: dt)
            creatures[i].carry(to: leap.position, rotation: leap.rotation, pose: leap.pose)
            if leap.isDone {
                help.stage = .holding(leap.to)
                clipHelp = help
                trace?("clip \(character(forCreature: i).name) holds the corner")
                if settings.clipHelperTalks, settings.talkEnabled {
                    _ = say(ClipHelper.line(by: character(forCreature: i).name, using: &rng), from: i, builtIn: true)
                }
                return
            }
            help.stage = .going(leap)
        case .holding(let perch):
            let since = elapsed - help.moodSince
            switch help.mood {
            case .calm:
                creatures[i].carry(to: perch, rotation: 0, pose: "idle")
            case .thinking:
                creatures[i].carry(to: perch, rotation: 0, pose: "idle")
                // One, two, three dots, round and round: never said, never voiced.
                let dots = String(repeating: "•", count: Int(since * 3) % 3 + 1)
                if bubbles[i]?.text != dots {
                    bubbleSerial += 1
                    bubbles[i] = Bubble(text: dots, until: elapsed + 1, serial: bubbleSerial)
                }
            case .puzzled:
                // A shrug: up a few points and down again, a "?" over it for two seconds.
                let lift = since < 0.3 ? 6 * sin(.pi * since / 0.3) : 0
                creatures[i].carry(to: CGPoint(x: perch.x, y: perch.y + lift), rotation: 0, pose: since < 0.3 ? "jump" : "idle")
                if since < 2, bubbles[i]?.text != "?" {
                    bubbleSerial += 1
                    bubbles[i] = Bubble(text: "?", until: elapsed + 2 - since, serial: bubbleSerial)
                }
            }
        case .returning(var leap):
            leap.update(dt: dt)
            creatures[i].carry(to: leap.position, rotation: leap.rotation, pose: leap.pose)
            if leap.isDone {
                clipHelperLand(i)
                trace?(String(format: "clip %@ is back at (%.0f, %.0f)", character(forCreature: i).name,
                              creatures[i].position.x, creatures[i].position.y))
                return
            }
            help.stage = .returning(leap)
        }
        clipHelp = help
    }

    /// Done helping, or cut short: onto the nearest edge, free again.
    func clipHelperLand(_ i: Int) {
        clipHelp = nil
        busy.remove(i)
        guard creatures.indices.contains(i) else { return }
        bubbles.removeValue(forKey: i)
        creatures[i].touchDown()
    }
}
