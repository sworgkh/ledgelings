// Chilled to the bone: frost ferns creep over the body, icicles hang and drip, breath steams, snow settles,
// a shiver every second, frost spreads underfoot. pixelfx's `status/frozen` (MIT).

import Foundation

final class FXFrozen: FXEffect {
    static let meta = FXMeta(id: "status/frozen", size: (72, 64), origin: (36, 54), duration: 2, loop: true,
                             palette: ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], seed: 4)
    static let D = 2.0, shiver = 1.0
    let o: FXOptions
    let C: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 8) }

    static func since(_ t: Double) -> Double { FX.mod(FX.mod(t, shiver) + shiver, shiver) }
    static func shake(_ t: Double) -> Double { since(t) < 0.22 ? (FX.mod(FX.floor(t * 50), 2) != 0 ? 1 : -1) : 0 }
    /// The effect draws the whole (chilled, shivering) body, so the stand-in is hidden throughout.
    func actorAlpha(_ t: Double) -> Double { 0 }

    struct Icicle { let x: Double, y: Double, len: Double, phase: Double, period: Double }
    struct Plan {
        let ferns: [(Int, Int, Double, Int)]
        let icicles: [Icicle]
        let snow: [(Int, Int, Int)]
        let mouth: (Double, Double)
    }
    nonisolated(unsafe) static let plans = FXMemo<Plan>()

    /// Worked out once per creature: fern paths creeping in from the outline, icicle roots, snow ledges, the mouth.
    static func plan(_ a: FXActor, _ seed: Double) -> Plan {
        plans.get(a.key &* 31 &+ Int(seed)) {
            let S = FXStatus.shape(a), H = Double(S.h), W = Double(S.w), R = Rng(seed * 11 + 1)
            // ferns: a stem walking in from an edge with fronds branching off it at alternate sides
            var ferns: [(Int, Int, Double, Int)] = []
            let roots = Array(FX.jsSort(S.side.filter { Double($0.1) > H * 0.2 && Double($0.1) < H * 0.85 }) { _, _ in R.next() - 0.5 }.prefix(6))
            for (i, (x0, y0, dir)) in roots.enumerated() {
                var x = Double(x0), y = Double(y0), ang = dir < 0 ? -0.5 : Double.pi + 0.5
                ang += R.range(-0.4, 0.4)
                for s in 0..<9 {
                    x += cos(ang) * 1.1
                    y += sin(ang) * 1.1
                    let px = Int(FX.round(x)), py = Int(FX.round(y))
                    if !S.on(px, py) { break }
                    ferns.append((px, py, Double(s) / 9, i))
                    if s % 2 == 1 {
                        for side in [-1.0, 1.0] {
                            let ba = ang + side * 1.05, L = 1 + Int(FX.round(R.range(0, 2) * (1 - Double(s) / 9)))
                            if L >= 1 {
                                for k in 1...L {
                                    let bx = Int(FX.round(x + cos(ba) * Double(k))), by = Int(FX.round(y + sin(ba) * Double(k)))
                                    if S.on(bx, by) { ferns.append((bx, by, (Double(s) + Double(k) * 0.6) / 9, i)) }
                                }
                            }
                        }
                    }
                    ang += R.range(-0.25, 0.25)
                }
            }
            // icicles under the hair tips, the jaw and the hands: bottom edges with clear space under them
            func clear(_ x: Int, _ y: Int) -> Int {
                var n = 0
                while n < 7 && y + 1 + n < S.h && !S.on(x, y + 1 + n) { n += 1 }
                return n
            }
            let hangs = S.body.filter { (x, y) in !S.on(x, y + 1) && S.on(x, y - 1) && Double(y) < H * 0.72 && y > 4 }
                .map { (x, y) in (x, y, clear(x, y)) }.filter { $0.2 >= 4 }
            func best(_ f: ((Int, Int, Int)) -> Bool, _ key: ((Int, Int, Int), (Int, Int, Int)) -> Double) -> (Int, Int, Int)? {
                FX.jsSort(hangs.filter(f), key).first
            }
            let picks: [(Int, Int, Int)?] = [
                best({ Double($0.1) < H * 0.36 }, { p, q in Double(p.0 - q.0) }),
                best({ Double($0.1) < H * 0.36 }, { p, q in Double(q.0 - p.0) }),
                best({ Double($0.1) >= H * 0.36 && Double($0.1) < H * 0.5 && Double($0.0) < W / 2 }, { p, q in Double(q.0 - p.0) }),
                best({ Double($0.1) >= H * 0.36 && Double($0.1) < H * 0.5 && Double($0.0) >= W / 2 }, { p, q in Double(p.0 - q.0) }),
                best({ Double($0.1) >= H * 0.5 && Double($0.0) < W / 2 }, { p, q in Double(p.0 - q.0) }),
                best({ Double($0.1) >= H * 0.5 && Double($0.0) >= W / 2 }, { p, q in Double(q.0 - p.0) }),
            ]
            let icicles = picks.compactMap { $0 }.enumerated().map { i, h in
                let len = Swift.min(Double(h.2 - 1), R.range(3, 5.5))
                return Icicle(x: Double(h.0), y: Double(h.1 + 1), len: len, phase: R.next(), period: i % 2 != 0 ? 1 : 2)
            }
            // snow ledges: the upward edges of the head and the shoulders
            let snow = S.up.filter { Double($0.1) < H * 0.6 }.map { (x, y) in (x, y, 1 + (FX.rand(Double(x), seed, 3) < 0.45 ? 1 : 0)) }
            let E = FXStatus.eyes(a)
            let mouth = E.count == 2 ? (Double(E[0].x1 + E[1].x0 + 1) / 2, Double(Swift.max(E[0].y1, E[1].y1) + 2)) : (W / 2, H * 0.38)
            return Plan(ferns: ferns, icicles: icicles, snow: snow, mouth: mouth)
        }
    }

    /// Frost on the floor round the feet: a white crust, a pale bloom under it, its edge creeping out and back.
    func frost(_ p: Painter, _ t: Double, _ reach: Double) {
        let C = self.C
        var x = -FX.ceil(reach) - 1
        while x <= reach + 1 {
            defer { x += 1 }
            let q = abs(x + 0.5) / reach, h = FX.rand(x, 17), k = 1 - q * q
            if q > 1 + h * 0.15 { continue }
            let tw = sin((t / Self.D) * FX.tau * 2 + FX.rand(x, 3) * FX.tau) > 0.94
            p.px(x, 0, tw || h < 0.3 ? C[7] : q > 0.85 ? C[5] : C[6])
            if h < 0.3 * k { p.px(x, -1, C[6]) }
            var j = 1.0
            while j <= 1 + FX.round(2 * k) { p.dot(x, j, j == 1 ? C[5] : C[4], (1.05 - j / 4) * 0.85); j += 1 }
        }
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let C = self.C, reach = 13 + 3.5 * sin((t / Self.D) * FX.tau)
        p.shade(-28, -3, 28, 6) { x, y, out in
            let d = hypot(x / 24, (y - 0.5) / 4)
            if d < 1 { out.l = C[4]; out.k = 0.24 * (1 - d) * (1 - d) }
            return 0
        }
        frost(p, t, reach)
    }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, S = FXStatus.shape(a), H = Double(S.h), P = Self.plan(a, o.seed), dx = Self.shake(t), ph = Self.since(t)
        let ax = Double(a.x), ay = Double(a.y)
        func X(_ mx: Double) -> Double { ax + mx + dx }
        func Y(_ my: Double) -> Double { ay + my }
        // the body, chilled: its colours pulled toward ice; the rim frosted and lit
        for (mx, my) in S.body {
            let c = FXStatus.colorAt(a, mx, my), ice = C[Int(FX.clamp(1 + FX.round(FX.luma(c) * 5.6), 1, 7))]
            let rim = !S.on(mx - 1, my) || !S.on(mx, my - 1) || !S.on(mx + 1, my)
            p.px(X(Double(mx)), Y(Double(my)), rim && FX.luma(c) < 0.3 ? (Double(my) < H * 0.5 || !S.on(mx - 1, my) ? C[5] : C[3]) : FX.mix(c, ice, 0.38))
        }
        // frost ferns creeping in from the outline; each shiver cracks most of it off and it creeps back
        let grow = 0.2 + 0.65 * FX.smooth(0.05, 0.95, ph)
        for (x, y, u, _) in P.ferns where u < grow {
            p.px(X(Double(x)), Y(Double(y)), u > grow - 0.1 ? FX.white : FX.rand(Double(x), Double(y), 5) < 0.5 ? C[6] : C[5])
        }
        // snow settled on the head and shoulders
        for (x, y, d) in P.snow {
            p.px(X(Double(x)), Y(Double(y)) - 1, C[7])
            if d > 1 { p.px(X(Double(x)), Y(Double(y)) - 2, FX.rand(Double(x), Double(y), 9) < 0.5 ? C[7] : C[6]) }
        }
        // icicles hanging under the chin, hands and hair: they grow, a drop gathers and falls, they shrink back
        for ic in P.icicles {
            let per = ic.period, u = FX.mod(FX.mod(t / per + ic.phase, 1) + 1, 1), L = ic.len * (0.55 + 0.45 * FX.smooth(0, 0.7, u))
            let x = X(ic.x), y0 = Y(ic.y)
            var j = 0.0
            while j < L {
                let v = j / L
                p.px(x, y0 + j, v > 0.75 ? FX.white : v < 0.3 ? C[7] : C[6])
                if v < 0.5 { p.px(x + 1, y0 + j, C[4]) }
                j += 1
            }
            // the drop: it swells at the tip, lets go and falls to the floor
            if u > 0.7 && u < 0.86 { p.px(x, y0 + L, C[6]) }
            else if u >= 0.86 {
                let f = (u - 0.86) * per, y = y0 + L + 0.5 * 760 * f * f
                if y < -1 { p.px(x, y, C[6]); p.px(x, y - 1, C[5]) }
            }
            p.glow(x, y0 + L * 0.6, 4, C[5], 0.18)
        }
        // breath steaming from the mouth between shivers
        let (mx0, my0) = P.mouth
        for i in 0..<4 {
            let fi = Double(i), age = ph - 0.35 - fi * 0.05
            if age < 0 || age > 0.65 { continue }
            let u = age / 0.65, x = X(mx0) + 1 + FXStatus.travel(16, 0, 2.2, age) + fi, y = Y(my0) - FXStatus.travel(6, 3, 1, age) - fi * 0.5
            let rad = 0.8 + 2.4 * u.squareRoot()
            p.disc(x, y, rad, C[7], 0.5 * (1 - u) * Swift.min(1, u * 8))
            p.disc(x - rad * 0.2, y - rad * 0.3, rad * 0.5, FX.white, 0.4 * (1 - u))
        }
        // snow falling and settling; flakes flung off by the shiver
        FX.cycle(t, Self.D, 9, o.seed + 2, { r in r.range(1.2, 1.8) }) { age, _, r, _ in
            let x = r.range(-14, 14) + sin(age * 3 + r.next() * FX.tau) * 1.5, y = ay - 16 + age * 14
            if y > ay + 2 { return }
            p.dot(x, y, r.next() < 0.5 ? FX.white : C[6], Swift.min(1, age * 4))
        }
        if ph < 0.5 {
            for i in 0..<8 {
                let fi = Double(i), side: Double = i % 2 != 0 ? 1 : -1
                let vx = side * (20 + 30 * FX.rand(fi, 4)), vy = -(20 + 30 * FX.rand(fi, 5))
                let x = side * (6 + 6 * FX.rand(fi, 6)) + vx * ph, y = ay + 3 * FX.rand(fi, 7) + vy * ph + 0.5 * 300 * ph * ph
                p.dot(x, y, i % 3 != 0 ? C[6] : FX.white, 1.2 - ph * 2)
            }
        }
        if ph < 0.25 { FX.sparkle(p, X(FX.round(Double(S.w) * 0.3)), Y(4), FX.round(3 * (1 - ph / 0.25)), C[6], C[5], 0.4) }
        // cold light: off the body, lifting with each shiver
        p.glow(0, ay + H * 0.45, 30, C[4], 0.2 + 0.12 * exp(-ph / 0.2))
        p.glow(0, ay + 2, 16, C[5], 0.1)
    }
}
