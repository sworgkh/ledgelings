import Foundation

/// A creature written as letters: nine 32×32 grids, one per pose, which is
/// what a chat model can produce when asked. This turns such text into the
/// same sheet layout the built-in creature uses (poses in columns, eye
/// variants in rows), with the real palette, so recolouring and blinking work
/// on an imported creature exactly as on the built-in one.
///
/// The format:
///
///     name: pip
///     pose: idle
///     ................................   (32 rows of 32 letters)
///     pose: walk-0
///     ...
///
/// Letters: `.` nothing, `o` outline, `b` body, `l` light, `s` shade,
/// `k` eye (black; it blinks), `x` black that never blinks.
public enum SpriteText {
    public static let cell = 32
    /// x, y, width, height of the square the body must stay inside.
    public static let box = (x: 5, y: 5, w: 22, h: 22)
    /// The row just below the creature: every pose must have ink on the row above it.
    public static var floor: Int { box.y + box.h }
    public static let poses = ["idle", "walk-0", "walk-1", "walk-2", "walk-3", "jump", "land", "sleep-0", "sleep-1"]
    public static let variants = ["open", "half", "closed"]
    public static let animations: [String: (frames: [String], fps: Double, loop: Bool)] = [
        "idle": (["idle"], 1, true),
        "walk": (["walk-0", "walk-1", "walk-2", "walk-3"], 8, true),
        "jump": (["jump"], 1, true),
        "land": (["land"], 1, true),
        "sleep": (["sleep-0", "sleep-1"], 0.8, true),
    ]
    public static let describePlaceholder = "<describe your creature here>"

    public enum Ink: String, CaseIterable, Sendable {
        case clear = ".", outline = "o", body = "b", light = "l", shade = "s", eye = "k", black = "x"
        public var letter: Swift.Character { rawValue.first! }
        public init?(letter: Swift.Character) { self.init(rawValue: String(letter)) }
    }

    public struct Tint: Equatable, Sendable {
        public var r, g, b: UInt8
        public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
        public init?(hex: String) {
            let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
            self.init(r: UInt8(value >> 16 & 0xff), g: UInt8(value >> 8 & 0xff), b: UInt8(value & 0xff))
        }
        public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    }

    /// The four colours a sheet is painted in; the app swaps them for each creature's own.
    public struct Palette: Equatable, Sendable {
        public var body, light, shade, outline: Tint
        public static let blocky = Palette(body: Tint(hex: "#ff8a3d")!, light: Tint(hex: "#ffb27a")!,
                                           shade: Tint(hex: "#d66220")!, outline: Tint(hex: "#3b1f0f")!)
        public init(body: Tint, light: Tint, shade: Tint, outline: Tint) {
            self.body = body; self.light = light; self.shade = shade; self.outline = outline
        }

        func tint(of ink: Ink) -> Tint? {
            switch ink {
            case .clear: nil
            case .outline: outline
            case .body: body
            case .light: light
            case .shade: shade
            case .eye, .black: Tint(r: 0, g: 0, b: 0)
            }
        }
    }

    public struct Sheet: Equatable, Sendable {
        public var name: String
        /// What the creature is, for the model: "a fat green frog with big eyes".
        public var kind: String?
        /// Who its creatures are; creatures of this species take these in turn.
        public var cast: [Character]
        /// The body colour this species always wears, when the sheet says; otherwise
        /// the app paints it in each creature's own colour.
        public var colour: Tint?
        /// pose → 32 rows of 32 inks, eyes open.
        public var poses: [String: [[Ink]]]
    }

    /// An RGBA sheet, 8 bits a channel, rows top to bottom.
    public struct Image: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var rgba: [UInt8]
        public init(width: Int, height: Int, rgba: [UInt8]) { self.width = width; self.height = height; self.rgba = rgba }
    }

    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case noName
        case missingPose(String)
        case unknownPose(String)
        case wrongRowCount(pose: String, rows: Int)
        case wrongRowLength(pose: String, row: Int, length: Int)
        case strangeLetter(pose: String, row: Int, letter: Swift.Character)
        case outsideTheBox(pose: String, row: Int, column: Int)
        case notOnTheFloor(String)
        case empty(String)
        case badColour(String)

        public var description: String {
            switch self {
            case .badColour(let value): "colour must be six hex digits like #f0a0b0, not \"\(value)\""
            case .noName: "the first line should be `name: something`"
            case .missingPose(let p): "pose \(p) is missing"
            case .unknownPose(let p): "pose \(p) is not one of \(poses.joined(separator: ", "))"
            case .wrongRowCount(let p, let n): "pose \(p) has \(n) rows, not \(cell)"
            case .wrongRowLength(let p, let r, let n): "pose \(p), row \(r + 1) has \(n) letters, not \(cell)"
            case .strangeLetter(let p, let r, let c): "pose \(p), row \(r + 1): `\(c)` is not one of . o b l s k x"
            case .outsideTheBox(let p, let r, let c):
                "pose \(p) has ink at row \(r + 1), column \(c + 1), outside columns \(box.x + 1)–\(box.x + box.w) and rows \(box.y + 1)–\(box.y + box.h)"
            case .notOnTheFloor(let p): "pose \(p) does not stand on the floor: row \(floor) is empty"
            case .empty(let p): "pose \(p) is empty"
            }
        }
    }

    // MARK: Reading

    public static func parse(_ text: String) throws -> Sheet {
        var name: String?
        var kind: String?
        var cast: [Character] = []
        var colour: Tint?
        var poses: [String: [[Ink]]] = [:]
        var current: String?
        var rows: [[Ink]] = []

        func finish() throws {
            guard let pose = current else { return }
            guard rows.count == cell else { throw ParseError.wrongRowCount(pose: pose, rows: rows.count) }
            try validate(pose: pose, rows)
            poses[pose] = rows
            rows = []
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty line is nothing; a line of spaces inside a pose is a row of nothing.
            if raw.trimmingCharacters(in: .newlines).isEmpty || line.hasPrefix("#") { continue }
            if line.isEmpty, current == nil { continue }
            if let value = keyed(line, "name") { name = value; continue }
            if let value = keyed(line, "kind") { kind = value.isEmpty ? nil : value; continue }
            if let value = keyed(line, "colour") ?? keyed(line, "color") {
                guard let tint = Tint(hex: value) else { throw ParseError.badColour(value) }
                colour = tint; continue
            }
            if let value = keyed(line, "character") {
                // "Name: what they are like" — the first colon splits them.
                let parts = value.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if let who = parts.first, !who.isEmpty { cast.append(Character(name: who, persona: parts.count > 1 ? parts[1] : "")) }
                continue
            }
            if let value = keyed(line, "pose") {
                try finish()
                guard Self.poses.contains(value) else { throw ParseError.unknownPose(value) }
                current = value
                continue
            }
            guard let pose = current else { continue }
            var row: [Ink] = []
            for (column, letter) in raw.enumerated() {
                if let ink = Ink(letter: letter) { row.append(ink) }
                else if letter == " " || letter == "-" || letter == "_" { row.append(.clear) }
                else if letter == "\t" || letter == "\r" { continue }
                else { throw ParseError.strangeLetter(pose: pose, row: rows.count, letter: letter) }
                _ = column
            }
            while row.count > cell, row.last == .clear { row.removeLast() }
            if row.count < cell, row.allSatisfy({ $0 == .clear }) { row += Array(repeating: .clear, count: cell - row.count) }
            guard row.count == cell else { throw ParseError.wrongRowLength(pose: pose, row: rows.count, length: row.count) }
            rows.append(row)
        }
        try finish()
        guard let name, !name.isEmpty else { throw ParseError.noName }
        for pose in Self.poses where poses[pose] == nil { throw ParseError.missingPose(pose) }
        return Sheet(name: name, kind: kind, cast: cast, colour: colour, poses: poses)
    }

    private static func keyed(_ line: String, _ key: String) -> String? {
        guard line.lowercased().hasPrefix(key + ":") else { return nil }
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    private static func validate(pose: String, _ rows: [[Ink]]) throws {
        var any = false, onFloor = false
        for (y, row) in rows.enumerated() {
            for (x, ink) in row.enumerated() where ink != .clear {
                any = true
                guard (box.x..<(box.x + box.w)).contains(x), (box.y..<(box.y + box.h)).contains(y) else {
                    throw ParseError.outsideTheBox(pose: pose, row: y, column: x)
                }
                if y == floor - 1 { onFloor = true }
            }
        }
        guard any else { throw ParseError.empty(pose) }
        guard onFloor else { throw ParseError.notOnTheFloor(pose) }
    }

    // MARK: Eyes

    /// The lids come down: `half` keeps the lower half of each vertical run of
    /// eye pixels, `closed` keeps its bottom row. What the lid covers becomes body.
    public static func variant(_ open: [[Ink]], _ variant: String) -> [[Ink]] {
        guard variant != "open" else { return open }
        var grid = open
        let columns = open.first?.count ?? 0
        for x in 0..<columns {
            var y = 0
            while y < open.count {
                guard open[y][x] == .eye else { y += 1; continue }
                var end = y
                while end < open.count, open[end][x] == .eye { end += 1 }
                let run = end - y
                let keep = variant == "closed" ? 1 : (run + 1) / 2
                for row in y..<(end - keep) { grid[row][x] = .body }
                y = end
            }
        }
        return grid
    }

    // MARK: Pixels

    /// The whole sheet: poses left to right, eye variants top to bottom.
    public static func pixels(_ sheet: Sheet, palette: Palette) -> Image {
        let width = poses.count * cell, height = variants.count * cell
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for (column, pose) in poses.enumerated() {
            guard let open = sheet.poses[pose] else { continue }
            for (row, name) in variants.enumerated() {
                let grid = variant(open, name)
                for y in 0..<cell {
                    for x in 0..<cell {
                        guard let tint = palette.tint(of: grid[y][x]) else { continue }
                        let i = ((row * cell + y) * width + column * cell + x) * 4
                        rgba[i] = tint.r; rgba[i + 1] = tint.g; rgba[i + 2] = tint.b; rgba[i + 3] = 255
                    }
                }
            }
        }
        return Image(width: width, height: height, rgba: rgba)
    }

    /// The open-eyes grid of one pose, read back from a sheet, as rows of letters.
    /// A colour that is none of the palette's comes back as `x`.
    public static func describe(_ image: Image, pose: String, palette: Palette) -> [String] {
        guard let column = poses.firstIndex(of: pose) else { return [] }
        return (0..<cell).map { y in
            String((0..<cell).map { x -> Swift.Character in
                let i = (y * image.width + column * cell + x) * 4
                guard image.rgba[i + 3] >= 128 else { return Ink.clear.letter }
                let here = Tint(r: image.rgba[i], g: image.rgba[i + 1], b: image.rgba[i + 2])
                for ink in [Ink.outline, .body, .light, .shade] where close(palette.tint(of: ink)!, here) { return ink.letter }
                return close(Tint(r: 0, g: 0, b: 0), here) ? Ink.eye.letter : Ink.black.letter
            })
        }
    }

    private static func close(_ a: Tint, _ b: Tint) -> Bool {
        abs(Int(a.r) - Int(b.r)) <= 2 && abs(Int(a.g) - Int(b.g)) <= 2 && abs(Int(a.b) - Int(b.b)) <= 2
    }

    // MARK: The atlas file

    /// The JSON the app loads, for a sheet laid out by `pixels`.
    public static func atlas(name: String, palette: Palette = .blocky, kind: String? = nil, cast: [Character] = [],
                             colour: Tint? = nil) -> [String: Any] {
        var frames: [String: [String: Int]] = [:]
        for (column, pose) in poses.enumerated() {
            for (row, variant) in variants.enumerated() {
                frames["\(pose)_\(variant)"] = ["x": column * cell, "y": row * cell, "w": cell, "h": cell]
            }
        }
        var animations: [String: [String: Any]] = [:]
        for (key, a) in Self.animations { animations[key] = ["frames": a.frames, "fps": a.fps, "loop": a.loop] }
        var meta: [String: Any] = [
            "name": name, "image": "\(name).png",
            "cell": [cell, cell], "contentBox": [box.x, box.y, box.w, box.h],
            "variants": variants,
            "palette": ["body": palette.body.hex, "light": palette.light.hex, "shade": palette.shade.hex, "outline": palette.outline.hex],
            "frames": frames, "animations": animations,
        ]
        if let kind { meta["kind"] = kind }
        if !cast.isEmpty { meta["cast"] = cast.map { ["name": $0.name, "persona": $0.persona] } }
        if let colour { meta["colour"] = colour.hex }
        return meta
    }

    // MARK: The prompt

    /// What to paste into a chat model, with the built-in creature's idle pose as the worked example.
    public static func prompt(example: [String]) -> String {
        """
        I need a tiny pixel-art creature for a desktop toy, written as text so I can paste it back.
        The creature: \(describePlaceholder)

        Write it as a sprite sheet in this exact text format and nothing else:

        name: <one lowercase word, letters and digits only>
        kind: <what it is, in a few words, e.g. "a fat green frog with big eyes">
        colour: <its body colour as six hex digits, e.g. #6cbf4a; leave this line out to let the app pick>
        character: <a name>: <its personality in one or two sentences>
        character: <another name>: <another personality>
        character: <a third name>: <a third personality>
        pose: idle
        <32 rows of exactly 32 characters>
        pose: walk-0
        <32 rows>
        ... and so on for every pose, in this order: \(poses.joined(separator: ", "))

        Characters, one per pixel:
          .  nothing (transparent)
          o  outline, a dark line around the body
          b  body, the main colour
          l  light, a highlight along the top and left inside the outline
          s  shade, a shadow along the bottom and right inside the outline
          k  eye pixels (black). Make each eye a vertical block of k; the app blinks by lowering a lid over it
          x  other black detail that must not blink (a mouth, a spot)

        Rules the app checks:
          - Every pose is exactly 32 rows of exactly 32 characters. No other characters, no spaces inside rows.
          - The creature stays inside columns \(box.x + 1) to \(box.x + box.w) and rows \(box.y + 1) to \(box.y + box.h) (1-based). Rows outside are empty.
          - Row \(floor) is the floor: every pose has ink on row \(floor). The creature stands on it, facing RIGHT.
          - Keep the body roughly centred left-to-right in that box; the app rotates it about the centre at screen corners.
          - The poses: idle stands still. walk-0 to walk-3 are one walk cycle (walk-1 squashed a little, walk-3 stretched, feet alternating).
            jump is stretched tall with feet tucked in. land is squashed very flat and wide. sleep-0 and sleep-1 are slumped low,
            eyes still drawn as k (the app closes them), sleep-1 one row lower than sleep-0.
          - Use only . o b l s k x. Do not add colours, comments or explanations. Output the text block and nothing else.
          - The three characters are who the creatures of this kind will be when they talk to each other: give each a
            distinct voice that fits what the creature is.

        Here is the built-in creature's idle pose, as an example of the size and style (a square body, two eyes, small feet):

        pose: idle
        \(example.joined(separator: "\n"))
        """
    }
}
