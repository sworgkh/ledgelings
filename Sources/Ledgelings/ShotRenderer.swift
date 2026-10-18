import AppKit
import LedgelingsCore

/// Puts the finished picture together from the frozen monitors: the area cut out (a
/// lasso's outside left see-through), or every monitor stitched, then each mark drawn
/// on in order. A blur is baked in: its blocks are averaged from what is under them
/// by then, boxes and arrows included, so nothing hidden can be read back.
@MainActor
enum ShotRenderer {
    /// What was taken: an area of one monitor, a loop on one, or all of them.
    enum Area {
        case rect(CGRect, monitor: Int)
        case lasso(Shot.Lasso, monitor: Int)
        case all

        /// The area in global points; every monitor's frame together for `all`.
        func bounds(_ frames: [ShotFrame]) -> CGRect {
            switch self {
            case .rect(let r, let m): r.intersection(frames[m].monitor.frame)
            case .lasso(let l, let m): l.bounds.intersection(frames[m].monitor.frame)
            case .all: frames.map(\.monitor.frame).reduce(frames.first?.monitor.frame ?? .zero) { $0.union($1) }
            }
        }
    }

    static func mapping(_ area: Area, frames: [ShotFrame]) -> Shot.Mapping {
        switch area {
        case .rect(_, let m), .lasso(_, let m): .area(area.bounds(frames), scale: frames[m].monitor.scale)
        case .all: .all(frames.map(\.monitor))
        }
    }

    static func render(_ frames: [ShotFrame], area: Area, marks: [Shot.Mark]) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let map = mapping(area, frames: frames)
        let size: CGSize
        switch area {
        case .rect(_, let m), .lasso(_, let m):
            size = Shot.pixelRect(area.bounds(frames), on: frames[m].monitor).size
        case .all:
            size = Shot.stitch(frames.map(\.monitor)).size
        }
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Pixels from the top-left, y down, as the core counts them.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        switch area {
        case .rect(_, let m), .lasso(_, let m):
            let frame = frames[m]
            if case .lasso(let lasso, _) = area {
                let path = CGMutablePath()
                path.addLines(between: lasso.points.map(map.pixel))
                path.closeSubpath()
                context.addPath(path)
                context.clip()
            }
            let cut = Shot.pixelRect(area.bounds(frames), on: frame.monitor)
            if let piece = frame.image.cropping(to: cut) { draw(piece, in: CGRect(origin: .zero, size: cut.size), context) }
        case .all:
            let places = Shot.stitch(frames.map(\.monitor)).places
            for (frame, place) in zip(frames, places) { draw(frame.image, in: place, context) }
        }
        context.resetClip()
        for mark in marks {
            let scale = map.scale(at: mark.anchor)
            draw(map.pixels(mark), in: context, size: size, block: Int((Shot.blurBlock * scale).rounded()))
        }
        return context.makeImage()
    }

    /// An image upright in a y-down context.
    private static func draw(_ image: CGImage, in rect: CGRect, _ context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func colour(_ index: Int, alpha: Double = 1) -> CGColor {
        let c = Shot.palette[Shot.colourRange.contains(index) ? index : 0]
        return CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: alpha)
    }

    /// One mark, already in the context's units. A blur needs the context's own pixels
    /// (`size` of them, `block` to a square); on screen it is drawn by `ShotCanvas` instead.
    static func draw(_ mark: Shot.Mark, in context: CGContext, size: CGSize = .zero, block: Int = 0) {
        context.saveGState()
        defer { context.restoreGState() }
        // Square ends and sharp corners: nothing round, as in the creatures' sheets.
        context.setLineCap(.square)
        context.setLineJoin(.miter)
        switch mark {
        case .box(let r, let c, let t):
            context.setStrokeColor(colour(c))
            context.setLineWidth(t)
            context.stroke(r.insetBy(dx: t / 2, dy: t / 2))
        case .arrow(let a, let b, let c, let t):
            let head = Shot.arrowHead(from: a, to: b, thickness: t)
            context.setStrokeColor(colour(c))
            context.setFillColor(colour(c))
            context.setLineWidth(t)
            context.setLineCap(.butt)
            context.move(to: a)
            context.addLine(to: CGPoint(x: (head[1].x + head[2].x) / 2, y: (head[1].y + head[2].y) / 2))
            context.strokePath()
            context.move(to: head[0])
            context.addLine(to: head[1])
            context.addLine(to: head[2])
            context.closePath()
            context.fillPath()
        case .highlight(let r, let c):
            context.setFillColor(colour(c, alpha: Shot.highlightOpacity))
            context.fill(r)
        case .blur(let r):
            pixelate(context, cells: Shot.blurCells(r, block: block, size: size))
        case .brush(let points, let width):
            pixelate(context, cells: Shot.brushCells(points, width: width, block: block, size: size))
        }
    }

    /// Averages each cell of the context's own pixels, in place. Its first row is the picture's top.
    private static func pixelate(_ context: CGContext, cells: [CGRect]) {
        guard !cells.isEmpty, let data = context.data else { return }
        let count = context.bytesPerRow * context.height
        var bytes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
        Shot.pixelate(&bytes, width: context.width, height: context.height, bytesPerRow: context.bytesPerRow, cells: cells)
        bytes.withUnsafeBufferPointer { data.copyMemory(from: $0.baseAddress!, byteCount: count) }
    }

    /// The whole picture in big square blocks, for drawing a blur on screen before it is baked.
    static func blocky(_ image: CGImage, block: CGFloat) -> CGImage? {
        let w = max(Int((CGFloat(image.width) / block).rounded(.up)), 1), h = max(Int((CGFloat(image.height) / block).rounded(.up)), 1)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width) / block, height: CGFloat(image.height) / block))
        return context.makeImage()
    }

    /// A tiny picture of the shot for a creature to carry: `size` pixels, a 1-pixel
    /// dark rim like the creatures' own, the shot squeezed inside it.
    static func thumbnail(_ image: CGImage, size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 2, h > 2,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(ScreenOverlay.ink)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
        context.interpolationQuality = .medium
        let inside = CGRect(x: 1, y: 1, width: w - 2, height: h - 2)
        let k = min(inside.width / CGFloat(image.width), inside.height / CGFloat(image.height))
        let fit = CGRect(x: 0, y: 0, width: max((CGFloat(image.width) * k).rounded(), 1), height: max((CGFloat(image.height) * k).rounded(), 1))
        context.draw(image, in: fit.offsetBy(dx: inside.midX - fit.width / 2, dy: inside.midY - fit.height / 2).integral)
        return context.makeImage()
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
