// A speckled egg rocks three times, each rock cracking it further with warm light leaking out, then pops: light
// pours out of the opening and lit shell halves tumble away. pixelfx's `spawn/egg-hatch` (MIT), after Sprite
// Fusion's open-source ice shatter (https://www.spritefusion.com/pixel-art-vfx/ice), MIT,
// Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXEggHatch: FXEffect {
    static let meta = FXMeta(id: "spawn/egg-hatch", size: (120, 96), origin: (60, 84), duration: 3.1, loop: false,
                             palette: ["#1e1826", "#4a3e52", "#857684", "#c4b4ac", "#ece0d2", "#fffaf0"], seed: 31)
    static let glowRamp = ["#ff8a2a", "#ffd25a", "#fff3c0"], speckle = "#9a6a52"
    static let wobbles: [(Double, Double)] = [(0.3, 0.11), (0.85, 0.19), (1.4, 0.28)], POP = 1.98, EW = 16, EH = 20, ZY = 11
    static let LIGHT = [-0.72, 0.5, 0.48] // from the upper left, a little toward us
    static let CRUMBLE = meta.duration - 0.55
    static let cross = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// One pixel of the egg: x across from its middle, y up from its base.
    struct Egg { let x: Int, y: Int, u: Double, v: Double, half: Double; var c: FXColor = 0, lit = 0.0 }
    static let shape: [Egg] = {
        var out: [Egg] = []
        for y in 0..<EH {
            for x in (-EW / 2)..<(EW / 2) {
                let v = (Double(y) + 0.5) / Double(EH), u = (Double(x) + 0.5) / Double(EW / 2), q = 2 * v - 1
                let half = Swift.max(0, 1 - q * q).squareRoot() * (1.08 - 0.22 * v)
                if abs(u) <= half { out.append(Egg(x: x, y: y, u: u, v: v, half: half)) }
            }
        }
        return out
    }()
    @inline(__always) static func key(_ x: Int, _ y: Int) -> Int { (x + 512) * 1024 + (y + 512) }

    final class Piece {
        let id: Int, r: Double, map: [Int: (FXColor, Bool)], max: Double, born: Double
        var x: Double, y: Double, vx: Double, vy: Double, a = 0.0, va: Double, life: Double, rest = false
        init(id: Int, x: Double, y: Double, vx: Double, vy: Double, va: Double, r: Double, map: [Int: (FXColor, Bool)], life: Double, born: Double) {
            self.id = id; self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.va = va; self.r = r; self.map = map
            self.life = life; self.max = life; self.born = born
        }
    }

    let o: FXOptions
    let C: [FXColor], G: [FXColor], SPK: FXColor
    let R: Rng
    var egg: [Egg]
    var at: [Int: Int] = [:]
    var crack: [Int: Int] = [:]
    var zig: [Int] = []
    var near: [[Int: Double]] = []
    let ps: FXParticles
    let lights = FXLights()
    let bits = FXBits(ground: { _ in 0 })
    var pieces: [Piece] = []
    var t = 0.0, popped = false, crumbled = false, cupA = 0.0, cupV = 0.0
    var done = [false, false, false]

    init(_ o: FXOptions) {
        self.o = o
        let C = FX.fit(o.palette, 6), G = FX.fit(FX.ramp(Self.glowRamp), 3), SPK = FX.hex(Self.speckle), R = Rng(o.seed), W = FX.white
        self.C = C; self.G = G; self.SPK = SPK; self.R = R
        ps = FXParticles(rng: R, ground: { _ in 0 }, sparks: [W, G[2], G[1], G[0]])
        egg = Self.shape
        for (i, e) in egg.enumerated() { at[Self.key(e.x, e.y)] = i }
        let has = { [at] (x: Int, y: Int) in at[Self.key(x, y)] != nil }
        // shading: a round shell lit from the upper left, a core shadow, a rim of bounce light on the dark side
        let L = Self.LIGHT
        for i in egg.indices {
            let e = egg[i]
            let nx = FX.clamp(e.u / Swift.max(0.05, e.half), -1, 1), ny = (2 * e.v - 1) * 0.9, nz = Swift.max(0, 1 - nx * nx - ny * ny).squareRoot()
            let d = nx * L[0] + ny * L[1] + nz * L[2], edge = !has(e.x - 1, e.y) || !has(e.x + 1, e.y) || !has(e.x, e.y - 1) || !has(e.x, e.y + 1)
            var c = d > 0.9 ? W : d > 0.62 ? C[5] : d > 0.32 ? C[4] : d > 0.02 ? C[3] : d > -0.3 ? C[2] : C[1]
            if edge && nx > 0.25 && ny < 0.55 { c = C[3] } // rim light on the shadow side
            else if FX.rand(Double(e.x), Double(e.y), 3) < 0.08 && e.v > 0.12 && !edge { c = d > 0.2 ? SPK : FX.mix(SPK, C[1], 0.5) }
            egg[i].c = c
            egg[i].lit = d
        }
        // cracks: three stages, the last a zigzag right round the egg where the top breaks off
        func walk(_ x: Double, _ y: Double, _ a: Double, _ len: Int, _ s: Int) {
            var x = x, y = y, a = a, px = FX.round(x), py = FX.round(y)
            for i in 0..<len {
                let side = (i % 2 != 0 ? 1.0 : -1.0) * R.range(0.6, 1.3)
                a += R.range(-0.25, 0.25)
                x += cos(a) * 1.8 - sin(a) * side * 0.6
                y += sin(a) * 1.8 + cos(a) * side * 0.6
                let nx = FX.round(x), ny = FX.round(y), n = Swift.max(abs(nx - px), abs(ny - py))
                var j = 1.0
                while j <= n {
                    let k = Self.key(Int(FX.round(px + ((nx - px) * j) / n)), Int(FX.round(py + ((ny - py) * j) / n)))
                    if at[k] == nil { return }
                    if crack[k] == nil { crack[k] = s }
                    j += 1
                }
                px = nx; py = ny
            }
        }
        walk(2, 15, -2.2, 3, 0)
        walk(2, 15, 0.3, 2, 0)
        walk(-2, 13, -0.6, 3, 1)
        walk(-2, 13, 2.7, 3, 1)
        walk(3, 11, 1.9, 2, 1)
        walk(2, 15, 1.5, 2, 1)
        for x in (-Self.EW / 2)..<(Self.EW / 2) {
            let m = (x + 8) % 3, y = Self.ZY + (m == 0 ? 1 : m == 1 ? 0 : -1)
            zig.append(y)
            if has(x, y) { crack[Self.key(x, y)] = 2 }
        }
        // how close each pixel of shell is to an open crack, per stage: light shows through the shell round them
        let cracks = crack.map { (k, s) in (k / 1024 - 512, k % 1024 - 512, s) }
        near = (0..<3).map { s in
            let pts = cracks.filter { $0.2 <= s }
            var m: [Int: Double] = [:]
            for e in egg {
                var best = 9.0
                for (cx, cy, _) in pts { best = Swift.min(best, hypot(Double(cx - e.x), Double(cy - e.y))) }
                m[Self.key(e.x, e.y)] = best
            }
            return m
        }
    }

    func zigAt(_ x: Int) -> Int { zig[Swift.min(zig.count - 1, Swift.max(0, x + Self.EW / 2))] }
    func cell(_ x: Int, _ y: Int) -> Egg? { at[Self.key(x, y)].map { egg[$0] } }

    static func stage(_ t: Double) -> Int { t > wobbles[2].0 + 0.05 ? 3 : t > wobbles[1].0 + 0.05 ? 2 : t > wobbles[0].0 + 0.05 ? 1 : 0 }
    /// The rock: a damped swing about the base, each one harder; a shiver just before it pops.
    static func angle(_ t: Double) -> Double {
        var a = 0.0
        for (t0, amp) in wobbles {
            let u = t - t0
            if u > 0 && u < 0.55 { a += amp * sin(u * 22) * exp(-u * 5) }
        }
        if t > POP - 0.14 && t < POP { a += 0.05 * sin(t * 120) }
        return a
    }
    /// The light inside: grows with each crack, flashes at the pop, then dies down in the empty cup.
    static func inner(_ t: Double) -> Double {
        let st = Double(stage(t))
        return t < POP ? st / 3 + 0.25 * Swift.max(0, sin(t * 9)) * (st / 3) : 1.6 * exp(-(t - POP) * 2.6)
    }

    /// Break part of the shell into pieces round a few seeds; each keeps its lit outside and a hot broken edge.
    func breakUp(_ keep: (Int, Int) -> Bool, _ n: Int, _ v: (Double, Double) -> (Double, Double), _ life: () -> Double) {
        let R = self.R, C = self.C, EW = Double(Self.EW)
        var seeds: [(Double, Double)] = []
        for _ in 0..<n { let sx = R.range(-EW / 2 + 1, EW / 2 - 1); seeds.append((sx, R.range(0, Double(Self.EH)))) }
        var order: [Int] = [], cells: [Int: [Egg]] = [:]
        for e in egg {
            if !keep(e.x, e.y) { continue }
            var best = 0, bd = 1e9
            for (i, (sx, sy)) in seeds.enumerated() {
                let d = hypot(Double(e.x) - sx, Double(e.y) - sy)
                if d < bd { bd = d; best = i }
            }
            if cells[best] == nil { cells[best] = []; order.append(best) }
            cells[best]!.append(e)
        }
        for ci in order {
            let px = cells[ci]!
            var cx = 0.0, cy = 0.0
            for e in px { cx += Double(e.x) + 0.5; cy += Double(e.y) + 0.5 }
            cx /= Double(px.count); cy /= Double(px.count)
            var map: [Int: (FXColor, Bool)] = [:]
            let mine = Set(px.map { Self.key($0.x, $0.y) })
            for e in px {
                let edge = Self.cross.contains { (dx, dy) in !mine.contains(Self.key(e.x + dx, e.y + dy)) && at[Self.key(e.x + dx, e.y + dy)] != nil }
                // lit by the flash: no piece flies off in shadow
                let c = e.c == C[1] || e.c == C[2] ? C[3] : e.c
                map[Self.key(Int(FX.round(Double(e.x) + 0.5 - cx)), Int(FX.round(-(Double(e.y) + 0.5 - cy))))] = (c, edge)
            }
            var r = -Double.infinity
            for e in px { r = Swift.max(r, hypot(Double(e.x) + 0.5 - cx, Double(e.y) + 0.5 - cy)) }
            r += 1
            let (vx, vy) = v(cx, cy), l = life()
            pieces.append(Piece(id: pieces.count + 1, x: cx, y: -cy, vx: vx, vy: vy, va: R.range(-10, 10), r: r, map: map, life: l, born: t))
        }
    }

    func pop() {
        let R = self.R, C = self.C, G = self.G, ZY = Double(Self.ZY), W = FX.white
        popped = true
        breakUp({ x, y in y >= self.zigAt(x) }, 6, { cx, _ in (cx * R.range(8, 13) + R.range(-14, 14), -R.range(140, 210)) }, { R.range(0.95, 1.15) })
        for _ in 0..<14 {
            let a = -Double.pi / 2 + R.range(-1.2, 1.2), sp = R.range(70, 170)
            let x = R.range(-5, 5), y = -ZY - R.range(0, 4), life = R.range(0.55, 0.85), an = R.range(0, FX.tau), va = R.range(-20, 20), s = R.range(1.2, 2.4)
            let c = R.pick([C[5], C[5], C[4], G[2]])
            bits.add(FXBits.Bit(kind: .shard, x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp, a: an, va: va, s: s, c: c, g: 0.9, drag: 0.6, bounce: 0.3, life: life))
        }
        for _ in 0..<12 {
            let a = -Double.pi / 2 + R.range(-1.1, 1.1), sp = R.range(50, 110)
            ps.spawn(.star, R.range(-3, 3), -ZY - 2, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.9), R.pick([W, G[2], G[1]]), R.range(1, 2.2))
        }
        for _ in 0..<10 {
            let a = -Double.pi / 2 + R.range(-1, 1), sp = R.range(100, 200)
            ps.spawn(.spark, R.range(-3, 3), -ZY - 1, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.45))
        }
        // a puff of pale dust at the base, gone in a few frames
        for _ in 0..<4 {
            let s = R.sign()
            ps.spawn(.dust, s * R.range(5, 8), -1, s * R.range(25, 50), -R.range(2, 6), R.range(0.15, 0.25), C[5], R.range(1, 1.8))
        }
        lights.add(0, -ZY - 10, 40, G[1], 0.9, 0.55)
        lights.add(0, -ZY - 2, 18, W, 0.9, 0.12)
        cupV = R.sign() * 3
    }

    func update(_ dt: Double) {
        let R = self.R, C = self.C, G = self.G, ZY = Double(Self.ZY), W = FX.white
        t += dt
        // each rock opens more crack: a tick of light, a chip or two of shell, a puff at the base
        for (i, (t0, _)) in Self.wobbles.enumerated() where !done[i] && t >= t0 + 0.05 {
            done[i] = true
            let fi = Double(i)
            lights.add(i == 1 ? -3 : 2, -14 + fi, 8 + fi * 2, G[1], 0.25 + fi * 0.08, 0.18)
            for _ in 0..<(2 + i * 2) {
                ps.spawn(.star, R.range(-5, 5), -R.range(8, 17), R.range(-20, 20), -R.range(10, 30), R.range(0.25, 0.5), R.pick([W, G[2]]), R.range(0.6, 1.4))
            }
            for _ in 0..<(i + 1) {
                let x = R.range(-4, 4), y = -R.range(10, 16), vx = R.range(-50, 50), vy = -R.range(40, 90), life = R.range(0.5, 0.8)
                let a = R.range(0, FX.tau), va = R.range(-20, 20), s = R.range(1, 1.6)
                bits.add(FXBits.Bit(kind: .shard, x: x, y: y, vx: vx, vy: vy, a: a, va: va, s: s, c: C[4], g: 0.9, drag: 0.5, bounce: 0.3, life: life))
            }
            ps.spawn(.dust, R.sign() * R.range(5, 7), -0.5, R.sign() * R.range(8, 18), -R.range(1, 3), R.range(0.15, 0.25), C[5], R.range(0.8, 1.4))
        }
        if !popped && t >= Self.POP { pop() }
        // light keeps welling up out of the empty cup for a moment: something came out of there
        if popped && t < Self.POP + 0.6 && R.chance(0.35) {
            ps.spawn(.mote, R.range(-4, 4), -ZY - 1, R.range(-8, 8), -R.range(40, 80), Swift.min(R.range(0.4, 0.8), Self.meta.duration - 0.1 - t), R.pick([G[2], G[1], W]), 0.7)
        }
        if popped && !crumbled && t >= Self.CRUMBLE {
            crumbled = true
            breakUp({ x, y in y < self.zigAt(x) }, 4, { cx, _ in (cx * R.range(4, 8), -R.range(40, 80)) }, { R.range(0.38, 0.48) })
            for _ in 0..<3 { ps.spawn(.dust, R.range(-6, 6), -1, R.sign() * R.range(10, 25), -R.range(2, 6), R.range(0.15, 0.25), C[5], R.range(1, 1.6)) }
        }
        if popped {
            cupV += (-cupA * 90 - cupV * 4) * dt
            cupA += cupV * dt
        }
        var i = pieces.count - 1
        while i >= 0 {
            defer { i -= 1 }
            let q = pieces[i]
            q.life -= dt
            if q.life <= 0 { pieces.remove(at: i); continue }
            if q.rest { continue }
            q.vy += 900 * dt
            q.vx -= q.vx * 0.6 * dt
            q.x += q.vx * dt
            q.y += q.vy * dt
            q.a += q.va * dt
            let g = -q.r * 0.45
            if q.y > g && q.vy > 0 {
                q.y = g
                if q.vy > 80 { q.vy *= -0.35; q.vx *= 0.6; q.va *= 0.5 } else { q.rest = true; q.vx = 0; q.vy = 0 }
            }
        }
        bits.update(dt)
        ps.update(dt)
        lights.update(dt)
    }

    func drawBack(_ p: Painter, _ _t: Double) {
        let t = self.t
        // a soft contact shadow under the egg, shifting as it rocks
        if !crumbled {
            let sx = popped ? 0 : -Self.angle(t) * 8, k = popped ? 1 - FX.smooth(Self.POP, Self.CRUMBLE, t) * 0.4 : 1
            for y in -1...1 {
                for x in -10...10 {
                    let dx = (Double(x) + 0.5 - sx) / 9.5, dy = (Double(y) + 0.5) / 1.8, d = dx * dx + dy * dy
                    if d < 1 { p.blend(Double(x), Double(y), C[0], 0.5 * k * (1 - d)) }
                }
            }
        }
        // warm light on the floor as it leaks out
        let g = Self.inner(t)
        if g > 0.05 { p.glow(0, -3, 22, G[0], 0.18 * Swift.min(1.2, g)) }
        ps.draw(p, .back)
    }

    func draw(_ p: Painter, _ _t: Double) {
        let C = self.C, G = self.G, SPK = self.SPK, W = FX.white, t = self.t, popped = self.popped
        let st = Self.stage(t), a = popped ? cupA * 0.03 : Self.angle(t), ca = cos(a), sa = sin(a), g = Self.inner(t)
        let ZY = Double(Self.ZY), EH = Double(Self.EH)
        if !crumbled {
            p.shade(-12, -EH - 4, 12, 1) { x, y, out in
                let ux = Int(FX.floor(x * ca + y * sa)), uy = Int(FX.floor(-(-x * sa + y * ca)))
                let e = self.cell(ux, uy)
                let inside = e != nil && !(popped && uy >= self.zigAt(ux))
                guard let e, inside else {
                    // a dark outline holds the egg's shape
                    let n = Self.cross.contains { (dx, dy) in self.cell(ux + dx, uy + dy) != nil && !(popped && uy + dy >= self.zigAt(ux + dx)) }
                    if n && !(popped && uy >= self.zigAt(ux) && uy <= self.zigAt(ux) + 1) { out.c = C[0] }
                    return 0
                }
                let cs = self.crack[Self.key(ux, uy)]
                if popped {
                    // the cup: its broken rim burns with the light inside, cooling as it fades
                    let rim = uy >= self.zigAt(ux) - 1
                    out.c = rim ? (g > 0.9 ? W : g > 0.4 ? G[2] : g > 0.12 ? G[1] : C[4]) : e.c
                    if rim { out.k = 0.25 * g; out.l = G[1] }
                    return 0
                }
                if let cs, cs < st {
                    // an open crack: deep orange light in the gap, flashing white the moment it opens
                    let fresh = t - Self.wobbles[cs].0 < 0.17
                    out.c = fresh ? W : FX.rand(Double(ux), Double(uy), Double(FX.i32(t * 20))) < 0.25 + 0.1 * Double(st) ? G[1] : G[0]
                    out.k = 0.14 + 0.06 * Double(st)
                    out.l = G[1]
                    return 0
                }
                // the lip of each crack falls into shadow below it, so the gap reads as a gap
                if (self.crack[Self.key(ux, uy + 1)].map { $0 < st } ?? false) || (self.crack[Self.key(ux + 1, uy)].map { $0 < st } ?? false) {
                    out.c = e.lit > 0.3 ? C[2] : C[1]
                    return 0
                }
                // light shows through the shell in a halo round the cracks, and the whole egg warms a little
                let dn = st > 0 ? self.near[st - 1][Self.key(ux, uy)]! : 9, k = Swift.min(1, g * 1.5)
                let base = st > 0 && e.c != SPK ? FX.mix(e.c, G[0], 0.05 * Double(st) * k) : e.c
                out.c = dn < 1.6 ? FX.mix(base, G[1], (st >= 2 ? 0.32 : 0.2) * k) : dn < 2.7 && st >= 2 ? FX.mix(base, G[1], 0.14 * k) : base
                return 0
            }
        }
        // the pop: the opening floods white, and light rays fan up out of it
        let q = t - Self.POP
        if popped && q < 1.2 && !crumbled && g > 0.22 {
            let oy = -ZY + 0.5, rx = 7
            for y in -2...2 {
                for x in -rx...rx {
                    let d = hypot((Double(x) + 0.5) / Double(rx), (Double(y) + 0.5) / 2.2)
                    if d > 1 { continue }
                    if g < 0.6 && d > 0.75 { continue }
                    p.px(Double(x), oy + Double(y), g > 1 ? (d < 0.7 ? W : G[2]) : g > 0.6 ? (d < 0.5 ? G[2] : G[1]) : d < 0.45 ? G[1] : G[0])
                }
            }
            p.glow(0, oy, 16, G[1], 0.6 * g)
            if q < 0.65 {
                let rk = q / 0.65, L = 36 * FX.Ease.outCubic(FX.clamp(q / 0.1)) * (1 - rk * 0.6)
                for i in 0..<7 {
                    let an = -Double.pi / 2 + Double(i - 3) * 0.24 + 0.05 * sin(t * 6 + Double(i)), len = L * (i % 2 != 0 ? 0.65 : 1), w = i % 2 != 0 ? 1 : 2
                    let x1 = cos(an) * len, y1 = oy + sin(an) * len
                    for j in 0..<w {
                        let o = Double(j) * 0.8 - 0.4
                        p.line(o, oy - 1, x1 + o, y1, { u in u < 0.3 ? W : u < 0.65 ? G[2] : G[1] }, { u in (1 - u * u) * (1.1 - rk) })
                    }
                    p.glowLine(0, oy, x1, y1, 5, G[1], 0.35 * (1 - rk))
                }
            }
            if q < 0.1 { p.glow(0, oy - 4, 30, W, 0.6 * (1 - q / 0.1)) }
            // the light that lingers over the cup
            p.glowLine(0, oy, 0, oy - 26, 8, G[1], 0.25 * g)
        }
        // the inside glow through the shell before it pops
        if !popped && g > 0 { p.glow(0, -EH * 0.55, 7 + 2 * Double(st), G[1], 0.05 * g) }
        // pieces of shell: their lit outsides, their broken edges hot at first
        for s in pieces {
            let c2 = cos(s.a), s2 = sin(s.a), f = Swift.min(1, s.life / 0.4), r = Int(FX.ceil(s.r)), hot = t - s.born < 0.35
            for py in -r...r {
                for px in -r...r {
                    let fx = Double(px), fy = Double(py)
                    let ux = Int(FX.round(fx * c2 + fy * s2)), uy = Int(FX.round(-fx * s2 + fy * c2))
                    if let m = s.map[Self.key(ux, uy)], FX.rand(Double(ux), Double(uy), Double(s.id)) < f {
                        p.px(FX.floor(s.x) + fx, FX.floor(s.y) + fy, m.1 ? (hot ? G[2] : C[4]) : m.0)
                    }
                }
            }
            if hot { p.glow(s.x, s.y, 6, G[1], 0.3) }
        }
        bits.draw(p)
        if popped && q < 0.9 { FX.sparkle(p, -3, -ZY - 6, FX.round(4 * (1 - q / 0.9)), W, G[1], 0.4) }
        ps.draw(p, .front)
        lights.draw(p)
    }
}
