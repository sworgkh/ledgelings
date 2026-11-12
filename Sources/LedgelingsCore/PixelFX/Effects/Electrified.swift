// Current runs through a character: arcs crawl over and leap across the body, sparks spit off, the body flares
// to an electric silhouette on each jolt, and the feet ground out. pixelfx's `lightning/electrified` (MIT),
// after Sprite Fusion's open-source lightning crackle (https://www.spritefusion.com/pixel-art-vfx/lightning),
// MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXElectrified: FXEffect {
    static let meta = FXMeta(id: "lightning/electrified", size: (108, 92), origin: (54, 76), duration: 2, loop: true, palette: FXLightning.volt, seed: 5)
    static let FPS = 30.0, N = 60, P = 2.0, jolts: [(Int, Double)] = [(3, 1), (22, 0.7), (41, 0.9)]
    nonisolated(unsafe) static let edges = FXMemo<[(Double, Double)]>()
    let o: FXOptions
    let C: [FXColor], S: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 8); S = FX.ramp(FXLightning.plasma) }

    /// The silhouette's edge pixels, in local space (pixel centres).
    static func edgeOf(_ A: FXActor) -> [(Double, Double)] {
        edges.get(A.key) {
            let m = A.mask
            let on = { (x: Int, y: Int) in x >= 0 && y >= 0 && x < m.w && y < m.h && m.data[y * m.w + x] != 0 }
            var e: [(Double, Double)] = []
            for y in 0..<m.h { for x in 0..<m.w where on(x, y) && (!on(x - 1, y) || !on(x + 1, y) || !on(x, y - 1) || !on(x, y + 1)) {
                e.append((Double(A.x + x) + 0.5, Double(A.y + y) + 0.5))
            } }
            return e
        }
    }
    static func jolt(_ f: Int) -> (a: Int, k: Double)? {
        for (f0, k) in jolts where f >= f0 && f < f0 + 3 { return (f - f0, k) }
        return nil
    }
    static func frame(_ t: Double) -> Int { Int(FX.floor(t * FPS + 1e-6)) % N }

    func drawBack(_ p: Painter, _ t: Double) {
        let C = self.C, A = o.actor, f = Self.frame(t), j = Self.jolt(f), r = FX.rng(o.seed, 4, Double(f))
        // a cold aura: a broken outline that flickers round the body, light pooling at the feet
        let oc = j != nil ? C[4] : r.next() < 0.5 ? C[2] : C[1]
        p.outline(A.mask, Double(A.x), Double(A.y), { _, _ in oc })
        p.glow(0, -18, 30, C[3], j != nil ? 0.55 * j!.k : 0.16 + 0.1 * r.next())
        p.glow(0, -2, 22, C[4], 0.18)
    }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, S = self.S, A = o.actor, E = Self.edgeOf(A), f = Self.frame(t), j = Self.jolt(f), seed = o.seed
        // the jolt: the body flares to an electric silhouette, then fades back through its own shading
        if let j {
            let lift = [1.1, 0.6, -0.2][j.a] * j.k, ramp = [C[1], C[2], C[3], C[4], C[5], C[6], C[7]]
            for y in 0..<A.h {
                for x in 0..<A.w {
                    let c = A.pixels[y * A.w + x]
                    if c != 0 { p.px(Double(A.x + x), Double(A.y + y), ramp[Int(FX.clamp(FX.round(0.4 + FX.luma(c) * 6 + lift), 0, 6))]) }
                }
            }
            p.glow(0, -19, 26, C[5], 0.5 * j.k * (1 - Double(j.a) / 3))
        }
        // arcs: two or three at a time, re-struck every other frame, leaping between nearby points of the edge
        let r = FX.rng(seed, 7, Double(f >> 1)), n = 2 + (j != nil ? 2 : Int(r.int(0, 1)))
        for i in 0..<n {
            let a = r.pick(E), ang = r.range(0, FX.tau), d = r.range(6, 14)
            var b = (a.0 + cos(ang) * d, a.1 + sin(ang) * d)
            for _ in 0..<10 {
                let c = r.pick(E)
                if hypot(c.0 - b.0, c.1 - b.1) < 5 && hypot(c.0 - a.0, c.1 - a.1) > 4 { b = c }
            }
            let k = (f & 1 != 0 ? 0.75 : 0.95) * r.range(0.6, 1)
            FXLightning.crackle(p, FXLightning.zigzag(FX.rng(seed, 8, Double(f), Double(i)), a.0, a.1, b.0, b.1, 0.42, 0.35), k, C, 0.4)
            // the edge catches the light where an arc touches it
            for (x, y) in E where hypot(x - a.0, y - a.1) < 3.5 || hypot(x - b.0, y - b.1) < 3 { p.px(x - 0.5, y - 0.5, C[5]) }
        }
        // the feet ground out to the floor now and then
        if r.next() < (j != nil ? 0.9 : 0.35) {
            let s = r.sign(), x0 = s * r.range(3, 8)
            let g = FX.rng(seed, 9, Double(f))
            FXLightning.crackle(p, FXLightning.zigzag(g, x0, -1.5, x0 + s * r.range(5, 12), -0.5, 0.45, 0.3), 0.7, C, 0.35)
            p.glow(x0, -1, 10, C[5], 0.35)
        }
        // sparks: a spray off the edge with every jolt, and a few spat out between them
        for (f0, k) in Self.jolts {
            let age = FX.mod(FX.mod(t - Double(f0) / Self.FPS, Self.P) + Self.P, Self.P)
            for i in 0..<9 {
                let q = FX.rng(seed, 21, Double(f0), Double(i)), life = q.range(0.18, 0.4)
                if age >= life { continue }
                let (x0, y0) = E[Int(FX.floor(q.next() * Double(E.count)))], ang = atan2(y0 + 19, x0) + q.range(-0.7, 0.7), sp = q.range(60, 150) * k
                let (x, y, vx, vy) = FXLightning.flight(x0, y0, cos(ang) * sp, sin(ang) * sp - 30, age, floor: 0)
                FXLightning.spark(p, x, y, vx, vy, 1 - age / life, S)
            }
        }
        FX.cycle(t, Self.P, 8, seed + 3, { g in g.range(0.15, 0.3) }) { age, life, q, _ in
            let (x0, y0) = E[Int(FX.floor(q.next() * Double(E.count)))], ang = atan2(y0 + 19, x0) + q.range(-0.6, 0.6), sp = q.range(50, 110)
            let (x, y, vx, vy) = FXLightning.flight(x0, y0, cos(ang) * sp, sin(ang) * sp - 20, age, floor: 0)
            FXLightning.spark(p, x, y, vx, vy, 1 - age / life, S)
        }
    }
}
