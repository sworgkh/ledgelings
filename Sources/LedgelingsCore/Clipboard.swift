import Foundation

/// The clipboard manager: what was copied lately (the history) and the texts the
/// user keeps to paste again (the snippets), searched together from one field.
///
/// The history is a list of clips, newest first. Copying the same text again
/// moves its clip to the top instead of adding a second one. Pinned clips stay
/// whatever the limits say; the others go once there are more than `limit` of
/// them, or once they are older than the days to keep.
///
/// A snippet marked protected keeps no text here at all: its text lives in the
/// platform's secret store (the Mac's Keychain, Windows' Credential Manager),
/// fetched only when it is pasted. The book and anything exported from it know
/// its title and nothing else.
///
/// Nothing in here is ever sent anywhere: no model sees a clip or a snippet.
public enum Clipboard {
    // MARK: Clips

    public enum Kind: String, Codable, Sendable {
        /// Plain text.
        case text
        /// Text with its formatting kept beside it, as RTF.
        case rich
        /// Files copied in Finder or Explorer: `text` holds their paths, one a line.
        case files
    }

    public struct Clip: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var kind: Kind
        /// What was copied, as plain text: the words, or the files' paths.
        public var text: String
        /// The formatting, for a `rich` clip; pasted unless plain text is asked for.
        public var rtf: Data?
        public var copiedAt: Date
        /// The app it was copied from, by name, for the picker: "Safari".
        public var app: String?
        public var pinned: Bool

        public init(id: UUID = UUID(), kind: Kind = .text, text: String, rtf: Data? = nil, copiedAt: Date,
                    app: String? = nil, pinned: Bool = false) {
            self.id = id; self.kind = kind; self.text = text; self.rtf = rtf
            self.copiedAt = copiedAt; self.app = app; self.pinned = pinned
        }

        /// The files' paths, for a `files` clip.
        public var paths: [String] { kind == .files ? text.split(separator: "\n").map(String.init) : [] }

        /// One line for a list: whitespace runs folded to one space, cut at `limit` characters.
        public func preview(_ limit: Int = 80) -> String {
            if kind == .files { return Clipboard.preview(paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "), limit) }
            return Clipboard.preview(text, limit)
        }
    }

    /// Longest text a clip keeps, in characters; a bigger copy is kept cut to this.
    public static let longestClip = 100_000
    /// Most RTF a rich clip keeps, in bytes; past it the clip keeps only its words.
    public static let largestRTF = 512 * 1024

    public struct History: Codable, Equatable, Sendable {
        /// Newest first.
        public var clips: [Clip]
        public init(clips: [Clip] = []) { self.clips = clips }

        /// A new copy: a clip at the top, or the clip with the same words moved there.
        /// Blank text is no copy. Returns whether the history changed.
        @discardableResult
        public mutating func add(_ clip: Clip) -> Bool {
            var clip = clip
            guard !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if clip.text.count > Clipboard.longestClip { clip.text = String(clip.text.prefix(Clipboard.longestClip)) }
            if let rtf = clip.rtf, rtf.count > Clipboard.largestRTF { clip.rtf = nil; clip.kind = .text }
            if let at = clips.firstIndex(where: { $0.text == clip.text && $0.kind == clip.kind }) {
                let old = clips.remove(at: at)
                clip.id = old.id
                clip.pinned = old.pinned
                if clip.rtf == nil, old.rtf != nil, clip.kind == old.kind { clip.rtf = old.rtf }
            }
            clips.insert(clip, at: 0)
            return true
        }

        /// Keeps the newest `limit` unpinned clips copied within `days` (0: however old). Pinned clips always stay.
        public mutating func prune(limit: Int, days: Int, now: Date) {
            let oldest = days > 0 ? now.addingTimeInterval(-Double(days) * 86_400) : .distantPast
            var kept = 0
            clips = clips.filter { clip in
                if clip.pinned { return true }
                guard clip.copiedAt >= oldest, kept < limit else { return false }
                kept += 1
                return true
            }
        }

        public mutating func togglePin(_ id: UUID) {
            if let i = clips.firstIndex(where: { $0.id == id }) { clips[i].pinned.toggle() }
        }

        public mutating func remove(_ id: UUID) { clips.removeAll { $0.id == id } }

        /// Clear All: every clip but the pinned ones, unless `pinnedToo`.
        public mutating func clear(pinnedToo: Bool = false) {
            clips = pinnedToo ? [] : clips.filter(\.pinned)
        }
    }

    // MARK: Snippets

    public struct Snippet: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        /// The words to paste; always empty for a protected snippet, whose words are in the secret store.
        public var text: String
        public var protected: Bool
        /// Its own shortcut from any app, as the platform's key number and `Shortcut.Modifiers`; nil: none.
        public var keyCode: Int?
        public var modifiers: Int?

        public init(id: UUID = UUID(), title: String, text: String = "", protected: Bool = false,
                    keyCode: Int? = nil, modifiers: Int? = nil) {
            self.id = id; self.title = title; self.text = protected ? "" : text; self.protected = protected
            self.keyCode = keyCode; self.modifiers = modifiers
        }

        /// Its own shortcut, when it has a usable one.
        public var shortcut: Shortcut? {
            get {
                guard let keyCode, let modifiers else { return nil }
                let made = Shortcut(keyCode: keyCode, modifiers: Shortcut.Modifiers(rawValue: modifiers))
                return made.isUsable ? made : nil
            }
            set { keyCode = newValue?.keyCode; modifiers = newValue?.modifiers.rawValue }
        }

        /// The account its words are kept under in the secret store.
        public var secretAccount: String { "snippet.\(id.uuidString)" }

        /// What the picker shows: the words, or dots for a protected one.
        public func preview(_ limit: Int = 80) -> String {
            protected ? Clipboard.mask : Clipboard.preview(text, limit)
        }
    }

    /// What a protected snippet looks like until it is pasted.
    public static let mask = "••••••••"

    public struct Folder: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var snippets: [Snippet]

        public init(id: UUID = UUID(), title: String, snippets: [Snippet] = []) {
            self.id = id; self.title = title; self.snippets = snippets
        }
    }

    /// Every folder of snippets, in the user's order.
    public struct SnippetBook: Codable, Equatable, Sendable {
        public var folders: [Folder]
        public init(folders: [Folder] = []) { self.folders = folders }

        /// Every snippet with its folder, in order.
        public var all: [(folder: Folder, snippet: Snippet)] {
            folders.flatMap { folder in folder.snippets.map { (folder, $0) } }
        }

        public func snippet(_ id: UUID) -> Snippet? { all.first { $0.snippet.id == id }?.snippet }

        public func folder(of id: UUID) -> Folder? { all.first { $0.snippet.id == id }?.folder }

        @discardableResult
        public mutating func addFolder(_ title: String) -> UUID {
            let folder = Folder(title: title)
            folders.append(folder)
            return folder.id
        }

        /// A snippet at the end of `folder`, or of the first folder; a folder is made when there is none.
        @discardableResult
        public mutating func add(_ snippet: Snippet, to folder: UUID? = nil) -> UUID {
            if folders.isEmpty { addFolder(tr("Snippets")) }
            let i = folders.firstIndex { $0.id == folder } ?? 0
            folders[i].snippets.append(snippet)
            return snippet.id
        }

        public mutating func update(_ snippet: Snippet) {
            for f in folders.indices {
                if let s = folders[f].snippets.firstIndex(where: { $0.id == snippet.id }) {
                    var kept = snippet
                    if kept.protected { kept.text = "" }
                    folders[f].snippets[s] = kept
                }
            }
        }

        public mutating func renameFolder(_ id: UUID, to title: String) {
            if let i = folders.firstIndex(where: { $0.id == id }) { folders[i].title = title }
        }

        /// Takes the folder or the snippet with this id out of the book, whichever it is.
        /// Returns the snippets that went, so their secrets can go too.
        @discardableResult
        public mutating func remove(_ id: UUID) -> [Snippet] {
            if let i = folders.firstIndex(where: { $0.id == id }) { return folders.remove(at: i).snippets }
            for f in folders.indices {
                if let s = folders[f].snippets.firstIndex(where: { $0.id == id }) { return [folders[f].snippets.remove(at: s)] }
            }
            return []
        }

        /// Moves the folder up (-1) or down (+1) among the folders, or the snippet within its
        /// folder, stepping into the next folder past either end.
        public mutating func move(_ id: UUID, by step: Int) {
            if let i = folders.firstIndex(where: { $0.id == id }) {
                let to = i + step
                guard folders.indices.contains(to) else { return }
                folders.swapAt(i, to)
                return
            }
            guard let f = folders.firstIndex(where: { $0.snippets.contains { $0.id == id } }),
                  let s = folders[f].snippets.firstIndex(where: { $0.id == id }) else { return }
            let to = s + step
            if folders[f].snippets.indices.contains(to) {
                folders[f].snippets.swapAt(s, to)
            } else if folders.indices.contains(f + step) {
                let snippet = folders[f].snippets.remove(at: s)
                if step < 0 { folders[f + step].snippets.append(snippet) } else { folders[f + step].snippets.insert(snippet, at: 0) }
            }
        }

        /// The folders read from a file, added after the ones there.
        public mutating func merge(_ other: SnippetBook) { folders += other.folders }
    }

    // MARK: Search

    /// What the field matches, found in one go across the history and the snippets.
    public struct Found: Equatable, Sendable {
        public var clips: [Clip]
        public var snippets: [Snippet]
        public init(clips: [Clip] = [], snippets: [Snippet] = []) { self.clips = clips; self.snippets = snippets }
        public var isEmpty: Bool { clips.isEmpty && snippets.isEmpty }
    }

    /// Every clip and snippet holding every word of `query`, in any order and any case,
    /// accents ignored ("cafe" finds "Café"). A clip matches on its text and its app; a
    /// snippet on its title, its folder's title and its words, but a protected snippet
    /// only on its title and folder: its words are not here to search. An empty query
    /// finds everything: the pinned clips first, then the rest newest first.
    public static func search(_ query: String, history: History, snippets: SnippetBook) -> Found {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        func holds(_ haystack: String) -> Bool {
            let folded = fold(haystack)
            return words.allSatisfy { folded.contains($0) }
        }
        let clips = history.clips.filter { words.isEmpty || holds($0.text + " " + ($0.app ?? "")) }
        let ordered = clips.filter(\.pinned) + clips.filter { !$0.pinned }
        let found = snippets.all.filter { folder, snippet in
            words.isEmpty || holds([snippet.title, folder.title, snippet.protected ? "" : snippet.text].joined(separator: " "))
        }
        return Found(clips: ordered, snippets: found.map(\.snippet))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func preview(_ text: String, _ limit: Int) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > limit ? String(line.prefix(max(limit - 1, 0))) + "…" : line
    }

    // MARK: What not to keep

    /// Pasteboard types that mark a copy as not for keeping (nspasteboard.org): a password
    /// manager's secret, a value that is gone in a moment, or one an app made up by itself.
    public static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        // Older names some password managers still write.
        "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping",
        "Pasteboard generator type", "net.antelle.keeweb",
    ]

    /// Clipboard formats Windows uses for the same (`ExcludeClipboardContentFromMonitorProcessing`,
    /// and `CanIncludeInClipboardHistory` set to 0 is checked by its value, not its name).
    public static let windowsConcealedFormats: Set<String> = ["ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore"]

    /// Password managers and the like, by bundle id: nothing copied while one of them is in front is kept.
    public static let defaultExcludedMacApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "org.keepassxc.keepassxc",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
        "in.sinew.Enpass-Desktop", "com.markmcguill.strongbox.mac",
    ]

    /// The same on Windows, by process name.
    public static let defaultExcludedWindowsApps = [
        "1Password.exe", "Bitwarden.exe", "KeePass.exe", "KeePassXC.exe", "LastPass.exe", "Dashlane.exe", "Enpass.exe",
    ]

    /// Whether a copy should go into the history: not marked as secret or passing by
    /// `types`, and not copied in an excluded app (compared without case).
    public static func shouldKeep(types: [String], app: String?, excluded: [String]) -> Bool {
        if types.contains(where: concealedTypes.contains) || types.contains(where: windowsConcealedFormats.contains) { return false }
        guard let app = app?.lowercased() else { return true }
        return !excluded.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == app }
    }

    // MARK: Files

    /// `clipboard.json` and `snippets.json`, side by side in the app's folder.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var historyFile: URL { directory.appendingPathComponent("clipboard.json") }
        public var snippetsFile: URL { directory.appendingPathComponent("snippets.json") }

        public func loadHistory() -> History { load(historyFile) ?? History() }
        public func loadSnippets() -> SnippetBook { load(snippetsFile) ?? SnippetBook() }
        public func save(_ history: History) throws { try save(history, to: historyFile) }
        public func save(_ book: SnippetBook) throws { try save(book, to: snippetsFile) }

        private func load<T: Decodable>(_ file: URL) -> T? {
            guard let data = try? Data(contentsOf: file) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(T.self, from: data)
        }

        private func save(_ value: some Encodable, to file: URL) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: file, options: .atomic)
        }
    }
}
