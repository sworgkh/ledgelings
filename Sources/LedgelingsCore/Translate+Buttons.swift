import Foundation

extension Translate {
    /// Every button the translator draws: a pixel picture of what it does (11×11,
    /// `#` ink, `.` paper) and, on hover, its name and the key that does the same.
    public enum Button: String, CaseIterable, Sendable {
        /// The sheet: swap the languages, copy the translation, paste it into the app you were in, clear.
        case swap, copy, paste, clear
        /// The clipboard picker's row: translate it, open it in the sheet.
        case translate, openSheet
        /// Saved translations: the star that keeps this one, the drawer of them, and each row's copy and bin.
        case save, savedList, copySaved, deleteSaved

        public var key: String {
            switch self {
            case .swap: "⌘S"
            case .copy: "⏎"
            case .paste: "⌘⏎"
            case .clear: "⌘⌫"
            case .translate: "⌘T"
            case .openSheet: "⌘⇧T"
            case .save: "⌘D"
            case .savedList: "⌘L"
            case .copySaved: "⌘C"
            case .deleteSaved: "⌫"
            }
        }

        /// What it does and its key. `app` is the app a paste goes into, by name;
        /// `on`: the translation is saved already (the star), or the drawer is open.
        public func tooltip(app: String? = nil, on: Bool = false) -> String {
            switch self {
            case .swap: tr("Swap languages (%@)", key)
            case .copy: tr("Copy the translation (%@)", key)
            case .paste: app.map { tr("Paste into %@ (%@)", $0, key) } ?? tr("Paste into the app you were in (%@)", key)
            case .clear: tr("Clear the text (%@)", key)
            case .translate: tr("Translate (%@)", key)
            case .openSheet: tr("Open in the Translate sheet (%@)", key)
            case .save: on ? tr("Remove from saved (%@)", key) : tr("Save this translation (%@)", key)
            case .savedList: on ? tr("Hide saved translations (%@)", key) : tr("Show saved translations (%@)", key)
            case .copySaved: tr("Copy this translation (%@)", key)
            case .deleteSaved: tr("Delete from saved (%@)", key)
            }
        }

        /// The picture as it stands: the star filled once the translation is saved.
        public func icon(on: Bool) -> [String] {
            self == .save && on ? Self.filledStar : icon
        }

        public static let filledStar = [".....#.....", "....###....", "....###....", "###########", ".#########.", "..#######..", "..#######..", ".#########.", ".####.####.", "####...####", "###.....###"]

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
            // A star's outline; filled once saved (`filledStar`).
            case .save: [".....#.....", "....#.#....", "....#.#....", "####...####", ".#.......#.", "..#.....#..", "..#.....#..", ".#...#...#.", ".#..#.#..#.", "#..#...#..#", "###.....###"]
            // A page with a list on it: a dot and a line, four times.
            case .savedList: ["#########..", "#.......#..", "#.#.###.#..", "#.......#..", "#.#.###.#..", "#.......#..", "#.#.###.#..", "#.......#..", "#.#.###.#..", "#.......#..", "#########.."]
            // Two pages with lines, one over the other.
            case .copySaved: ["..######...", "..#....#...", "######.#...", "#....#.#...", "#.##.#.#...", "#....###...", "#.##.#.....", "#....#.....", "######.....", "...........", "..........."]
            // A bin: its lid with a handle, a body with ribs.
            case .deleteSaved: ["....###....", "###########", ".#########.", ".#.#.#.#.#.", ".#.#.#.#.#.", ".#.#.#.#.#.", ".#.#.#.#.#.", ".#.#.#.#.#.", ".#########.", "...........", "..........."]
            }
        }
    }
}
