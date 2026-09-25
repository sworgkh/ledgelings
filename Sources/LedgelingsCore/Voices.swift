import Foundation

/// Who sounds like whom, and what of a line is worth saying out loud. No audio
/// here: the app's `Voice` does the speaking, this decides what and with which voice.
public enum Voices {

    /// Every character in `names` gets a voice from `pool`, and the same name
    /// gets the same voice every launch while the pool stays the same. Two
    /// characters share a voice only once the pool has run out.
    ///
    /// Each name starts from a spot picked by a hash of the name and takes the
    /// first voice nobody has yet, going round the pool. Names are handled in
    /// sorted order, so the answer does not depend on who happens to be first.
    public static func assign(_ names: [String], pool: [String]) -> [String: String] {
        guard !pool.isEmpty else { return [:] }
        var taken: Set<String> = []
        var result: [String: String] = [:]
        for name in Set(names).sorted() {
            let start = Int(stableHash(name) % UInt64(pool.count))
            let free = (0..<pool.count).map { pool[(start + $0) % pool.count] }.first { !taken.contains($0) }
            let voice = free ?? pool[start]
            taken.insert(voice)
            result[name] = voice
        }
        return result
    }

    /// A small nudge in 0.9...1.1 that is always the same for a name, so two
    /// characters sharing a voice still do not sound identical.
    public static func pitchNudge(for name: String) -> Double {
        0.9 + 0.2 * Double(stableHash(name + "#pitch") % 1000) / 999
    }

    /// FNV-1a over the UTF-8 bytes. Swift's own `hashValue` changes every launch.
    public static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash
    }

    /// The English voices of a speech model's list, when its names say which
    /// they are; otherwise the whole list. Providers mark language in the name:
    /// `flux-kit-en`, `en_paul_happy`, `gb_jane_sad`, `English_Comedian`,
    /// `en-US-Harper:MAI-Voice-2`, Kokoro's `af_bella` / `bm_george`.
    public static func englishFirst(_ voices: [String]) -> [String] {
        let english = voices.filter(isEnglish)
        return english.isEmpty ? voices : english
    }

    static func isEnglish(_ voice: String) -> Bool {
        let v = voice.lowercased()
        if v.hasSuffix("-en") || v.hasPrefix("en_") || v.hasPrefix("gb_") || v.hasPrefix("en-") || v.hasPrefix("english_") { return true }
        // Kokoro: first letter is the language (a = American, b = British), second the sex.
        let parts = v.split(separator: "_", maxSplits: 1)
        if parts.count == 2, let tag = parts.first, tag.count == 2, ["af", "am", "bf", "bm"].contains(tag) { return true }
        return false
    }

    /// The line as it should be heard: no emoji, no *stage directions*, no
    /// markdown marks, no runs of spaces. Empty when nothing sayable is left.
    public static func speakable(_ line: String) -> String {
        var text = line.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)   // **bold** is said
        text = text.replacingOccurrences(of: #"\*[^*]+\*"#, with: " ", options: .regularExpression)             // *sighs* is not
        text = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C))
                && scalar != "\u{FE0F}" && scalar != "\u{200D}" && !"*_~`#".unicodeScalars.contains(scalar)
        }))
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: #" ([.,!?;:])"#, with: "$1", options: .regularExpression)
    }
}
