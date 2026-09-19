import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The built-in creatures are written in the letter format under sprites/text/.
/// This keeps the shipped sheets in step with them, and rebuilds them when asked:
///
///     LEDGELINGS_BUILD_CREATURES=1 swift test --filter ShippedCreaturesTests
@Suite struct ShippedCreaturesTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let texts = repo.appendingPathComponent("sprites/text")
    static let resources = repo.appendingPathComponent("Sources/Ledgelings/Resources/sprites")
    static let building = ProcessInfo.processInfo.environment["LEDGELINGS_BUILD_CREATURES"] == "1"

    @Test(arguments: SpriteLibrary.builtIn.filter { $0 != "blocky" })
    func shippedSheetMatchesItsText(name: String) throws {
        let text = try String(contentsOf: Self.texts.appendingPathComponent("\(name).txt"), encoding: .utf8)
        let sheet = try SpriteText.parse(text)
        #expect(sheet.name == name)
        #expect(sheet.kind != nil && sheet.cast.count >= 3, "a built-in creature knows what it is and has a cast")
        let image = SpriteText.pixels(sheet, palette: .blocky)
        if Self.building {
            try SpriteLibrary.writePNG(image, to: Self.resources.appendingPathComponent("\(name).png"))
            let meta = SpriteText.atlas(name: name, kind: sheet.kind, cast: sheet.cast)
            try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
                .write(to: Self.resources.appendingPathComponent("\(name).json"))
            return
        }
        let shipped = try SpriteAtlas(named: name)
        #expect(try shipped.image() == image, "\(name).png differs from sprites/text/\(name).txt; rebuild with LEDGELINGS_BUILD_CREATURES=1")
        #expect(shipped.meta.kind == sheet.kind)
        #expect(shipped.meta.cast == sheet.cast)
    }
}
