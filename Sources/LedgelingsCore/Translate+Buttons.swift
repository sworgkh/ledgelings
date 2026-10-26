import Foundation

extension Translate {
    /// Every button the translator draws: a pixel picture of what it does (11×11,
    /// `#` ink, `.` paper) and, on hover, its name and the key that does the same.
    public enum Button: String, CaseIterable, Sendable {
        /// The sheet: swap the languages, copy the translation, paste it into the app you were in, clear.
        case swap, copy, paste, clear
        /// The clipboard picker's row: translate it, open it in the sheet.
        case translate, openSheet

        public var key: String {
            switch self {
            case .swap: "⌘S"
            case .copy: "⏎"
            case .paste: "⌘⏎"
            case .clear: "⌘⌫"
            case .translate: "⌘T"
            case .openSheet: "⌘⇧T"
            }
        }

        /// What it does and its key. `app` is the app a paste goes into, by name.
        public func tooltip(app: String? = nil) -> String {
            switch self {
            case .swap: tr("Swap languages (%@)", key)
            case .copy: tr("Copy the translation (%@)", key)
            case .paste: app.map { tr("Paste into %@ (%@)", $0, key) } ?? tr("Paste into the app you were in (%@)", key)
            case .clear: tr("Clear the text (%@)", key)
            case .translate: tr("Translate (%@)", key)
            case .openSheet: tr("Open in the Translate sheet (%@)", key)
            }
        }

        public var icon: [String] {
            switch self {
            // Two letter squares, one over the other: A and a line of script.
            case .translate: ["######.....", "#.##.#.....", "#.##.#.....", "#....#.....", "#.##.######", "######....#", ".....#.#..#", ".....#.##.#", ".....#.#.##", ".....#....#", ".....######"]
            case .swap: ["...#.......", "..##.......", ".#########.", "..##.......", "...#.......", "...........", ".......#...", ".......##..", ".#########.", ".......##..", ".......#..."]
            case .copy: ["######.....", "#....#.....", "#.######...", "#.#....#...", "#.#....#...", "###....#...", "..#....#...", "..######...", "...........", "...........", "..........."]
            case .paste: ["...###.....", "####.####..", "#.......#..", "#.#####.#..", "#.......#..", "#.#####.#..", "#.......#..", "#.###...#..", "#.......#..", "#########..", "..........."]
            case .clear: ["#.......#..", ".#.....#...", "..#...#....", "...#.#.....", "....#......", "...#.#.....", "..#...#....", ".#.....#...", "#.......#..", "...........", "..........."]
            // The sheet: a page with a swap arrow on it.
            case .openSheet: ["#########..", "#.......#..", "#..#....#..", "#.#####.#..", "#..#....#..", "#.......#..", "#....#..#..", "#.#####.#..", "#....#..#..", "#.......#..", "#########.."]
            }
        }
    }
}
