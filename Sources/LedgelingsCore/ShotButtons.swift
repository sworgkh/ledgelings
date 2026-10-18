import Foundation

extension Shot {
    /// Every button on the screenshot toolbar: a pixel picture of what it does and,
    /// on hover, its name and the key that does the same. The keys never change;
    /// only the pictures stand where letters once did.
    public enum Button: String, CaseIterable, Sendable {
        case rectangle, lasso, screen, all
        case box, arrow, highlight, blur, brush
        case undo, done, save, cancel

        public init(_ mode: Mode) {
            switch mode {
            case .rectangle: self = .rectangle
            case .lasso: self = .lasso
            case .screen: self = .screen
            case .all: self = .all
            }
        }

        public init(_ tool: Tool) {
            switch tool {
            case .box: self = .box
            case .arrow: self = .arrow
            case .highlight: self = .highlight
            case .blur: self = .blur
            case .brush: self = .brush
            }
        }

        /// The key that presses it.
        public var key: String {
            switch self {
            case .rectangle: Mode.rectangle.key
            case .lasso: Mode.lasso.key
            case .screen: Mode.screen.key
            case .all: Mode.all.key
            case .box: Tool.box.key
            case .arrow: Tool.arrow.key
            case .highlight: Tool.highlight.key
            case .blur: Tool.blur.key
            case .brush: Tool.brush.key
            case .undo: "⌘Z"
            case .done: "⏎"
            case .save: "⌘S"
            case .cancel: "⎋"
            }
        }

        /// What it does, in plain words, then its key. `copies` and `saves` are what ⏎
        /// does as Productivity tools › Screenshots says.
        public func tooltip(copies: Bool = true, saves: Bool = false) -> String {
            switch self {
            case .rectangle: tr("Rectangle (R)")
            case .lasso: tr("Lasso (L)")
            case .screen: tr("The screen under the cursor (W)")
            case .all: tr("All screens (A)")
            case .box: tr("Box (B)")
            case .arrow: tr("Arrow (→)")
            case .highlight: tr("Highlight (H)")
            case .blur: tr("Blur rectangle (X)")
            case .brush: tr("Freehand blur (F)")
            case .undo: tr("Undo the last mark (⌘Z)")
            case .done:
                copies && saves ? tr("Copy and save it (⏎)") : saves ? tr("Save it (⏎)") : tr("Copy it (⏎ or ⌘C)")
            case .save: tr("Save it to the folder (⌘S)")
            case .cancel: tr("Cancel (⎋)")
            }
        }

        /// The picture, 11×11 pixels, top row first: `#` ink, `+` faint ink, anything else see-through.
        /// Square pixels, no curves: a bend is a step.
        public var icon: [String] {
            switch self {
            case .rectangle: [
                "##.###.##..",
                "#.........#",
                "...........",
                "#.........#",
                "#.........#",
                "...........",
                "#.........#",
                "#.........#",
                "...........",
                "#.........#",
                "..##.###.##",
            ]
            case .lasso: [
                "...#####...",
                ".##.....##.",
                "#.........#",
                "#.........#",
                "#.........#",
                ".##.....##.",
                "...##.##...",
                ".....#.....",
                "....#......",
                "...#.......",
                "..##.......",
            ]
            case .screen: [
                "###########",
                "#+++++++++#",
                "#+++++++++#",
                "#+++++++++#",
                "#+++++++++#",
                "#+++++++++#",
                "###########",
                ".....#.....",
                ".....#.....",
                "...#####...",
                "...........",
            ]
            case .all: [
                "...........",
                "#####.#####",
                "#+++#.#+++#",
                "#+++#.#+++#",
                "#+++#.#+++#",
                "#+++#.#+++#",
                "#####.#####",
                "..#.....#..",
                ".###...###.",
                "...........",
                "...........",
            ]
            case .box: [
                "...........",
                ".#########.",
                ".#########.",
                ".##.....##.",
                ".##.....##.",
                ".##.....##.",
                ".##.....##.",
                ".##.....##.",
                ".#########.",
                ".#########.",
                "...........",
            ]
            case .arrow: [
                "....#######",
                "......#####",
                ".......####",
                "......#####",
                ".....###.##",
                "....###...#",
                "...###.....",
                "..###......",
                ".###.......",
                "###........",
                "##.........",
            ]
            case .highlight: [
                "...........",
                "...........",
                "+++++++++++",
                "+#######+++",
                "+++++++++++",
                "+#####+###+",
                "+++++++++++",
                "...........",
                ".#####.....",
                "...........",
                "...........",
            ]
            case .blur: [
                "###########",
                "#++##++##+#",
                "#++##++##+#",
                "###++##++##",
                "###++##++##",
                "#++##++##+#",
                "#++##++##+#",
                "###++##++##",
                "###++##++##",
                "#++##++##+#",
                "###########",
            ]
            case .brush: [
                ".........##",
                "........###",
                ".......###.",
                "......###..",
                ".....###...",
                "....###....",
                "##++##.....",
                "##++##.....",
                "++##++.....",
                "++##++.....",
                "...........",
            ]
            case .undo: [
                "...#.......",
                "..##.......",
                ".#######...",
                "###.....#..",
                ".##......#.",
                "..#......#.",
                ".........#.",
                ".........#.",
                "........#..",
                "...#####...",
                "...........",
            ]
            case .done: [
                "...........",
                "..........#",
                ".........##",
                "........##.",
                ".......##..",
                "#.....##...",
                "##...##....",
                ".##.##.....",
                "..###......",
                "...#.......",
                "...........",
            ]
            case .save: [
                ".....#.....",
                ".....#.....",
                ".....#.....",
                ".....#.....",
                "...#.#.#...",
                "....###....",
                ".....#.....",
                "#.........#",
                "#.........#",
                "###########",
                "...........",
            ]
            case .cancel: [
                "...........",
                ".##.....##.",
                ".###...###.",
                "..###.###..",
                "...#####...",
                "....###....",
                "...#####...",
                "..###.###..",
                ".###...###.",
                ".##.....##.",
                "...........",
            ]
            }
        }
    }

    /// A palette colour's name and key, for the toolbar's colour squares.
    public static func colourTooltip(_ n: Int) -> String {
        switch n {
        case 0: tr("Red (1)")
        case 1: tr("Yellow (2)")
        case 2: tr("Green (3)")
        case 3: tr("Blue (4)")
        case 4: tr("White (5)")
        default: tr("Black (6)")
        }
    }
}
