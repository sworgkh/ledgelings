// Fast asleep: eyes shut, soft outlined Zs float up off the head one after another, swaying and growing as
// they rise, dream motes drift, a slow breathing glow. pixelfx's `status/sleep` (MIT); its shaded, outlined
// letters adapt Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
// MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXSleep: FXEffect {
    static let meta = FXMeta(id: "status/sleep", size: (60, 82), origin: (26, 74), duration: 2.4, loop: true,
                             palette: ["#1a1636", "#3c3a7a", "#6f78c8", "#a9b8f0", "#dfe6ff", "#ffffff"], seed: 3)
    static let D = 2.4, NZ = 3
    static let lidColor: FXColor = 0xff1f1726
    // the letter at four sizes: it grows a step at a time as it rises
    nonisolated(unsafe) static let zs = [
        ["#####", "...#.", "..#..", ".#...", "#####"],
        ["#######", ".....#.", "....#..", "...#...", "..#....", ".#.....", "#######"],
        [".#######.", "#########", "......##.", ".....##..", "....##...", "...##....", "..##.....", "#########", ".#######."],
        [".#########.", "###########", ".......###.", "......###..", ".....###...", "....###....", "...###.....", "..###......", ".###.......", "###########", ".#########."],
    ].map { FXStatus.bitmap($0) }
    let o: FXOptions
    let C: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 6) }

    /// A Z at age u (0..1): where it is, how big, how solid.
    func zAt(_ i: Int, _ u: Double) -> (x: Double, y: Double, size: Int, k: Double) {
        let a = o.actor, side = i % 2 != 0 ? 1 : 0.6, x0 = Double(a.x) + Double(a.w) * 0.78, y0 = Double(a.y) + 7
        let x = x0 + 13 * side * u + 2.5 * sin(FX.tau * 1.1 * u + Double(i) * 2.1), y = y0 - 32 * (1 - pow(1 - u, 1.35))
        let size = u < 0.18 ? 0 : u < 0.42 ? 1 : u < 0.68 ? 2 : 3, k = Swift.min(1, u / 0.06)
        return (x, y, size, k)
    }

    /// Shut the eyes: paint them over with skin and draw a soft lid line.
    func shut(_ p: Painter) {
        let a = o.actor, ax = Double(a.x), ay = Double(a.y)
        for e in FXStatus.eyes(a) {
            for (x, y) in e.px { p.px(ax + Double(x), ay + Double(y), e.skin) }
            let y = ay + Double(e.y1) - 1
            for x in e.x0...e.x1 { p.px(ax + Double(x), y, Self.lidColor) }
            p.px(ax + Double(e.x0) - 1, y - 1, Self.lidColor)
            p.px(ax + Double(e.x1) + 1, y - 1, Self.lidColor)
        }
    }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, D = Self.D, breath = 0.5 + 0.5 * sin((t / D) * FX.tau * 2)
        let ax = Double(a.x), ay = Double(a.y), aw = Double(a.w)
        shut(p)
        // a slow breathing glow round the head, and soft dream light drifting about it
        p.glow(0, ay + 10, 24, C[3], 0.1 + 0.1 * breath)
        FX.cycle(t, D, 5, o.seed + 6, D) { age, life, r, _ in
            let u = age / life, x = ax + aw * r.range(0.3, 1.1) + sin(u * FX.tau + r.next() * FX.tau) * 3, y = ay + r.range(-6, 8) - u * 10
            let rad = r.range(3, 5) * (0.8 + 0.4 * u), k = sin(Double.pi * u)
            p.glow(x, y, rad * 2.4, C[3], 0.1 * k)
        }
        // dream motes drifting up
        FX.cycle(t, D, 14, o.seed + 4, { r in r.range(1.2, 2) }) { age, life, r, _ in
            let u = age / life, x = ax + aw * r.range(0.4, 1.1) + sin(age * 2 + r.next() * FX.tau) * 2, y = ay + r.range(0, 10) - age * r.range(10, 18)
            let tw = sin(Double.pi * u) * (0.6 + 0.4 * sin(age * 9 + r.next() * FX.tau))
            if tw < 0.15 { return }
            FX.sparkle(p, x, y, tw > 0.7 && r.next() < 0.4 ? 1 : 0, C[4], C[3], 0.3 * tw)
            p.dot(x, y, tw > 0.6 ? C[5] : C[4], tw * 1.3)
        }
        // the Zs, oldest (biggest) first so the young ones sit on top
        var zs: [(i: Int, u: Double)] = []
        for i in 0..<Self.NZ { zs.append((i, FX.mod(FX.mod(t - (Double(i) * D) / Double(Self.NZ), D) + D, D) / D)) }
        zs = FX.jsSort(zs) { p1, p2 in p2.u - p1.u }
        for (i, u) in zs {
            let z = zAt(i, u)
            if u > 0.9 {
                // it pops into motes
                let k = (u - 0.9) / 0.1
                for j in 0..<7 {
                    let an = (Double(j) / 7) * FX.tau + Double(i), d = 3 + 6 * k.squareRoot()
                    p.dot(z.x + cos(an) * d, z.y + sin(an) * d * 0.8, j % 2 != 0 ? C[4] : C[5], 1.2 - k)
                }
                p.glow(z.x, z.y, 10, C[3], 0.25 * (1 - k))
                continue
            }
            // a dotted trail where it has been
            for j in 1...6 {
                let fj = Double(j), q = zAt(i, Swift.max(0, u - fj * 0.025))
                if j % 2 == 0 || u - fj * 0.025 < 0.05 { continue }
                p.dot(q.x - 1, q.y + 4 + Double(q.size), C[3], (1 - fj / 7) * 0.9)
            }
            // it dims down the ramp as it gets old
            let old = u > 0.78, R = old ? [C[0], C[1], C[2], C[3]] : [C[1], C[2], C[3], C[4]]
            let fs = Double(z.size)
            FXStatus.icon(p, z.x, z.y, 7, Self.zs[z.size], R, z.k)
            if !old { p.px(z.x - 2 - fs, z.y - 2 - fs * 0.8, C[5]) }
            p.glow(z.x, z.y, 7 + fs * 3, C[3], (old ? 0.12 : 0.26) * z.k)
        }
    }
}
