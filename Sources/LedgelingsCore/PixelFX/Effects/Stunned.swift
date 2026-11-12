// Dizzy, seeing stars: three spinning stars and two little birds circle the head on a tilted ring, ducking
// behind it and sweeping round in front, trailing glitter. pixelfx's `status/stunned` (MIT); its shaded,
// outlined icons and twinkles adapt Sprite Fusion's open-source heal
// (https://www.spritefusion.com/pixel-art-vfx/heal), MIT, Copyright (c) 2026 Hugo Duprez.

import Foundation

final class FXStunned: FXEffect {
    static let meta = FXMeta(id: "status/stunned", size: (60, 64), origin: (30, 56), duration: 2, loop: true,
                             palette: ["#3a1e0c", "#8a4a12", "#d88a1c", "#f5c030", "#ffe36e", "#fff6c8", "#ffffff"], seed: 2)
    static let birds = FX.fit(FX.ramp(["#1a1422", "#6a7fae", "#b8c8e8", "#f4f8ff"]), 4)
    static let beak = FX.hex("#ffae35")
    static let D = 2.0, turns = 2.0, N = 5
    nonisolated(unsafe) static let star7 = FXStatus.bitmap(["...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#."])
    /// A little bird facing right: body, head, eye, beak, tail, a wing that beats.
    nonisolated(unsafe) static let bird: [(Int, Int) -> Swift.Character?] = [true, false].map { up in
        { dx, dy in
            let x = Double(dx) + 0.5, y = Double(dy) + 0.5
            if dx == 3 && dy == -2 { return "e" }
            if (dx == 5 || dx == 4) && dy == -1 { return dx == 5 ? "b" : "#" }
            let wing: [(Int, Int)] = up ? [(-1, -1), (-1, -2), (-2, -2), (-2, -3), (-3, -3), (-3, -4)] : [(-1, 1), (-1, 2), (-2, 2), (-2, 3), (0, 1)]
            if wing.contains(where: { $0.0 == dx && $0.1 == dy }) { return "w" }
            if pow(x / 3.3, 2) + pow((y - 0.6) / 1.9, 2) <= 1 || pow(x - 2.8, 2) + pow(y + 1.2, 2) <= pow(1.7, 2) { return "#" }
            if (dx == -4 && (dy == -1 || dy == 0)) || (dx == -5 && dy == -1) { return "#" }
            return nil
        }
    }
    nonisolated(unsafe) static let starFn = FXStatus.starShape(0.44)
    static func star(_ s: Double, _ ang: Double) -> (Int, Int) -> Swift.Character? { FXStatus.shaped(starFn, s, ang) }

    let o: FXOptions
    let C: [FXColor]
    init(_ o: FXOptions) { self.o = o; C = FX.fit(o.palette, 7) }

    struct Item { let i: Int, th: Double, x: Double, y: Double, near: Bool, depth: Double, bird: Bool, rx: Double, ry: Double, cy: Double }

    /// The ring round the head: stars at 0, 2, 4, birds between.
    func ring(_ t: Double) -> [Item] {
        let a = o.actor, cy = Double(a.y) + 2, rx = Double(a.w) * 0.62, ry = 4.5
        return (0..<Self.N).map { i in
            let th = FX.tau * ((Self.turns * t) / Self.D + Double(i) / Double(Self.N)), s = sin(th)
            return Item(i: i, th: th, x: cos(th) * rx, y: cy + s * ry, near: s >= 0, depth: 0.5 + 0.5 * s, bird: i % 2 == 1, rx: rx, ry: ry, cy: cy)
        }
    }

    func draw1(_ p: Painter, _ t: Double, _ far: Bool) {
        let C = self.C, Bd = Self.birds, D = Self.D
        let dim = { (c: FXColor) in far ? FX.mix(c, Bd[0], 0.3) : c }
        for it in ring(t) {
            if it.near == far { continue }
            let fi = Double(it.i)
            // glitter left along the ring behind each star
            if !it.bird {
                for k in 1...12 {
                    let fk = Double(k), th = it.th - fk * 0.085, x = cos(th) * it.rx, y = it.cy - 1 + sin(th) * it.ry
                    if (sin(th) >= 0) == far || FX.rand(fi, fk, FX.floor(((t / D) * Self.turns + fk * 0.37) * 9)) < 0.25 { continue }
                    p.dot(x, y, dim(k < 4 ? C[6] : k < 8 ? C[5] : C[4]), 1.1 - fk / 13)
                    if k < 6 { p.light(x, y, C[4], 0.3 * (1 - fk / 6)) }
                }
            }
            if it.bird {
                let up = FX.mod(FX.floor(t * 8 + fi * 0.5), 2) == 0, bob = sin((t / D) * FX.tau * 4 + fi) * 0.7, flip = it.near
                let f = Self.bird[up ? 0 : 1], ins: (Int, Int) -> Swift.Character? = flip ? { dx, dy in f(-dx, dy) } : f
                FXStatus.icon(p, it.x, it.y - 3 + bob, 7, ins, [Bd[0], dim(Bd[1]), dim(Bd[2]), dim(Bd[3])], 1,
                              ["e": Bd[0], "b": dim(Self.beak), "w": dim(Bd[1])])
            } else {
                let spin = (t / D) * FX.tau * 3 + fi, R = [C[0], dim(C[3]), dim(C[4]), dim(C[5])]
                if it.depth > 0.55 { FXStatus.icon(p, it.x, it.y - 1, 7, Self.star(4 + 0.8 * it.depth, spin), R) }
                else { FXStatus.icon(p, it.x, it.y - 1, 5, Self.star7, R) }
                p.px(it.x, it.y - 1, far ? C[5] : C[6])
                p.glow(it.x, it.y - 1, 11, C[4], 0.24 + 0.3 * it.depth)
                p.glow(it.x, it.y - 1, 4, C[6], 0.3 * it.depth)
                // a flare as it sweeps past the front, nearest the eye
                let fr = exp(-pow(atan2(sin(it.th - Double.pi / 2), cos(it.th - Double.pi / 2)) / 0.32, 2))
                if !far && fr > 0.08 { FX.flare(p, it.x, it.y - 1, 9 * fr, fr, [C[3], C[4], C[5], C[6]]) }
            }
        }
    }

    func drawBack(_ p: Painter, _ t: Double) { draw1(p, t, true) }

    func draw(_ p: Painter, _ t: Double) {
        let C = self.C, a = o.actor, aw = Double(a.w), ay = Double(a.y)
        draw1(p, t, false)
        // little twinkles popping round the ring
        FX.cycle(t, Self.D, 14, o.seed + 3, { r in r.range(0.25, 0.5) }) { age, life, r, _ in
            let th = r.range(0, FX.tau), u = age / life, x = cos(th) * aw * r.range(0.45, 0.95), y = ay + 1 + sin(th) * 7 - r.range(0, 9)
            let arm = FX.round(r.range(1, 2.6) * sin(Double.pi * u))
            if arm < 1 { p.dot(x, y, C[6], sin(Double.pi * u) * 1.4) }
            FX.sparkle(p, x, y, arm, C[5], C[4], 0.35 * sin(Double.pi * u))
        }
        p.glow(0, ay + 1, 26, C[4], 0.13)
    }
}
