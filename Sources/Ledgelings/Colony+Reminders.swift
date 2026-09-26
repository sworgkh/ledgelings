import AppKit
import LedgelingsCore

/// Reminders: when one comes due, a creature stops, folds it into a paper
/// plane and throws it at the user. The plane swirls across the sky to the
/// middle of the screen, growing as it comes, turns head-on and rushes at you,
/// then unfolds into a letter: your reminder, a note from the thrower in its
/// own voice, its signature. A click folds the letter back into a plane that
/// flies off; so does time, but only while you are at the computer.
extension Colony {
    struct Delivery {
        enum Phase: Equatable {
            /// Looking for someone free to throw it, since then.
            case finding(since: Double)
            /// The thrower has stopped and is winding up.
            case windup(until: Double)
            case flying
            /// Over the middle: turns head-on and comes at you, from where and how big it was.
            case arriving(since: Double, from: CGPoint, scale: CGFloat)
            /// Head-on in the middle, waiting for the model's note (a few seconds at most).
            case hovering(since: Double)
            case opening(since: Double)
            /// The letter is up; `shown` counts only the time the user was at the computer.
            case open(since: Double, shown: Double)
            case closing(since: Double)
            /// Folded again, flying off the screen.
            case leaving(since: Double)
        }

        var id: Int
        var reminder: Reminders.Reminder
        /// The creature throwing it; nil when nobody could, and it comes in from below.
        var thrower: Int?
        /// Who signs the letter.
        var writer: String
        var stamp: CGImage?
        var plane: PaperPlane
        /// The middle of the screen the user is on, and that screen.
        var target: CGPoint
        var screen: CGRect
        var startDistance: CGFloat = 1
        var baseScale: CGFloat
        var phase: Phase
        var note: String?
        /// The letter's top line, decided as it opens.
        var title = ""
        var writing = false
        var provider = AppSettings.Brain.script.title
        var model = ""
        var cost: Double?
        var tokens: Int?
        /// Where the plane is drawn outside the physics: arriving, hovering, opening.
        var shownAt: CGPoint = .zero
        var shownScale: CGFloat = 2
    }

    static let reminderWindup = 0.6
    static let reminderArrive = 0.6
    static let reminderOpen = 0.55
    static let reminderClose = 0.3
    /// Longest a thrower is looked for before anyone at all will do.
    static let reminderFindFor = 3.0
    /// Longest the plane hovers in the middle waiting for the model's note.
    static let reminderModelWait = 4.0
    /// Longest a reminder plane flies before it is pulled to the middle anyway.
    static let reminderFlightLimit = 7.0
    /// How close to the middle counts as there.
    static let reminderReach: CGFloat = 40
    /// The plane head-on is this many times its flying size when it opens.
    static let reminderZoom: CGFloat = 3.2
    /// The user counts as away after this long without touching anything.
    static let awayAfter = 30.0

    // MARK: Checking the clock

    func updateReminders(dt: Double) {
        if elapsed >= nextReminderCheck {
            nextReminderCheck = elapsed + 1
            if settings.remindersEnabled {
                let at = now(), queued = Set(deliveryQueue.map(\.id)) .union(delivery.map { [$0.reminder.id] } ?? [])
                for reminder in reminders.book.due(at: at) where !queued.contains(reminder.id) {
                    deliveryQueue.append(reminder)
                    reminders.markSent(reminder.id, at: at)
                }
            }
        }
        if delivery == nil, !deliveryQueue.isEmpty { startDelivery(deliveryQueue.removeFirst()) }
        stepDelivery(dt: dt)
    }

    /// Deliver `reminder` now, whatever its time: the Send Now button, the test letter, `--remind`.
    func deliverNow(_ reminder: Reminders.Reminder) {
        deliveryQueue.append(reminder)
        if delivery == nil { startDelivery(deliveryQueue.removeFirst()) }
    }

    /// The middle of the screen the cursor is on.
    private func targetScreen() -> CGRect {
        let cursor = stage == nil ? NSEvent.mouseLocation : .zero
        return (displays.first { $0.frame.contains(cursor) } ?? displays.first)?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func startDelivery(_ reminder: Reminders.Reminder) {
        let screen = targetScreen()
        let target = CGPoint(x: screen.midX, y: screen.midY)
        deliveryCount += 1
        delivery = Delivery(id: deliveryCount, reminder: reminder, thrower: nil, writer: "The Ledgelings",
                            plane: PaperPlane(from: -1, to: -1, start: target, inward: CGVector(dx: 0, dy: 1), target: target),
                            target: target, screen: screen, baseScale: 2.5, phase: .finding(since: elapsed))
    }

    /// Anyone free to throw; after a few seconds, anyone on screen at all; nil when nobody is.
    private func pickThrower(desperate: Bool) -> Int? {
        let free = creatures.indices.filter { canHandleMail($0) && !expectsPlane($0) }
        if let one = free.randomElement(using: &rng) { return one }
        guard desperate else { return nil }
        let there = creatures.indices.filter { !hideout.isInside($0) && !creatures[$0].isHeld }
        return there.first { !creatures[$0].looksAsleep } ?? there.randomElement(using: &rng)
    }

    /// The thrower stops, and the plane leaves its head in weather of its own.
    private func launch(_ mail: inout Delivery, from thrower: Int?) {
        mail.thrower = thrower
        var start = CGPoint(x: mail.target.x + .random(in: -200...200, using: &rng), y: mail.screen.minY - 16)
        var inward = CGVector(dx: 0, dy: 1)
        if let i = thrower {
            creatures[i].meet(facing: creatures[i].direction, for: Self.reminderWindup + 0.6)
            start = head(of: i)
            inward = creatures[i].loop.inward(ofSegment: creatures[i].segment)
            mail.writer = character(forCreature: i).name
            mail.baseScale = CGFloat(sizes[i])
            mail.stamp = frames[i].frame(animation: "idle", time: 0)
        }
        var plane = PaperPlane.thrown(from: thrower ?? -1, to: -1, start: start, inward: inward, target: mail.target, using: &rng)
        // A reminder is in a hurry: less swirl, quicker to the middle.
        plane.swirl *= 0.5
        plane.cruise = max(plane.cruise, 420)
        mail.plane = plane
        mail.startDistance = max(1, plane.distance(to: mail.target))
        mail.shownScale = mail.baseScale
        if settings.talkEnabled, thrower != nil { writeReminderNote(&mail) }
    }

    // MARK: Every frame

    private func stepDelivery(dt: Double) {
        guard var mail = delivery else { return }
        if let i = mail.thrower, !creatures.indices.contains(i) { mail.thrower = nil }
        switch mail.phase {
        case .finding(let since):
            let desperate = elapsed - since >= Self.reminderFindFor || hideout.isActive
            if let thrower = pickThrower(desperate: desperate) {
                launch(&mail, from: thrower)
                mail.phase = .windup(until: elapsed + Self.reminderWindup)
            } else if desperate {
                launch(&mail, from: nil)
                mail.phase = .flying
            }

        case .windup(let until):
            if elapsed >= until { mail.phase = .flying }

        case .flying:
            mail.plane.fly(dt: dt, toward: mail.target, time: elapsed)
            let progress = 1 - min(1, mail.plane.distance(to: mail.target) / mail.startDistance)
            // Coming closer to you: it grows as it nears the middle.
            mail.shownScale = mail.baseScale * (1 + 0.8 * progress * progress)
            if mail.plane.passed(within: Self.reminderReach, of: mail.target) || mail.plane.age > Self.reminderFlightLimit {
                mail.phase = .arriving(since: elapsed, from: mail.plane.position, scale: mail.shownScale)
            }

        case .arriving(let since, let from, let scale):
            mail.plane.fadeTrail(dt: dt)
            let t = min(1, (elapsed - since) / Self.reminderArrive)
            let ease = CGFloat(t * t)                     // speeding up as it comes at you
            mail.shownAt = CGPoint(x: from.x + (mail.target.x - from.x) * CGFloat(t), y: from.y + (mail.target.y - from.y) * CGFloat(t))
            mail.shownScale = scale + (mail.baseScale * Self.reminderZoom - scale) * ease
            if t >= 1 { if mail.writing { mail.phase = .hovering(since: elapsed) } else { beginOpening(&mail) } }

        case .hovering(let since):
            mail.plane.fadeTrail(dt: dt)
            mail.shownAt = CGPoint(x: mail.target.x, y: mail.target.y + 6 * sin((elapsed - since) * 4))
            if !mail.writing || elapsed - since > Self.reminderModelWait { beginOpening(&mail) }

        case .opening(let since):
            mail.plane.fadeTrail(dt: dt)
            mail.shownAt = mail.target
            if elapsed - since >= Self.reminderOpen { mail.phase = .open(since: elapsed, shown: 0) }

        case .open(let since, let shown):
            // The clock only runs while someone is there to read it.
            let here = userIdleSeconds() < Self.awayAfter
            let now = shown + (here ? dt : 0)
            mail.phase = now >= settings.reminderLetterSeconds ? .closing(since: elapsed) : .open(since: since, shown: now)

        case .closing(let since):
            if elapsed - since >= Self.reminderClose {
                // Folded again: off it goes, up and away over the top of the screen.
                let away = CGPoint(x: mail.target.x + (Bool.random(using: &rng) ? 1 : -1) * mail.screen.width * 0.7,
                                   y: mail.screen.maxY + mail.screen.height * 0.4)
                var plane = PaperPlane.thrown(from: -1, to: -1, start: mail.target, inward: CGVector(dx: 0, dy: 1), target: away, using: &rng)
                plane.swirl *= 0.3
                plane.cruise = 700
                mail.plane = plane
                mail.phase = .leaving(since: elapsed)
            }

        case .leaving(let since):
            let gone = !mail.screen.insetBy(dx: -80, dy: -80).contains(mail.plane.position) || elapsed - since > 3
            if gone {
                // Off the screen: only its trail is left, fading.
                mail.plane.fadeTrail(dt: dt)
                if mail.plane.trail.isEmpty { delivery = nil; return }
            } else {
                let away = CGPoint(x: mail.target.x, y: mail.screen.maxY + mail.screen.height)
                mail.plane.fly(dt: dt, toward: away, time: elapsed)
                let t = min(1, (elapsed - since) / 1.2)
                mail.shownScale = mail.baseScale * (Self.reminderZoom - (Self.reminderZoom - 1) * CGFloat(t))
            }
        }
        delivery = mail
    }

    /// The plane starts to unfold: the note is decided, logged with the chats, and read out loud if asked.
    private func beginOpening(_ mail: inout Delivery) {
        let modelWrote = mail.note != nil
        let note = mail.note ?? Reminders.note(by: mail.writer, reminder: mail.reminder.text, using: &rng)
        mail.note = note
        mail.writing = false
        mail.phase = .opening(since: elapsed)
        let late = now().timeIntervalSince(mail.reminder.time) > 120
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        mail.title = late ? "REMINDER · for \(Reminders.when(mail.reminder.time, now: now()))" : "REMINDER · \(clock.string(from: mail.reminder.time))"
        talkStatus = "\(mail.writer) delivered a reminder: \(mail.reminder.text)"
        history.record(ChatLog.Exchange(
            time: Date(), situation: "\(mail.writer) brought you a reminder by paper plane: \"\(mail.reminder.text)\".",
            provider: modelWrote ? mail.provider : AppSettings.Brain.script.title, model: modelWrote ? mail.model : "",
            lines: [ChatLog.Line(speaker: mail.writer, text: note)], cost: mail.cost, tokens: mail.tokens))
        if settings.reminderReadAloud, isVoiced, mail.thrower != nil {
            _ = voice?.say(note, as: mail.writer, builtIn: !modelWrote)
        }
        trace?("reminder #\(mail.id) open: \(mail.writer): \(note) / \(mail.reminder.text)")
    }

    /// Fold the letter away now (a click on it).
    func closeLetter() {
        guard var mail = delivery, case .open = mail.phase else { return }
        mail.phase = .closing(since: elapsed)
        delivery = mail
    }

    /// With a model: the note, in the thrower's voice, while the plane is in the air.
    private func writeReminderNote(_ mail: inout Delivery) {
        guard settings.brain != .script, let service = settings.chatClient(), let i = mail.thrower else { return }
        let me = character(forCreature: i)
        let vars = ["speaker": me.name, "speakerKind": kind(ofCreature: i), "speakerPersona": me.persona,
                    "listener": "you", "listenerKind": "the person at the computer",
                    "listenerPersona": "The person whose screen you all live on.",
                    "situation": almanac, "reminder": mail.reminder.text]
        let system = Bonds.withRelationship(settings.systemPrompt, vars, context: "")
        let user = Banter.render(Reminders.notePrompt, vars).trimmingCharacters(in: .whitespacesAndNewlines)
        let id = mail.id
        mail.writing = true
        mail.provider = service.provider.title
        mail.model = service.model
        talkStatus = "\(me.name) is writing a reminder via \(service.model)…"
        Task { [weak self] in
            var note: String?, cost: Double?, tokens: Int?
            do {
                try await service.checkModel()
                let answer = try await service.reply(system: system, user: user)
                // Paid for, whatever comes back.
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .reminders)
                    cost = usage.cost
                    tokens = usage.promptTokens + usage.completionTokens
                }
                let line = Banter.cleanLine(answer.text, speaker: me.name)
                if !line.isEmpty { note = line }
            } catch {
                self?.talkStatus = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings reminder: \(error)\n".utf8))
            }
            guard let self, var mail = self.delivery, mail.id == id, mail.writing else { return }
            mail.note = note
            mail.cost = cost
            mail.tokens = tokens
            mail.writing = false
            self.delivery = mail
        }
    }

    // MARK: Drawing

    func reminderSnapshot() -> ReminderSnapshot? {
        guard let mail = delivery else { return nil }
        let puffs = mail.plane.trail.map { ($0.position, Float(max(0, 1 - $0.age / mail.plane.puffLife)) * 0.8) }
        let puffSize = max(2, (mail.baseScale * 1.5).rounded())
        func plane(_ image: CGImage?, at p: CGPoint, heading: Double, scale: CGFloat, opacity: Float = 1) -> PlaneSnapshot {
            PlaneSnapshot(image: image, position: p, heading: heading, scale: scale, opacity: opacity, trail: puffs, puffSize: puffSize)
        }
        let side = planeFrames.frame(animation: "fly", time: 0)
        var snap = ReminderSnapshot()
        switch mail.phase {
        case .finding, .windup:
            return nil
        case .flying, .leaving:
            snap.plane = plane(side, at: mail.plane.position, heading: mail.plane.heading, scale: mail.shownScale)
        case .arriving(let since, _, _):
            // Half-way in it turns to face you.
            let t = (elapsed - since) / Self.reminderArrive
            let heading = t < 0.5 ? mail.plane.heading * (1 - t * 2) : 0
            snap.plane = plane(t < 0.5 ? side : planeFrames.frame(animation: "front", time: 0),
                               at: mail.shownAt, heading: heading, scale: mail.shownScale)
        case .hovering:
            snap.plane = plane(planeFrames.frame(animation: "front", time: 0), at: mail.shownAt, heading: 0, scale: mail.shownScale)
        case .opening(let since):
            let t = (elapsed - since) / Self.reminderOpen
            if t < 0.3 {
                snap.plane = plane(planeFrames.frame(animation: "opening", time: 0), at: mail.target, heading: 0, scale: mail.shownScale)
            } else if t < 0.6 {
                snap.plane = plane(planeFrames.frame(animation: "letter", time: 0), at: mail.target, heading: 0,
                                   scale: mail.shownScale * CGFloat(1 + (t - 0.3) * 2))
            } else {
                // The sheet spreads out to its full size, a touch past it, and settles.
                let k = (t - 0.6) / 0.4
                snap.plane = plane(nil, at: mail.target, heading: 0, scale: 0, opacity: 0)
                snap.letter = letter(mail, grow: CGFloat(0.3 + 0.78 * k), opacity: 1)
            }
        case .open(let since, _):
            let settle = min(1, (elapsed - since) / 0.15)
            snap.plane = plane(nil, at: mail.target, heading: 0, scale: 0, opacity: 0)
            snap.letter = letter(mail, grow: CGFloat(1.08 - 0.08 * settle), opacity: 1)
        case .closing(let since):
            let t = min(1, (elapsed - since) / Self.reminderClose)
            snap.plane = plane(nil, at: mail.target, heading: 0, scale: 0, opacity: 0)
            snap.letter = letter(mail, grow: CGFloat(1 - 0.8 * t), opacity: Float(1 - t))
        }
        return snap
    }

    private func letter(_ mail: Delivery, grow: CGFloat, opacity: Float) -> LetterSnapshot {
        LetterSnapshot(id: mail.id, centre: mail.target, grow: grow, opacity: opacity, title: mail.title,
                              text: mail.reminder.text, note: mail.note ?? "", signature: "— \(mail.writer)",
                              stamp: mail.stamp, hint: "click to fold it away")
    }

    /// The open letter is under `point`.
    func letterContains(_ point: CGPoint) -> Bool {
        guard let mail = delivery, case .open = mail.phase else { return false }
        return overlays.contains { $0.letterFrame?.contains(point) == true }
    }
}
