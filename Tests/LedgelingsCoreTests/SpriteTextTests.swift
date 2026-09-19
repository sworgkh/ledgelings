import Testing
@testable import LedgelingsCore

/// A creature written as letters, the way a chat model can produce one.
@Suite struct SpriteTextTests {
    /// A 32x32 grid with a 12-wide, 8-tall box standing on the floor row (26), eyes as k.
    static func grid(width: Int = 12, height: Int = 8, eyeRows: Int = 2) -> [String] {
        var rows = Array(repeating: String(repeating: ".", count: 32), count: 32)
        let left = 5 + (22 - width) / 2, top = 27 - height
        for y in top..<27 {
            var row = Array(rows[y])
            for x in left..<(left + width) {
                let edge = y == top || y == 26 || x == left || x == left + width - 1
                row[x] = edge ? "o" : "b"
            }
            rows[y] = String(row)
        }
        for y in (top + 2)..<(top + 2 + eyeRows) {
            var row = Array(rows[y]); row[left + 4] = "k"; row[left + 7] = "k"; rows[y] = String(row)
        }
        return rows
    }

    static func text(name: String = "boxy", poses: [String] = SpriteText.poses, grid: [String] = grid()) -> String {
        var out = ["name: \(name)"]
        for pose in poses { out.append("pose: \(pose)"); out += grid }
        return out.joined(separator: "\n") + "\n"
    }

    @Test func parsesNinePosesOfThirtyTwoByThirtyTwo() throws {
        let sheet = try SpriteText.parse(Self.text())
        #expect(sheet.name == "boxy")
        #expect(Set(sheet.poses.keys) == Set(SpriteText.poses))
        let idle = try #require(sheet.poses["idle"])
        #expect(idle.count == 32 && idle.allSatisfy { $0.count == 32 })
        #expect(idle[26][10] == .outline && idle[22][12] == .body)
    }

    @Test func spacesDashesAndCommentsAreForgiven() throws {
        var grid = Self.grid()
        grid[0] = String(repeating: "-", count: 32)
        grid[1] = String(repeating: " ", count: 32)
        let text = "# my creature\n" + Self.text(grid: grid).replacingOccurrences(of: "pose: idle\n", with: "pose: idle   \n\n")
        let sheet = try SpriteText.parse(text)
        #expect(sheet.poses["idle"]?[0].allSatisfy { $0 == .clear } == true)
    }

    @Test func aMissingPoseIsRefusedByName() {
        #expect(throws: SpriteText.ParseError.self) {
            try SpriteText.parse(Self.text(poses: Array(SpriteText.poses.dropLast())))
        }
        do { _ = try SpriteText.parse(Self.text(poses: Array(SpriteText.poses.dropLast()))) } catch {
            #expect("\(error)".contains("sleep-1"))
        }
    }

    @Test func aRowOfTheWrongLengthOrAStrangeLetterIsRefused() {
        var grid = Self.grid(); grid[20] = String(repeating: ".", count: 12) + "ob" + String(repeating: ".", count: 17)   // 31 with ink
        #expect(throws: SpriteText.ParseError.self) { try SpriteText.parse(Self.text(grid: grid)) }
        var short = Self.grid(); short[3] = "..."                                                                    // short but empty: fine
        #expect(throws: Never.self) { try SpriteText.parse(Self.text(grid: short)) }
        var odd = Self.grid(); odd[3] = String(repeating: "?", count: 32)
        #expect(throws: SpriteText.ParseError.self) { try SpriteText.parse(Self.text(grid: odd)) }
    }

    @Test func inkOutsideTheBodyBoxOrFloatingAboveTheFloorIsRefused() {
        var outside = Self.grid(); outside[26] = "o" + String(repeating: ".", count: 31)
        #expect(throws: SpriteText.ParseError.self) { try SpriteText.parse(Self.text(grid: outside)) }
        var floating = Self.grid(); floating[26] = String(repeating: ".", count: 32)
        #expect(throws: SpriteText.ParseError.self) { try SpriteText.parse(Self.text(grid: floating)) }
    }

    @Test func eyesCloseDownwardsForTheHalfAndClosedVariants() throws {
        let sheet = try SpriteText.parse(Self.text(grid: Self.grid(eyeRows: 4)))
        let open = sheet.poses["idle"]!
        let half = SpriteText.variant(open, "half"), closed = SpriteText.variant(open, "closed")
        let col = 5 + (22 - 12) / 2 + 4
        func eyeRows(_ g: [[SpriteText.Ink]]) -> [Int] { (0..<32).filter { g[$0][col] == .eye } }
        #expect(eyeRows(open).count == 4)
        #expect(eyeRows(half) == Array(eyeRows(open).suffix(2)), "the lid comes down, the bottom rows stay")
        #expect(eyeRows(closed) == [eyeRows(open).last!])
        #expect(half[eyeRows(open)[0]][col] == .body, "where the eye was is body again")
    }

    @Test func pixelsLayOutPosesInColumnsAndVariantsInRowsWithThePalette() throws {
        let sheet = try SpriteText.parse(Self.text())
        let image = SpriteText.pixels(sheet, palette: .blocky)
        #expect(image.width == 288 && image.height == 96)
        func px(_ x: Int, _ y: Int) -> [UInt8] { Array(image.rgba[(y * 288 + x) * 4 ..< (y * 288 + x) * 4 + 4]) }
        #expect(px(0, 0) == [0, 0, 0, 0])
        #expect(px(10, 26) == [0x3b, 0x1f, 0x0f, 255], "outline in the open row")
        #expect(px(12, 22) == [0xff, 0x8a, 0x3d, 255], "body")
        #expect(px(32 + 10, 32 + 26) == [0x3b, 0x1f, 0x0f, 255], "walk-0 sits in the second column, half row below")
    }

    @Test func atlasMetadataMatchesTheBuiltInSheetsShape() throws {
        let meta = SpriteText.atlas(name: "boxy")
        #expect(meta["cell"] as? [Int] == [32, 32])
        #expect(meta["contentBox"] as? [Int] == [5, 5, 22, 22])
        let frames = try #require(meta["frames"] as? [String: [String: Int]])
        #expect(frames.count == 27)
        #expect(frames["walk-1_half"] == ["x": 64, "y": 32, "w": 32, "h": 32])
        let animations = try #require(meta["animations"] as? [String: [String: Any]])
        #expect(animations["walk"]?["frames"] as? [String] == ["walk-0", "walk-1", "walk-2", "walk-3"])
        #expect((meta["palette"] as? [String: String])?["body"] == "#ff8a3d")
    }

    @Test func pixelsReadBackAsTheSameLetters() throws {
        let sheet = try SpriteText.parse(Self.text())
        let image = SpriteText.pixels(sheet, palette: .blocky)
        let back = SpriteText.describe(image, pose: "idle", palette: .blocky)
        #expect(back == Self.grid())
    }

    @Test func thePromptCarriesTheRulesAndTheExample() {
        let prompt = SpriteText.prompt(example: ["....", "..o."])
        #expect(prompt.contains("pose: idle") && prompt.contains("32") && prompt.contains("..o."))
        #expect(prompt.contains(SpriteText.describePlaceholder))
        for pose in SpriteText.poses { #expect(prompt.contains(pose)) }
    }
}
