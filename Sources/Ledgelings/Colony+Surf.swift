import AppKit
import LedgelingsCore

/// Surfing (`Plays.Surf`): the tide comes in along the widest floor (the
/// screen's bottom edge), everyone who plays leaps there first, and waves roll
/// along it. The players are off their edges (`playing`) for the whole session
/// and the colony puts each, and its board, where the game says, every frame.
/// The water is drawn in code, a fresh picture each frame in square pixels at
/// the creatures' own scale: flat see-through bands, a 1-pixel dark top, a
/// light line under it, the wave's lip thrown forward over a hollow, foam, and
/// the drops of a splash flying (particles). Boards, splashes and spray come
/// from the play sheet. The scoreboard sits at the top, as in the ball games.
extension Colony {

    /// What surfing needs besides the game: drops in the air, splashes, its scale.
    struct Surfing {
        var scale: CGFloat
        var drops: [Drop] = []
        var splashes: [(at: CGPoint, since: Double)] = []
        /// Each rider's board on the play sheet.
        var boards: [Int: String] = [:]

        struct Drop {
            var position: CGPoint
            var velocity: CGVector
            var life: Double
        }
    }

    /// The colours of the water, traced flat from the owner's chosen Wixel wave
    /// (its soft edges taken off): the body, the deep band, the top's outline,
    /// the light line and the streaks, the foam. Nearly solid here: how much of
    /// the desktop shows through is the owner's, `surfWaterOpacity`, laid over it all.
    enum Water {
        static let body: UInt32 = rgba(24, 166, 246, 225)
        static let deep: UInt32 = rgba(6, 134, 230, 240)
        static let outline: UInt32 = rgba(8, 70, 198, 255)
        static let light: UInt32 = rgba(88, 228, 246, 215)
        static let foam: UInt32 = rgba(244, 246, 250, 255)
        /// The lip thrown over the hollow: the body's colour, nearly solid, so it reads against the sky.
        static let lip: UInt32 = rgba(16, 150, 240, 235)

        static func rgba(_ r: UInt32, _ g: UInt32, _ b: UInt32, _ a: UInt32) -> UInt32 {
            // Premultiplied, as the bitmap context below keeps it, little-endian RGBA.
            let pr = r * a / 255, pg = g * a / 255, pb = b * a / 255
            return pr | (pg << 8) | (pb << 16) | (a << 24)
        }
    }

    // MARK: Starting

    /// Surfing is on the widest floor, as soccer is: everyone leaps there first.
    func beginSurf(_ session: inout PlaySession) -> Bool {
        beginSoccer(&session)
    }

    /// Everyone is on the floor: the tide comes in.
    func startSurf(_ session: inout PlaySession) -> Bool {
        guard let pitch = session.pitch else { return false }
        let players = session.players
        var halves: [Int: CGFloat] = [:], at: [Int: CGFloat] = [:]
        for p in players {
            halves[p] = half(p)
            at[p] = creatures[p].position.x
            creatures[p].takeOff()
        }
        let scale = CGFloat(players.map { sizes[$0] }.reduce(0, +) / Double(players.count))
        let body = players.map { half($0) * 2 }.reduce(0, +) / CGFloat(players.count)
        session.surf = Plays.Surf(players: players, halves: halves, at: at, floorY: pitch.floorY, span: pitch.span,
                                  waveHeight: body * CGFloat(settings.surfWaveHeight), depth: body * AppSettings.surfDepth,
                                  waves: settings.surfWaves, length: settings.surfMinutes * 60, using: &rng)
        var surfing = Surfing(scale: scale)
        for p in players { surfing.boards[p] = "board-\(Plays.Surf.board(of: name(p)))" }
        session.surfing = surfing
        session.ballGame = BallGame(boardAt: boardPlace(over: CGPoint(x: (pitch.span.lowerBound + pitch.span.upperBound) / 2, y: pitch.floorY + half(players[0])),
                                                        world: creatures[players[0]].world, inset: half(players[0])), scale: scale,
                                    bounds: bounds(of: creatures[players[0]].world, inset: half(players[0])))
        trace?("play surf boards: " + players.map { "\(name($0)) \(surfing.boards[$0] ?? "?")" }.joined(separator: ", "))
        return true
    }

    // MARK: Running

    func runSurf(_ s: inout PlaySession, dt: Double) {
        guard var game = s.surf, s.players.allSatisfy({ creatures[$0].isPlaying }) else { return endPlay(completed: false) }
        for event in game.update(dt: dt, using: &rng) { surf(event, game, &s) }
        for r in game.riders {
            creatures[r.index].face(r.facing)
            creatures[r.index].carry(to: CGPoint(x: r.x, y: r.y), rotation: r.rotation, pose: r.pose)
        }
        s.surf = game
        runDrops(&s, dt: dt)
        runExtras(&s)
        if game.isFinished {
            trace?("play surf over: \(game.board(name))")
            for p in s.players { creatures[p].touchDown(standingFor: .infinity) }
            let best = game.winners.first ?? s.players[0]
            wrapUp(&s, speaker: best)
        }
    }

    private func surf(_ event: Plays.Surf.Event, _ game: Plays.Surf, _ s: inout PlaySession) {
        switch event {
        case .tideIn: trace?("play surf the tide comes in")
        case .wave(let n, let way): trace?("play surf wave \(n) rolls in \(way > 0 ? "left to right" : "right to left")")
        case .caught(let by):
            trace?("play surf \(name(by)) catches the wave")
            ballLine(.wave, by: by, &s, score: game.board(name))
        case .missed(let by): trace?("play surf \(name(by)) lets it roll by")
        case .trick(let by, let trick):
            trace?("play surf \(name(by)) lands a \(trick.rawValue)")
            ballLine(.trick, by: by, &s, score: game.board(name))
        case .wipeout(let by, let at):
            trace?(String(format: "play surf %@ wipes out at %.0f", name(by), at.x))
            splash(at: at, &s)
            cheer(tr("WIPEOUT!"), at: CGPoint(x: at.x, y: at.y + 140 * (s.surfing?.scale ?? 2.5) / 2.5), &s)
            ballLine(.wipeout, by: by, &s, score: game.board(name))
        case .kickOut(let by, let points): trace?("play surf \(name(by)) rides it out: \(points) points")
        case .back(let by): trace?("play surf \(name(by)) waits for a wave")
        case .tideOut: trace?("play surf the tide goes out")
        case .won(let by):
            trace?("play surf won by \(by.isEmpty ? "nobody" : by.map(name).joined(separator: " and "))")
            if let first = by.first { ballLine(.surfWin, by: first, &s, score: game.board(name)) }
        case .over: break
        }
    }

    /// A splash: the sheet's crown rising and falling, and drops flying out of it.
    private func splash(at point: CGPoint, _ s: inout PlaySession) {
        guard var surfing = s.surfing else { return }
        surfing.splashes.append((point, elapsed))
        for _ in 0..<14 {
            let v = CGVector(dx: .random(in: -160...160, using: &rng), dy: .random(in: 160...380, using: &rng))
            surfing.drops.append(.init(position: point, velocity: v, life: .random(in: 0.6...1.1, using: &rng)))
        }
        s.surfing = surfing
    }

    private func runDrops(_ s: inout PlaySession, dt: Double) {
        guard var surfing = s.surfing, let game = s.surf else { return }
        for k in surfing.drops.indices {
            surfing.drops[k].velocity.dy -= Plays.gravity * 0.6 * CGFloat(dt)
            surfing.drops[k].position.x += surfing.drops[k].velocity.dx * CGFloat(dt)
            surfing.drops[k].position.y += surfing.drops[k].velocity.dy * CGFloat(dt)
            surfing.drops[k].life -= dt
        }
        surfing.drops.removeAll { $0.life <= 0 || ($0.velocity.dy < 0 && $0.position.y < game.surface(at: $0.position.x)) }
        // Spray off the lip of a wave someone rides.
        if let wave = game.wave, game.riders.contains(where: \.isRiding), Double.random(in: 0..<1, using: &rng) < dt * 12 {
            let top = CGPoint(x: wave.crest + game.way * game.height * 0.5, y: game.surface(at: wave.crest) - game.height * 0.4)
            surfing.drops.append(.init(position: top, velocity: CGVector(dx: game.way * .random(in: 60...160, using: &rng), dy: .random(in: 40...160, using: &rng)),
                                       life: .random(in: 0.4...0.8, using: &rng)))
        }
        surfing.splashes.removeAll { elapsed - $0.since > 0.6 }
        s.surfing = surfing
    }

    /// Stop surfing at once: the water, the boards and the board go, everyone back on the edge.
    func stopSurf() {
        guard play?.kind == .surf else { return }
        endPlay(completed: false)
        fadingBoard = nil
    }

    // MARK: Drawing

    func surfProps(_ s: PlaySession) -> [PropSnapshot] {
        guard let game = s.surf, let surfing = s.surfing else { return [] }
        var props: [PropSnapshot] = []
        func image(_ animation: String, _ time: Double = 0) -> CGImage? { playFrames.frame(animation: animation, time: time) }
        let scale = surfing.scale
        if let water = waterImage(game, surfing) { props.append(water) }
        for r in game.riders {
            let name = surfing.boards[r.index] ?? "board-0"
            props.append(PropSnapshot(image: image(name), position: r.board, rotation: r.boardRotation, scale: scale, mirrored: r.facing < 0))
            if r.isRiding {
                let tail = CGPoint(x: r.board.x - r.facing * 12 * scale, y: r.board.y + 3 * scale)
                props.append(PropSnapshot(image: image("spray", elapsed), position: tail, rotation: 0, scale: scale, mirrored: r.facing < 0, inFront: true))
            }
        }
        for splash in surfing.splashes {
            // The crown's pool sits on the cell's bottom rows: lift the cell so it sits on the water.
            let at = CGPoint(x: splash.at.x, y: splash.at.y + (playCell.height / 2 - 2) * scale)
            let big = scale * 1.6
            let lifted = CGPoint(x: at.x, y: splash.at.y + (playCell.height / 2 - 2) * big)
            props.append(PropSnapshot(image: image("splash", elapsed - splash.since), position: lifted, rotation: 0, scale: big, inFront: true))
        }
        return props
    }

    /// The water as one picture in square pixels, `scale` points each: from the
    /// screen's floor up to the wave's top and the drops above it.
    func waterImage(_ g: Plays.Surf, _ surfing: Surfing) -> PropSnapshot? {
        guard g.tide > 0 else { return nil }
        let scale = surfing.scale
        let x0 = g.span.lowerBound - 30, x1 = g.span.upperBound + 30
        let w = Int(((x1 - x0) / scale).rounded(.up)), h = Int(((g.depth + g.height * 2.2) / scale).rounded(.up)) + 4
        guard w > 0, h > 0, w * h < 4_000_000 else { return nil }
        var pixels = [UInt32](repeating: 0, count: w * h)
        func put(_ x: Int, _ y: Int, _ c: UInt32) {
            guard x >= 0, x < w, y >= 0, y < h else { return }
            pixels[(h - 1 - y) * w + x] = c
        }
        func px(_ xPoints: CGFloat) -> Int { Int(((xPoints - x0) / scale).rounded(.down)) }
        let deep = max(1, Int(g.depth * CGFloat(g.tide) / scale / 2))
        let frame = Int(elapsed * 8)
        func noise(_ a: Int, _ b: Int) -> UInt32 {
            var z = UInt32(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ frame &* 83_492_791)
            z ^= z >> 13; z &*= 0x5bd1e995; z ^= z >> 15
            return z % 100
        }
        var tops = [Int](repeating: 0, count: w)
        for x in 0..<w {
            let xp = x0 + (CGFloat(x) + 0.5) * scale
            let top = Int(((g.surface(at: xp) - g.floorY) / scale).rounded())
            tops[x] = top
            guard top > 0 else { continue }
            // The wave's body carries light streaks slanting up toward the crest, as the chosen wave does.
            let rising = g.lift(at: xp) > 2 * scale
            for y in 0..<top {
                let streak = rising && y > top * 2 / 5 && y < top - 3 && ((x * (g.way > 0 ? 1 : -1) + y * 2) % 17 + 17) % 17 < 2
                put(x, y, streak ? Water.light : y < deep ? Water.deep : Water.body)
            }
            put(x, top - 1, Water.outline)
            if top - 2 >= deep { put(x, top - 2, Water.light) }
        }
        // Little ripples on the calm water, drifting.
        for x in stride(from: (frame / 2) % 11, to: w, by: 11) where g.lift(at: x0 + CGFloat(x) * scale) == 0 && tops[x] > 3 {
            put(x, tops[x] - 2, Water.foam); put(x + 1, tops[x] - 2, Water.foam)
        }
        if let wave = g.wave {
            let c = px(wave.crest), way = g.way > 0 ? 1 : -1
            let height = Int(g.height * CGFloat(g.tide) / scale), lift = Int(g.lift(at: wave.crest) / scale)
            let top = (c >= 0 && c < w ? tops[c] : Int((g.depth + g.height) / scale))
            // The lip, thrown forward off the crest and drooping, a hollow under it.
            let length = max(3, Int(Double(height) * 0.6))
            if lift > 4 {
                for k in 0...length {
                    let u = Double(k) / Double(length)
                    let y = top + 1 - Int(u * u * Double(height) * 0.4)
                    let thick = max(3, Int(7 * (1 - u)) + 3)
                    let x = c + way * k
                    put(x, y, Water.outline)
                    for t in 0..<thick { put(x, y - 1 - t, t < 2 ? Water.foam : t < 4 ? Water.light : Water.lip) }
                    put(x, y - thick - 1, Water.outline)
                }
                // The tip curls back under, toward the face: a hook of foam.
                let tip = (x: c + way * length, y: top + 1 - Int(Double(height) * 0.4))
                for k in 1...max(1, height / 6) {
                    put(tip.x - way * (k / 2), tip.y - 1 - k, Water.foam)
                    put(tip.x - way * (k / 2) + way, tip.y - 1 - k, Water.outline)
                }
                for k in 0..<6 where noise(k, 1) < 70 { put(tip.x + way * Int(noise(k, 2) % 5), tip.y - 2 - Int(noise(k, 3) % 8), Water.foam) }
            }
            // Foam along the crest's back, and whitewater at the foot of the face.
            let back = Int(g.backWidth * 0.35 / scale), face = Int(g.faceWidth / scale)
            for k in -back...0 {
                let x = c + way * k
                guard x >= 0, x < w, tops[x] > 2 else { continue }
                if noise(x, 4) < 60 { put(x, tops[x] - 1, Water.foam) }
                if noise(x, 5) < 30 { put(x, tops[x] - 2, Water.foam) }
                if noise(x, 6) < 10 { put(x, tops[x], Water.foam) }
            }
            for k in Int(Double(face) * 0.55)...max(Int(Double(face) * 0.55), Int(Double(face) * 1.05)) {
                let x = c + way * k
                guard x >= 0, x < w, tops[x] > 2 else { continue }
                if noise(x, 7) < 50 { put(x, tops[x] - 1, Water.foam) }
            }
        }
        // The drops, two pixels each.
        for d in surfing.drops {
            let x = px(d.position.x), y = Int(((d.position.y - g.floorY) / scale).rounded())
            put(x, y, Water.foam); put(x + 1, y, Water.light); put(x, y - 1, Water.light)
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        _ = info
        let centre = CGPoint(x: x0 + CGFloat(w) * scale / 2, y: g.floorY + CGFloat(h) * scale / 2)
        return PropSnapshot(image: image, position: centre, rotation: 0, scale: scale, opacity: Float(settings.surfWaterOpacity / 100),
                            size: CGSize(width: w, height: h))
    }
}
