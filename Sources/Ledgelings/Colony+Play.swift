import AppKit
import LedgelingsCore

/// Plays: now and then, and more often between close friends, one creature
/// (or a pair) stops walking and plays a game (`Plays`): tag round the edges,
/// a swing on a ninja rope, a parachute jump from the ceiling, a few throws at
/// a hoop on the wall. One game at a time; its players are `busy` meanwhile,
/// so nothing else (a talk, a tea party, a plane, a grab) starts with them,
/// and a game only starts with creatures that are free and awake.
extension Colony {

    /// The game going on, who plays it, and where each part of it is.
    struct PlaySession {
        var kind: Plays.Kind
        var players: [Int]
        var serial: Int
        var stage: Stage = .reaching
        /// When it began, on the colony's clock; a game that cannot get going gives up.
        var since: Double
        var tag: Plays.Tag?
        var rope: Plays.Rope?
        var chute: Plays.Chute?
        var court: Court?
        var pitch: Plays.Pitch?
        var soccer: Plays.Soccer?
        var baseball: Plays.Baseball?
        var ballGame: BallGame?
        /// Where the players are going before it starts: leaping to a floor or the ceiling.
        var reaching: [Int: EdgeWorld.Spot] = [:]
        /// Whose invitation started it, for the players' memory.
        var askedBy: String?

        enum Stage: Equatable {
            /// Getting to where the game is played.
            case reaching
            case on
            /// Over: the hoop going, the last line; then it is let go at `until`.
            case ending(until: Double)
        }
    }

    /// The hoop on its wall, the ball, and whose throw it is.
    struct Court {
        var hoop: Plays.Hoop
        var floor: EdgeWorld.Level
        /// The screen's floor and its two ends, for the ball.
        var floorY: CGFloat
        var ends: ClosedRange<CGFloat>
        var scale: CGFloat
        var throwsLeft: Int
        var turn = 0
        var step: Step = .walking
        var ball: Plays.Ball?
        var thrownAt = 0.0
        var ballGone: Double?
        var swishUntil = 0.0
        var grown = 0.0
        var made: [Int: Int] = [:]

        enum Step: Equatable { case walking, windUp(until: Double), throwing(until: Double), watching }
    }

    static let reachTimeout = 6.0
    static let endPause = 0.8

    // MARK: When

    /// Every frame: start a game when one is due, and run the one going on.
    func updatePlay(dt: Double) {
        if play != nil { runPlay(dt: dt); return }
        guard settings.playEnabled, !isNight, !hideout.isActive, grab == nil, held == nil else { return }
        if playEveryWas != settings.playEveryMinutes || nextPlayAt == nil {
            playEveryWas = settings.playEveryMinutes
            nextPlayAt = elapsed + Plays.wait(everyMinutes: settings.playEveryMinutes, boost: settings.playBondBoost,
                                              closeness: closestPairOnScreen(), using: &rng)
        }
        guard let due = nextPlayAt, elapsed >= due else { return }
        if !startPlay(nil) {
            // Nobody free, or nowhere to play: look again in a little while.
            nextPlayAt = elapsed + 30
        }
    }

    /// Awake, on an edge, walking or standing about, and in nothing else.
    func freeToPlay(_ i: Int) -> Bool {
        guard creatures.indices.contains(i) else { return false }
        return creatures[i].isAtLeisure && !busy.contains(i) && !expectsPlane(i) && gifts.hat(of: i) == nil
            && !gardeners.contains(i) && bedTrips[i] == nil && letters[i] == nil && !complaining.contains(i)
            && !hideout.isInside(i) && !chats.contains { $0.involves(i) } && grab?.index != i && held?.index != i
            && teaInvite?.guest != i && teaInvite?.host != i
    }

    /// How close two creatures' characters are, 0...1.
    func closeness(_ i: Int, _ j: Int) -> Double {
        Plays.closeness(bonds.bond(character(forCreature: i).name, character(forCreature: j).name))
    }

    private func closestPairOnScreen() -> Double {
        var best = 0.0
        for i in creatures.indices { for j in creatures.indices where j > i { best = max(best, closeness(i, j)) } }
        return best
    }

    /// Start a game now: `kind`, or one chosen for whoever is free (`Plays.choose`).
    /// The Actions sheet asks for one by kind; tag then takes the closest pair
    /// on one outline, basketball the initiator's closest friend if it has one,
    /// and a ball game everyone free, closest friends first, up to its most
    /// players (or `count`, as the film asks).
    @discardableResult
    func startPlay(_ kind: Plays.Kind?, by chosen: Int? = nil, count: Int? = nil) -> Bool {
        guard play == nil, !hideout.isActive else { return false }
        let free = creatures.indices.filter(freeToPlay)
        guard let first = chosen.flatMap({ free.contains($0) ? $0 : nil }) ?? free.randomElement(using: &rng) else { talkStatus = tr("nobody is free to play"); return false }
        func partners(of i: Int) -> [(index: Int, closeness: Double)] {
            free.filter { $0 != i && creatures[$0].spot.loop == creatures[i].spot.loop }.map { ($0, closeness(i, $0)) }
        }
        var tries: [(Plays.Kind, [Int])] = []
        if let kind {
            switch kind {
            case .tag:
                // The closest pair that shares an outline.
                var pairs: [(Int, Int, Double)] = []
                for i in free where chosen == nil || i == chosen { for (j, c) in partners(of: i) where j != i { pairs.append((i, j, c)) } }
                guard let pair = pairs.max(by: { $0.2 < $1.2 }) else { talkStatus = tr("tag needs two free creatures on one screen outline"); return false }
                tries = [(.tag, chosen != nil || Bool.random(using: &rng) ? [pair.0, pair.1] : [pair.1, pair.0])]
            case .basketball:
                let friend = partners(of: first).filter { $0.closeness >= Double(Plays.friendsAt) / Plays.closeAt }.max { $0.closeness < $1.closeness }
                tries = [(.basketball, [first] + (friend.map { [$0.index] } ?? []))]
            case .rope, .parachute:
                tries = [(kind, [first])]
            case .soccer, .baseball:
                tries = [(kind, Plays.joining(initiator: first, crowd: crowd(of: first), max: count ?? settings.ballGamePlayers[kind] ?? 6))]
            }
        } else {
            // A ball game for everyone free, now and then, if one is due.
            if let team = Plays.chooseTeamGame(initiator: first, crowd: crowd(of: first), enabled: ballGamesDue,
                                               maxPlayers: settings.ballGamePlayers, using: &rng), begin(team.kind, team.players) {
                return true
            }
            guard let chosen = Plays.choose(initiator: first, others: partners(of: first), enabled: settings.enabledPlays, using: &rng) else { return false }
            tries = [(chosen.kind, chosen.players)]
            // No room for that one here: a game alone that fits instead.
            for other in Plays.Kind.allCases.shuffled(using: &rng) where other != chosen.kind && other.canSolo && settings.enabledPlays.contains(other) {
                tries.append((other, [first]))
            }
        }
        for (k, players) in tries where begin(k, players) { return true }
        if kind != nil { talkStatus = tr("no room to play that here") }
        return false
    }

    /// Start `kind` with these two because they agreed to (`Deeds`): a ball game
    /// takes everyone else free too, the invited one first. `asked`: whose
    /// invitation it was, for their memory.
    @discardableResult
    func startPlay(_ kind: Plays.Kind, with pair: [Int], asked: String?) -> Bool {
        guard play == nil, !hideout.isActive, pair.count == 2, pair.allSatisfy(freeToPlay) else { return false }
        var players = pair
        if kind.isTeamGame {
            let crowd = [(index: pair[1], closeness: 2.0)] + crowd(of: pair[0]).filter { $0.index != pair[1] }
            players = Plays.joining(initiator: pair[0], crowd: crowd, max: settings.ballGamePlayers[kind] ?? 6)
        }
        guard begin(kind, players) else { return false }
        play?.askedBy = asked
        return true
    }

    // MARK: Starting

    private func onFloor(_ i: Int) -> Bool { creatures[i].loop.direction(ofSegment: creatures[i].segment).dx > 0.5 }

    /// The floor under creature `i`, in its own world.
    private func floorUnder(_ i: Int) -> EdgeWorld.Level? {
        creatures[i].world.floor(under: creatures[i].position)
    }

    func spot(on level: EdgeWorld.Level, x: CGFloat, for i: Int) -> EdgeWorld.Spot {
        let w = creatures[i].world
        let clamped = min(max(x, level.span.lowerBound), level.span.upperBound)
        return EdgeWorld.Spot(loop: level.loop, t: w.loops[level.loop].nearest(to: CGPoint(x: clamped, y: level.y)).t)
    }

    private func begin(_ kind: Plays.Kind, _ players: [Int]) -> Bool {
        guard players.allSatisfy(freeToPlay) else { return false }
        playCount += 1
        var session = PlaySession(kind: kind, players: players, serial: playCount, since: elapsed)
        switch kind {
        case .tag:
            guard players.count == 2, creatures[players[0]].spot.loop == creatures[players[1]].spot.loop else { return false }
            // The one who starts it runs; the other is "it".
            session.tag = Plays.Tag(it: players[1], other: players[0], length: settings.tagSeconds)
            session.stage = .on
        case .rope:
            let i = players[0]
            guard let floor = floorUnder(i) else { return false }
            let x = onFloor(i) ? creatures[i].position.x
                : floor.span.lowerBound + (floor.span.upperBound - floor.span.lowerBound) * .random(in: 0.25...0.75, using: &rng)
            let at = spot(on: floor, x: x, for: i)
            guard rope(for: i, at: creatures[i].world.point(at: at), floor: floor) != nil else { return false }
            if !onFloor(i) { session.reaching[i] = at }
        case .parachute:
            let i = players[0], w = creatures[i].world
            let over = w.ceiling(over: creatures[i].position).map { [$0] } ?? []
            let ceilings = (over + w.ceilings.shuffled(using: &rng)).filter { level in
                level.span.upperBound - level.span.lowerBound > 120
                    && w.floor(under: CGPoint(x: (level.span.lowerBound + level.span.upperBound) / 2, y: level.y)).map { level.y - $0.y > 200 } == true
            }
            guard let ceiling = ceilings.first else { return false }
            let lo = ceiling.span.lowerBound, hi = ceiling.span.upperBound
            let x = min(max(creatures[i].position.x, lo + (hi - lo) * 0.15), hi - (hi - lo) * 0.15)
            guard w.floor(under: CGPoint(x: x, y: ceiling.y)) != nil else { return false }
            session.reaching[i] = spot(on: ceiling, x: x, for: i)
        case .basketball:
            guard let court = court(for: players) else { return false }
            session.court = court
            for i in players where !(onFloor(i) && creatures[i].world.floor(under: creatures[i].position)?.segment == court.floor.segment
                                       && creatures[i].spot.loop == court.floor.loop) {
                let f = court.floor
                session.reaching[i] = spot(on: f, x: f.span.lowerBound + (f.span.upperBound - f.span.lowerBound) * .random(in: 0.3...0.7, using: &rng), for: i)
            }
        case .soccer:
            guard beginSoccer(&session) else { return false }
        case .baseball:
            guard beginBaseball(&session) else { return false }
        }
        busy.formUnion(players)
        for (i, to) in session.reaching { creatures[i].leap(to: to) }
        for i in players where session.reaching[i] == nil && !creatures[i].isPlaying { creatures[i].standStill(for: .infinity) }
        play = session
        let names = players.map { character(forCreature: $0).name }
        talkStatus = names.count == 2 ? tr("%@ and %@: %@", names[0], names[1], kind.title) : tr("%@: %@", names.joined(separator: ", "), kind.title)
        trace?("play \(kind.rawValue) \(names.joined(separator: " & "))\(session.reaching.isEmpty ? "" : " (getting there)")")
        if kind == .baseball { startLine(session) } else if session.reaching.isEmpty { started() }
        return true
    }

    /// A rope swing for `i` from `point` (its centre on `floor`), or nil when there is no room.
    private func rope(for i: Int, at point: CGPoint, floor: EdgeWorld.Level) -> Plays.Rope? {
        let w = creatures[i].world, inset = atlas.bodyHalfSize * CGFloat(sizes[i])
        guard let ceiling = w.ceiling(over: point) else { return nil }
        let way: CGFloat = point.x < (floor.span.lowerBound + floor.span.upperBound) / 2 ? 1 : -1
        return Plays.Rope(from: point, ceilingY: ceiling.y + inset, floor: floor.span, way: way, clearance: inset * 2.5)
    }

    /// A hoop on a wall at an end of the initiator's floor (or the floor under it), with room to throw from.
    private func court(for players: [Int]) -> Court? {
        let i = players[0], w = creatures[i].world
        guard let floor = floorUnder(i) else { return nil }
        let inset = atlas.bodyHalfSize * CGFloat(sizes[i])
        let length = floor.span.upperBound - floor.span.lowerBound
        guard length >= 260 else { return nil }
        // The wall furthest from it, so it has room to throw.
        guard let wall = w.walls(of: floor).max(by: { abs($0.x - creatures[i].position.x) < abs($1.x - creatures[i].position.x) }) else { return nil }
        let scale = CGFloat(players.map { sizes[$0] }.reduce(0, +) / Double(players.count))
        let screenFloor = floor.y - inset
        let height = min(max((wall.height + inset) * 0.45, 90), 240)
        let hoop = Plays.Hoop(wallX: wall.x + wall.side * inset, side: wall.side, floorY: screenFloor, height: height, scale: scale)
        return Court(hoop: hoop, floor: floor, floorY: screenFloor,
                     ends: (floor.span.lowerBound - inset)...(floor.span.upperBound + inset),
                     scale: scale, throwsLeft: settings.basketballThrows * players.count)
    }

    /// Everyone is in place: the game begins, and whoever started it says so.
    private func started() {
        guard var session = play else { return }
        session.stage = .on
        let i = session.players[0]
        switch session.kind {
        case .rope:
            guard let floor = floorUnder(i), let rope = rope(for: i, at: creatures[i].position, floor: floor) else { return endPlay(completed: false) }
            creatures[i].face(rope.way)
            creatures[i].takeOff()
            session.rope = rope
        case .parachute:
            let w = creatures[i].world
            guard let floor = w.floor(under: creatures[i].position) else { return endPlay(completed: false) }
            creatures[i].takeOff()
            session.chute = Plays.Chute(from: creatures[i].position, floorY: floor.y, floor: floor.span,
                                        fallSpeed: CGFloat(settings.parachuteFallSpeed))
        case .soccer:
            guard startSoccer(&session) else { return endPlay(completed: false) }
        case .tag, .basketball, .baseball:
            break
        }
        play = session
        startLine(session)
    }

    // MARK: Running

    private func runPlay(dt: Double) {
        guard var session = play else { return }
        if hideout.isActive || !session.players.allSatisfy(creatures.indices.contains) { return endPlay(completed: false) }
        if case .ending(let until) = session.stage {
            if var court = session.court { court.grown = max(0, court.grown - dt / 0.4); session.court = court; play = session }
            if elapsed >= until { endPlay(completed: true) }
            return
        }
        if session.stage == .reaching {
            if elapsed - session.since > Self.reachTimeout { return endPlay(completed: false) }
            let there = session.reaching.allSatisfy { creatures[$0.key].hasArrived }
            // Leapt off course (startled, picked up): no game.
            func onTheWay(_ c: Creature) -> Bool {
                if c.isJumping || c.hasArrived { return true }
                if case .landing = c.mode { return true }
                return false
            }
            if session.reaching.contains(where: { !onTheWay(creatures[$0.key]) }) { return endPlay(completed: false) }
            guard there else { return }
            for i in session.players { creatures[i].standStill(for: .infinity) }
            started()
            return
        }
        switch session.kind {
        case .tag: runTag(&session, dt: dt)
        case .rope: runRope(&session, dt: dt)
        case .parachute: runChute(&session, dt: dt)
        case .basketball: runBasketball(&session, dt: dt)
        case .soccer: runSoccer(&session, dt: dt)
        case .baseball: runBaseball(&session, dt: dt)
        }
        if play?.serial == session.serial { play = session }
    }

    private func runTag(_ s: inout PlaySession, dt: Double) {
        guard var tag = s.tag else { return }
        let a = s.players[0], b = s.players[1]
        // Picked up, startled into a jump, asleep: the game is off.
        guard [a, b].allSatisfy({ !creatures[$0].isHeld && !creatures[$0].isJumping && !creatures[$0].looksAsleep && !creatures[$0].isChatting }) else {
            return endPlay(completed: false)
        }
        for event in tag.update(dt: dt) {
            switch event {
            case .go: trace?("play tag \(character(forCreature: tag.it).name) is it")
            case .puffing:
                for i in [a, b] { creatures[i].standStill(for: Plays.Tag.puffTime + 1) }
                creatures[a].face(facing(a, toward: b)); creatures[b].face(facing(b, toward: a))
                trace?("play tag over after \(tag.touches) touches, both out of breath")
            case .over:
                s.tag = tag
                return wrapUp(&s, speaker: tag.it)
            case .tagged: break
            }
        }
        if tag.phase == .chase {
            let it = tag.it, runner = tag.runner
            let loop = creatures[runner].loop
            let ahead = loop.wrap(creatures[it].t - creatures[runner].t)
            let gap = min(ahead, loop.length - ahead)
            let away: CGFloat = ahead <= loop.length / 2 ? -1 : 1
            creatures[runner].run(to: creatures[runner].t + away * 400, pace: Plays.Tag.fleeSpeed / creatures[runner].config.walkSpeed)
            if tag.itIsCounting {
                if creatures[it].isRunning { creatures[it].standStill(for: .infinity) }
            } else {
                creatures[it].run(to: creatures[runner].t, pace: Plays.Tag.chaseSpeed / creatures[it].config.walkSpeed)
            }
            let reach = atlas.bodyHalfSize * CGFloat(sizes[it] + sizes[runner])
            if case .tagged(let by, let now) = tag.near(gap: gap, reach: reach) {
                creatures[now].standStill(for: .infinity)
                let p = creatures[now].position
                sparks.burst(at: p, inward: creatures[now].loop.inward(ofSegment: creatures[now].segment), using: &rng)
                trace?("play tag \(character(forCreature: by).name) tags \(character(forCreature: now).name)")
            }
        }
        s.tag = tag
    }

    private func runRope(_ s: inout PlaySession, dt: Double) {
        let i = s.players[0]
        guard var rope = s.rope, creatures[i].isPlaying else { return endPlay(completed: false) }
        for event in rope.update(dt: dt) {
            switch event {
            case .fired: trace?(String(format: "play rope %@ fires at (%.0f, %.0f)", character(forCreature: i).name, rope.anchor.x, rope.anchor.y))
            case .hooked, .swinging: break
            case .letGo: trace?("play rope \(character(forCreature: i).name) lets go")
            case .landed:
                creatures[i].carry(to: rope.position, rotation: 0, pose: "land")
                creatures[i].touchDown(standingFor: 1)
                trace?(String(format: "play rope %@ lands at %.0f", character(forCreature: i).name, rope.position.x))
                s.rope = rope
                return wrapUp(&s, speaker: i)
            }
        }
        creatures[i].carry(to: rope.position, rotation: rope.rotation, pose: rope.pose)
        s.rope = rope
    }

    private func runChute(_ s: inout PlaySession, dt: Double) {
        let i = s.players[0]
        guard var chute = s.chute, creatures[i].isPlaying else { return endPlay(completed: false) }
        for event in chute.update(dt: dt) {
            switch event {
            case .jumped: trace?("play parachute \(character(forCreature: i).name) jumps")
            case .opened: trace?("play parachute \(character(forCreature: i).name) opens the parachute")
            case .landed: trace?(String(format: "play parachute %@ lands at %.0f", character(forCreature: i).name, chute.position.x))
            case .packed:
                creatures[i].carry(to: chute.position, rotation: 0, pose: "idle")
                creatures[i].touchDown(standingFor: 0.8)
                s.chute = chute
                return wrapUp(&s, speaker: i)
            }
        }
        creatures[i].carry(to: chute.position, rotation: chute.rotation, pose: chute.pose)
        s.chute = chute
    }

    private func runBasketball(_ s: inout PlaySession, dt: Double) {
        guard var court = s.court else { return }
        court.grown = min(1, court.grown + dt / 0.4)
        let thrower = s.players[court.turn % s.players.count]
        let others = s.players.filter { $0 != thrower }
        // Startled into a jump or picked up: the game is off.
        guard s.players.allSatisfy({ !creatures[$0].isHeld && !creatures[$0].isJumping && !creatures[$0].looksAsleep }) else {
            return endPlay(completed: false)
        }
        for k in others where creatures[k].isRunning { creatures[k].standStill(for: .infinity) }
        let name = character(forCreature: thrower).name
        switch court.step {
        case .walking:
            let c = creatures[thrower]
            if !c.isRunning, !c.hasArrived {
                let d = CGFloat.random(in: 150...380, using: &rng)
                let wallLoopX = court.hoop.wallX - court.hoop.side * atlas.bodyHalfSize * CGFloat(sizes[thrower])
                let to = spot(on: court.floor, x: wallLoopX - court.hoop.side * d, for: thrower)
                creatures[thrower].run(to: to.t, pace: 2.2)
            } else if c.hasArrived {
                creatures[thrower].face(court.hoop.side)
                creatures[thrower].takeOff()
                creatures[thrower].carry(to: c.position, rotation: c.restingRotation, pose: "land")
                court.step = .windUp(until: elapsed + 0.35)
            }
        case .windUp(let until):
            guard elapsed >= until else { break }
            let c = creatures[thrower], half = atlas.bodyHalfSize * CGFloat(sizes[thrower])
            creatures[thrower].carry(to: c.position, rotation: c.restingRotation, pose: "jump")
            let from = CGPoint(x: c.position.x + court.hoop.side * half * 0.4, y: c.position.y + half * 1.1)
            var v = Plays.Ball.aim(from: from, hoop: court.hoop, apex: .random(in: 50...150, using: &rng))
            let makes = Double.random(in: 0..<1, using: &rng) < Plays.makeChance
            if !makes { v.dx *= Bool.random(using: &rng) ? .random(in: 0.8...0.9, using: &rng) : .random(in: 1.1...1.2, using: &rng) }
            court.ball = Plays.Ball(at: from, velocity: v, radius: Plays.Props.ballRadius * court.scale, bounce: CGFloat(settings.ballBounce / 100),
                                    hoop: court.hoop, floorY: court.floorY, court: court.ends)
            court.thrownAt = elapsed
            court.ballGone = nil
            court.throwsLeft -= 1
            court.step = .throwing(until: elapsed + 0.3)
            trace?("play basketball \(name) throws")
        case .throwing(let until):
            guard elapsed >= until else { break }
            creatures[thrower].touchDown(standingFor: .infinity)
            court.step = .watching
        case .watching:
            break
        }
        if var ball = court.ball {
            for event in ball.step(dt: dt) {
                switch event {
                case .scored:
                    court.made[thrower, default: 0] += 1
                    court.swishUntil = elapsed + 0.5
                    sparks.burst(at: CGPoint(x: court.hoop.rimX, y: court.hoop.rimY), inward: CGVector(dx: 0, dy: 1), using: &rng)
                    trace?("play basketball \(name) scores")
                case .rim: trace?("play basketball clang off the rim")
                case .board: trace?("play basketball off the board")
                case .floor: break
                }
            }
            court.ball = ball
            if court.ballGone == nil, ball.resting || elapsed - court.thrownAt > 5 { court.ballGone = elapsed }
            if let gone = court.ballGone, elapsed - gone > 0.5, court.step == .watching {
                court.ball = nil
                if !ball.scored { trace?("play basketball \(name) misses") }
                if court.throwsLeft <= 0 {
                    s.court = court
                    let best = s.players.max { court.made[$0, default: 0] < court.made[$1, default: 0] } ?? thrower
                    trace?("play basketball over: " + s.players.map { "\(character(forCreature: $0).name) \(court.made[$0, default: 0])" }.joined(separator: ", "))
                    return wrapUp(&s, speaker: best)
                }
                court.turn += 1
                court.step = .walking
                let next = s.players[court.turn % s.players.count]
                creatures[next].standStill(for: .infinity)
            }
        }
        s.court = court
    }

    // MARK: Ending

    /// The game is over and went well: the last word, its place in their story, then let go.
    func wrapUp(_ s: inout PlaySession, speaker: Int) {
        s.stage = .ending(until: elapsed + Self.endPause)
        // Everyone who played together lived it together: teammates, and the
        // other side too, with how it ended and whose idea it was.
        let (score, winners) = gameResult(s)
        trace?("play \(s.kind.rawValue) result: \(score ?? "-"), won by \(winners.map { $0.isEmpty ? "nobody (a draw)" : $0.joined(separator: ", ") } ?? "-")")
        for a in s.players.indices {
            for b in s.players.indices where b > a {
                shared(s.players[a], s.players[b], .play, detail: s.kind.rawValue, score: score, winners: winners, asked: s.askedBy)
            }
        }
        doneLine(by: speaker, s)
    }

    /// How the game ended: the board's score and who won (empty for a draw, nil
    /// for a game with no winner, as the rope, or one played alone).
    func gameResult(_ s: PlaySession) -> (score: String?, winners: [String]?) {
        func won(_ sides: [(players: [Int], points: Int)]) -> [String]? {
            guard sides.count >= 2, let best = sides.map(\.points).max() else { return nil }
            let top = sides.filter { $0.points == best }
            return top.count > 1 ? [] : top[0].players.map(name)
        }
        switch s.kind {
        case .tag:
            return (s.tag.map { trCount($0.touches, "touch", "touches") }, nil)
        case .rope, .parachute:
            return (nil, nil)
        case .basketball:
            guard let court = s.court else { return (nil, nil) }
            let sides = s.players.map { (players: [$0], points: court.made[$0, default: 0]) }
            return (sides.map { "\($0.points)" }.joined(separator: "-"), won(sides))
        case .soccer:
            guard let m = s.soccer else { return (nil, nil) }
            return (soccerScore(m), m.lineup == .solo ? nil : m.winners.map(name).sorted())
        case .baseball:
            guard let g = s.baseball, g.lineup != .solo else { return (s.baseball.map(baseballScore), nil) }
            let sides: [(players: [Int], points: Int)] = g.lineup == .rotation
                ? s.players.map { ([$0], g.runsBy[$0, default: 0]) }
                : g.sides.indices.map { (g.sides[$0], g.sideRuns.indices.contains($0) ? g.sideRuns[$0] : 0) }
            return (baseballScore(g), won(sides))
        }
    }

    /// Let everyone go: down from the air, off the spot they waited on, out of `busy`.
    func endPlay(completed: Bool) {
        guard let s = play else { return }
        play = nil
        for i in s.players where creatures.indices.contains(i) {
            if creatures[i].isPlaying { creatures[i].touchDown() }
            if case .idle = creatures[i].mode { creatures[i].standStill(for: 0.6) }
            if creatures[i].isRunning { creatures[i].standStill(for: 0.6) }
        }
        busy.subtract(s.players)
        if s.kind.isTeamGame {
            ballGameEnded[s.kind] = elapsed
            // The final score stays up a moment, fading.
            if let board = ballGameProps(s).first(where: { $0.size != nil && $0.position == s.ballGame?.boardAt }) {
                fadingBoard = (board, elapsed + Self.boardShown)
            }
        }
        nextPlayAt = elapsed + Plays.wait(everyMinutes: settings.playEveryMinutes, boost: settings.playBondBoost,
                                          closeness: closestPairOnScreen(), using: &rng)
        if !completed { trace?("play \(s.kind.rawValue) broken off") }
        trace?("play \(s.kind.rawValue) done")
    }

    // MARK: Words

    private var playCanTalk: Bool { settings.playTalk && settings.talkEnabled && !voiceIsTaken }

    private func playSituation(_ s: PlaySession) -> String {
        var parts = [timeOfDay]
        if !almanac.isEmpty { parts.insert(almanac, at: 0) }
        parts.append(contentsOf: s.players.map { describe($0) + "." })
        return parts.joined(separator: " ")
    }

    /// Whoever started it says so: a built-in line, or one from the model.
    private func startLine(_ s: PlaySession) {
        guard playCanTalk else { return }
        let i = s.players[0], me = character(forCreature: i)
        let other = s.players.dropFirst().prefix(4).map { character(forCreature: $0).name }.joined(separator: ", ")
        let builtIn = Plays.startLine(by: me.name, s.kind, other: other)
        let situation = playSituation(s)
        guard settings.brain != .script, let service = settings.chatClient() else {
            sayPlayLine(builtIn, by: i, situation: situation, provider: AppSettings.Brain.script.title, model: "", cost: nil, tokens: nil)
            return
        }
        let vars = ["speaker": me.name, "speakerKind": Banter.spoken(kind(ofCreature: i)), "speakerPersona": Banter.persona(me.persona),
                    "play": s.kind.title, "others": other.isEmpty ? "" : tr(" with %@", other), "situation": situation]
        let serial = s.serial
        Task { [weak self] in
            var line = "", cost: Double?, tokens: Int?
            do {
                let answer = try await service.line(system: Plays.lineSystemPrompt, user: Banter.render(Plays.linePrompt, vars))
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }       // a local model is free
                    cost = usage.cost
                    tokens = usage.promptTokens + usage.completionTokens
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage,
                                       purpose: s.kind.isTeamGame ? .ballGames : .plays)
                }
                line = Banter.cleanLine(answer.text, speaker: me.name, cut: answer.cut)
            } catch {
                FileHandle.standardError.write(Data("Ledgelings play: \(error)\n".utf8))
            }
            guard let self, play?.serial == serial else { return }
            if line.isEmpty {
                sayPlayLine(builtIn, by: i, situation: situation, provider: AppSettings.Brain.script.title, model: "", cost: nil, tokens: nil)
            } else {
                sayPlayLine(line, by: i, situation: situation, provider: service.provider.title, model: service.model, cost: cost, tokens: tokens,
                            builtIn: false)
            }
        }
    }

    private func doneLine(by i: Int, _ s: PlaySession) {
        guard playCanTalk, creatures.indices.contains(i) else { return }
        sayPlayLine(Plays.doneLine(by: character(forCreature: i).name, using: &rng), by: i, situation: playSituation(s),
                    provider: AppSettings.Brain.script.title, model: "", cost: nil, tokens: nil)
    }

    private func sayPlayLine(_ text: String, by i: Int, situation: String, provider: String, model: String,
                             cost: Double?, tokens: Int?, builtIn: Bool = true) {
        guard !text.isEmpty, creatures.indices.contains(i) else { return }
        say(text, from: i, builtIn: builtIn)
        history.record(ChatLog.Exchange(time: Date(), situation: situation, provider: provider, model: model,
                                        lines: [ChatLog.Line(speaker: character(forCreature: i).name, text: text)],
                                        cost: cost, tokens: tokens))
    }

    // MARK: Drawing

    /// How much higher creature `i`'s bubble floats: clear of its open parachute.
    func playBubbleLift(of i: Int) -> CGFloat {
        guard let s = play, s.kind == .parachute, s.players.first == i, let chute = s.chute, chute.canopy > 0 else { return 0 }
        return playCell.height * CGFloat(sizes[i]) * CGFloat(chute.canopy)
    }

    /// The props of the game going on, in global points.
    func playProps() -> [PropSnapshot] {
        var fading: [PropSnapshot] = []
        if let f = fadingBoard {
            if elapsed > f.until { fadingBoard = nil } else {
                var board = f.prop
                board.opacity = Float(min(1, (f.until - elapsed) / 1.2))
                fading = [board]
            }
        }
        guard let s = play else { return fading }
        var props: [PropSnapshot] = []
        func image(_ animation: String, _ time: Double = 0) -> CGImage? { playFrames.frame(animation: animation, time: time) }
        func up(_ rotation: Double) -> CGVector { CGVector(dx: -sin(rotation), dy: cos(rotation)) }
        switch s.kind {
        case .tag:
            guard let tag = s.tag, tag.phase == .puffing || tag.phase == .over else { break }
            for i in s.players {
                let c = creatures[i], half = atlas.bodyHalfSize * CGFloat(sizes[i]), scale = CGFloat(sizes[i])
                let bob = CGFloat(sin(elapsed * 6)) * scale
                let u = up(c.rotation)
                let lift = half + 5 * scale + bob
                props.append(PropSnapshot(image: image("drop"), position: CGPoint(x: c.position.x + u.dx * lift + u.dy * half * 0.7 * (c.isMirrored ? 1 : -1),
                                                                                   y: c.position.y + u.dy * lift - u.dx * half * 0.7 * (c.isMirrored ? 1 : -1)),
                                          rotation: c.rotation, scale: scale))
            }
        case .rope:
            guard let rope = s.rope, rope.ropeIsOut else { break }
            let i = s.players[0], c = creatures[i], scale = CGFloat(sizes[i])
            let half = atlas.bodyHalfSize * scale
            let u = up(c.rotation)
            let hands = CGPoint(x: c.position.x + u.dx * half * 0.8, y: c.position.y + u.dy * half * 0.8)
            let toHook = CGVector(dx: rope.hook.x - hands.x, dy: rope.hook.y - hands.y)
            let length = hypot(toHook.dx, toHook.dy)
            let turn = atan2(-Double(toHook.dx), Double(toHook.dy))
            // The hook's shaft ends 3 sheet pixels below its middle; the rope runs up to there.
            let shaft = max(0, length - 3 * scale)
            let step = 2 * scale
            var along: CGFloat = 0
            while along < shaft {
                let k = along / max(length, 1)
                props.append(PropSnapshot(image: image("rope"), position: CGPoint(x: hands.x + toHook.dx * k, y: hands.y + toHook.dy * k),
                                          rotation: 0, scale: scale))
                along += step
            }
            props.append(PropSnapshot(image: image("hook"), position: rope.hook, rotation: turn, scale: scale))
        case .parachute:
            guard let chute = s.chute, chute.canopy > 0 else { break }
            let i = s.players[0], c = creatures[i], scale = CGFloat(sizes[i])
            let half = atlas.bodyHalfSize * scale
            let open = CGFloat(chute.canopy)
            let u = up(c.rotation)
            let height = playCell.height * scale * open
            let lift = half * 0.8 + height / 2
            props.append(PropSnapshot(image: image("chute"), position: CGPoint(x: c.position.x + u.dx * lift, y: c.position.y + u.dy * lift),
                                      rotation: c.rotation, scale: scale * open))
        case .basketball:
            guard let court = s.court, court.grown > 0 else { break }
            let hoopImage = elapsed < court.swishUntil ? image("swish") : image("hoop")
            props.append(PropSnapshot(image: hoopImage, position: court.hoop.centre, rotation: 0, scale: court.scale,
                                      mirrored: court.hoop.side < 0, opacity: Float(court.grown)))
            if let ball = court.ball {
                let fade = court.ballGone.map { Float(max(0, 1 - (elapsed - $0) / 0.5)) } ?? 1
                // A frame for every eighth of a turn it has rolled: the seams go round.
                props.append(PropSnapshot(image: image("ball", abs(ball.turn) / (.pi / 4) / 8), position: ball.position,
                                          rotation: 0, scale: court.scale, opacity: fade, inFront: true))
            }
        case .soccer, .baseball:
            props += ballGameProps(s)
        }
        return props + fading
    }
}
