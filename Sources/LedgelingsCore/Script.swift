import Foundation

/// Conversations written in advance, for a colony with no model behind it.
///
/// The text form is made to be typed by hand or by a chat model: one
/// conversation per block, blocks separated by a blank line, the lines of a
/// block alternating between the one who bumped (first line) and the one who
/// was bumped into. `#` starts a comment. A block may open with tags in square
/// brackets, `[flower]` or `[night, flower]`, and is then only used when the
/// moment matches; an untagged block fits any moment. `{speaker}`,
/// `{listener}`, `{flower}` and `{holiday}` are filled in when the line is said.
public struct Script: Equatable, Sendable {
    public struct Conversation: Equatable, Sendable {
        public var tags: Set<String>
        public var lines: [String]
        public init(tags: Set<String> = [], lines: [String]) { self.tags = tags; self.lines = lines }
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        /// 1-based line of the text.
        public var line: Int
        public var message: String
        public var description: String { line > 0 ? "line \(line): \(message)" : message }
    }

    /// What a block may be tagged with, and what a moment can be.
    public static let tags: Set<String> = ["flower", "night", "day", "holiday"]
    public static let placeholders = ["speaker", "listener", "flower", "holiday"]

    public var conversations: [Conversation]

    public init(conversations: [Conversation]) { self.conversations = conversations }

    // MARK: Text form

    public static func parse(_ text: String) throws(ParseError) -> Script {
        var conversations: [Conversation] = []
        var block: Conversation?
        var blockStart = 0
        func close() throws(ParseError) {
            guard let done = block else { return }
            guard !done.lines.isEmpty else { throw ParseError(line: blockStart, message: "a conversation needs at least one line after its tags") }
            conversations.append(done)
            block = nil
        }
        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = offset + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { try close(); continue }
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                guard block == nil else { throw ParseError(line: number, message: "tags go on the first line of a conversation") }
                let names = line.dropFirst().dropLast().split { $0 == "," || $0 == " " }.map { $0.lowercased() }
                if let bad = names.first(where: { !tags.contains($0) }) {
                    throw ParseError(line: number, message: "unknown tag \"\(bad)\"; the tags are \(tags.sorted().joined(separator: ", "))")
                }
                block = Conversation(tags: Set(names), lines: [])
                blockStart = number
                continue
            }
            if block == nil { block = Conversation(lines: []); blockStart = number }
            block?.lines.append(line)
        }
        try close()
        guard !conversations.isEmpty else { throw ParseError(line: 0, message: "no conversations") }
        return Script(conversations: conversations)
    }

    /// The script written back out in its own format.
    public func text() -> String {
        conversations.map { c in
            (c.tags.isEmpty ? [] : ["[" + c.tags.sorted().joined(separator: ", ") + "]"]) + c.lines
        }.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    // MARK: Choosing and saying

    /// The conversation to use now, by index: from the blocks whose every tag
    /// holds for `moment`, the most specifically tagged ones, and among those
    /// one not in `recent` (oldest first); when they all are, the one used
    /// longest ago, never the one just said. Nil when nothing fits.
    public func pick(for moment: Set<String>, avoiding recent: [Int],
                     using rng: inout some RandomNumberGenerator) -> Int? {
        let fitting = conversations.indices.filter { conversations[$0].tags.isSubset(of: moment) }
        guard let best = fitting.map({ conversations[$0].tags.count }).max() else { return nil }
        let pool = fitting.filter { conversations[$0].tags.count == best }
        let fresh = pool.filter { !recent.contains($0) }
        if let one = fresh.randomElement(using: &rng) { return one }
        return pool.min { recent.lastIndex(of: $0)! < recent.lastIndex(of: $1)! }
    }

    public static func fill(_ line: String, speaker: String, listener: String, flower: String?, holiday: String? = nil) -> String {
        Banter.render(line, ["speaker": speaker, "listener": listener, "flower": flower ?? "flower", "holiday": holiday ?? "the holiday"])
    }

    // MARK: Getting a model to write more

    /// A prompt to paste into any chat model: the format, the rules, the cast.
    public static func agentPrompt(cast: [Character], count: Int = 40) -> String {
        let who = cast.isEmpty ? "" : "\nThe creatures who might be talking (a line must work for any of them, so never use a name; write {speaker} and {listener} instead):\n"
            + cast.map { "- \($0.name): \($0.persona)" }.joined(separator: "\n") + "\n"
        return """
        Write \(count) short conversations between two small pixel creatures who live on the edges of a computer screen. \
        They crawl along the bottom, the sides and the ceiling, flee the mouse cursor, sleep at night, and sometimes walk into each other. \
        Each conversation happens when one creature walks into another. Make them funny, teasing, a little odd; never mean-spirited.

        Format, exactly:
        - One conversation per block, with a blank line between blocks.
        - The lines of a block alternate: the first line is the one who bumped, the second is the one who was bumped into, and so on. Two to four lines per block, mostly two.
        - Each line is at most 20 words. No name prefixes, no quotes, no numbering.
        - Placeholders: {speaker} is the one saying the line, {listener} is the other one, {flower} is the flower being given, {holiday} is the holiday it is today.
        - Use *asterisks* for an action or emphasis, like *sighs*.
        - About a quarter of the blocks start with the tag line [flower]: the one who bumped has just given the other a {flower}, and the lines are about it.
        - A few blocks start with [night]: it is dark, and they are supposed to be asleep. A block can have both: [night, flower].
        - A few blocks start with [holiday]: today is a holiday, named by {holiday} (it could be Christmas, Hanukkah, Eid al-Fitr or any other), so the lines must fit any of them.
        - Blocks without a tag line happen at any time.
        \(who)
        Example:

        Nice edge you've got there, {listener}.
        It was nicer before you turned up.

        [flower]
        Here. I found a {flower} under the cursor.
        Is it... ticking?

        [night]
        *whispers* Are you awake?
        No.

        Output only the blocks, nothing before or after.
        """
    }
}
