import CoreGraphics
import Foundation

/// Every edge a creature can walk, across all monitors.
///
/// Monitors that touch are fused: the creature walks the OUTLINE of the whole
/// desktop, not the border of each screen. So it crosses from one monitor to the
/// next along a shared floor, climbs the wall where a taller monitor begins, and
/// never walks the invisible seam between two screens.
///
/// The outline is pulled inwards by `inset` (half the creature's body), so a
/// loop position is where the creature's CENTRE goes. That makes every corner a
/// plain rotation about the creature's own centre.
public struct EdgeWorld: Equatable, Sendable {
    public struct Spot: Equatable, Sendable {
        public var loop: Int
        public var t: CGFloat
        public init(loop: Int, t: CGFloat) { self.loop = loop; self.t = t }
    }

    public let loops: [EdgeLoop]

    public init(loops: [EdgeLoop]) {
        precondition(!loops.isEmpty, "a world needs at least one loop")
        self.loops = loops
    }

    public init(screens: [CGRect], inset: CGFloat) {
        let usable = screens.filter { $0.width > 4 && $0.height > 4 }
        let smallest = usable.map { min($0.width, $0.height) }.min() ?? 0
        let d = max(0, min(inset, smallest / 2 - 1))
        let traced = Self.trace(screens: usable, inset: d)
        self.init(loops: traced.isEmpty ? [EdgeLoop(rect: CGRect(x: 0, y: 0, width: 100, height: 100))] : traced)
    }

    public func point(at spot: Spot) -> CGPoint { loops[spot.loop].point(at: spot.t) }

    public func nearest(to point: CGPoint) -> Spot {
        let all = loops.indices.map { (loop: $0, hit: loops[$0].nearest(to: point)) }
        let best = all.min { $0.hit.distance < $1.hit.distance }!
        return Spot(loop: best.loop, t: best.hit.t)
    }

    /// Every (loop, segment) pair, for choosing somewhere to jump to.
    public var segments: [(loop: Int, segment: Int, length: CGFloat)] {
        loops.indices.flatMap { l in
            (0..<loops[l].segmentCount).map { (l, $0, loops[l].length(ofSegment: $0)) }
        }
    }

    // MARK: Tracing the outline

    /// Shrink the union of `screens` by `d` and return its boundary loops.
    ///
    /// Works on a grid whose lines are every screen edge and every screen edge
    /// moved by ±d -- the only places the shrunken outline can turn. A grid cell
    /// survives if the cell grown back by `d` is still fully on screen.
    static func trace(screens: [CGRect], inset d: CGFloat) -> [EdgeLoop] {
        guard !screens.isEmpty else { return [] }
        func lines(_ edges: [CGFloat]) -> [CGFloat] {
            let all = edges.flatMap { [$0 - d, $0, $0 + d] }.sorted()
            return all.reduce(into: [CGFloat]()) { if $0.isEmpty || $1 - $0.last! > 0.01 { $0.append($1) } }
        }
        let edgeXs = screens.flatMap { [$0.minX, $0.maxX] }, edgeYs = screens.flatMap { [$0.minY, $0.maxY] }
        let xs = lines(edgeXs), ys = lines(edgeYs)

        func covered(_ r: CGRect) -> Bool {
            let cx = ([r.minX, r.maxX] + edgeXs.filter { $0 > r.minX && $0 < r.maxX }).sorted()
            let cy = ([r.minY, r.maxY] + edgeYs.filter { $0 > r.minY && $0 < r.maxY }).sorted()
            for i in 0..<(cx.count - 1) where cx[i + 1] - cx[i] > 0.001 {
                for j in 0..<(cy.count - 1) where cy[j + 1] - cy[j] > 0.001 {
                    let mid = CGPoint(x: (cx[i] + cx[i + 1]) / 2, y: (cy[j] + cy[j + 1]) / 2)
                    if !screens.contains(where: { $0.contains(mid) }) { return false }
                }
            }
            return true
        }

        let nx = xs.count - 1, ny = ys.count - 1
        var inside = Array(repeating: Array(repeating: false, count: ny), count: nx)
        for i in 0..<nx { for j in 0..<ny {
            let cell = CGRect(x: xs[i], y: ys[j], width: xs[i + 1] - xs[i], height: ys[j + 1] - ys[j])
            inside[i][j] = covered(cell.insetBy(dx: -d + 0.01, dy: -d + 0.01))
        } }
        func isIn(_ i: Int, _ j: Int) -> Bool { i >= 0 && j >= 0 && i < nx && j < ny && inside[i][j] }

        // Boundary edges between grid points, directed so the inside is on the left.
        struct P: Hashable { let i: Int, j: Int }
        var out: [P: [P]] = [:]
        for i in 0..<nx { for j in 0..<ny where inside[i][j] {
            if !isIn(i, j - 1) { out[P(i: i, j: j), default: []].append(P(i: i + 1, j: j)) }
            if !isIn(i + 1, j) { out[P(i: i + 1, j: j), default: []].append(P(i: i + 1, j: j + 1)) }
            if !isIn(i, j + 1) { out[P(i: i + 1, j: j + 1), default: []].append(P(i: i, j: j + 1)) }
            if !isIn(i - 1, j) { out[P(i: i, j: j + 1), default: []].append(P(i: i, j: j)) }
        } }

        var loops: [EdgeLoop] = []
        while let start = out.keys.min(by: { ($0.j, $0.i) < ($1.j, $1.i) }) {
            var path = [start], here = start
            repeat {
                guard var nexts = out[here], !nexts.isEmpty else { break }
                let next = nexts.removeFirst()
                out[here] = nexts.isEmpty ? nil : nexts
                path.append(next)
                here = next
            } while here != start
            guard here == start, path.count > 4 else { continue }
            path.removeLast()
            // Keep only real corners.
            let n = path.count
            let corners = (0..<n).filter { k in
                let a = path[(k + n - 1) % n], b = path[k], c = path[(k + 1) % n]
                return (b.i - a.i) * (c.j - b.j) - (b.j - a.j) * (c.i - b.i) != 0
            }
            guard corners.count >= 4 else { continue }
            loops.append(EdgeLoop(vertices: corners.map { CGPoint(x: xs[path[$0].i], y: ys[path[$0].j]) }))
        }
        return loops
    }
}
