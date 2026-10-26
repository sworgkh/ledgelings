import CryptoKit
import Foundation

/// The clipboard manager: what was copied lately (the history) and the texts the
/// user keeps to paste again (the snippets), searched together from one field.
///
/// The history is a list of clips, newest first. Copying the same text again
/// moves its clip to the top instead of adding a second one. Pinned clips stay
/// whatever the limits say; the others go once there are more than `limit` of
/// them, or once they are older than the days to keep.
///
/// A copied picture is a clip too, labelled "Image 1280×720"; its bytes are files in
/// `clipboard-images` beside the history, one per type it was copied as, so the
/// JSON stays small. The same picture copied again moves to the top like words do.
///
/// A snippet marked protected keeps no text here at all: its text lives in the
/// platform's secret store (the Mac's Keychain, Windows' Credential Manager),
/// fetched only when it is pasted. The book and anything exported from it know
/// its title and a salted fingerprint of its words, nothing else. A copy in the
/// history with exactly those words is shown masked, `PWD:Wi-Fi: [16] chars`,
/// and searched by that label; it still pastes its own words.
///
/// Nothing in here is sent anywhere on its own. A clip or an ordinary snippet
/// reaches a model only when the owner translates it (§7.14: the picker's ⌘T, the
/// last-copy shortcut); a protected snippet, and a copy of its words, never do
/// (`Translate.refusal`).
public enum Clipboard {
    // MARK: Clips

    public enum Kind: String, Codable, Sendable {
        /// Plain text.
        case text
        /// Text with its formatting kept beside it, as RTF.
        case rich
        /// Files copied in Finder or Explorer: `text` holds their paths, one a line.
        case files
        /// A picture: `text` is its label, `picture` says where its bytes are.
        case image
    }

    /// A copied picture's size and the types it was kept as, each a file beside the history.
    public struct Picture: Codable, Equatable, Sendable {
        public var width: Int
        public var height: Int
        /// Every kept type's bytes together.
        public var bytes: Int
        /// A fingerprint of the best type's bytes: the same picture copied again is the same clip.
        public var digest: String
        /// The types kept, best first ("public.png", "public.tiff"); each is a file.
        public var types: [String]

        public init(width: Int, height: Int, bytes: Int, digest: String, types: [String]) {
            self.width = width; self.height = height; self.bytes = bytes; self.digest = digest; self.types = types
        }
    }

    /// What an image clip is called, in English, as its `text`: "Image 1280×720".
    public static func imageLabel(width: Int, height: Int) -> String { "Image \(width)×\(height)" }

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
        /// An `image` clip's size and kept types.
        public var picture: Picture?

        public init(id: UUID = UUID(), kind: Kind = .text, text: String, rtf: Data? = nil, copiedAt: Date,
                    app: String? = nil, pinned: Bool = false, picture: Picture? = nil) {
            self.id = id; self.kind = kind; self.text = text; self.rtf = rtf
            self.copiedAt = copiedAt; self.app = app; self.pinned = pinned; self.picture = picture
        }

        /// A picture copied from `app`, labelled by its size.
        public static func image(_ picture: Picture, copiedAt: Date, app: String? = nil) -> Clip {
            Clip(kind: .image, text: Clipboard.imageLabel(width: picture.width, height: picture.height), copiedAt: copiedAt,
                 app: app, picture: picture)
        }

        /// The files' paths, for a `files` clip.
        public var paths: [String] { kind == .files ? text.split(separator: "\n").map(String.init) : [] }

        /// One line for a list: whitespace runs folded to one space, cut at `limit` characters.
        public func preview(_ limit: Int = 80) -> String {
            if kind == .image, let picture { return Clipboard.preview(tr("Image %d×%d", picture.width, picture.height), limit) }
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

        /// A new copy: a clip at the top, or the clip with the same words (for a picture,
        /// the same bytes) moved there. Blank text is no copy. Returns whether the history changed.
        @discardableResult
        public mutating func add(_ clip: Clip) -> Bool {
            var clip = clip
            guard !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if clip.text.count > Clipboard.longestClip { clip.text = String(clip.text.prefix(Clipboard.longestClip)) }
            if let rtf = clip.rtf, rtf.count > Clipboard.largestRTF { clip.rtf = nil; clip.kind = .text }
            if let at = clips.firstIndex(where: { $0.kind == clip.kind && (clip.kind == .image ? $0.picture?.digest == clip.picture?.digest : $0.text == clip.text) }) {
                let old = clips.remove(at: at)
                clip.id = old.id
                clip.pinned = old.pinned
                // Its files are under the old id, in the old types.
                if clip.kind == .image { clip.picture = old.picture }
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
        /// A protected snippet's words, fingerprinted: SHA-256 of `secretSalt`'s bytes and then the words',
        /// so a copy of them in the history is told apart without the words themselves on disk.
        public var secretSalt: String?
        public var secretHash: String?

        public init(id: UUID = UUID(), title: String, text: String = "", protected: Bool = false,
                    keyCode: Int? = nil, modifiers: Int? = nil) {
            self.id = id; self.title = title; self.text = protected ? "" : text; self.protected = protected
            self.keyCode = keyCode; self.modifiers = modifiers
        }

        /// Fingerprints `words` with a fresh salt, for a protected snippet; nil words forget the fingerprint.
        public mutating func seal(_ words: String?) {
            guard let words, !words.isEmpty else { secretSalt = nil; secretHash = nil; return }
            let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            secretSalt = salt.base64EncodedString()
            secretHash = Clipboard.fingerprint(words, salt: salt)
        }

        /// Whether `text` is this protected snippet's words.
        public func holds(_ text: String) -> Bool {
            guard protected, let secretHash, let secretSalt, let salt = Data(base64Encoded: secretSalt),
                  text.count <= Clipboard.longestSecret else { return false }
            return Clipboard.fingerprint(text, salt: salt) == secretHash
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

    /// Longest words compared with protected snippets: a password is short, a page of text is not one.
    public static let longestSecret = 1024

    static func fingerprint(_ words: String, salt: Data) -> String {
        SHA256.hash(data: salt + Data(words.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// How a copy holding a protected snippet's words is shown: `PWD:Wi-Fi: [16] chars`.
    public static func maskLabel(_ title: String, length: Int) -> String { "PWD:\(title): [\(length)] chars" }

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

        /// The protected snippet whose words `text` is, if any.
        public func secret(matching text: String) -> Snippet? {
            all.lazy.map(\.snippet).first { $0.holds(text) }
        }

        /// What the picker shows for `clip`: its mask when it holds a protected snippet's words, else nil.
        public func mask(for clip: Clip) -> String? {
            guard clip.kind == .text || clip.kind == .rich, let snippet = secret(matching: clip.text) else { return nil }
            return Clipboard.maskLabel(snippet.title, length: clip.text.count)
        }

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
                    if kept.protected { kept.text = "" } else { kept.seal(nil) }
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
    /// accents ignored ("cafe" finds "Café"). A clip matches on its text and its app (a
    /// picture on its label, "Image 1280×720", in English and as shown; one holding a
    /// protected snippet's words only on its mask, `PWD:Wi-Fi: [16] chars`); a
    /// snippet on its title, its folder's title and its words, but a protected snippet
    /// only on its title and folder: its words are not here to search. An empty query
    /// finds everything: the pinned clips first, then the rest newest first.
    public static func search(_ query: String, history: History, snippets: SnippetBook) -> Found {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        func holds(_ haystack: String) -> Bool {
            let folded = fold(haystack)
            return words.allSatisfy { folded.contains($0) }
        }
        let clips = history.clips.filter { clip in
            if words.isEmpty { return true }
            if let mask = snippets.mask(for: clip) { return holds(mask + " " + (clip.app ?? "")) }
            return holds([clip.text, clip.app ?? "", clip.kind == .image ? clip.preview(200) : ""].joined(separator: " "))
        }
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

    // MARK: Pictures

    /// Picture types kept from the Mac's pasteboard, best first: the smallest that pastes everywhere leads.
    public static let imageTypes = ["public.png", "public.jpeg", "public.tiff", "com.compuserve.gif", "public.heic", "org.webmproject.webp"]

    /// Which of the types found to keep, best first in `preference`: each while all kept so far
    /// stay within `cap` bytes, so a huge TIFF is left out while its PNG stays. Empty: none fits.
    public static func keptImageTypes(_ found: [String: Int], cap: Int, preference: [String] = imageTypes) -> [String] {
        var total = 0
        return preference.filter { type in
            guard let bytes = found[type], total + bytes <= cap else { return false }
            total += bytes
            return true
        }
    }

    /// A short fingerprint of `data` (FNV-1a, 64 bits): equal bytes, equal digest.
    public static func digest(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(format: "%016llx-%d", hash, data.count)
    }

    // MARK: Files

    /// `clipboard.json` and `snippets.json`, side by side in the app's folder, and the
    /// pictures in `clipboard-images` there, a file per clip and type: `<id>.public.png`.
    public struct Store: Sendable {
        public let directory: URL
        public init(directory: URL) { self.directory = directory }
        public var historyFile: URL { directory.appendingPathComponent("clipboard.json") }
        public var snippetsFile: URL { directory.appendingPathComponent("snippets.json") }

        public var imagesDirectory: URL { directory.appendingPathComponent("clipboard-images") }
        public func imageFile(_ id: UUID, _ type: String) -> URL {
            imagesDirectory.appendingPathComponent("\(id.uuidString).\(type.replacingOccurrences(of: "/", with: "_"))")
        }

        /// A picture's bytes, a file per type.
        public func saveImage(_ id: UUID, _ kinds: [(type: String, data: Data)]) throws {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            for (type, data) in kinds { try data.write(to: imageFile(id, type), options: .atomic) }
        }

        /// An image clip's bytes in the types it was kept as, best first; empty when its files are gone.
        public func loadImage(_ clip: Clip) -> [(type: String, data: Data)] {
            (clip.picture?.types ?? []).compactMap { type in (try? Data(contentsOf: imageFile(clip.id, type))).map { (type, $0) } }
        }

        /// Deletes every picture file whose clip is no longer in `history`.
        public func sweepImages(keeping history: History) {
            let kept = Set(history.clips.filter { $0.kind == .image }.map(\.id.uuidString))
            let files = (try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                let id = String(file.lastPathComponent.prefix(36))
                if !kept.contains(id) { try? FileManager.default.removeItem(at: file) }
            }
        }

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
