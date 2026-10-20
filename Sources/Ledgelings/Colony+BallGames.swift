import AppKit
import LedgelingsCore

/// Soccer and baseball (`Plays.Soccer`, `Plays.Baseball`): a game for however
/// many are free, closest friends joining first. Soccer is played on the
/// widest floor, the players leaping there first; baseball on every edge, the
/// game hopping everyone to their places itself. The players are off their
/// edges (`playing`) for the whole game and the colony puts each where the
/// game says, every frame; a scoreboard in pixel letters sits at the top of
/// the screen while it lasts and fades after.
extension Colony {

    /// Everything a ball game needs besides the game itself.
    struct BallGame {
        /// A cheer across the screen ("GOAL!"), from `since` until `until`.
        var banner: (image: CGImage?, size: CGSize, at: CGPoint, since: Double, until: Double)?
        /// Fireworks still to go off, by when.
        var fireworks: [(at: Double, point: CGPoint)] = []
        /// Where the scoreboard goes: the top of the screen the game is on.
        var boardAt: CGPoint
        var scale: CGFloat
        /// The screens the game is on, to keep a cheer inside them.
        var bounds: CGRect = .infinite
        /// Who has had an "oops" or wandered off already: once a game each.
        var said: Set<String> = []
    }

    static let boardShown = 3.0

    func half(_ i: Int) -> CGFloat { atlas.bodyHalfSize * CGFloat(sizes[i]) }

    /// The ball games that may start now: on, and not played too lately.
    var ballGamesDue: Set<Plays.Kind> {
        Set(Plays.Kind.allCases.filter { kind in
            kind.isTeamGame && settings.enabledPlays.contains(kind)
                && ballGameEnded[kind].map { elapsed - $0 >= settings.ballGameEvery(kind) * 60 } ?? true
        })
    }

    /// Everyone else free to play, wherever they are, with how close each is to `i`.
    func crowd(of i: Int) -> [(index: Int, closeness: Double)] {
        creatures.indices.filter { $0 != i && freeToPlay($0) }.map { ($0, closeness(i, $0)) }
    }

    /// Two sides for team play, friends together, and their keepers (soccer, from six).
    func sides(_ players: [Int], keepers: Bool) -> (teams: [[Int]], keepers: Set<Int>) {
        let teams = Plays.split(players) { closeness($0, $1) }
        guard keepers, players.count >= 6 else { return (teams, []) }
        return (teams, Set(teams.compactMap { Plays.keeper(of: $0) { closeness($0, $1) } }))
    }

    // MARK: Starting

    /// The pitch for soccer, and everyone leaping onto it, spread along it.
    func beginSoccer(_ session: inout PlaySession) -> Bool {
        let i = session.players[0]
        guard let pitch = Plays.Pitch.choose(in: creatures[i].world, inset: half(i)) else { return false }
        let n = session.players.count
        for (k, p) in session.players.enumerated() {
            let w = creatures[p].world
            let x = pitch.span.lowerBound + pitch.length * (0.2 + 0.6 * (CGFloat(k) + 0.5) / CGFloat(n))
            guard let level = w.floor(under: CGPoint(x: x, y: pitch.floorY + half(p) + 1)),
                  abs(level.y - (pitch.floorY + half(p))) < 2 else { return false }
            let onIt = onPitch(p, pitch)
            if !onIt { session.reaching[p] = spot(on: level, x: x, for: p) }
        }
        session.pitch = pitch
        return true
    }

    private func onPitch(_ p: Int, _ pitch: Plays.Pitch) -> Bool {
        let c = creatures[p]
        return c.loop.direction(ofSegment: c.segment).dx > 0.5 && abs(c.position.y - (pitch.floorY + half(p))) < 2
            && pitch.span.contains(c.position.x)
    }

    /// Everyone is on the pitch: the match begins.
    func startSoccer(_ session: inout PlaySession) -> Bool {
        guard let pitch = session.pitch else { return false }
        let players = session.players
        let lineup = players.count >= 4 ? sides(players, keepers: true) : (teams: [[Int]](), keepers: Set<Int>())
        var halves: [Int: CGFloat] = [:], at: [Int: CGFloat] = [:]
        for p in players {
            halves[p] = half(p)
            at[p] = creatures[p].position.x
            creatures[p].takeOff()
        }
        let scale = CGFloat(players.map { sizes[$0] }.reduce(0, +) / Double(players.count))
        session.soccer = Plays.Soccer(players: players, teams: lineup.teams.isEmpty ? nil : lineup.teams, keepers: lineup.keepers,
                                      halves: halves, at: at, pitch: pitch, scale: scale, goalsToWin: settings.soccerGoals,
                                      length: settings.soccerMinutes * 60, using: &rng)
        session.ballGame = BallGame(boardAt: boardPlace(over: CGPoint(x: (pitch.span.lowerBound + pitch.span.upperBound) / 2, y: pitch.floorY + half(players[0])),
                                                        world: creatures[players[0]].world, inset: half(players[0])), scale: scale,
                                    bounds: bounds(of: creatures[players[0]].world, inset: half(players[0])))
        if !lineup.teams.isEmpty {
            trace?("play soccer teams: " + lineup.teams.map { $0.map(name).joined(separator: ", ") }.joined(separator: " v ")
                   + (lineup.keepers.isEmpty ? "" : "; in goal " + lineup.keepers.map(name).sorted().joined(separator: " and ")))
        }
        return true
    }

    /// The field for baseball, from where the first player stands; the game takes it from there.
    func beginBaseball(_ session: inout PlaySession) -> Bool {
        let i = session.players[0]
        guard let field = Plays.Field.choose(in: creatures[i].world, inset: half(i), batter: creatures[i].spot) else { return false }
        let players = session.players
        var halves: [Int: CGFloat] = [:], starts: [Int: Plays.Place] = [:]
        for p in players {
            halves[p] = half(p)
            starts[p] = Plays.Place(creatures[p].spot, in: creatures[p].world, inset: half(p))
        }
        let teams = players.count >= 6 ? sides(players, keepers: false).teams : nil
        let mood: Double = switch CursorMood.current { case .good: 0.5; case .neutral: 0; case .bad: -0.4 }
        session.baseball = Plays.Baseball(players: players, teams: teams, starts: starts, halves: halves, field: field,
                                          innings: settings.baseballInnings, mood: mood) { [unowned self] in closeness($0, $1) }
        let scale = CGFloat(players.map { sizes[$0] }.reduce(0, +) / Double(players.count))
        let middle = ([field.home] + field.bases).map(\.edge.x).reduce(0, +) / 4
        // Under the ceiling, clear of a base there and whoever stands on it.
        session.ballGame = BallGame(boardAt: CGPoint(x: middle, y: field.top - 110 * scale / 2.5), scale: scale,
                                    bounds: bounds(of: creatures[i].world, inset: half(i)))
        for p in players { creatures[p].takeOff() }
        session.stage = .on
        if let teams { trace?("play baseball teams: " + teams.map { $0.map(name).joined(separator: ", ") }.joined(separator: " v ")) }
        trace?("play baseball bases: " + ([field.home] + field.bases).map { String(format: "(%.0f, %.0f)", $0.edge.x, $0.edge.y) }.joined(separator: " "))
        return true
    }

    /// Round every screen of `world`.
    func bounds(of world: EdgeWorld, inset: CGFloat) -> CGRect {
        let points = world.loops.flatMap(\.vertices)
        guard let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() else { return .infinite }
        return CGRect(x: x0 - inset, y: y0 - inset, width: x1 - x0 + inset * 2, height: y1 - y0 + inset * 2)
    }

    /// Just under the top of the screen over `point`.
    func boardPlace(over point: CGPoint, world: EdgeWorld, inset: CGFloat) -> CGPoint {
        let top = world.ceiling(over: point).map { $0.y + inset } ?? point.y + 500
        return CGPoint(x: point.x, y: top - 24)
    }

    func name(_ i: Int) -> String { creatures.indices.contains(i) ? character(forCreature: i).name : "?" }

    // MARK: Running

    func runSoccer(_ s: inout PlaySession, dt: Double) {
        guard var match = s.soccer, s.players.allSatisfy({ creatures[$0].isPlaying }) else { return endPlay(completed: false) }
        for event in match.update(dt: dt, using: &rng) { soccer(event, match, &s) }
        for p in match.players {
            let at = CGPoint(x: p.x, y: match.pitch.floorY + p.half + p.lift)
            creatures[p.index].face(p.facing)
            creatures[p.index].carry(to: at, rotation: p.rotation, pose: p.pose)
        }
        s.soccer = match
        runExtras(&s)
        if match.isFinished {
            let best = match.goalsBy.max { $0.value < $1.value }?.key ?? s.players[0]
            trace?("play soccer over: \(match.board(name))")
            for p in s.players { creatures[p].touchDown(standingFor: .infinity) }
            wrapUp(&s, speaker: best)
        }
    }

    private func soccer(_ event: Plays.Soccer.Event, _ match: Plays.Soccer, _ s: inout PlaySession) {
        switch event {
        case .kickoff(let by): trace?("play soccer \(name(by)) kicks off")
        case .touches(let by, let count): trace?("play soccer \(name(by)) keepy-uppy: \(count) touches")
        case .pass(let from, let to): trace?("play soccer \(name(from)) passes to \(name(to))")
        case .shot(let by): trace?("play soccer \(name(by)) shoots")
        case .header(let by): trace?("play soccer \(name(by)) heads it")
        case .goal(let by, _):
            let score = soccerScore(match)
            trace?("play soccer \(name(by)) scores \(score)")
            let goal = match.goals.min { abs($0.x - match.ball.position.x) < abs($1.x - match.ball.position.x) }
            // High over the goal, clear of the scorer's bubble.
            let at = CGPoint(x: goal.map { $0.x - $0.side * 160 } ?? match.ball.position.x, y: match.pitch.floorY + 230 * (s.ballGame?.scale ?? 2.5) / 2.5)
            cheer(tr("GOAL!"), at: at, &s)
            for k in 0..<3 {
                sparks.burst(at: CGPoint(x: (goal?.x ?? at.x) + CGFloat(k - 1) * 14, y: match.pitch.floorY + 30), inward: CGVector(dx: 0, dy: 1), using: &rng)
            }
            ballLine(.goal, by: by, &s, score: score)
        case .save(let by): trace?("play soccer \(name(by)) saves")
        case .woodwork(let by): trace?("play soccer \(name(by)) hits the bar")
        case .whiff(let by):
            trace?("play soccer \(name(by)) kicks the air")
            ballLine(.oops, by: by, &s, score: soccerScore(match))
        case .tackle(let by, let from): trace?("play soccer \(name(by)) slides in and takes it off \(name(from))")
        case .out(let by): trace?("play soccer out" + (by.map { " off \(name($0))" } ?? ""))
        case .throwIn(let by): trace?("play soccer \(name(by)) throws it in")
        case .wandersOff(let i):
            trace?("play soccer \(name(i)) wanders off")
            ballLine(.wander, by: i, &s, score: soccerScore(match))
        case .comesBack(let i): trace?("play soccer \(name(i)) comes back")
        case .keeperNow(let i): trace?("play soccer \(name(i)) goes in goal")
        case .over: break
        }
    }

    /// The score in short: "2-1" for two sides, each player's goals otherwise.
    func soccerScore(_ match: Plays.Soccer) -> String {
        switch match.lineup {
        case .solo: "\(match.goalsBy.values.reduce(0, +))"
        case .keeper: match.players.map { "\(match.goalsBy[$0.index, default: 0])" }.joined(separator: "-")
        default: "\(match.teamGoals[0])-\(match.teamGoals[1])"
        }
    }

    func runBaseball(_ s: inout PlaySession, dt: Double) {
        guard var game = s.baseball, s.players.allSatisfy({ creatures[$0].isPlaying }) else { return endPlay(completed: false) }
        for event in game.update(dt: dt, using: &rng) { baseball(event, game, &s) }
        for p in s.players {
            guard let pose = game.pose(of: p) else { continue }
            creatures[p].face(pose.facing)
            creatures[p].carry(to: pose.position, rotation: pose.rotation, pose: pose.pose)
        }
        s.baseball = game
        runExtras(&s)
        if game.isFinished {
            let best = game.runsBy.max { $0.value < $1.value }?.key ?? s.players[0]
            trace?("play baseball over: \(game.board(name))")
            for p in s.players { creatures[p].touchDown(standingFor: .infinity) }
            wrapUp(&s, speaker: best)
        }
    }

    private func baseball(_ event: Plays.Baseball.Event, _ game: Plays.Baseball, _ s: inout PlaySession) {
        let bases = ["first", "second", "third", "home"]
        switch event {
        case .pitch(let by): trace?("play baseball \(name(by)) pitches")
        case .toss(let by): trace?("play baseball \(name(by)) tosses it up")
        case .swing(let by, let result): trace?("play baseball \(name(by)) swings: \(result.rawValue)")
        case .strike(let by, let count): trace?("play baseball \(name(by)) strike \(count)")
        case .out(let by, let how):
            trace?("play baseball \(name(by)) is out, \(how)")
            if how == "struck out" { ballLine(.oops, by: by, &s, score: baseballScore(game)) }
        case .caught(let by): trace?("play baseball \(name(by)) catches it")
        case .fumble(let by):
            trace?("play baseball \(name(by)) drops it")
            ballLine(.oops, by: by, &s, score: baseballScore(game))
        case .runs(let by, let to): trace?("play baseball \(name(by)) runs to \(bases[min(3, max(0, to - 1))])")
        case .safe(let by, let at): trace?("play baseball \(name(by)) is safe at \(bases[min(3, max(0, at - 1))])")
        case .scored(let by, let score): trace?("play baseball \(name(by)) scores \(game.lineup == .solo ? "\(game.hits)" : score)")
        case .homeRun(let by, let runs):
            trace?("play baseball HOME RUN \(name(by)), \(runs) in")
            let exit = game.lastHomeRun ?? game.field.home.edge
            cheer(tr("HOME RUN!"), at: CGPoint(x: exit.x, y: exit.y - 140), &s)
            for k in 0..<6 {
                let point = CGPoint(x: exit.x + .random(in: -180...180, using: &rng), y: exit.y - .random(in: 30...170, using: &rng))
                s.ballGame?.fireworks.append((elapsed + 0.25 * Double(k) + 0.6, point))
            }
            ballLine(.homeRun, by: by, &s, score: baseballScore(game))
        case .fetch(let by): trace?("play baseball \(name(by)) fetches it")
        case .sidesChange(let inning, let batting): trace?("play baseball inning \(inning): \(batting.map(name).joined(separator: ", ")) to bat")
        case .ghost(let i, let base): trace?("play baseball \(name(i)) leaves a ghost on \(bases[min(3, max(0, base - 1))])")
        case .over: break
        }
    }

    func baseballScore(_ game: Plays.Baseball) -> String {
        game.lineup == .solo ? "\(game.hits)" : game.sideRuns.map(String.init).joined(separator: "-")
    }

    /// A cheer across the screen, popping up, for a little under two seconds.
    func cheer(_ text: String, at point: CGPoint, _ s: inout PlaySession) {
        let image = pixelText(text, PixelText.banner)
        let size = image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        var at = point
        if let b = s.ballGame?.bounds, !b.isInfinite {
            let w = size.width * (s.ballGame?.scale ?? 2.5) / 2 + 12, h = size.height * (s.ballGame?.scale ?? 2.5) / 2 + 12
            at = CGPoint(x: min(max(point.x, b.minX + w), b.maxX - w), y: min(max(point.y, b.minY + h), b.maxY - h))
        }
        s.ballGame?.banner = (image, size, at, elapsed, elapsed + 1.8)
    }

    private func runExtras(_ s: inout PlaySession) {
        guard var extras = s.ballGame else { return }
        while let next = extras.fireworks.first, next.at <= elapsed {
            extras.fireworks.removeFirst()
            sparks.burst(at: next.point, inward: CGVector(dx: 0, dy: 1), count: 10, using: &rng)
            sparks.burst(at: next.point, inward: CGVector(dx: 0, dy: -1), count: 6, using: &rng)
        }
        if let b = extras.banner, elapsed > b.until { extras.banner = nil }
        s.ballGame = extras
    }

    /// `text` in pixel letters, drawn once.
    func pixelText(_ text: String, _ style: PixelText.Style) -> CGImage? {
        let key = "\(style.size)|\(text)"
        if let made = pixelTexts[key] { return made }
        if pixelTexts.count > 60 { pixelTexts.removeAll() }
        let made = PixelText.image(text, style)
        pixelTexts[key] = made
        return made
    }

    // MARK: Words

    /// A line at a big moment: built in, or from the model for a goal or a home run.
    func ballLine(_ moment: Plays.Moment, by i: Int, _ s: inout PlaySession, score: String) {
        guard settings.playTalk, settings.talkEnabled, !voiceIsTaken, creatures.indices.contains(i) else { return }
        // A small moment keeps quiet when someone has only just spoken.
        guard moment.asksTheModel || elapsed - lastBallLine > 5 else { return }
        if !moment.asksTheModel {
            let key = "\(moment.rawValue) \(i)"
            guard s.ballGame?.said.contains(key) == false else { return }
            s.ballGame?.said.insert(key)
        }
        lastBallLine = elapsed
        let me = character(forCreature: i)
        let builtIn = Plays.cheerLine(by: me.name, moment)
        let situation = [timeOfDay] + s.players.prefix(4).map { describe($0) + "." }
        guard moment.asksTheModel, settings.brain != .script, let service = settings.chatClient() else {
            return sayBallLine(builtIn, by: i, situation: situation.joined(separator: " "), provider: AppSettings.Brain.script.title, model: "", cost: nil, tokens: nil)
        }
        let vars = ["speaker": me.name, "speakerKind": Banter.spoken(kind(ofCreature: i)), "speakerPersona": Banter.persona(me.persona),
                    "play": s.kind.title, "moment": moment.happening, "score": score, "situation": situation.joined(separator: " ")]
        let serial = s.serial
        Task { [weak self] in
            var line = "", cost: Double?, tokens: Int?
            do {
                let answer = try await service.line(system: Plays.lineSystemPrompt, user: Banter.render(Plays.cheerPrompt, vars))
                if var usage = answer.usage {
                    if service.provider == .lmStudio { usage.cost = 0 }       // a local model is free
                    cost = usage.cost
                    tokens = usage.promptTokens + usage.completionTokens
                    self?.spend.record(provider: service.provider, model: service.model, usage: usage, purpose: .ballGames)
                }
                line = Banter.cleanLine(answer.text, speaker: me.name, cut: answer.cut)
            } catch {
                FileHandle.standardError.write(Data("Ledgelings ball game: \(error)\n".utf8))
            }
            guard let self, play?.serial == serial else { return }
            if line.isEmpty {
                sayBallLine(builtIn, by: i, situation: vars["situation"]!, provider: AppSettings.Brain.script.title, model: "", cost: nil, tokens: nil)
            } else {
                sayBallLine(line, by: i, situation: vars["situation"]!, provider: service.provider.title, model: service.model,
                            cost: cost, tokens: tokens, builtIn: false)
            }
        }
    }

    private func sayBallLine(_ text: String, by i: Int, situation: String, provider: String, model: String,
                             cost: Double?, tokens: Int?, builtIn: Bool = true) {
        guard !text.isEmpty, creatures.indices.contains(i) else { return }
        say(text, from: i, builtIn: builtIn)
        history.record(ChatLog.Exchange(time: Date(), situation: situation, provider: provider, model: model,
                                        lines: [ChatLog.Line(speaker: character(forCreature: i).name, text: text)],
                                        cost: cost, tokens: tokens))
    }

    // MARK: Their story

    /// Who played whom: in a team game teammates; otherwise everyone together.
    func ballGamePairs(_ s: PlaySession) -> [(Int, Int)] {
        let groups: [[Int]]
        if let m = s.soccer, m.lineup == .teams { groups = (0...1).map { t in m.players.filter { $0.team == t }.map(\.index) } }
        else if let g = s.baseball, g.lineup == .teams { groups = g.sides }
        else { groups = [s.players] }
        return groups.flatMap { side in side.indices.flatMap { a in side.indices.filter { $0 > a }.map { (side[a], side[$0]) } } }
    }

    // MARK: Drawing

    func ballGameProps(_ s: PlaySession) -> [PropSnapshot] {
        var props: [PropSnapshot] = []
        func image(_ animation: String, _ time: Double = 0) -> CGImage? { playFrames.frame(animation: animation, time: time) }
        let extras = s.ballGame
        let scale = extras?.scale ?? 2.5
        if let m = s.soccer {
            for g in m.goals {
                // The post (the cell's mouth column) on the goal line, the cell's foot on the floor.
                let centre = CGPoint(x: g.x + g.side * (playCell.width / 2 - Plays.Soccer.Net.mouthColumn) * m.scale,
                                     y: m.pitch.floorY + playCell.height / 2 * m.scale)
                props.append(PropSnapshot(image: image("net"), position: centre, rotation: 0, scale: m.scale, mirrored: g.side < 0))
            }
            if m.ball.opacity > 0 {
                props.append(PropSnapshot(image: image("soccer", abs(m.ball.turn) / (.pi / 2) / 8), position: m.ball.position,
                                          rotation: 0, scale: m.scale, opacity: Float(m.ball.opacity), inFront: true))
            }
            props.append(board(m.board(name), at: extras?.boardAt, scale: scale))
        }
        if let g = s.baseball {
            for (n, base) in g.field.bases.enumerated() {
                let taken = g.bases[n]?.ghost == true
                props.append(PropSnapshot(image: image(taken ? "base-taken" : "base"), position: baseCentre(base, scale: scale),
                                          rotation: base.rotation, scale: scale))
            }
            props.append(PropSnapshot(image: image("base"), position: baseCentre(g.field.home, scale: scale), rotation: g.field.home.rotation, scale: scale))
            if let b = g.actor(g.batter), let pose = g.pose(of: g.batter), g.phase != .over, !b.isHopping {
                // The bat over the batter's shoulder, swung through in front of it.
                let up = CGVector(dx: -sin(pose.rotation), dy: cos(pose.rotation))
                let ahead = CGVector(dx: up.dy * pose.facing, dy: -up.dx * pose.facing)
                let hands = CGPoint(x: pose.position.x + up.dx * b.half * 0.2 + ahead.dx * b.half * 0.5,
                                    y: pose.position.y + up.dy * b.half * 0.2 + ahead.dy * b.half * 0.5)
                let swing = g.batSwing
                let angle = pose.rotation + Double(-pose.facing) * (0.5 - swing * 2.3)
                let along = CGVector(dx: -sin(angle), dy: cos(angle))
                props.append(PropSnapshot(image: image("bat"), position: CGPoint(x: hands.x + along.dx * 6 * scale, y: hands.y + along.dy * 6 * scale),
                                          rotation: angle, scale: scale, inFront: true))
            }
            if let at = g.ballPosition {
                props.append(PropSnapshot(image: image("baseball"), position: at, rotation: 0, scale: scale, inFront: true))
            }
            props.append(board(g.board(name), at: extras?.boardAt, scale: scale))
        }
        if let b = extras?.banner {
            let age = elapsed - b.since
            let pop = CGFloat(min(1, 0.5 + age * 4))
            let fade = Float(min(1, max(0, (b.until - elapsed) / 0.4)))
            props.append(PropSnapshot(image: b.image, position: b.at, rotation: 0, scale: scale * pop, opacity: fade, inFront: true, size: b.size))
        }
        return props
    }

    /// A base lies flat on its edge, its bag just inside it.
    func baseCentre(_ place: Plays.Place, scale: CGFloat) -> CGPoint {
        // The bag's outline ends 3 sheet pixels below the cell's middle (rows 12 to 16 of 28).
        let below = (17 - playCell.height / 2) * scale
        return CGPoint(x: place.edge.x + place.inward.dx * below, y: place.edge.y + place.inward.dy * below)
    }

    /// The scoreboard: pixel letters on a dark plate at `at`.
    func board(_ text: String, at: CGPoint?, scale: CGFloat) -> PropSnapshot {
        let image = pixelText(text, PixelText.board)
        let size = image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        let boardScale = max(2, (scale * 0.8).rounded())
        // Behind the creatures and their bubbles: a line said near the top stays readable.
        return PropSnapshot(image: image, position: at ?? .zero, rotation: 0, scale: boardScale, size: size)
    }
}
