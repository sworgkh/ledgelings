import CoreGraphics
import Foundation

/// A closed path made only of horizontal and vertical segments, walked with the
/// inside of the screens on the LEFT. Coordinates are AppKit's global ones:
/// origin bottom-left, y up.
///
/// A position on the loop is one number `t` in `0..<length`. Each segment has a
/// `rotation`: how far a sprite drawn "standing on a floor, facing right" must be
/// turned (radians, counter-clockwise) to stand on that segment with its body
/// pointing inside. Walking rightwards along a floor is rotation 0.
public struct EdgeLoop: Equatable, Sendable {
    public let vertices: [CGPoint]
    private let starts: [CGFloat]      // loop position where each segment begins
    public let length: CGFloat

    public init(vertices: [CGPoint]) {
        precondition(vertices.count >= 4, "a loop needs at least four corners")
        self.vertices = vertices
        var starts: [CGFloat] = [], total: CGFloat = 0
        for i in vertices.indices {
            starts.append(total)
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            total += abs(b.x - a.x) + abs(b.y - a.y)
        }
        self.starts = starts
        length = total
    }

    /// The loop just inside one rectangle, starting at its bottom-left corner.
    public init(rect: CGRect) {
        self.init(vertices: [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ])
    }

    public var segmentCount: Int { vertices.count }

    public func wrap(_ t: CGFloat) -> CGFloat {
        let m = t.truncatingRemainder(dividingBy: length)
        return m < 0 ? m + length : m
    }

    public func segment(at t: CGFloat) -> Int {
        let w = wrap(t)
        return (starts.lastIndex { $0 <= w }) ?? 0
    }

    public func length(ofSegment i: Int) -> CGFloat {
        (i + 1 < starts.count ? starts[i + 1] : length) - starts[i]
    }

    /// Unit vector along segment `i`, in walking (+t) direction.
    public func direction(ofSegment i: Int) -> CGVector {
        let a = vertices[i], b = vertices[(i + 1) % vertices.count]
        let len = max(length(ofSegment: i), .leastNonzeroMagnitude)
        return CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
    }

    /// Unit vector pointing from segment `i` into the screen.
    public func inward(ofSegment i: Int) -> CGVector {
        let d = direction(ofSegment: i)
        return CGVector(dx: -d.dy, dy: d.dx)
    }

    public func rotation(ofSegment i: Int) -> Double {
        let d = direction(ofSegment: i)
        let angle = atan2(Double(d.dy), Double(d.dx))
        return angle < 0 ? angle + 2 * .pi : angle
    }

    public func point(at t: CGFloat) -> CGPoint {
        let i = segment(at: t), d = direction(ofSegment: i), along = wrap(t) - starts[i]
        return CGPoint(x: vertices[i].x + d.dx * along, y: vertices[i].y + d.dy * along)
    }

    public func t(onSegment i: Int, fraction: CGFloat) -> CGFloat {
        starts[i] + length(ofSegment: i) * min(max(fraction, 0), 1)
    }

    /// The loop position closest to `point`, and how far away it is.
    public func nearest(to point: CGPoint) -> (t: CGFloat, distance: CGFloat) {
        var best: (t: CGFloat, distance: CGFloat) = (0, .infinity)
        for i in vertices.indices {
            let a = vertices[i], d = direction(ofSegment: i)
            let along = min(max((point.x - a.x) * d.dx + (point.y - a.y) * d.dy, 0), length(ofSegment: i))
            let distance = hypot(a.x + d.dx * along - point.x, a.y + d.dy * along - point.y)
            if distance < best.distance { best = (starts[i] + along, distance) }
        }
        return best
    }
}
