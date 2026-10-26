import Foundation

/// The Tools screen (§7.15): every tool the creatures run for the owner on one
/// small sheet, a big pixel picture each, its name and its keys. A click, its
/// number, or the arrows and ⏎ start it; a tool that is switched off is greyed,
/// its tag saying where to switch it on.
public enum Tools {
    public enum Tool: String, CaseIterable, Sendable {
        case translate, dictation, screenshot, fullScreen, lastRectangle, clipHistory, snippets, reminder

        public var title: String {
            switch self {
            case .translate: tr("TRANSLATE")
            case .dictation: tr("DICTATE")
            case .screenshot: tr("SCREENSHOT")
            case .fullScreen: tr("FULL SCREEN")
            case .lastRectangle: tr("LAST RECTANGLE")
            case .clipHistory: tr("CLIPBOARD HISTORY")
            case .snippets: tr("SNIPPETS")
            case .reminder: tr("ADD A REMINDER")
            }
        }

        /// What it does, in plain words, for its hover tag.
        public var does: String {
            switch self {
            case .translate: tr("Type to translate")
            case .dictation: tr("Speak, and the words land on the clipboard")
            case .screenshot: tr("A screenshot with the toolbar")
            case .fullScreen: tr("The full screen, straight out")
            case .lastRectangle: tr("The last rectangle again")
            case .clipHistory: tr("Your recent copies, to paste again")
            case .snippets: tr("The snippets, to paste")
            case .reminder: tr("A reminder, thrown at you by paper plane")
            }
        }

        /// Where it is switched on: its settings page.
        public var page: SettingsPage {
            switch self {
            case .translate: .translate
            case .dictation: .dictation
            case .screenshot, .fullScreen, .lastRectangle: .screenshots
            case .clipHistory, .snippets: .clipboard
            case .reminder: .reminders
            }
        }

        /// The tag: what it does and its keys, `1 · ⌃⌥T`; switched off, where to switch it on.
        public func tooltip(number: Int, shortcut: String?, on: Bool) -> String {
            guard on else { return tr("Off: switch it on in Settings › Tools › %@ (%d)", page.title, number) }
            return shortcut.map { tr("%@ (%d · %@)", does, number, $0) } ?? tr("%@ (%d)", does, number)
        }

        /// 11×11, `#` ink, `.` paper, drawn like the game.
        public var icon: [String] {
            switch self {
            case .translate: Translate.Button.translate.icon
            case .dictation: ["...###.....", "..#...#....", "..#.#.#....", "..#...#....", "..#.#.#....", "#.#...#.#..", "#..###..#..", ".#.....#...", "..#####....", "....#......", "..#####...."]
            case .screenshot: Shot.Button.rectangle.icon
            case .fullScreen: ["###########", "#.........#", "#.#.....#.#", "#.........#", "#.........#", "#.........#", "#.#.....#.#", "#.........#", "###########", "....###....", "..#######.."]
            case .lastRectangle: ["##.###.....", "#.........#", "....######.", "#...#....#.", "#...#....#.", "....#..#.#.", "#...#.##.#.", "#...#....#.", "....######.", "#..........", "..##.###.##"]
            case .clipHistory: ["...###.....", "####.####..", "#.......#..", "#.#####.#..", "#.......#..", "#.###...#..", "#.......#..", "#.#####.#..", "#.......#..", "#########..", "..........."]
            case .snippets: ["#########..", "#.......##.", "#.#####.#.#", "#.......###", "#.#####...#", "#.........#", "#.###.....#", "#.........#", "#.#####...#", "#.........#", "###########"]
            case .reminder: ["..........#", "........##.", "......##.#.", "....##..#..", "..##...#...", "##....#....", "..##.#.....", "....##.....", "....#.#....", "....#..#...", "....#......"]
            }
        }
    }

    /// The Tools screen itself, on the Creature Actions sheet: a wrench, as in the settings sidebar.
    public static let sheetIcon = ["......###..", ".....#..#..", "....#..#...", "...#.##....", "..#.#......", ".#.#.......", "#.#........", "##.........", "...........", "...........", "..........."]

    /// The tools shown, in order, from the saved codes: unknown ones dropped, each once.
    public static func shown(_ saved: [String]) -> [Tool] {
        var seen = Set<Tool>()
        return saved.compactMap(Tool.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    /// Every tool, in this order: what the screen shows until the owner changes it.
    public static let defaultShown = Tool.allCases.map(\.rawValue)

    /// The tile `from` moves to with an arrow, in a grid `columns` wide; nil at an edge.
    public static func step(from: Int, by key: Arrow, count: Int, columns: Int = 4) -> Int {
        guard count > 0 else { return 0 }
        let to: Int
        switch key {
        case .left: to = from - 1
        case .right: to = from + 1
        case .up: to = from - columns
        case .down: to = from + columns
        }
        return to >= 0 && to < count ? to : from
    }

    public enum Arrow: Sendable { case left, right, up, down }
}
