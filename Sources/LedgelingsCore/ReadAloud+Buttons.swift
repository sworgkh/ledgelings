import Foundation

extension ReadAloud {
    /// Every button Read aloud draws: a pixel picture of what it does (11×11,
    /// `#` ink, `.` paper) and, on hover, its name and the key that does the same.
    public enum Button: String, CaseIterable, Sendable {
        /// The sheet: read or go on, pause, stop, save the sound, copy it, slower, faster, the next reader.
        case play, pause, stop, save, copy, slower, faster, reader
        /// The clipboard picker's row: read it aloud.
        case readRow

        public var key: String {
            switch self {
            case .play, .pause: "⏎"
            case .stop: "⌘."
            case .save: "⌘S"
            case .copy: "⌘⇧C"
            case .slower: "⌘−"
            case .faster: "⌘="
            case .reader, .readRow: "⌘R"
            }
        }

        /// What it does and its key.
        public var tooltip: String {
            switch self {
            case .play: tr("Read it aloud (%@)", key)
            case .pause: tr("Pause (%@)", key)
            case .stop: tr("Stop reading (%@)", key)
            case .save: tr("Save the sound as a file (%@)", key)
            case .copy: tr("Copy the sound file (%@)", key)
            case .slower: tr("Slower (%@)", key)
            case .faster: tr("Faster (%@)", key)
            case .reader: tr("The next reader (%@)", key)
            case .readRow: tr("Read aloud (%@)", key)
            }
        }

        public var icon: [String] {
            switch self {
            case .play: ["..#........", "..##.......", "..###......", "..####.....", "..#####....", "..######...", "..#####....", "..####.....", "..###......", "..##.......", "..#........"]
            case .pause: ["...........", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..##..##...", "..........."]
            case .stop: ["...........", "...........", ".#######...", ".#######...", ".#######...", ".#######...", ".#######...", ".#######...", ".#######...", "...........", "..........."]
            // A floppy disk: the shutter on top, the label below.
            case .save: ["#########..", "#.#####.##.", "#.#####..#.", "#.#####..#.", "#........#.", "#.######.#.", "#.#....#.#.", "#.#....#.#.", "#.#....#.#.", "##########.", "..........."]
            // A page with a note on it, a second page behind.
            case .copy: ["######.....", "#....#.....", "#.#######..", "#.#.....#..", "#.#...###..", "###...#.#..", "..#...#.#..", "..#.###.#..", "..#.###.#..", "..#######..", "..........."]
            // One step forward, then two: slower and faster.
            case .slower: ["...........", "...........", "...#.......", "...##......", "...#.#.....", "...#..#....", "...#.#.....", "...##......", "...#.......", "...........", "###########"]
            case .faster: ["...........", "...........", ".#....#....", ".##...##...", ".#.#..#.#..", ".#..#.#..#.", ".#.#..#.#..", ".##...##...", ".#....#....", "...........", "###########"]
            // A creature, square with square eyes, as the readers are drawn.
            case .reader: [".#########.", ".#.......#.", ".#....#.##.", ".#....#.##.", ".#.......#.", ".#.......#.", ".#.......#.", ".#########.", "..##...##..", "...........", "..........."]
            case .readRow: Self.speaker
            }
        }

        /// A loudspeaker with its sound going out: the tool's own picture.
        public static let speaker = ["....#......", "...##....#.", "..#.#..#..#", "###.#...#.#", "#...#.#.#.#", "#...#.#.#.#", "#...#.#.#.#",
                                     "###.#...#.#", "..#.#..#..#", "...##....#.", "....#......"]
    }
}
