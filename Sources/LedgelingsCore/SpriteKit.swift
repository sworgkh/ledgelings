import Foundation

/// The sprite kit on Settings › Sprites: a small form saying what the creature
/// is, a prompt for an IMAGE model built from it, the two pictures attached to
/// that prompt, and the reader that turns whatever picture the model sends
/// back into a sheet.
///
/// The pictures (`posesImage`, `templateImage`) are 1728×288: a header strip, one
/// row of nine 32×32 cells drawn 6× bigger, and a strip of labels. Image models
/// never answer at exactly that size, so `read` does not trust the layout: it
/// finds the creatures in the picture, orders them, and brings each down to a
/// 32×32 cell in the sheet's inks (`SpriteText.Ink`).
public enum SpriteKit {

    // MARK: The form

    /// What the person filled in. Empty means "let the model choose".
    public struct Form: Codable, Equatable, Sendable {
        /// What the creature is: "a fat green frog with big eyes".
        public var kind: String
        public var name: String
        /// Its body colour, `#rrggbb`; empty lets the model choose.
        public var colour: String
        /// Always three; a character with no name is the model's to choose.
        public var cast: [Character]

        public static let castSize = 3

        public init(kind: String = "", name: String = "", colour: String = "", cast: [Character] = []) {
            self.kind = kind; self.name = name; self.colour = colour
            self.cast = Self.three(cast)
        }

        /// `cast` cut or padded to three.
        public static func three(_ cast: [Character]) -> [Character] {
            Array((cast + Array(repeating: Character(name: "", persona: ""), count: castSize)).prefix(castSize))
        }

        public var tint: SpriteText.Tint? { SpriteText.Tint(hex: colour.trimmingCharacters(in: .whitespaces)) }
        /// The characters that have a name.
        public var namedCast: [Character] {
            cast.map { Character(name: $0.name.trimmingCharacters(in: .whitespaces), persona: $0.persona.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.name.isEmpty }
        }
        public var trimmedKind: String { kind.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// A name the sprites folder takes: lowercase Latin letters, digits and dashes.
    /// Nil when nothing usable is left.
    public static func speciesName(_ typed: String) -> String? {
        var out = ""
        for scalar in typed.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) { out.unicodeScalars.append(scalar) }
            else if !out.isEmpty, out.last != "-" { out.append("-") }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? nil : out
    }

    // MARK: The pictures

    /// Image pixels per sprite pixel in the pictures.
    public static let scale = 6
    public static var cellSize: Int { SpriteText.cell * scale }
    /// Height of the strip above the cells (the picture's number and title) and of the labels below.
    public static let strip = 48
    public static var width: Int { SpriteText.poses.count * cellSize }
    public static var height: Int { strip + cellSize + strip }

    static let key = SpriteText.Tint(r: 255, g: 0, b: 255)
    static let gridLine = SpriteText.Tint(r: 200, g: 0, b: 200)
    static let boxLine = SpriteText.Tint(r: 255, g: 120, b: 255)
    static let ink = SpriteText.Tint(r: 0, g: 0, b: 0)

    /// What the pictures say at the top. English in every language: the font
    /// has only Latin capitals, and the prompt names the pictures by number.
    public static let posesTitle = "1 - POSES: COPY THIS STYLE AND ORDER"
    public static let templateTitle = "2 - TEMPLATE: PAINT YOUR CREATURE HERE"

    /// Picture 2: the empty sheet to paint on. Magenta, a line between cells,
    /// a pink frame round each body box (its bottom edge is the floor), the poses' names below.
    public static func templateImage() -> SpriteText.Image { canvas(title: templateTitle) }

    /// Picture 1: `sheet` (the built-in creature's 288×96 sheet; its top row, eyes
    /// open) drawn on the template, every sprite pixel a 6×6 square.
    public static func posesImage(_ sheet: SpriteText.Image) -> SpriteText.Image {
        var image = canvas(title: posesTitle)
        let cell = SpriteText.cell
        for column in 0..<min(SpriteText.poses.count, sheet.width / cell) {
            for y in 0..<cell {
                for x in 0..<cell {
                    let i = (y * sheet.width + column * cell + x) * 4
                    guard sheet.rgba[i + 3] >= 128 else { continue }
                    let tint = SpriteText.Tint(r: sheet.rgba[i], g: sheet.rgba[i + 1], b: sheet.rgba[i + 2])
                    fill(&image, x: column * cellSize + x * scale, y: strip + y * scale, w: scale, h: scale, tint)
                }
            }
        }
        return image
    }

    static func canvas(title: String) -> SpriteText.Image {
        var image = SpriteText.Image(width: width, height: height, rgba: [UInt8](repeating: 0, count: width * height * 4))
        fill(&image, x: 0, y: 0, w: width, h: height, key)
        let box = SpriteText.box, line = 2
        for column in 0..<SpriteText.poses.count {
            let left = column * cellSize
            // Between cells and round the row.
            fill(&image, x: left, y: strip, w: line, h: cellSize, gridLine)
            fill(&image, x: left + cellSize - line, y: strip, w: line, h: cellSize, gridLine)
            fill(&image, x: left, y: strip, w: cellSize, h: line, gridLine)
            fill(&image, x: left, y: strip + cellSize - line, w: cellSize, h: line, gridLine)
            // The body box, just outside it so the creature's own pixels stay clear.
            let bx = left + box.x * scale, by = strip + box.y * scale, bw = box.w * scale, bh = box.h * scale
            fill(&image, x: bx - line, y: by - line, w: bw + 2 * line, h: line, boxLine)
            fill(&image, x: bx - line, y: by + bh, w: bw + 2 * line, h: line, boxLine)
            fill(&image, x: bx - line, y: by, w: line, h: bh, boxLine)
            fill(&image, x: bx + bw, y: by, w: line, h: bh, boxLine)
            // Its pose's name, centred under it.
            let label = SpriteText.poses[column].uppercased(), size = 4
            draw(label, x: left + (cellSize - textWidth(label) * size) / 2, y: strip + cellSize + (strip - 7 * size) / 2,
                 size: size, colour: ink, on: &image)
        }
        draw(title, x: 24, y: (strip - 7 * 4) / 2, size: 4, colour: ink, on: &image)
        return image
    }

    static func fill(_ image: inout SpriteText.Image, x: Int, y: Int, w: Int, h: Int, _ t: SpriteText.Tint) {
        for yy in max(0, y)..<min(image.height, y + h) {
            for xx in max(0, x)..<min(image.width, x + w) {
                let i = (yy * image.width + xx) * 4
                image.rgba[i] = t.r; image.rgba[i + 1] = t.g; image.rgba[i + 2] = t.b; image.rgba[i + 3] = 255
            }
        }
    }
}
