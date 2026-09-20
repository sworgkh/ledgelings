import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Imported creatures: text or PNG in, a loadable atlas out, kept in their own folder.
@MainActor
@Suite struct SpriteLibraryTests {
    func fresh() -> SpriteLibrary {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-sprites-\(UUID().uuidString)")
        return SpriteLibrary(directory: dir)
    }

    @Test func theBuiltInCreatureIsAlwaysThereAndCannotBeRemoved() throws {
        let library = fresh()
        #expect(library.species.map(\.name) == SpriteLibrary.builtIn)
        let allBuiltIn = library.species.allSatisfy { $0.isBuiltIn }
        #expect(allBuiltIn)
        library.remove("blocky")
        #expect(library.species.map(\.name) == SpriteLibrary.builtIn)
        #expect(library.kind(of: "frog").contains("frog") && library.cast(of: "frog").count == 3)
        #expect(library.cast(of: "blocky") == Banter.defaultCharacters)
    }

    @Test func theBuiltInCreatureRoundTripsThroughTheTextFormat() throws {
        let library = fresh()
        let text = library.exampleText
        let sheet = try SpriteText.parse(text)
        #expect(sheet.name == "blocky")
        let original = try SpriteAtlas(named: "blocky").image()
        let rebuilt = SpriteText.pixels(sheet, palette: .blocky)
        #expect(rebuilt == original, "letters → pixels gives back the shipped sheet exactly")
    }

    @Test func aSheetThatNamesItsColourAlwaysWearsIt() throws {
        let library = fresh()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hog-\(UUID().uuidString).txt")
        try library.exampleText.replacingOccurrences(of: "name: blocky", with: "name: hog\ncolour: #f0a0b0").write(to: file, atomically: true, encoding: .utf8)
        try library.importFile(file)
        let slot = RGB(hex: "#3366ff")!
        #expect(library.bodyColour(of: "hog", slot: slot) == RGB(hex: "#f0a0b0"))
        #expect(library.bodyColour(of: "blocky", slot: slot) == slot, "a sheet with no colour line takes the creature's slot colour")
        #expect(library.bodyColour(of: "nobody", slot: slot) == slot)
    }

    @Test func aTextFileBecomesASpeciesWithAFullAtlas() throws {
        let library = fresh()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pip-\(UUID().uuidString).txt")
        try library.exampleText.replacingOccurrences(of: "name: blocky", with: "name: pip").write(to: file, atomically: true, encoding: .utf8)
        let name = try library.importFile(file)
        #expect(name == "pip")
        #expect(library.species.map(\.name) == SpriteLibrary.builtIn + ["pip"])
        let atlas = try SpriteAtlas(directory: library.directory.appendingPathComponent("pip"), name: "pip")
        #expect(atlas.meta.frames.count == 27)
        #expect(atlas.frames().frame(animation: "walk", time: 0.2, eyes: .half) != nil)
        #expect(atlas.bodyHalfSize == 11)
        library.remove("pip")
        #expect(library.species.map(\.name) == SpriteLibrary.builtIn)
        #expect(!FileManager.default.fileExists(atPath: library.directory.appendingPathComponent("pip").path))
    }

    @Test func aPaintedSheetOnMagentaIsKeyedOutAndSliced() throws {
        let library = fresh()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        // The shipped sheet, put back on the key colour, is what an image model would hand us.
        let original = try SpriteAtlas(named: "blocky").image()
        var onMagenta = original
        for i in stride(from: 0, to: onMagenta.rgba.count, by: 4) where onMagenta.rgba[i + 3] < 128 {
            onMagenta.rgba[i] = 255; onMagenta.rgba[i + 1] = 0; onMagenta.rgba[i + 2] = 255; onMagenta.rgba[i + 3] = 255
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dot.png")
        try SpriteLibrary.writePNG(onMagenta, to: file)
        let name = try library.importFile(file)
        #expect(name == "dot")
        let atlas = try SpriteAtlas(directory: library.directory.appendingPathComponent("dot"), name: "dot")
        #expect(try atlas.image() == original, "magenta became transparent, nothing else changed")
    }

    @Test func aBadTextFileIsRefusedWithTheParsersWords() throws {
        let library = fresh()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).txt")
        try "name: bad\npose: idle\n....\n".write(to: file, atomically: true, encoding: .utf8)
        do { _ = try library.importFile(file); Issue.record("should have refused") } catch {
            #expect("\(error)".contains("rows"))
        }
        #expect(library.species.count == SpriteLibrary.builtIn.count)
    }

    @Test func thePromptShowsTheBuiltInIdlePoseAsLetters() {
        let library = fresh()
        let prompt = library.prompt
        #expect(prompt.contains(SpriteText.describePlaceholder))
        let idle = SpriteText.describe(try! SpriteAtlas(named: "blocky").image(), pose: "idle", palette: .blocky)
        #expect(prompt.contains(idle.joined(separator: "\n")))
        #expect(idle[26].contains("o"), "the example stands on the floor")
    }
}
