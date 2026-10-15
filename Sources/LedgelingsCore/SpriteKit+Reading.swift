import Foundation

extension SpriteKit {
    public enum ReadError: Error, CustomStringConvertible, Equatable {
        case tooFew(Int)

        public var description: String {
            switch self {
            case .tooFew(let n):
                tr("found %d creatures in the picture, not %d: it needs one per pose, apart from each other, on a plain background", n, SpriteText.poses.count)
            }
        }
    }

    /// What a picture held: each pose's open-eyes grid, and the body colour it was painted in.
    public struct Reading: Equatable, Sendable {
        public var poses: [String: [[SpriteText.Ink]]]
        public var colour: SpriteText.Tint

        /// The whole sheet in the built-in palette, eye variants and all, ready to save.
        public var sheet: SpriteText.Image {
            SpriteText.pixels(SpriteText.Sheet(name: "", kind: nil, cast: [], colour: nil, poses: poses), palette: .blocky)
        }
    }

    /// Read nine creatures out of a picture an image model (or anyone) painted:
    /// any size, any layout that reads left to right and top to bottom (one row,
    /// three rows of the old sheet, a 3×3 grid), on magenta, white, a checkerboard
    /// or transparency. Lines, labels and specks are left out. Each creature is
    /// brought down to the size the built-in creature has, every sprite pixel
    /// taking the colour most of its square has, then snapped to the sheet's inks:
    /// a 1-pixel outline all round, black eyes, light, shade and body.
    public static func read(_ image: SpriteText.Image) throws -> Reading {
        let w = image.width, h = image.height
        let background = backgroundColours(image)
        var solid = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { solid[i] = !isBackground(image, i, background) }

        let found = blobs(solid, w, h).filter { b in
            let long = max(b.w, b.h), short = min(b.w, b.h)
            return short * 12 >= long // a grid or frame line is not a creature
        }
        // How far apart two patches may be and still be one creature: a tenth of a big patch's size.
        let big = found.sorted { $0.count > $1.count }.prefix(SpriteText.poses.count).map { max($0.w, $0.h) }.sorted()
        var groups = merged(found, margin: max(1, median(big) / 10))
        let reference = median(Array(groups.map(\.count).sorted(by: >).prefix(SpriteText.poses.count)))
        groups = groups.filter { g in
            g.count * 5 >= reference && max(g.w, g.h) <= 4 * min(g.w, g.h) // labels, words and specks
        }
        guard groups.count >= SpriteText.poses.count else { throw ReadError.tooFew(groups.count) }
        let ordered = Array(readingOrder(groups).prefix(SpriteText.poses.count))

        // One scale for all nine, so a squashed pose stays squashed: the biggest fills the body box.
        let side = Double(ordered.map { max($0.w, $0.h) }.max() ?? 1) / Double(SpriteText.box.w)
        let grids = ordered.map { downscale(image, solid, $0, side) }
        let body = bodyColour(grids)
        var poses: [String: [[SpriteText.Ink]]] = [:]
        for (pose, grid) in zip(SpriteText.poses, grids) { poses[pose] = inks(placed(grid), body: body) }
        return Reading(poses: poses, colour: body)
    }

    // MARK: Background

    /// Colours that cover at least a tenth of the picture's edge: the paper it was painted on.
    static func backgroundColours(_ image: SpriteText.Image) -> [SpriteText.Tint] {
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        var total = 0
        func look(_ x: Int, _ y: Int) {
            let i = (y * image.width + x) * 4
            guard image.rgba[i + 3] >= 128 else { return }
            total += 1
            let r = Int(image.rgba[i]), g = Int(image.rgba[i + 1]), b = Int(image.rgba[i + 2])
            let bucket = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let c = counts[bucket] ?? (0, 0, 0, 0)
            counts[bucket] = (c.n + 1, c.r + r, c.g + g, c.b + b)
        }
        for x in 0..<image.width { look(x, 0); look(x, image.height - 1) }
        for y in 0..<image.height { look(0, y); look(image.width - 1, y) }
        guard total > 0 else { return [] }
        return counts.values.filter { $0.n * 10 >= total }
            .map { SpriteText.Tint(r: UInt8($0.r / $0.n), g: UInt8($0.g / $0.n), b: UInt8($0.b / $0.n)) }
    }

    static func isBackground(_ image: SpriteText.Image, _ pixel: Int, _ paper: [SpriteText.Tint]) -> Bool {
        let i = pixel * 4
        guard image.rgba[i + 3] >= 128 else { return true }
        let r = Int(image.rgba[i]), g = Int(image.rgba[i + 1]), b = Int(image.rgba[i + 2])
        // Magenta and everything mixed from it: the template's lines, a blurred edge of the key.
        if r >= 140, b >= 140, g * 10 < min(r, b) * 6 { return true }
        for t in paper {
            let dr = r - Int(t.r), dg = g - Int(t.g), db = b - Int(t.b)
            if dr * dr + dg * dg + db * db <= 40 * 40 { return true }
        }
        return false
    }

    // MARK: Finding the creatures

    struct Blob: Equatable {
        var x: Int, y: Int, w: Int, h: Int, count: Int
        var midX: Double { Double(x) + Double(w) / 2 }
        var midY: Double { Double(y) + Double(h) / 2 }
    }

    /// Every 8-connected patch of painted pixels, specks dropped.
    static func blobs(_ solid: [Bool], _ w: Int, _ h: Int) -> [Blob] {
        var seen = [Bool](repeating: false, count: w * h)
        var out: [Blob] = []
        let speck = max(3, w * h / 50000)
        var stack: [Int] = []
        for start in 0..<(w * h) where solid[start] && !seen[start] {
            seen[start] = true
            stack.append(start)
            var x0 = w, y0 = h, x1 = -1, y1 = -1, n = 0
            while let p = stack.popLast() {
                let x = p % w, y = p / w
                n += 1
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for dy in -1...1 {
                    let yy = y + dy
                    guard yy >= 0, yy < h else { continue }
                    for dx in -1...1 {
                        let xx = x + dx
                        guard xx >= 0, xx < w else { continue }
                        let q = yy * w + xx
                        if solid[q], !seen[q] { seen[q] = true; stack.append(q) }
                    }
                }
            }
            if n >= speck { out.append(Blob(x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1, count: n)) }
        }
        return out
    }

    /// Patches close together are one creature (feet drawn apart from the body, an eye's shine).
    static func merged(_ blobs: [Blob], margin: Int) -> [Blob] {
        var groups = blobs
        var changed = true
        while changed {
            changed = false
            outer: for a in groups.indices {
                for b in groups.indices where b > a {
                    let p = groups[a], q = groups[b]
                    let apart = p.x - margin > q.x + q.w || q.x - margin > p.x + p.w
                        || p.y - margin > q.y + q.h || q.y - margin > p.y + p.h
                    guard !apart else { continue }
                    let x0 = min(p.x, q.x), y0 = min(p.y, q.y)
                    let x1 = max(p.x + p.w, q.x + q.w), y1 = max(p.y + p.h, q.y + q.h)
                    groups[a] = Blob(x: x0, y: y0, w: x1 - x0, h: y1 - y0, count: p.count + q.count)
                    groups.remove(at: b)
                    changed = true
                    break outer
                }
            }
        }
        return groups
    }

    /// Top row first, each row left to right; a row is everything whose middle is
    /// within half a creature of the row's first.
    static func readingOrder(_ groups: [Blob]) -> [Blob] {
        let tall = median(groups.map(\.h).sorted())
        var rows: [[Blob]] = []
        for g in groups.sorted(by: { $0.midY < $1.midY }) {
            if let first = rows.last?.first, abs(g.midY - first.midY) <= Double(tall) / 2 { rows[rows.count - 1].append(g) }
            else { rows.append([g]) }
        }
        return rows.flatMap { $0.sorted { $0.midX < $1.midX } }
    }

    static func median(_ sorted: [Int]) -> Int { sorted.isEmpty ? 0 : sorted[sorted.count / 2] }

    // MARK: Down to sprite pixels

    /// The creature in `g` as a grid of colours (nil = nothing), each sprite pixel
    /// `side` picture pixels wide. A sprite pixel is painted when most of the middle
    /// of its square is, in the middle colour of what is painted there, so a blurred
    /// or anti-aliased edge never decides it.
    static func downscale(_ image: SpriteText.Image, _ solid: [Bool], _ g: Blob, _ side: Double) -> [[SpriteText.Tint?]] {
        let limit = SpriteText.box.w
        let tw = min(limit, max(1, Int((Double(g.w) / side).rounded()))), th = min(limit, max(1, Int((Double(g.h) / side).rounded())))
        let sx = Double(g.w) / Double(tw), sy = Double(g.h) / Double(th)
        var grid = [[SpriteText.Tint?]](repeating: [SpriteText.Tint?](repeating: nil, count: tw), count: th)
        for ty in 0..<th {
            for tx in 0..<tw {
                let x0 = Double(g.x) + (Double(tx) + 0.2) * sx, x1 = Double(g.x) + (Double(tx) + 0.8) * sx
                let y0 = Double(g.y) + (Double(ty) + 0.2) * sy, y1 = Double(g.y) + (Double(ty) + 0.8) * sy
                let xs = samples(x0, x1), ys = samples(y0, y1)
                var r: [UInt8] = [], gg: [UInt8] = [], b: [UInt8] = [], total = 0
                for y in ys where y >= 0 && y < image.height {
                    for x in xs where x >= 0 && x < image.width {
                        total += 1
                        let p = y * image.width + x
                        guard solid[p] else { continue }
                        r.append(image.rgba[p * 4]); gg.append(image.rgba[p * 4 + 1]); b.append(image.rgba[p * 4 + 2])
                    }
                }
                guard total > 0, r.count * 2 > total else { continue }
                r.sort(); gg.sort(); b.sort()
                grid[ty][tx] = SpriteText.Tint(r: r[r.count / 2], g: gg[gg.count / 2], b: b[b.count / 2])
            }
        }
        return grid
    }

    /// Up to nine evenly spaced picture coordinates across [a, b).
    static func samples(_ a: Double, _ b: Double) -> [Int] {
        let first = Int(a.rounded(.down)), last = max(first, Int(b.rounded(.up)) - 1)
        let span = last - first + 1
        guard span > 9 else { return Array(first...last) }
        return (0..<9).map { first + $0 * (span - 1) / 8 }
    }

    /// The grid trimmed and put in a 32×32 cell: centred left to right in the body
    /// box, standing on the floor.
    static func placed(_ grid: [[SpriteText.Tint?]]) -> [[SpriteText.Tint?]] {
        let cell = SpriteText.cell, box = SpriteText.box
        var out = [[SpriteText.Tint?]](repeating: [SpriteText.Tint?](repeating: nil, count: cell), count: cell)
        let rows = grid.indices.filter { y in grid[y].contains { $0 != nil } }
        let columns = (grid.first?.indices ?? 0..<0).filter { x in grid.contains { $0[x] != nil } }
        guard let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last else { return out }
        let w = right - left + 1, h = bottom - top + 1
        let ox = box.x + (box.w - w) / 2, oy = SpriteText.floor - h
        for y in 0..<h { for x in 0..<w { out[oy + y][ox + x] = grid[top + y][left + x] } }
        return out
    }

    // MARK: Inks

    static func luma(_ t: SpriteText.Tint) -> Double { 0.299 * Double(t.r) + 0.587 * Double(t.g) + 0.114 * Double(t.b) }

    static func nearBlack(_ t: SpriteText.Tint) -> Bool {
        let hi = max(t.r, t.g, t.b), lo = min(t.r, t.g, t.b)
        return hi < 72 && hi - lo < 36
    }

    /// The colour most of the creatures' insides are painted in.
    static func bodyColour(_ grids: [[[SpriteText.Tint?]]]) -> SpriteText.Tint {
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        func count(insideOnly: Bool) {
            for grid in grids {
                for y in grid.indices {
                    for x in grid[y].indices {
                        guard let t = grid[y][x] else { continue }
                        if insideOnly {
                            let edge = [(0, -1), (0, 1), (-1, 0), (1, 0)].contains { dx, dy in
                                let yy = y + dy, xx = x + dx
                                return !grid.indices.contains(yy) || !grid[yy].indices.contains(xx) || grid[yy][xx] == nil
                            }
                            if edge || nearBlack(t) { continue }
                        }
                        let bucket = Int(t.r >> 4) << 8 | Int(t.g >> 4) << 4 | Int(t.b >> 4)
                        let c = counts[bucket] ?? (0, 0, 0, 0)
                        counts[bucket] = (c.n + 1, c.r + Int(t.r), c.g + Int(t.g), c.b + Int(t.b))
                    }
                }
            }
        }
        count(insideOnly: true)
        if counts.isEmpty { count(insideOnly: false) }
        guard let top = counts.values.max(by: { $0.n < $1.n }) else { return SpriteText.Palette.blocky.body }
        return SpriteText.Tint(r: UInt8(top.r / top.n), g: UInt8(top.g / top.n), b: UInt8(top.b / top.n))
    }

    /// Colours to inks, in Blocky's style: every pixel on the edge is outline;
    /// inside, a dark patch touching the outline is more outline (the feet), a
    /// black patch on its own is an eye, and the rest is light, shade or body by
    /// how bright it is beside the body colour.
    static func inks(_ grid: [[SpriteText.Tint?]], body: SpriteText.Tint) -> [[SpriteText.Ink]] {
        let n = grid.count
        let lb = luma(body), step = max(16, lb * 0.1)
        func painted(_ x: Int, _ y: Int) -> Bool { y >= 0 && y < n && x >= 0 && x < n && grid[y][x] != nil }
        func edge(_ x: Int, _ y: Int) -> Bool { !painted(x - 1, y) || !painted(x + 1, y) || !painted(x, y - 1) || !painted(x, y + 1) }
        func dark(_ t: SpriteText.Tint) -> Bool { nearBlack(t) || luma(t) < lb * 0.55 }

        var out = [[SpriteText.Ink]](repeating: [SpriteText.Ink](repeating: .clear, count: n), count: n)
        var done = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        for y in 0..<n {
            for x in 0..<n {
                guard let t = grid[y][x] else { continue }
                if edge(x, y) { out[y][x] = .outline; done[y][x] = true; continue }
                guard !dark(t) else { continue }
                let l = luma(t)
                out[y][x] = l > lb + step ? .light : l < lb - step ? .shade : .body
                done[y][x] = true
            }
        }
        // What is left is dark and inside: one patch at a time.
        for y in 0..<n {
            for x in 0..<n where !done[y][x] && grid[y][x] != nil {
                var patch: [(Int, Int)] = [], stack = [(x, y)], touchesOutline = false, black = 0
                done[y][x] = true
                while let (px, py) = stack.popLast() {
                    patch.append((px, py))
                    if nearBlack(grid[py][px]!) { black += 1 }
                    for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                        let qx = px + dx, qy = py + dy
                        guard painted(qx, qy) else { continue }
                        if edge(qx, qy) { if dark(grid[qy][qx]!) { touchesOutline = true } ; continue }
                        if !done[qy][qx], dark(grid[qy][qx]!) { done[qy][qx] = true; stack.append((qx, qy)) }
                    }
                }
                let ink: SpriteText.Ink = touchesOutline ? .outline : black * 2 >= patch.count ? .eye : .shade
                for (px, py) in patch { out[py][px] = ink }
            }
        }
        // A blurred eye leaves a shade-dark halo beside it, which would stay put
        // when the lid comes down. Shade touching an eye, away from the outline
        // (where the real shade line runs), is part of the eye.
        // One pixel deep: a whole darker patch beside an eye stays shade.
        var halo: [(Int, Int)] = []
        for y in 0..<n {
            for x in 0..<n where out[y][x] == .shade {
                let around = [(0, -1), (0, 1), (-1, 0), (1, 0)].map { dx, dy in
                    y + dy >= 0 && y + dy < n && x + dx >= 0 && x + dx < n ? out[y + dy][x + dx] : .clear
                }
                if around.contains(.eye), !around.contains(.outline) { halo.append((x, y)) }
            }
        }
        for (x, y) in halo { out[y][x] = .eye }
        return out
    }
}
