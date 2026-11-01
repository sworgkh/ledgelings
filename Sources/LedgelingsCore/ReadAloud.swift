import Foundation

/// Read aloud (§7.16): text in, audio out. Pasted or typed text is cut into
/// parts at paragraph and sentence ends, each part's language told by its
/// letters, and each part read by a speech model (or the Mac's own voices) in a
/// preset's voice and pace. The parts play as they arrive; the whole reading can
/// be saved as one audio file or put on the clipboard as one.
///
/// Everything here is plain logic: the parts, the presets, the voice that fits a
/// language, the price before sending, the buttons' pictures and words. The
/// sound itself is made and played by the app.
public enum ReadAloud {
    // MARK: Engines

    /// Who reads: a speech model on OpenRouter, the Mac's own voices, or a speech server on this computer.
    public enum Engine: String, CaseIterable, Codable, Sendable {
        case openRouter, system, local

        public var title: String {
            switch self {
            case .openRouter: tr("OpenRouter speech model")
            case .system: tr("The Mac's own voices")
            case .local: tr("Local speech server")
            }
        }

        /// A paid call, priced on Settings › Costs; the others are free.
        public var isPaid: Bool { self == .openRouter }
    }

    /// Gemini 3.8 Flash Lite TTS: one voice list for every language (Hebrew too),
    /// a natural read, about a cent per thousand characters. Measured against
    /// Kokoro (English only) and MAI Voice 2.1 Flash (no Hebrew) with `--read-bench`.
    public static let defaultModel = "google/gemini-3.8-flash-lite-tts"

    // MARK: Presets

    /// A ready-made way of reading: who reads (the engine, the model, a voice),
    /// as whom (a character, or a narrator), how fast, and how long it rests at
    /// the end of a paragraph. Saved in the settings; the owner adds, renames and
    /// deletes their own.
    public struct Preset: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var engine: Engine
        /// The OpenRouter model; empty: `defaultModel`.
        public var model: String
        /// One of the model's voices, or a Mac voice identifier; empty: chosen for
        /// the character (cast from its persona) or the narrator's first.
        public var voice: String
        /// A character's name, from any species' cast; empty: a narrator.
        public var character: String
        /// 1 is the voice's own pace.
        public var speed: Double
        /// Seconds of quiet at the end of each paragraph.
        public var pause: Double
        /// "en", "ru" or "he" to read everything as that language; empty: told per part.
        public var language: String

        public init(id: UUID = UUID(), name: String, engine: Engine = .openRouter, model: String = "", voice: String = "",
                    character: String = "", speed: Double = 1, pause: Double = defaultPause, language: String = "") {
            self.id = id; self.name = name; self.engine = engine; self.model = model; self.voice = voice
            self.character = character; self.speed = speed; self.pause = pause; self.language = language
        }

        /// Read leniently: a missing or unknown field takes its default, numbers are clamped.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            engine = (try? c.decode(String.self, forKey: .engine)).flatMap(Engine.init(rawValue:)) ?? .openRouter
            model = (try? c.decode(String.self, forKey: .model)) ?? ""
            voice = (try? c.decode(String.self, forKey: .voice)) ?? ""
            character = (try? c.decode(String.self, forKey: .character)) ?? ""
            speed = (try? c.decode(Double.self, forKey: .speed)) ?? 1
            pause = (try? c.decode(Double.self, forKey: .pause)) ?? ReadAloud.defaultPause
            language = (try? c.decode(String.self, forKey: .language)) ?? ""
            self = clamped()
        }

        /// The numbers inside their ranges, a known language or none, a name.
        public func clamped() -> Preset {
            var p = self
            p.speed = (min(max(speed, ReadAloud.speedRange.lowerBound), ReadAloud.speedRange.upperBound) * 20).rounded() / 20
            p.pause = (min(max(pause, ReadAloud.pauseRange.lowerBound), ReadAloud.pauseRange.upperBound) * 10).rounded() / 10
            if Translate.language(language) == nil { p.language = "" }
            p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.name.isEmpty { p.name = tr("Preset") }
            p.model = model.trimmingCharacters(in: .whitespaces)
            return p
        }

        /// The model this preset asks.
        public var modelOrDefault: String { model.isEmpty ? ReadAloud.defaultModel : model }

        /// Its name in the app's language: a shipped preset's name is translated, the owner's own is shown as written.
        public var title: String { tr(name) }

        /// The language it forces, if any.
        public var forcedLanguage: Translate.Language? { Translate.language(language) }
    }

    public static let speedRange = 0.5...2.0
    public static let pauseRange = 0.0...3.0
    public static let defaultPause = 0.6

    /// The shipped presets, with fixed ids so the default survives a relaunch. Editable like any other.
    public static let defaultPresets: [Preset] = [
        Preset(id: UUID(uuidString: "6E61722D-0000-4000-8000-000000000001")!, name: "Narrator", voice: "Charon", speed: 1, pause: 0.6),
        Preset(id: UUID(uuidString: "6E61722D-0000-4000-8000-000000000002")!, name: "Quick skim", voice: "Puck", speed: 1.6, pause: 0.2),
        Preset(id: UUID(uuidString: "6E61722D-0000-4000-8000-000000000003")!, name: "Bedtime", character: "Zed", speed: 0.8, pause: 1.2),
        Preset(id: UUID(uuidString: "6E61722D-0000-4000-8000-000000000004")!, name: "Robot", character: "Unit 7", speed: 1.1, pause: 0.4),
        Preset(id: UUID(uuidString: "6E61722D-0000-4000-8000-000000000005")!, name: "Russian", voice: "Kore", speed: 1, pause: 0.6, language: "ru"),
    ]

    /// The default of the defaults: the narrator.
    public static var defaultPresetID: UUID { defaultPresets[0].id }

    /// At most this many presets, so each keeps a number key on the sheet.
    public static let mostPresets = 9

    /// Presets as saved: each id once, at most `mostPresets`, the shipped ones when none are left.
    public static func cleaned(_ presets: [Preset]) -> [Preset] {
        var seen = Set<UUID>()
        let kept = presets.map { $0.clamped() }.filter { seen.insert($0.id).inserted }.prefix(mostPresets)
        return kept.isEmpty ? defaultPresets : Array(kept)
    }

    /// A name not yet taken: "My preset", "My preset 2"…
    public static func freeName(_ wanted: String, among presets: [Preset]) -> String {
        let taken = Set(presets.map { $0.name.lowercased() })
        guard taken.contains(wanted.lowercased()) else { return wanted }
        var n = 2
        while taken.contains("\(wanted) \(n)".lowercased()) { n += 1 }
        return "\(wanted) \(n)"
    }

    // MARK: Parts

    /// One piece of the text, read in one call: its words, the language its
    /// letters say, and whether a paragraph ends with it (a rest follows).
    public struct Part: Equatable, Sendable {
        public var text: String
        public var language: Translate.Language?
        public var paragraphEnd: Bool
        public init(text: String, language: Translate.Language?, paragraphEnd: Bool) {
            self.text = text; self.language = language; self.paragraphEnd = paragraphEnd
        }
    }

    /// The first part is short, so the first sound comes quickly; the rest are longer, so there are fewer calls.
    public static let firstPartSize = 240
    public static let partSize = 900
    /// Parts asked for ahead of the one playing.
    public static let partsAhead = 2

    /// The text in parts: a paragraph is a line with words on it; a paragraph
    /// longer than a part is cut after a sentence, else after a comma, else
    /// after a word. `forced` reads every part as that language.
    public static func parts(_ text: String, first: Int = firstPartSize, size: Int = partSize,
                             forced: Translate.Language? = nil) -> [Part] {
        let paragraphs = text.components(separatedBy: .newlines)
            .map { Voices.speakable($0) }
            .filter { !$0.isEmpty }
        var parts: [Part] = []
        var language: Translate.Language?
        for paragraph in paragraphs {
            var rest = Substring(paragraph)
            while !rest.isEmpty {
                let limit = parts.isEmpty ? first : size
                let piece = rest.count <= limit ? rest : rest.prefix(upTo: cut(rest, limit: limit))
                rest = rest[piece.endIndex...].drop { $0 == " " }
                let words = piece.trimmingCharacters(in: .whitespaces)
                guard !words.isEmpty else { continue }
                // A part with no letters of its own (a number, a link) keeps the language before it.
                if let told = Translate.detect(Translate.protect(words).text) { language = told }
                parts.append(Part(text: words, language: forced ?? language, paragraphEnd: rest.isEmpty))
            }
        }
        return parts
    }

    /// Where to cut `text` to at most `limit` characters: after the last sentence end, else comma or dash, else at a space.
    static func cut(_ text: Substring, limit: Int) -> Substring.Index {
        let window = text.prefix(limit)
        guard window.count >= 3 else { return window.endIndex }
        // Not so early that a part is a few words only.
        let floor = window.index(window.startIndex, offsetBy: max(1, limit / 3))
        func ends(_ i: Substring.Index) -> Bool {
            let next = text.index(after: i)
            return next == text.endIndex || text[next] == " "
        }
        for marks in [".!?…", ",;:—–"] {
            var i = window.index(before: window.endIndex)
            while i >= floor {
                if marks.contains(window[i]), ends(i) { return text.index(after: i) }
                if i == floor { break }
                i = window.index(before: i)
            }
        }
        return window[floor...].lastIndex(of: " ") ?? window.endIndex
    }

    // MARK: What is never sent

    public enum Refusal: Equatable, Sendable {
        /// Nothing but spaces and new lines.
        case empty
        /// A protected snippet, or a copy of its words: they stay on this computer.
        case protected
        /// Longer than `hardCap`.
        case tooLong

        public var line: String {
            switch self {
            case .empty: tr("Nothing to read: paste or type some text")
            case .protected: tr("That is a protected snippet; it stays on this computer")
            case .tooLong: tr("Too long: at most %@ characters at a time", Translate.grouped(hardCap))
            }
        }
    }

    public static let hardCap = 50_000
    /// Above this many characters a paid reading waits for ⏎, showing its price first.
    public static let longLimitRange = 500...20_000
    public static let defaultLongLimit = 3_000

    /// The one check before anything is read: the sheet, the picker's button and the flag all ask it.
    public static func refusal(_ text: String, snippets: Clipboard.SnippetBook) -> Refusal? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if snippets.secret(matching: text) != nil { return .protected }
        if text.count > hardCap { return .tooLong }
        if parts(text).isEmpty { return .empty }
        return nil
    }

    public static func refusal(_ clip: Clipboard.Clip, snippets: Clipboard.SnippetBook) -> Refusal? {
        guard clip.kind == .text || clip.kind == .rich else { return .empty }
        if snippets.mask(for: clip) != nil { return .protected }
        return refusal(clip.text, snippets: snippets)
    }

    public static func refusal(_ snippet: Clipboard.Snippet, snippets: Clipboard.SnippetBook) -> Refusal? {
        snippet.protected ? .protected : refusal(snippet.text, snippets: snippets)
    }

    // MARK: The price before sending

    /// About how many seconds a text takes to say at 1×: 15 characters a second.
    public static func seconds(characters: Int, speed: Double = 1) -> Double { Double(characters) / 15 / max(speed, 0.1) }

    /// About what reading `characters` costs, from the model's list prices per
    /// token. A model that charges for its sound (Gemini: 25 audio tokens a
    /// second) pays for the seconds too; one that charges per character pays for
    /// the characters alone. Nil when the price is not known.
    public static func estimate(characters: Int, promptPerToken: Double?, completionPerToken: Double?) -> Double? {
        guard let promptPerToken else { return nil }
        let completion = completionPerToken ?? 0
        if completion > 0 {
            let input = Double(characters) / 4 + 30
            let output = seconds(characters: characters) * 25
            return input * promptPerToken + output * completion
        }
        return Double(characters) * promptPerToken
    }

    // MARK: Voices that speak a language

    /// The voices of a model's list that speak `language`. A list whose names
    /// carry no language mark (Gemini's `Kore`, `Puck`) speaks them all; a list
    /// that marks its languages (Kokoro's `af_bella`, MAI's `ru-RU-Lev:…`) speaks
    /// only the marked ones, and may speak none: then the Mac's voice reads that part.
    public static func voices(_ voices: [String], speaking language: Translate.Language) -> [String] {
        let marked = voices.filter { mark(of: $0) != nil }
        if marked.isEmpty { return voices }
        return voices.filter { mark(of: $0) == language.code }
    }

    /// The language a voice's name says it speaks, as a code; nil when it says none.
    static func mark(of voice: String) -> String? {
        let v = voice.lowercased()
        if Voices.isRussian(v) { return "ru" }
        if v.hasPrefix("he-") || v.hasPrefix("he_") || v.hasPrefix("hebrew") || v.hasPrefix("iw-") || v.hasSuffix("-he") { return "he" }
        if Voices.orpheusEnglish.contains(v) { return "en" }
        if Voices.isEnglish(voice) { return "en" }
        // Another language by its mark: `es-MX-…`, Kokoro's `ef_dora` (Spanish), `jf_alpha`, `zf_xiaobei`.
        if v.range(of: #"^[a-z]{2}-[a-z]{2}-"#, options: .regularExpression) != nil { return String(v.prefix(2)) }
        if v.range(of: #"^[abefhijpz][fm]_"#, options: .regularExpression) != nil { return "xx" }
        if v.range(of: #"^(spanish|french|german|italian|japanese|korean|chinese|portuguese|arabic|hindi)_"#, options: .regularExpression) != nil { return "xx" }
        return nil
    }

    // MARK: Saving

    public enum Format: String, CaseIterable, Codable, Sendable {
        case m4a, wav

        public var title: String {
            switch self {
            case .m4a: tr("M4A (small, plays everywhere)")
            case .wav: tr("WAV (big, exact)")
            }
        }
    }

    /// "Read aloud 2026-11-01 14.32 – The first words.m4a": the time it was made and the text's start.
    public static func fileName(for text: String, at date: Date, format: Format) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        // Marks a file name cannot hold become spaces before the words are counted.
        let plain = String(String.UnicodeScalarView(text.unicodeScalars.map { "/\\:*?\"<>|".unicodeScalars.contains($0) ? " " : $0 }))
        let words = Voices.speakable(plain).split(separator: " ").prefix(6).joined(separator: " ")
        let safe = words.prefix(48)
        let start = safe.isEmpty ? "" : " – " + safe
        return tr("Read aloud") + " " + f.string(from: date) + start + "." + format.rawValue
    }

    // MARK: Words for the sheet

    /// "1:05": minutes and seconds.
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The creature reading's bubble: a dot running along three, never said.
    public static func readingDots(since: Double) -> String {
        ["•··", "·•·", "··•", "·•·"][Int(since * 4) % 4]
    }

    /// How far a creature reading bobs, in points: a slow nod over the page.
    public static func readingBob(since: Double) -> Double {
        let phase = since.truncatingRemainder(dividingBy: 0.9) / 0.9
        return phase < 0.5 ? 2 : 0
    }

    /// The pace a step on the sheet goes to: 0.1 a step, inside the range.
    public static func step(_ speed: Double, by steps: Int) -> Double {
        let next = ((speed + Double(steps) * 0.1) * 10).rounded() / 10
        return min(max(next, speedRange.lowerBound), speedRange.upperBound)
    }

    /// "1.6×".
    public static func speedLabel(_ speed: Double) -> String { String(format: "%g×", (speed * 100).rounded() / 100) }
}
