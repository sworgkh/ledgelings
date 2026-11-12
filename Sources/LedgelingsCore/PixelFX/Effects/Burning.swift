// Fired up: small flames lick from four hot spots, trailing sparks and thin smoke; every 0.6 s they flare,
// the body flashes white then orange, scorch marks spread. pixelfx's `status/burning` (MIT); its flame
// tongues, embers and thin smoke adapt Sprite Fusion's open-source fire
// (https://www.spritefusion.com/pixel-art-vfx/fire), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXBurning: FXEffect {
    static let meta = FXMeta(id: "status/burning", size: (72, 80), origin: (36, 70), duration: 1.2, loop: true,
                             palette: ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"], seed: 3)
    static let char = FX.fit(FX.ramp(["#120c0a", "#2a1a14", "#4a2c1c"]), 3)
    static let smokeColor = FX.hex("#5b5566")
    static let D = 1.2, tickTime = 0.6, wind = -14.0
    let o: FXOptions
    let F: [FXColor]
    init(_ o: FXOptions) { self.o = o; F = FX.fit(o.palette, 9).reversed() }

    static func since(_ t: Double) -> Double { FX.mod(FX.mod(t, tickTime) + tickTime, tickTime) }
    static func flare(_ t: Double) -> Double { exp(-since(t) / 0.12) }
    /// The stand-in is hidden for the one white frame of each tick (the effect draws the body then).
    func actorAlpha(_ t: Double) -> Double { Self.since(t) < 0.034 ? 0 : 1 }

    struct Tongue { let dx: Double, h: Double, n: Double }
    struct Spot { let x: Double, y: Double, tongues: [Tongue] }
    struct Scorch { let x: Double, y: Double, r: Double }
    struct Spots { let list: [Spot]; let scorch: [[Scorch]] }
    nonisolated(unsafe) static let memo = FXMemo<Spots>()

    /// The hot spots on the outline: the hair tips, a shoulder, the back, a sleeve; scorch spots near them per tick.
    static func spots(_ a: FXActor, _ seed: Double) -> Spots {
        memo.get(a.key &* 31 &+ Int(seed)) {
            let S = FXStatus.shape(a), H = Double(S.h), W = Double(S.w), R = Rng(seed * 13 + 5)
            let ax = Double(a.x), ay = Double(a.y)
            func at(_ q: Double, _ side: Int) -> (Int, Int) {
                let my = Int(FX.round(H * q)), (l, r) = S.rows[my]
                return (side < 0 ? l : r, my)
            }
            let hair = FX.jsSort(S.up.filter { Double($0.0) < W * 0.42 }) { p, q in
                let d = Double(p.1 - q.1)
                return d != 0 ? d : Double(p.0 - q.0)
            }[0]
            let shoulder = FX.jsSort(S.up.filter { Double($0.0) > W / 2 && Double($0.1) > H * 0.4 && Double($0.1) < H * 0.62 }) { p, q in
                Double(p.1 - q.1)
            }.first ?? at(0.5, 1)
            let raw: [((Int, Int), Int, Double)] = [(hair, 3, 4.5), (shoulder, 2, 4), (at(0.62, -1), 2, 3.5), (at(0.6, 1), 2, 3.5)]
            let list = raw.enumerated().map { i, sp in
                let (pt, n, h) = sp
                let tongues = (0..<n).map { j in
                    let dx = (Double(j) - Double(n - 1) / 2) * 1.6 + R.range(-0.4, 0.4)
                    return Tongue(dx: dx, h: h * R.range(0.8, 1.2), n: Double(i * 17 + j * 5) + seed)
                }
                return Spot(x: ax + Double(pt.0) + 0.5, y: ay + Double(pt.1) + 1.5, tongues: tongues)
            }
            // scorch marks: each tick chars two patches on the clothes near the spots
            let lum = { (x: Int, y: Int) in FX.luma(FXStatus.colorAt(a, x, y)) }
            let scorch = [0, 1].map { tick in
                [0, 1].map { k -> Scorch in
                    // on the clothes (mid-tones, where char shows), near a hot spot
                    let sp = list[(tick * 2 + k + 1) % list.count]
                    var cand = S.body.filter { (x, y) in
                        hypot(ax + Double(x) + 0.5 - sp.x, ay + Double(y) + 0.5 - sp.y) < 9 && Double(y) > H * 0.42 && lum(x, y) > 0.3 && lum(x, y) < 0.6
                    }
                    if cand.isEmpty { cand = S.body.filter { Double($0.1) > H * 0.45 } }
                    let (x, y) = cand[Int(FX.floor(R.next() * Double(cand.count)))]
                    return Scorch(x: ax + Double(x) + 0.5, y: ay + Double(y) + 0.5, r: R.range(3.2, 4.4))
                }
            }
            return Spots(list: list, scorch: scorch)
        }
    }

    func drawBack(_ p: Painter, _ t: Double) {
        let F = self.F, a = o.actor, fl = Self.flare(t), flick = 0.8 + 0.2 * FXStatus.tnoise(t, Self.D, 7.5, 3)
        // warm flicker on the floor
        p.shade(-30, -3, 30, 7) { x, y, out in
            let d = hypot(x / 26, (y - 0.5) / 4.5)
            if d < 1 { out.l = FX.mix(F[3], F[4], 0.5); out.k = (0.16 + 0.22 * fl) * flick * (1 - d) * (1 - d) }
            return 0
        }
        // thin smoke drifting up and away from each spot
        let smokeC = FX.mix(Self.smokeColor, F[6], 0.2), list = Self.spots(a, o.seed).list, W = Self.wind
        FX.cycle(t, Self.D, 16, o.seed + 4, { r in r.range(0.8, 1.2) }) { age, life, r, i in
            let sp = list[i % list.count]
            let x = sp.x + FXStatus.travel(W * 0.6, W * 0.5, 0.8, age) + sin(age * 4 + Double(i)) * 1.2, y = sp.y - 3 - FXStatus.travel(18, 6, 1, age)
            FXStatus.smoke(p, x, y, r.range(1.1, 1.9), age / life, smokeC, 0.9)
        }
    }

    func draw(_ p: Painter, _ t: Double) {
        let F = self.F, CH = Self.char, a = o.actor, S = FXStatus.shape(a), sp0 = Self.spots(a, o.seed), list = sp0.list
        let ax = Double(a.x), ay = Double(a.y), D = Self.D, W = Self.wind
        let ph = Self.since(t), tick = Int(FX.mod(FX.floor(t / Self.tickTime), 2)), fl = Self.flare(t)
        // the tick: the body's own pixels flash white for a frame, then orange, fading
        if ph < 0.034 { for (mx, my) in S.body { p.px(ax + Double(mx), ay + Double(my), FX.white) } }
        else if ph < 0.22 {
            let k = 1 - (ph - 0.034) / 0.186
            for (mx, my) in S.body { p.blend(ax + Double(mx), ay + Double(my), F[4], 0.55 * k) }
        }
        // scorch marks spreading over the clothes from this tick, ember-edged, cooling and fading by the next
        for sc in sp0.scorch[tick] {
            let grow = FX.clamp(ph / 0.14), fade = 1 - FX.clamp((ph - 0.25) / 0.33), r = sc.r * (0.4 + 0.6 * grow)
            if fade <= 0 { continue }
            for (mx, my) in S.body {
                let fmx = Double(mx), fmy = Double(my)
                let x = ax + fmx + 0.5, y = ay + fmy + 0.5, d = hypot(x - sc.x, (y - sc.y) * 1.2) + FX.rand(fmx, fmy, 7) * 0.9
                if d > r { continue }
                let edge = d > r - 1
                if edge { p.dot(x - 0.5, y - 0.5, FX.rand(fmx, fmy, FX.floor(t * 20)) < 0.5 ? F[3] : F[4], fade * 1.2) }
                else { p.dot(x - 0.5, y - 0.5, d < r * 0.5 ? CH[0] : CH[1], fade * 1.1) }
            }
            p.glow(sc.x, sc.y, 6, F[4], 0.3 * fade)
        }
        // the hot spots: little tongues licking up, flaring on the tick
        for sp in list {
            for tg in sp.tongues {
                let h = tg.h * (0.85 + 0.25 * FXStatus.tnoise(t, D, 5, tg.n)) * (1 + 1.6 * fl)
                FXStatus.tongue(p, sp.x + tg.dx, sp.y, h, 1.1 + 0.3 * fl, W * 0.08 * h / 4 + FXStatus.tnoise(t, D, 3, tg.n + 9) * 0.8, F, t, D, tg.n)
            }
            p.glow(sp.x, sp.y - 2, 9 + 6 * fl, F[4], 0.22 + 0.35 * fl)
        }
        // sparks streaming up and away
        FX.cycle(t, D, 20, o.seed + 6, { r in r.range(0.5, 0.9) }) { age, life, r, i in
            let sp = list[i % list.count], fi = Double(i)
            let x = sp.x + r.range(-1.5, 1.5) + FXStatus.travel(W + r.range(-10, 6), W * 0.6, 1.2, age) + sin(age * 9 + fi) * 1.2 * age
            let y = sp.y - 2 + FXStatus.travel(-r.range(25, 55), -18, 1.4, age)
            FXStatus.ember(p, x, y, age / life, [F[1], F[3], F[5]], age + fi)
        }
        // the tick throws a burst of sparks off every spot
        if ph < 0.3 {
            for (k, sp) in list.enumerated() {
                for j in 0..<4 {
                    let fk = Double(k), fj = Double(j)
                    let an = -Double.pi / 2 + (FX.rand(fk, fj, Double(tick)) - 0.5) * 2.2, v = 50 + 50 * FX.rand(fk, fj, 2)
                    let x = sp.x + cos(an) * FXStatus.travel(v, 0, 3, ph), y = sp.y - 2 + sin(an) * FXStatus.travel(v, 0, 3, ph) + 60 * ph * ph
                    p.px(x, y, ph < 0.12 ? F[1] : F[3])
                    p.light(x, y, F[3], 0.4 * (1 - ph / 0.3))
                }
            }
        }
    }
}
