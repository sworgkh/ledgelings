import Foundation

extension Translate {
    // MARK: Saved translations

    /// A translation kept with the star (⌘D), as Google Translate keeps its
    /// starred ones: the text and the language it was read as, the translation and
    /// the language it went into, when, and the app the text came from.
    public struct Saved: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public var text: String
        /// The language the text was translated from: chosen by hand, or detected.
        public var from: String
        public var translation: String
        public var to: String
        public var savedAt: Date
        /// The app the sheet was opened over, if any.
        public var app: String?

        public init(id: UUID = UUID(), text: String, from: String, translation: String, to: String, savedAt: Date, app: String? = nil) {
            self.id = id
            self.text = text
            self.from = from
            self.translation = translation
            self.to = to
            self.savedAt = savedAt
            self.app = app
        }

        /// The same text with the same pair of languages is one entry, whatever its translation.
        public func same(text other: String, from: String, to: String) -> Bool {
            self.from == from && self.to == to && Saved.key(text) == Saved.key(other)
        }

        /// The text as it is compared: without the spaces and new lines at its edges.
        static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

        /// "EN → RU", the small tag on its row.
        public var pair: String { "\(from.uppercased()) → \(to.uppercased())" }
    }

    /// How many are kept; the oldest beyond it are dropped.
    public static let savedLimitRange = 50...5_000
    public static let defaultSavedLimit = 500

    /// Every saved translation, newest first.
    public struct SavedBook: Codable, Equatable, Sendable {
        public private(set) var entries: [Saved]

        public init(entries: [Saved] = []) {
            self.entries = entries.sorted { $0.savedAt > $1.savedAt }
        }

        public var count: Int { entries.count }
        public var isEmpty: Bool { entries.isEmpty }

        /// The entry for this text and pair, if it is saved.
        public func find(text: String, from: String, to: String) -> Saved? {
            entries.first { $0.same(text: text, from: from, to: to) }
        }

        /// Saves `entry` at the top. The same text and pair saved before is replaced,
        /// keeping its id, so it is never there twice; then the oldest beyond `limit` go.
        public mutating func save(_ entry: Saved, limit: Int) {
            var entry = entry
            if let old = entries.firstIndex(where: { $0.same(text: entry.text, from: entry.from, to: entry.to) }) {
                entry = Saved(id: entries[old].id, text: entry.text, from: entry.from, translation: entry.translation, to: entry.to,
                              savedAt: entry.savedAt, app: entry.app ?? entries[old].app)
                entries.remove(at: old)
            }
            entries.insert(entry, at: 0)
            prune(limit: limit)
        }

        /// The star pressed: saved when it was not, removed when it was. True when it is saved now.
        @discardableResult
        public mutating func toggle(_ entry: Saved, limit: Int) -> Bool {
            if let old = find(text: entry.text, from: entry.from, to: entry.to) {
                remove(old.id)
                return false
            }
            save(entry, limit: limit)
            return true
        }

        public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }

        public mutating func clear() { entries.removeAll() }

        /// The newest `limit` stay.
        public mutating func prune(limit: Int) {
            if entries.count > max(limit, 0) { entries.removeLast(entries.count - max(limit, 0)) }
        }

        /// The entries whose text or translation holds every word of `query`, in
        /// either case and with or without accents (ё as е); all of them for a blank one.
        public func search(_ query: String) -> [Saved] {
            let words = query.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0)) }
            guard !words.isEmpty else { return entries }
            return entries.filter { entry in
                let haystack = Self.fold(entry.text) + "\n" + Self.fold(entry.translation)
                return words.allSatisfy { haystack.contains($0) }
            }
        }

        static func fold(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }

        private enum CodingKeys: String, CodingKey { case entries }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(entries: try container.decode([Saved].self, forKey: .entries))
        }
    }

    /// `translations.json` beside the clipboard history, saved on every change.
    public struct SavedStore: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var file: URL { directory.appendingPathComponent("translations.json") }

        /// The book on disk; an empty one when there is none, or it cannot be read.
        public func load() -> SavedBook {
            guard let data = try? Data(contentsOf: file) else { return SavedBook() }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode(SavedBook.self, from: data)) ?? SavedBook()
        }

        public func save(_ book: SavedBook) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(book).write(to: file, options: .atomic)
        }
    }

    // MARK: The drawer

    /// Which side of the sheet the drawer of saved translations slides out of.
    public enum DrawerSide: Equatable, Sendable {
        case right, left

        /// Right, unless the drawer would run off that monitor there and fits on the left.
        /// `paperMinX` and `paperWidth` are the sheet's, `room` the monitor's width, all in points.
        public static func side(paperMinX: Double, paperWidth: Double, drawerWidth: Double, room: Double) -> DrawerSide {
            let fitsRight = paperMinX + paperWidth + drawerWidth <= room
            let fitsLeft = paperMinX - drawerWidth >= 0
            return fitsRight || !fitsLeft ? .right : .left
        }
    }

    /// "11 Nov", or "11 Nov 2025" from another year, in the app's language.
    public static func savedDate(_ date: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: LedgelingsCore.Language.current == .russian ? "ru_RU" : "en_GB")
        let calendar = Calendar.current
        f.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "d MMM" : "d MMM y")
        return f.string(from: date)
    }
}
