import CryptoKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The sprite kit: the pictures the prompt attaches, and reading back what an
/// image model paints, which is never the size or the crispness asked for.
@MainActor
@Suite struct SpriteKitTests {
    static let blocky = try! SpriteAtlas(named: "blocky").image()

    /// Blocky's open-eyes pose as inks, the answer every reading should give.
    static func inks(_ pose: String) -> [[SpriteText.Ink]] {
        SpriteText.describe(blocky, pose: pose, palette: .blocky).map { $0.map { SpriteText.Ink(letter: $0)! } }
    }

    struct Paint {
        var width = 1728, height = 288
        var paper = SpriteText.Tint(r: 255, g: 0, b: 255)
        var transparent = false
        /// Picture pixels per sprite pixel; need not be whole.
        var scale = 6.0
        var columns = 9
        var origin = (x: 0.0, y: 48.0)
        var cell = 192.0
        var blur = 0
        var noise = 0
        var labels = false
        var bodyColour: SpriteText.Tint? = nil
    }

    /// Blocky's nine poses painted the way an image model might hand them back.
    static func painted(_ p: Paint) -> SpriteText.Image {
        var img = SpriteText.Image(width: p.width, height: p.height, rgba: [UInt8](repeating: 0, count: p.width * p.height * 4))
        func put(_ x: Int, _ y: Int, _ t: SpriteText.Tint) {
            guard x >= 0, y >= 0, x < p.width, y < p.height else { return }
            let i = (y * p.width + x) * 4
            img.rgba[i] = t.r; img.rgba[i + 1] = t.g; img.rgba[i + 2] = t.b; img.rgba[i + 3] = 255
        }
        if !p.transparent { for y in 0..<p.height { for x in 0..<p.width { put(x, y, p.paper) } } }
        for (n, _) in SpriteText.poses.enumerated() {
            let cx = p.origin.x + Double(n % p.columns) * p.cell, cy = p.origin.y + Double(n / p.columns) * p.cell
            for y in 0..<32 {
                for x in 0..<32 {
                    let i = (y * blocky.width + n * 32 + x) * 4
                    guard blocky.rgba[i + 3] >= 128 else { continue }
                    var t = SpriteText.Tint(r: blocky.rgba[i], g: blocky.rgba[i + 1], b: blocky.rgba[i + 2])
                    if let body = p.bodyColour, t == SpriteText.Palette.blocky.body { t = body }
                    let x0 = Int(cx + Double(x) * p.scale), x1 = Int(cx + Double(x + 1) * p.scale)
                    let y0 = Int(cy + Double(y) * p.scale), y1 = Int(cy + Double(y + 1) * p.scale)
                    for yy in y0..<y1 { for xx in x0..<x1 { put(xx, yy, t) } }
                }
            }
            if p.labels {
                SpriteKit.draw(SpriteText.poses[n], x: Int(cx) + 10, y: Int(cy + 33 * p.scale), size: max(2, Int(p.scale / 2)),
                               colour: SpriteText.Tint(r: 20, g: 20, b: 20), on: &img)
            }
        }
        for _ in 0..<p.blur { img = boxBlur(img) }
        if p.noise > 0 {
            var seed: UInt32 = 12345
            for i in 0..<img.rgba.count where i % 4 != 3 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let d = Int(seed >> 24) % (2 * p.noise + 1) - p.noise
                img.rgba[i] = UInt8(max(0, min(255, Int(img.rgba[i]) + d)))
            }
        }
        return img
    }

    static func boxBlur(_ img: SpriteText.Image) -> SpriteText.Image {
        var out = img
        for y in 0..<img.height {
            for x in 0..<img.width {
                var sum = [0, 0, 0, 0], n = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, yy >= 0, xx < img.width, yy < img.height else { continue }
                        let i = (yy * img.width + xx) * 4
                        for c in 0..<4 { sum[c] += Int(img.rgba[i + c]) }
                        n += 1
                    }
                }
                let i = (y * img.width + x) * 4
                for c in 0..<4 { out.rgba[i + c] = UInt8(sum[c] / n) }
            }
        }
        return out
    }

    /// How many of a pose's 1024 pixels came back as Blocky has them.
    static func agreement(_ reading: SpriteKit.Reading) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: SpriteText.poses.map { pose in
            let want = inks(pose), got = reading.poses[pose] ?? []
            var same = 0
            for y in 0..<32 { for x in 0..<32 where got.count == 32 && got[y][x] == want[y][x] { same += 1 } }
            return (pose, same)
        })
    }

    // MARK: The pictures

    @Test func thePicturesShareOneGridAndThePosesAreBlockysOwn() {
        let poses = SpriteKit.posesImage(Self.blocky), template = SpriteKit.templateImage()
        #expect(poses.width == 1728 && poses.height == 288 && template.width == poses.width && template.height == poses.height)
        // Every pose pixel is a crisp 6×6 square of Blocky's colour, at its place in the cell.
        for (n, _) in SpriteText.poses.enumerated() {
            for (y, x) in [(10, 14), (24, 9), (6, 7)] {
                let src = (y * Self.blocky.width + n * 32 + x) * 4
                for (dy, dx) in [(0, 0), (5, 5)] {
                    let dst = ((48 + y * 6 + dy) * poses.width + n * 192 + x * 6 + dx) * 4
                    if Self.blocky.rgba[src + 3] >= 128 { #expect(Array(poses.rgba[dst..<dst + 3]) == Array(Self.blocky.rgba[src..<src + 3])) }
                }
            }
        }
        // Outside the creatures the two are the same picture, apart from the title.
        var differ = 0
        for y in 48..<288 { for x in 0..<1728 { let i = (y * 1728 + x) * 4; if poses.rgba[i..<i + 4] != template.rgba[i..<i + 4] { differ += 1 } } }
        let blockyPixels = (0..<(288 * 32)).filter { Self.blocky.rgba[$0 * 4 + 3] >= 128 }.count
        #expect(differ == blockyPixels * 36)
    }

    /// The Windows app draws the same pictures; both test the bytes against these.
    static let templateSHA = "18203cf4dcf942af7279f82ec25477c37741a7e02bf9e367901bd459a3150535"
    static let posesSHA = "aab71e929bb733b44e4e7e19bb05c7574fb2df8e68407704d28459580d0d6589"
    static func sha(_ image: SpriteText.Image) -> String { SHA256.hash(data: Data(image.rgba)).map { String(format: "%02x", $0) }.joined() }

    @Test func thePicturesAreTheSameBytesTheWindowsAppDraws() {
        #expect(Self.sha(SpriteKit.templateImage()) == Self.templateSHA)
        #expect(Self.sha(SpriteKit.posesImage(Self.blocky)) == Self.posesSHA)
    }

    @Test func thePicturesReadBackAsBlockyHimself() throws {
        let reading = try SpriteKit.read(SpriteKit.posesImage(Self.blocky))
        #expect(Self.agreement(reading).values.allSatisfy { $0 == 1024 }, "\(Self.agreement(reading))")
        #expect(reading.colour == SpriteText.Palette.blocky.body)
    }

    // MARK: Forgiving import

    @Test func aBlurredNoisyOffSizeStripStillReads() throws {
        var p = Paint()
        p.width = 1500; p.height = 260; p.scale = 5.3; p.cell = 166; p.origin = (12, 44); p.blur = 2; p.noise = 8; p.labels = true
        let reading = try SpriteKit.read(Self.painted(p))
        let worst = Self.agreement(reading).values.min() ?? 0
        #expect(worst >= 1000, "\(Self.agreement(reading))")
        // The eyes survive as eyes, so the creature still blinks.
        #expect(reading.poses["idle"]?.joined().filter { $0 == .eye }.count == 36)
    }

    @Test func aSquarePictureInThreeRowsOnWhiteReads() throws {
        var p = Paint()
        p.width = 1024; p.height = 1024; p.paper = SpriteText.Tint(r: 250, g: 250, b: 248); p.columns = 3
        p.scale = 9.4; p.cell = 330; p.origin = (20, 30); p.blur = 1; p.noise = 4
        p.bodyColour = SpriteText.Tint(hex: "#6cbf4a")
        let reading = try SpriteKit.read(Self.painted(p))
        #expect(Self.agreement(reading).values.min() ?? 0 >= 1000, "\(Self.agreement(reading))")
        let c = reading.colour
        #expect(abs(Int(c.r) - 0x6c) < 10 && abs(Int(c.g) - 0xbf) < 10 && abs(Int(c.b) - 0x4a) < 10, "\(c.hex)")
    }

    @Test func aTransparentPictureReads() throws {
        var p = Paint()
        p.transparent = true; p.scale = 4; p.cell = 140; p.width = 1300; p.height = 200; p.origin = (8, 20)
        let reading = try SpriteKit.read(Self.painted(p))
        #expect(Self.agreement(reading).values.allSatisfy { $0 == 1024 }, "\(Self.agreement(reading))")
    }

    @Test func tooFewCreaturesIsSaidPlainly() {
        var p = Paint()
        p.width = 900 // the last four poses fall off the edge
        #expect(throws: SpriteKit.ReadError.self) { try SpriteKit.read(Self.painted(p)) }
        // The empty template: its labels and title are words, not creatures.
        #expect(throws: SpriteKit.ReadError.self) { try SpriteKit.read(SpriteKit.templateImage()) }
        #expect(throws: SpriteKit.ReadError.self) { try SpriteKit.read(SpriteKit.posesImage(SpriteText.Image(width: 0, height: 0, rgba: []))) }
    }

    @Test func aModelsPictureImportsWithTheFormsNameKindColourAndCast() throws {
        let library = SpriteLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-kit-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: library.directory) }
        var p = Paint()
        p.width = 1536; p.height = 1024; p.scale = 5.5; p.cell = 170; p.origin = (5, 400); p.blur = 1
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ChatGPT Image \(UUID().uuidString).png")
        try SpriteLibrary.writePNG(Self.painted(p), to: file)
        let form = SpriteKit.Form(kind: "a boxy moss sprite", name: "Moss Ball", colour: "#55aa33",
                                  cast: [Character(name: "Fern", persona: "A tiny, anxious girl who speaks fast."), Character(name: "", persona: "")])
        let name = try library.importFile(file, form: form)
        #expect(name == "moss-ball")
        let atlas = try #require(library.atlas(named: "moss-ball"))
        #expect(atlas.meta.kind == "a boxy moss sprite")
        #expect(atlas.meta.colour == "#55aa33")
        #expect(atlas.meta.cast?.map(\.name) == ["Fern"])
        #expect(atlas.frames().frame(animation: "sleep", time: 0, eyes: .closed) != nil)
        #expect(library.cast(of: "moss-ball").first?.persona.contains("anxious") == true)
    }

    @Test func withNoColourChosenTheImportKeepsThePaintedOne() throws {
        let library = SpriteLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-kit-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: library.directory) }
        var p = Paint()
        p.bodyColour = SpriteText.Tint(hex: "#3d7bff")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bluey.png")
        try SpriteLibrary.writePNG(Self.painted(p), to: file)
        try library.importFile(file)
        #expect(library.atlas(named: "bluey")?.meta.colour == "#3d7bff")
    }

    @Test func saveImagesWritesBothAttachmentsByTheirNumbers() throws {
        let library = SpriteLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-kit-\(UUID().uuidString)"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kit-out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try library.saveKitImages(to: folder)
        #expect(files.map(\.lastPathComponent) == ["1-poses.png", "2-template.png"])
        #expect(try SpriteLibrary.readPNG(files[0]) == SpriteKit.posesImage(Self.blocky))
    }
}
