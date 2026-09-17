import AppKit
import LedgelingsCore

/// A packed sprite sheet: the PNG and JSON that `spritetool pack` writes.
struct SpriteAtlas {
    struct Meta: Decodable {
        struct Rect: Decodable { let x, y, w, h: Int }
        struct Animation: Decodable { let frames: [String]; let fps: Double; let loop: Bool }
        let name: String
        let image: String
        let cell: [Int]
        let contentBox: [Int]
        let variants: [String]
        let palette: [String: String]?
        let frames: [String: Rect]
        let animations: [String: Animation]
    }

    /// One recolouring of the sheet, already cut into frames.
    struct Frames {
        fileprivate let meta: Meta
        fileprivate let images: [String: CGImage]

        /// The frame for an animation at `time` seconds in, with the given eye state.
        func frame(animation: String, time: Double, eyes: Eyes = .open) -> CGImage? {
            guard let anim = meta.animations[animation], !anim.frames.isEmpty else { return nil }
            let raw = Int(time * anim.fps)
            let index = anim.loop ? raw % anim.frames.count : min(raw, anim.frames.count - 1)
            let pose = anim.frames[index]
            return images["\(pose)_\(eyes.rawValue)"] ?? images[pose]
        }
    }

    enum LoadError: Error, CustomStringConvertible {
        case notFound(String), unreadable(String), badFrame(String)
        var description: String {
            switch self {
            case .notFound(let what): "sprite resource not found: \(what)"
            case .unreadable(let what): "cannot read sprite resource: \(what)"
            case .badFrame(let name): "atlas frame \(name) lies outside the sheet"
            }
        }
    }

    let meta: Meta
    private let sheet: CGImage

    var cellSize: CGSize { CGSize(width: meta.cell[0], height: meta.cell[1]) }
    /// Half the width of the square the creature is drawn inside, in sheet pixels.
    var bodyHalfSize: CGFloat { CGFloat(meta.contentBox[2]) / 2 }

    init(named name: String) throws {
        let directory = try Self.spritesDirectory()
        let jsonURL = directory.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: jsonURL) else { throw LoadError.notFound(jsonURL.path) }
        meta = try JSONDecoder().decode(Meta.self, from: data)

        let imageURL = directory.appendingPathComponent(meta.image)
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw LoadError.unreadable(imageURL.path) }
        sheet = image
        for (frame, r) in meta.frames where r.x + r.w > image.width || r.y + r.h > image.height {
            throw LoadError.badFrame(frame)
        }
    }

    /// The sheet cut into frames, recoloured around `body` when the atlas has a
    /// palette. Nil body means "as painted".
    func frames(body: RGB? = nil) -> Frames {
        let source = body.flatMap { recoloured(around: $0) } ?? sheet
        var cut: [String: CGImage] = [:]
        for (frame, r) in meta.frames {
            // CGImage cropping is top-left origin, the same as the atlas JSON.
            cut[frame] = source.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h))
        }
        return Frames(meta: meta, images: cut)
    }

    /// Swap the atlas palette for shades of `body`. Every other pixel -- the
    /// black eyes above all -- is left exactly as it was.
    private func recoloured(around body: RGB) -> CGImage? {
        guard let palette = meta.palette, !palette.isEmpty else { return nil }
        let targets: [String: RGB] = [
            "body": body, "light": body.mixed(with: .white, 0.36),
            "shade": body.mixed(with: .black, 0.17), "outline": body.mixed(with: .black, 0.76),
        ]
        let swaps = palette.compactMap { name, hex -> (RGB, RGB)? in
            guard let from = RGB(hex: hex), let to = targets[name] else { return nil }
            return (from, to)
        }
        let w = sheet.width, h = sheet.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(sheet, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) where px[i + 3] == 255 {
            let here = RGB(r: px[i], g: px[i + 1], b: px[i + 2])
            if let (_, to) = swaps.first(where: { $0.0.isClose(to: here) }) {
                px[i] = to.r; px[i + 1] = to.g; px[i + 2] = to.b
            }
        }
        return ctx.makeImage()
    }

    /// Inside an .app the sheets sit in Contents/Resources/sprites; under
    /// `swift run` they are in the SwiftPM resource bundle. The main bundle is
    /// tried first ON PURPOSE: touching `Bundle.module` where that bundle does
    /// not exist (a hand-assembled .app) is a crash, not a nil.
    private static func spritesDirectory() throws -> URL {
        let exists = { (url: URL?) -> URL? in
            guard let dir = url?.appendingPathComponent("sprites", isDirectory: true),
                  FileManager.default.fileExists(atPath: dir.path) else { return nil }
            return dir
        }
        if let found = exists(Bundle.main.resourceURL) ?? exists(Bundle.module.resourceURL) { return found }
        throw LoadError.notFound("sprites/")
    }
}

/// An sRGB colour, 8 bits a channel, that round-trips through "#rrggbb".
struct RGB: Hashable {
    var r, g, b: UInt8

    static let white = RGB(r: 255, g: 255, b: 255)
    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
    }

    var hex: String { String(format: "#%02x%02x%02x", r, g, b) }

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * (1 - amount) + Double(b) * amount).rounded()) }
        return RGB(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b))
    }

    /// Exact in practice; the slack absorbs a colour-managed decode being off by one.
    func isClose(to other: RGB) -> Bool {
        abs(Int(r) - Int(other.r)) <= 2 && abs(Int(g) - Int(other.g)) <= 2 && abs(Int(b) - Int(other.b)) <= 2
    }
}
