import AppKit
import Combine
import LedgelingsCore
import UniformTypeIdentifiers

/// Every creature sheet the app can use: the built-in one, plus whatever the
/// user imported into `~/Library/Application Support/Ledgelings/sprites/<name>/`.
///
/// An import takes either the text format (`SpriteText`) or a painted PNG in
/// the same 288×96 layout on magenta, and writes a normal atlas (PNG + JSON)
/// the app loads like its own.
@MainActor
final class SpriteLibrary: ObservableObject {
    struct Species: Identifiable {
        let name: String
        let isBuiltIn: Bool
        let atlas: SpriteAtlas
        var id: String { name }
    }

    enum ImportError: Error, CustomStringConvertible {
        case unreadable(String), notASheet(String), wrongSize(Int, Int), badName(String)
        var description: String {
            switch self {
            case .unreadable(let what): "cannot read \(what)"
            case .notASheet(let what): "\(what) is neither a sprite text file (.txt, .md) nor a PNG"
            case .wrongSize(let w, let h): "the PNG is \(w)×\(h); a sheet is 288×96, or a whole multiple of that"
            case .badName(let n): "\"\(n)\" cannot be used: lowercase letters, digits and dashes only, and not a built-in name"
            }
        }
    }

    /// The sheets shipped in the app, in the order the Sprites tab shows them.
    nonisolated static let builtIn = ["blocky", "frog", "cat", "ghost", "slime", "robot", "triangle", "mushroom"]

    static var defaultDirectory: URL {
        ChatHistory.defaultDirectory.deletingLastPathComponent().appendingPathComponent("sprites", isDirectory: true)
    }
    nonisolated static let keyColour = SpriteText.Tint(r: 255, g: 0, b: 255)
    nonisolated static let keyTolerance = 60

    let directory: URL
    @Published private(set) var species: [Species] = []

    init(directory: URL = SpriteLibrary.defaultDirectory) {
        self.directory = directory
        reload()
    }

    func reload() {
        var found: [Species] = []
        for name in Self.builtIn {
            if let atlas = try? SpriteAtlas(named: name) { found.append(Species(name: name, isBuiltIn: true, atlas: atlas)) }
        }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        for name in names where !Self.builtIn.contains(name) {
            guard let atlas = try? SpriteAtlas(directory: directory.appendingPathComponent(name), name: name) else { continue }
            found.append(Species(name: name, isBuiltIn: false, atlas: atlas))
        }
        species = found
    }

    func atlas(named name: String) -> SpriteAtlas? { species.first { $0.name == name }?.atlas }

    /// What a species is, for the prompt: from its sheet, or the built-in wording.
    func kind(of name: String) -> String {
        if name == "blocky" { return Banter.defaultKind }
        return atlas(named: name)?.meta.kind ?? "a small pixel creature"
    }

    /// Who a species' creatures are, before the user edits them.
    func cast(of name: String) -> [Character] {
        if name == "blocky" { return Banter.defaultCharacters }
        let cast = atlas(named: name)?.meta.cast ?? []
        return cast.isEmpty ? [Character(name: name.capitalized, persona: "Curious and new here.")] : cast
    }

    /// What a creature of this species is painted in: the sheet's own colour when
    /// it names one, otherwise `slot`, the colour of the creature's number.
    func bodyColour(of name: String, slot: RGB) -> RGB {
        atlas(named: name)?.meta.colour.flatMap(RGB.init(hex:)) ?? slot
    }

    /// Import a text sheet or a painted PNG. Returns the species name.
    @discardableResult
    func importFile(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let sheet: SpriteText.Image
        let name: String
        var kind: String?
        var cast: [Character] = []
        var colour: SpriteText.Tint?
        var source: (data: Data, ext: String)?
        if ext == "png" {
            sheet = try Self.keyedOut(try Self.readPNG(url))
            name = url.deletingPathExtension().lastPathComponent.lowercased()
        } else if ["txt", "md", "text", ""].contains(ext) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw ImportError.unreadable(url.lastPathComponent) }
            let parsed = try SpriteText.parse(text)
            sheet = SpriteText.pixels(parsed, palette: .blocky)
            name = parsed.name
            kind = parsed.kind
            cast = parsed.cast
            colour = parsed.colour
            source = (Data(text.utf8), "txt")
        } else {
            throw ImportError.notASheet(url.lastPathComponent)
        }
        guard name.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil, !Self.builtIn.contains(name) else {
            throw ImportError.badName(name)
        }
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.writePNG(sheet, to: folder.appendingPathComponent("\(name).png"))
        let meta = try JSONSerialization.data(withJSONObject: SpriteText.atlas(name: name, kind: kind, cast: cast, colour: colour), options: [.prettyPrinted, .sortedKeys])
        try meta.write(to: folder.appendingPathComponent("\(name).json"))
        if let source { try source.data.write(to: folder.appendingPathComponent("\(name).\(source.ext)")) }
        reload()
        return name
    }

    func remove(_ name: String) {
        guard let found = species.first(where: { $0.name == name }), !found.isBuiltIn else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        reload()
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    // MARK: The sprite kit

    /// The built-in creature written in the text format: the worked example, and a file to hand out.
    var exampleText: String {
        guard let image = try? SpriteAtlas(named: "blocky").image() else { return "" }
        var lines = ["name: blocky"]
        for pose in SpriteText.poses {
            lines.append("pose: \(pose)")
            lines += SpriteText.describe(image, pose: pose, palette: .blocky)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// What to paste into a chat model.
    var prompt: String {
        let idle = (try? SpriteAtlas(named: "blocky").image()).map { SpriteText.describe($0, pose: "idle", palette: .blocky) } ?? []
        return SpriteText.prompt(example: idle)
    }

    /// A blank 288×96 sheet on magenta with the cells and body boxes marked, for an image model or a paint program.
    func templateImage() -> SpriteText.Image {
        let cell = SpriteText.cell, box = SpriteText.box
        let w = SpriteText.poses.count * cell, h = SpriteText.variants.count * cell
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ t: SpriteText.Tint) {
            let i = (y * w + x) * 4
            rgba[i] = t.r; rgba[i + 1] = t.g; rgba[i + 2] = t.b; rgba[i + 3] = 255
        }
        let key = Self.keyColour, grid = SpriteText.Tint(r: 200, g: 0, b: 200), boxLine = SpriteText.Tint(r: 255, g: 120, b: 255)
        for y in 0..<h { for x in 0..<w { put(x, y, key) } }
        for y in 0..<h { for x in stride(from: 0, to: w, by: cell) { put(x, y, grid) } }
        for x in 0..<w { for y in stride(from: 0, to: h, by: cell) { put(x, y, grid) } }
        for column in 0..<SpriteText.poses.count {
            for row in 0..<SpriteText.variants.count {
                let ox = column * cell + box.x, oy = row * cell + box.y
                for x in ox..<(ox + box.w) { put(x, oy, boxLine); put(x, oy + box.h - 1, boxLine) }
                for y in oy..<(oy + box.h) { put(ox, y, boxLine); put(ox + box.w - 1, y, boxLine) }
            }
        }
        return SpriteText.Image(width: w, height: h, rgba: rgba)
    }

    // MARK: PNG in and out

    nonisolated static func readPNG(_ url: URL) throws -> SpriteText.Image {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImportError.unreadable(url.lastPathComponent) }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { throw ImportError.unreadable(url.lastPathComponent) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return SpriteText.Image(width: w, height: h, rgba: Array(UnsafeBufferPointer(start: px, count: w * h * 4)))
    }

    /// Magenta (within tolerance) becomes transparent; alpha is hardened to 1 bit;
    /// a sheet painted at a whole-number scale is brought down by sampling.
    nonisolated static func keyedOut(_ image: SpriteText.Image) throws -> SpriteText.Image {
        let w = SpriteText.poses.count * SpriteText.cell, h = SpriteText.variants.count * SpriteText.cell
        guard image.width % w == 0, image.height % h == 0, image.width / w == image.height / h, image.width >= w else {
            throw ImportError.wrongSize(image.width, image.height)
        }
        let k = image.width / w
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let key = keyColour, limit = keyTolerance * keyTolerance
        for y in 0..<h {
            for x in 0..<w {
                let src = ((y * k + k / 2) * image.width + x * k + k / 2) * 4, dst = (y * w + x) * 4
                let r = Int(image.rgba[src]), g = Int(image.rgba[src + 1]), b = Int(image.rgba[src + 2]), a = Int(image.rgba[src + 3])
                let isKey = (r - Int(key.r)) * (r - Int(key.r)) + (g - Int(key.g)) * (g - Int(key.g)) + (b - Int(key.b)) * (b - Int(key.b)) <= limit
                guard a >= 128, !isKey else { continue }
                out[dst] = UInt8(r); out[dst + 1] = UInt8(g); out[dst + 2] = UInt8(b); out[dst + 3] = 255
            }
        }
        return SpriteText.Image(width: w, height: h, rgba: out)
    }

    nonisolated static func writePNG(_ image: SpriteText.Image, to url: URL) throws {
        var bytes = image.rgba
        let cg: CGImage? = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
        guard let cg, let sink = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        CGImageDestinationAddImage(sink, cg, nil)
        guard CGImageDestinationFinalize(sink) else { throw ImportError.unreadable(url.lastPathComponent) }
    }
}
