import Foundation

/// What each character has said lately, so it does not say it again every
/// round: a built-in line is picked from the ones it has not said lately, and
/// a model is shown its recent lines and asked for something new. A line comes
/// back only once everything else has had its turn.
public struct LineMemory: Equatable, Sendable {
    /// Lines kept per character; 0 remembers nothing.
    public var limit: Int
    /// By character name, oldest first.
    public private(set) var said: [String: [String]] = [:]

    public init(limit: Int) { self.limit = max(0, limit) }

    public mutating func remember(_ text: String, by name: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !text.isEmpty else { return }
        let key = Self.key(text)
        var lines = (said[name] ?? []).filter { Self.key($0) != key }
        lines.append(text)
        said[name] = Array(lines.suffix(limit))
    }

    /// Every line of `exchange`, by who said it.
    public mutating func remember(_ exchange: ChatLog.Exchange) {
        for line in exchange.lines { remember(line.text, by: line.speaker) }
    }

    /// `name`'s last lines, oldest first.
    public func recent(of name: String) -> [String] { Array((said[name] ?? []).suffix(limit)) }

    /// Keep only the last `limit` lines of everyone.
    public mutating func trim(to limit: Int) {
        self.limit = max(0, limit)
        said = said.mapValues { Array($0.suffix(self.limit)) }.filter { !$0.value.isEmpty }
    }

    /// Which of `candidates` `name` should say: one it has not said lately, at
    /// random; when it has said them all, the one said longest ago.
    public func pick(from candidates: [String], by name: String, using rng: inout some RandomNumberGenerator) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let recent = self.recent(of: name).map(Self.key)
        let fresh = candidates.indices.filter { !recent.contains(Self.key(candidates[$0])) }
        if let one = fresh.randomElement(using: &rng) { return one }
        return candidates.indices.min { recent.lastIndex(of: Self.key(candidates[$0]))! < recent.lastIndex(of: Self.key(candidates[$1]))! }
    }

    /// Two lines are the same if they differ only in case, spacing and punctuation.
    public static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Swift.Character.init))
    }

    /// The system prompt with `lines` after it, telling the model not to say them again.
    public static func withRecent(_ system: String, _ lines: [String]) -> String {
        guard !lines.isEmpty else { return system }
        return system + "\n" + note(lines)
    }

    /// What the model is told about its own recent lines.
    public static func note(_ lines: [String]) -> String {
        "You said these lately. Say something new: do not repeat them, their jokes, or the way they start.\n"
            + lines.map { "- \($0)" }.joined(separator: "\n")
    }
}
