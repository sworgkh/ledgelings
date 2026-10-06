import Foundation

/// Who a creature is when it opens its mouth.
public struct Character: Codable, Equatable, Sendable {
    public var name: String
    public var persona: String

    public init(name: String, persona: String) {
        self.name = name
        self.persona = persona
    }
}

/// The words that go to the model. Pure string work, so it is testable without
/// a server: templates with `{placeholders}`, filled from a small dictionary.
public enum Banter {
    public static let placeholders = ["speaker", "speakerKind", "speakerPersona", "listener", "listenerKind", "listenerPersona", "situation", "line", "relationship"]

    /// What the built-in creature is, for the prompt.
    public static let defaultKind = "a small square creature"

    /// A persona or species kind as a prompt in the current language carries it:
    /// a shipped one in that language's words, one the user wrote as written.
    /// The English stays the data: casting and planting read that.
    public static func spoken(_ text: String) -> String { Strings.lookup(text, in: .current) }

    /// A character's persona as `{speakerPersona}` and `{listenerPersona}` carry it:
    /// a shipped persona about the cursor as the cursor mood has it, in the current
    /// language, and then how its owner takes the cursor in that mood
    /// (`CursorMood.note`), so a model writes in the mood even for a character the
    /// user invented. Voices are still cast from the persona as written.
    public static func persona(_ persona: String) -> String {
        let mood = CursorMood.current
        let said = spoken(mood.persona(persona)), note = mood.note
        return note.isEmpty ? said : said.isEmpty ? note : said + " " + note
    }

    public static let systemPrompts = Translated(english: englishSystemPrompt, [.russian: russianSystemPrompt])
    public static let linePrompts = Translated(english: englishLinePrompt, [.russian: russianLinePrompt])
    public static let replyPrompts = Translated(english: englishReplyPrompt, [.russian: russianReplyPrompt])
    public static var defaultSystemPrompt: String { systemPrompts() }
    public static var defaultLinePrompt: String { linePrompts() }
    public static var defaultReplyPrompt: String { replyPrompts() }

    public static let englishSystemPrompt = """
    You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}
    You are talking to {listener}, {listenerKind}, who lives on the same edge. {listenerPersona}
    Say ONE line to {listener}: a joke, a jab or a tease, at most 20 words, in your own voice.
    Output only the line. No quotes, no name prefix, no explanation.
    """

    public static let englishLinePrompt = """
    Right now: {situation}
    Say your line to {listener}.
    """

    public static let englishReplyPrompt = """
    Right now: {situation}
    {listener} just said to you: "{line}"
    Answer back in ONE line, in character, at most 20 words.
    """

    public static let defaultCharacters: [Character] = [
        Character(name: "Blocky", persona: "Grumpy and proud. Hates the mouse cursor. Thinks the bottom edge is the only respectable edge."),
        Character(name: "Pip", persona: "Cheerful and easily impressed. Loves the ceiling. Laughs at everything, including insults."),
        Character(name: "Mortimer", persona: "Old and philosophical. Speaks slowly, quotes wisdom he made up, sighs a lot."),
        Character(name: "Zed", persona: "Sleepy. Would rather be napping. Every sentence drifts toward bed."),
        Character(name: "Dot", persona: "Tiny, fast and sarcastic. Brags about speed. Calls everyone else a boulder."),
        Character(name: "Ruth", persona: "Bossy, organised, keeps count of everything. Disapproves of jumping."),
    ]

    /// How long a bubble stays up for a line of typical length, in seconds.
    public static let defaultBubbleSeconds: Double = 14

    /// Seconds a bubble stays. `base` is the time for a line of about eight
    /// words; longer lines get a little more, never past twice the base.
    public static func showTime(_ text: String, base: Double) -> Double {
        let words = Double(text.split(separator: " ").count)
        return min(base * 2, base / 2 + words * 0.9)
    }

    /// Replace every `{key}` in `template` with its value. Unknown keys are left as they are.
    public static func render(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { text, pair in text.replacingOccurrences(of: "{\(pair.key)}", with: pair.value) }
    }

    /// One line, cleaned up the way a small model needs: first non-empty line,
    /// no wrapping quotes, no "Name:" prefix, no hidden-reasoning tags, capped.
    ///
    /// `cut`: the model ran out of room mid-answer. A line that runs to the end
    /// of such an answer is kept only up to its last whole sentence, and dropped
    /// if it has none, so no bubble ever stops mid-word; the caller's empty-line
    /// path (a built-in line, or nothing) takes over. A cap that falls mid-line
    /// also ends on a whole sentence when one fits, else on a whole word and "…".
    public static func cleanLine(_ raw: String, speaker: String, maxLength: Int = 160, cut: Bool = false) -> String {
        var text = raw
        if let close = text.range(of: "</think>") { text = String(text[close.upperBound...]) }
        else if text.contains("<think>") { return "" }       // still thinking when it stopped
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var line = lines.first ?? ""
        // Only the last line of a cut answer is the one the room ran out in.
        if cut, lines.count == 1 { line = wholeSentences(line) }
        for prefix in ["\(speaker):", "\(speaker.uppercased()):", "*\(speaker)*:"] where line.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        while let first = line.first, let last = line.last, line.count > 1,
              ["\"", "“", "'", "*"].contains(String(first)), ["\"", "”", "'", "*"].contains(String(last)) {
            line = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        // A quote opened in the part a cut took away.
        if let first = line.first, ["\"", "“"].contains(first), !line.dropFirst().contains(where: { ["\"", "”"].contains($0) }) {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if line.count > maxLength {
            let head = String(line.prefix(maxLength))
            let sentences = wholeSentences(head)
            if sentences.count >= maxLength / 3 {
                line = sentences
            } else {
                let words = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
                line = words.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
            }
        }
        return line
    }

    /// `text` up to the end of its last whole sentence (". ", "! ", "? ", "…",
    /// with any closing quote, bracket or star), or "" when no sentence ends in it.
    public static func wholeSentences(_ text: String) -> String {
        let enders: Set<Swift.Character> = [".", "!", "?", "…"]
        let closers: Set<Swift.Character> = ["\"", "”", "'", "’", ")", "*", "_"]
        let chars = Array(text)
        var end = 0
        var i = 0
        while i < chars.count {
            if enders.contains(chars[i]) {
                var j = i + 1
                while j < chars.count, enders.contains(chars[j]) || closers.contains(chars[j]) { j += 1 }
                if j == chars.count || chars[j] == " " { end = j }
                i = j
            } else {
                i += 1
            }
        }
        return String(chars[..<end]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: What the model's marks mean on screen

    /// A stretch of a line with one look: `*sighs*` and `_really_` are italic,
    /// `**important**` bold, `***loud***` both.
    public struct StyledRun: Equatable, Sendable {
        public var text: String
        public var bold: Bool
        public var italic: Bool
        public init(_ text: String, bold: Bool = false, italic: Bool = false) {
            self.text = text; self.bold = bold; self.italic = italic
        }
    }

    /// The line cut into runs. A mark only counts when it opens against a
    /// non-space, closes after a non-space, and has its twin later in the line
    /// (`_` also needs a word boundary on the outside), so "2 * 3" and
    /// "snake_case" stay as written. Runs of spaces collapse to one.
    public static func styled(_ line: String) -> [StyledRun] {
        let chars = Array(line)
        var runs: [StyledRun] = []
        var buffer = ""
        var bold = false, italic = false
        var open: [(mark: Swift.Character, count: Int)] = []
        var lastWasSpace = false
        func flush() {
            if !buffer.isEmpty { runs.append(StyledRun(buffer, bold: bold, italic: italic)); buffer = "" }
        }
        func isWordChar(_ c: Swift.Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
        func opens(at i: Int, _ n: Int) -> Bool {
            guard i + n < chars.count, !chars[i + n].isWhitespace, chars[i + n] != chars[i] else { return false }
            return chars[i] == "*" || !isWordChar(i > 0 ? chars[i - 1] : nil)
        }
        func closes(at i: Int, _ n: Int) -> Bool {
            guard i > 0, !chars[i - 1].isWhitespace, chars[i - 1] != chars[i] else { return false }
            return chars[i] == "*" || !isWordChar(i + n < chars.count ? chars[i + n] : nil)
        }
        func runLength(at i: Int) -> Int {
            var n = 1
            while i + n < chars.count, chars[i + n] == chars[i] { n += 1 }
            return n
        }
        func hasCloser(_ mark: Swift.Character, _ n: Int, from start: Int) -> Bool {
            var j = start
            while j < chars.count {
                if chars[j] == mark {
                    let m = runLength(at: j)
                    if m == n, closes(at: j, n) { return true }
                    j += m
                } else { j += 1 }
            }
            return false
        }
        func apply(_ mark: Swift.Character, _ n: Int, on: Bool) {
            switch n {
            case 1: italic = on
            case 2: bold = on
            default: bold = on; italic = on
            }
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "*" || c == "_" {
                let n = runLength(at: i)
                if n <= 3, let top = open.last, top.mark == c, top.count == n, closes(at: i, n) {
                    flush(); apply(c, n, on: false); open.removeLast(); i += n; continue
                }
                if n <= 3, opens(at: i, n), hasCloser(c, n, from: i + n) {
                    flush(); apply(c, n, on: true); open.append((c, n)); i += n; continue
                }
                buffer += String(repeating: c, count: n); lastWasSpace = false; i += n; continue
            }
            if c == " " {
                if !lastWasSpace { buffer.append(c) }
                lastWasSpace = true
            } else {
                buffer.append(c); lastWasSpace = false
            }
            i += 1
        }
        flush()
        return runs
    }

    /// The line with the marks taken out, for anywhere that cannot show a style.
    public static func plain(_ line: String) -> String { styled(line).map(\.text).joined() }
}
