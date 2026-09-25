import Foundation

/// Voices that fit personalities. A character's description and species are
/// read for words that say how it should sound (old, slow, tiny, cheerful,
/// grumpy, robot, ghost, he or she); every voice is tagged from what its name
/// or id says about it (Grandpa, `af_` for a female Kokoro voice,
/// `ManWithDeepVoice`); each character then gets the free voice that fits best.
///
/// Rules, not understanding: a description in words the rules do not know gets
/// a neutral profile. The brain model can cast instead (Settings › Voice).
public enum Casting {
    public enum Tag: String, CaseIterable, Codable, Sendable {
        case female, male, old, young, deep, bright, soft, robot, whisper
    }

    /// How a character should sound: how much each kind of voice suits it, and
    /// its pitch and speed as multipliers (1 is neutral).
    public struct Traits: Equatable, Sendable {
        public var wants: [Tag: Double] = [:]
        public var pitch = 1.0
        public var speed = 1.0
        public init(wants: [Tag: Double] = [:], pitch: Double = 1, speed: Double = 1) {
            self.wants = wants; self.pitch = pitch; self.speed = speed
        }
        public static let neutral = Traits()
    }

    public static let pitchRange = 0.7...1.5
    public static let speedRange = 0.75...1.3

    /// One rule: any of these word starts (or phrases) in the text, and the
    /// character wants these voices, a bit higher or lower, faster or slower.
    struct Rule {
        let words: [String]
        var wants: [Tag: Double] = [:]
        var pitch = 1.0
        var speed = 1.0
    }

    static let rules: [Rule] = [
        Rule(words: ["old", "ancient", "elder", "wise", "grand", "sage", "philosoph", "in my day", "proverb"],
             wants: [.old: 2, .deep: 0.5], pitch: 0.88, speed: 0.88),
        Rule(words: ["slow", "sleep", "nap", "drows", "yawn", "lazy", "patien", "calm", "damp", "purr"],
             wants: [.soft: 1], pitch: 0.95, speed: 0.85),
        Rule(words: ["fast", "quick", "speed", "hyper", "zipp", "rush"], wants: [.young: 1], speed: 1.2),
        Rule(words: ["tiny", "small", "little", "wee"], wants: [.young: 1], pitch: 1.12),
        Rule(words: ["cheer", "gigg", "laugh", "bounc", "excit", "enthus", "happy", "sweet", "ador", "playful",
                     "silly", "simple", "pleased"],
             wants: [.bright: 2], pitch: 1.08, speed: 1.05),
        Rule(words: ["grump", "gruff", "stubborn", "stable", "stern", "disapprov", "proud", "fat", "big", "huge"],
             wants: [.deep: 1.5], pitch: 0.88),
        Rule(words: ["boss", "organis", "organiz", "precise", "count"], speed: 1.05),
        Rule(words: ["loud", "dramat", "announc", "brag", "boast"], wants: [.bright: 0.5], speed: 1.05),
        Rule(words: ["anxi", "worr", "nerv", "scared", "afraid"], wants: [.soft: 0.5], pitch: 1.05, speed: 1.12),
        Rule(words: ["whisper", "wistful", "poet", "quiet", "soft", "dream", "earthy", "hush"],
             wants: [.soft: 1.5, .whisper: 0.5]),
        Rule(words: ["robot", "machine", "antenna", "rivet", "bolt", "status", "literal", "beep", "glitch", "virus",
                     "maintenance"],
             wants: [.robot: 3]),
        Rule(words: ["ghost", "spirit", "phantom", "haunt", "hover"], wants: [.whisper: 2.5, .soft: 0.5]),
        Rule(words: ["he", "him", "his", "sir", "man", "boy", "grandpa", "king", "mister", "gentleman"], wants: [.male: 2]),
        Rule(words: ["she", "her", "hers", "lady", "girl", "grandma", "queen", "madam", "woman"], wants: [.female: 2]),
    ]

    /// Words in `text`, lowercased: letters and apostrophes only.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0 == "'") }.map(String.init)
    }

    /// What `persona` and `kind` (the species, "a boxy little robot…") say about the voice.
    public static func traits(persona: String, kind: String) -> Traits {
        let text = persona + " " + kind
        let lower = " " + words(text).joined(separator: " ") + " "
        let tokens = words(text)
        var t = Traits()
        for rule in rules {
            let hit = rule.words.contains { stem in
                stem.contains(" ") ? lower.contains(" \(stem) ") : tokens.contains { word in
                    // Short words (he, her, man) must match whole, or "the" would be male.
                    stem.count <= 3 ? word == stem : word.hasPrefix(stem)
                }
            }
            guard hit else { continue }
            for (tag, weight) in rule.wants { t.wants[tag, default: 0] += weight }
            t.pitch *= rule.pitch
            t.speed *= rule.speed
        }
        t.pitch = min(max(t.pitch, pitchRange.lowerBound), pitchRange.upperBound)
        t.speed = min(max(t.speed, speedRange.lowerBound), speedRange.upperBound)
        return t
    }

    /// Voices known by name: the Mac's character and novelty voices, Kokoro's
    /// and Orpheus's that say more than their sex.
    static let known: [String: Set<Tag>] = [
        // Mac
        "grandma": [.old, .female], "grandpa": [.old, .male, .deep], "zarvox": [.robot], "trinoids": [.robot],
        "fred": [.robot, .male], "albert": [.robot, .male, .old], "whisper": [.whisper, .soft], "ralph": [.deep, .male],
        "rocko": [.deep, .male], "reed": [.male], "eddy": [.male, .young], "flo": [.female, .bright],
        "sandy": [.female], "shelley": [.female], "junior": [.young, .male, .bright], "kathy": [.female],
        "bubbles": [.bright, .young], "boing": [.bright], "bahh": [.bright], "wobble": [.soft], "jester": [.bright],
        // Kokoro
        "am_santa": [.old, .deep], "bm_george": [.old], "bm_lewis": [.old, .deep], "bm_fable": [.old],
        "am_onyx": [.deep], "am_fenrir": [.deep], "af_nicole": [.whisper, .soft], "af_sky": [.bright, .young],
        "af_bella": [.bright], "af_heart": [.bright], "am_puck": [.bright, .young], "am_echo": [.soft],
        "af_river": [.soft], "bf_lily": [.young],
        // Orpheus
        "tara": [.female], "leah": [.female, .bright], "jess": [.female, .bright], "mia": [.female, .young],
        "zoe": [.female, .young], "leo": [.male], "dan": [.male, .deep], "zac": [.male, .young],
    ]

    /// What a voice's id (and display name, if it has one) says about it.
    public static func tags(ofVoice id: String, name: String? = nil) -> Set<Tag> {
        var tags = Set<Tag>()
        let keys = [id.lowercased(), name?.lowercased()].compactMap { $0 }
        for key in keys { tags.formUnion(known[key] ?? []) }
        let text = keys.joined(separator: " ")
        // Kokoro: af_ am_ bf_ bm_ … the second letter is the sex.
        if let first = keys.first, first.count > 3, first.dropFirst(2).first == "_" {
            let sex = first.dropFirst().first
            if sex == "f" { tags.insert(.female) } else if sex == "m" { tags.insert(.male) }
        }
        // Names that describe themselves: MiniMax's English_ManWithDeepVoice, Voxtral's gb_jane_sad.
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["girl", "lady", "woman", "queen", "female", "jane", "marie"]) { tags.insert(.female) }
        else if has(["man", "boy", "gentleman", "bloke", "guy", "male", "paul", "oliver", "king"]) { tags.insert(.male) }
        if has(["deep", "angry", "frustrated", "bossy", "imposing"]) { tags.insert(.deep) }
        if has(["wise", "mature", "scholar", "mentor", "elder", "narrator", "storyteller"]) { tags.insert(.old) }
        if has(["whisper"]) { tags.insert(.whisper) }
        if has(["soft", "calm", "serene", "gentle", "sad", "patient"]) { tags.insert(.soft) }
        if has(["playful", "anime", "whimsical", "lovely", "upbeat", "radiant", "excited", "cheerful", "happy",
                "jovial", "comedian"]) { tags.insert(.bright) }
        if has(["boy", "girl", "teen", "young", "kid", "child"]) { tags.insert(.young) }
        if has(["robot"]) { tags.insert(.robot) }
        return tags
    }

    /// How well a voice with `tags` fits `traits`: wanted kinds add, the wrong
    /// sex takes away, and voices that are one strong thing (a robot, a whisper,
    /// an old voice) count against a character that did not ask for it.
    public static func score(_ tags: Set<Tag>, for traits: Traits) -> Double {
        var s = 0.0
        for (tag, weight) in traits.wants where tags.contains(tag) { s += weight }
        let wantsFemale = traits.wants[.female] ?? 0, wantsMale = traits.wants[.male] ?? 0
        if wantsFemale > 0, tags.contains(.male) { s -= wantsFemale }
        if wantsMale > 0, tags.contains(.female) { s -= wantsMale }
        if tags.contains(.robot), (traits.wants[.robot] ?? 0) == 0 { s -= 3 }
        // Only a character that really calls for it (a ghost) gets a whisper; a
        // poetic streak alone does not.
        if tags.contains(.whisper), (traits.wants[.whisper] ?? 0) < 2 { s -= 3 }
        if tags.contains(.old), (traits.wants[.old] ?? 0) == 0 { s -= 0.7 }
        return s
    }

    // MARK: Casting by the brain model

    /// What the model answers: a voice from the list, and pitch and speed multipliers.
    public struct Pick: Equatable, Sendable {
        public var voice: String
        public var pitch: Double?
        public var speed: Double?
        public var why: String?
        public init(voice: String, pitch: Double? = nil, speed: Double? = nil, why: String? = nil) {
            self.voice = voice; self.pitch = pitch; self.speed = speed; self.why = why
        }
    }

    public static let modelSystem = "You cast voices for small cartoon creatures that live on the edges of a computer screen. You answer with one JSON object and nothing else."

    /// The request: who the character is, and the voices to choose from, each
    /// with what is known about it.
    public static func modelPrompt(name: String, persona: String, kind: String,
                                   voices: [(id: String, hints: String)], cartoon: Bool) -> String {
        let list = voices.map { $0.hints.isEmpty ? "- \($0.id)" : "- \($0.id): \($0.hints)" }.joined(separator: "\n")
        return """
        Character: \(name), \(kind.isEmpty ? "a small creature" : kind).
        Personality: \(persona.isEmpty ? "not described" : persona)

        Pick the voice that fits this personality best, and how high and how fast it should speak.
        pitch and speed are multipliers: 1 is the voice as it is, 0.7 much lower or slower, 1.5 much higher or faster.\(cartoon ? " This is a cartoon: voices usually sit a little high, 1.1 to 1.4." : "")

        Voices:
        \(list)

        Answer with JSON only: {"voice": "<an id from the list>", "pitch": <0.7-1.6>, "speed": <0.75-1.3>, "why": "<a few words>"}
        """
    }

    /// The model's answer, from the first `{` to the last `}`, pitch and speed
    /// clamped; nil if there is no such object or it names no voice.
    public static func parsePick(_ text: String) -> Pick? {
        // A thinking model's reasoning comes first and may hold braces of its own.
        let text = text.range(of: "</think>").map { String(text[$0.upperBound...]) } ?? text
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let object = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              let voice = (object["voice"] as? String)?.trimmingCharacters(in: .whitespaces), !voice.isEmpty
        else { return nil }
        func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue ?? (object[key] as? String).flatMap(Double.init) }
        return Pick(voice: voice,
                    pitch: number("pitch").map { min(max($0, 0.5), 2) },
                    speed: number("speed").map { min(max($0, 0.5), 2) },
                    why: object["why"] as? String)
    }

    /// A voice from `pool` for every name, the best fit for its `traits` that is
    /// still free; hand-picked voices (`fixed`) are kept and not handed out.
    /// The characters with the strongest wishes choose first; ties go round the
    /// pool from a spot hashed from the name, so equal fits still differ.
    public static func assign(_ names: [String], traits: [String: Traits], pool: [String],
                              tags: [String: Set<Tag>], fixed: [String: String] = [:]) -> [String: String] {
        guard !pool.isEmpty else { return [:] }
        let everyone = Set(names)
        var result = fixed.filter { everyone.contains($0.key) }
        var taken = Set(result.values)
        func strength(_ n: String) -> Double { traits[n]?.wants.values.max() ?? 0 }
        let order = everyone.subtracting(result.keys).sorted { (strength($0), $1) > (strength($1), $0) }
        for name in order {
            let t = traits[name] ?? .neutral
            let start = Int(Voices.stableHash(name) % UInt64(pool.count))
            let rotated = (0..<pool.count).map { pool[(start + $0) % pool.count] }
            let free = rotated.filter { !taken.contains($0) }
            let choices = free.isEmpty ? rotated : free
            let best = choices.max { score(tags[$0] ?? [], for: t) < score(tags[$1] ?? [], for: t) } ?? choices[0]
            // `max` keeps the last of equals; the first in rotated order is wanted.
            let top = score(tags[best] ?? [], for: t)
            let pick = choices.first { score(tags[$0] ?? [], for: t) == top } ?? best
            result[name] = pick
            taken.insert(pick)
        }
        return result
    }
}
