import Foundation

/// One character's own voice settings, set by hand in Settings › Voice. Every
/// field left nil is automatic: a voice handed out by `Voices.assign`, the
/// global speed, the cartoon lift or small nudge for pitch.
public struct CharacterVoice: Codable, Equatable, Sendable {
    /// A Mac voice identifier, for the built-in engine.
    public var systemVoice: String?
    /// One of the speech model's voices, for OpenRouter. Ignored when the
    /// chosen model has no voice by that name.
    public var openRouterVoice: String?
    /// One of the local server's voices, for the Local server engine.
    public var localVoice: String?
    /// Times the global Speed.
    public var speed: Double?
    /// Times the global Pitch, instead of the automatic lift.
    public var pitch: Double?
    /// Speed follows pitch for this character; nil follows the overall setting.
    public var followPitch: Bool?

    public init(systemVoice: String? = nil, openRouterVoice: String? = nil, localVoice: String? = nil,
                speed: Double? = nil, pitch: Double? = nil, followPitch: Bool? = nil) {
        self.systemVoice = systemVoice; self.openRouterVoice = openRouterVoice; self.localVoice = localVoice
        self.speed = speed; self.pitch = pitch; self.followPitch = followPitch
    }

    public var isAutomatic: Bool { systemVoice == nil && openRouterVoice == nil && localVoice == nil && speed == nil && pitch == nil && followPitch == nil }
}

/// Who sounds like whom, and what of a line is worth saying out loud. No audio
/// here: the app's `Voice` does the speaking, this decides what and with which voice.
public enum Voices {

    /// `assign`, with some characters' voices chosen by hand (`fixed`, name to
    /// voice). They keep theirs; everyone else is handed voices from what is
    /// left of the pool, or from the whole pool when nothing is left.
    public static func assign(_ names: [String], pool: [String], fixed: [String: String]) -> [String: String] {
        let everyone = Set(names)
        let chosen = fixed.filter { everyone.contains($0.key) }
        let free = pool.filter { !chosen.values.contains($0) }
        var result = assign(names.filter { chosen[$0] == nil }, pool: free.isEmpty ? pool : free)
        result.merge(chosen) { _, mine in mine }
        return result
    }

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

    /// The voices in a Kokoro blend, weights dropped: `af_bella(2)+am_puck(1)`
    /// gives `af_bella`, `am_puck`. A plain voice gives itself.
    public static func blendParts(_ voice: String) -> [String] {
        voice.split(separator: "+").map { part in
            let name = part.split(separator: "(", maxSplits: 1).first ?? part
            return name.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    /// True when `voice` can be asked for from a server with `voices`: one of
    /// them, or a blend of them. An empty list means it could not be checked.
    public static func isUsable(_ voice: String, among voices: [String]) -> Bool {
        let parts = blendParts(voice)
        return !parts.isEmpty && (voices.isEmpty || parts.allSatisfy(voices.contains))
    }

    /// A cartoon lift for a name: 1.15...1.6 times the voice's own pitch, always
    /// the same for a name, so every character squeaks at a height of its own.
    public static func cartoonPitch(for name: String) -> Double {
        1.15 + 0.45 * Double(stableHash(name + "#cartoon") % 1000) / 999
    }

    /// Words in a voice's name that mean it is playful rather than a newsreader:
    /// MiniMax's `English_AnimeCharacter`, Voxtral's `en_paul_excited`, Kokoro's `am_santa`.
    static let playful = ["anime", "playful", "whimsical", "comedian", "jovial", "lovely", "upbeat",
                          "excited", "cheerful", "happy", "santa", "boy", "girl", "radiant", "kind-hearted"]

    /// The playful voices of a list when there are at least two, else the list as it is.
    public static func cartoonFirst(_ voices: [String]) -> [String] {
        let fun = voices.filter { v in let l = v.lowercased(); return playful.contains { l.contains($0) } }
        return fun.count >= 2 ? fun : voices
    }

    /// The speed to have a line spoken at, before it is played `pitch` times
    /// faster (and so that much higher), like a tape.
    ///
    /// Asking for the full `speed / pitch` keeps the pace exactly, but a voice
    /// asked to speak very slowly stretches its vowels into a smear that sounds
    /// like an echo. With `followPitch`, it is asked for `speed / √pitch`, half
    /// the slowdown in musical terms: at a 1.4× cartoon lift it speaks at 0.85×,
    /// which every voice renders cleanly, and the line ends up 1.18× quicker, as
    /// a higher voice naturally would.
    public static func askedSpeed(speed: Double, pitch: Double, followPitch: Bool) -> Double {
        let lift = max(pitch, 0.01)
        return followPitch ? speed / lift.squareRoot() : speed / lift
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
