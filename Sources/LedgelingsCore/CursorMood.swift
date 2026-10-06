import Foundation
import Synchronization

/// How the creatures take the mouse cursor that chases them about the edges.
///
/// The cursor itself does the same in every mood: a creature still jumps out of
/// its way and can still be picked up. What changes is what they make of it,
/// everywhere they talk about it:
/// - `good`: the cursor is a playmate and being chased is a game of tag;
/// - `neutral`: it just happens, like weather, nothing to have feelings about;
/// - `bad`: the cursor is a menace (how the creatures were first written).
///
/// Three ways a mood reaches what is said:
/// - A model hears it through `{speakerPersona}` (`Banter.persona`): a shipped
///   persona that mentions the cursor is rewritten for the mood, and every
///   persona, a user's own included, gains a sentence saying how its owner takes
///   the cursor. A prompt the user edited keeps working as long as it carries
///   `{speakerPersona}`, which every shipped prompt does.
/// - A shipped built-in line or conversation about the cursor is swapped for the
///   mood's version of it (`adjust`); lines the user wrote are left alone.
/// - The complaint a creature makes when chased too often has its own lines and
///   its own prompt per mood (`Complaints`).
public enum CursorMood: String, CaseIterable, Codable, Sendable {
    case good, neutral, bad

    /// What the creatures think the cursor is, as the settings picker and the menu show it.
    public var title: String {
        switch self {
        case .good: tr("A playmate")
        case .neutral: tr("Just there")
        case .bad: tr("A menace")
        }
    }

    /// The menu's status while a model writes what a creature says when chased too often.
    public var speakingUp: String {
        switch self {
        case .good: tr("%@ is teasing you via %@…")
        case .neutral: tr("%@ is talking to you via %@…")
        case .bad: tr("%@ is complaining via %@…")
        }
    }

    /// The menu's status once it has said it.
    public var spokeUp: String {
        switch self {
        case .good: tr("%@ teased you: %@")
        case .neutral: tr("%@ said to you: %@")
        case .bad: tr("%@ complained: %@")
        }
    }

    // MARK: The current mood

    private static let chosen = Mutex<CursorMood>(.bad)

    /// A mood for the code running inside `$override.withValue`, whatever the app
    /// has chosen: how tests ask for a mood without touching the app's choice.
    @TaskLocal public static var override: CursorMood?

    /// How the creatures take the cursor right now.
    public static var current: CursorMood { override ?? chosen.withLock { $0 } }

    /// Set by the app from its settings, at launch and on every change.
    public static func choose(_ mood: CursorMood) { chosen.withLock { $0 = mood } }

    // MARK: For a model

    /// The sentence every persona gains in this mood, in the current language.
    /// Bad adds none: the shipped personas already say it, as they always have.
    public var note: String { Self.notes(self)() }

    static func notes(_ mood: CursorMood) -> Translated<String> {
        switch mood {
        case .good: Translated(english: "To them the mouse cursor is a playmate: being chased by it is a game of tag, and they love to win it.",
                               [.russian: "Курсор мыши для них — приятель по играм: когда он гоняется за ними, это игра в догонялки, и они обожают в ней побеждать."])
        case .neutral: Translated(english: "The mouse cursor means nothing to them: it comes and goes like the weather, and they hop out of its way without a thought.",
                                  [.russian: "Курсор мыши для них ничего не значит: приходит и уходит, как погода, и они отпрыгивают с его пути не задумываясь."])
        case .bad: Translated(english: "")
        }
    }

    /// What the creatures do about the cursor, as the prompt for writing more
    /// built-in lines says it ("They crawl along the edges, …, sleep at night").
    public var agentPhrase: String {
        switch (self, Language.current) {
        case (.good, .english): "play tag with the mouse cursor"
        case (.neutral, .english): "hop out of the mouse cursor's way"
        case (.bad, .english): "flee the mouse cursor"
        case (.good, .russian): "играют с курсором мыши в догонялки"
        case (.neutral, .russian): "отпрыгивают с пути курсора мыши"
        case (.bad, .russian): "убегают от курсора мыши"
        }
    }

    /// `persona` as this mood has it, still in English: a shipped persona that
    /// talks about the cursor becomes the mood's version; any other stays itself.
    public func persona(_ persona: String) -> String {
        guard self != .bad, let moods = Self.personas[persona] else { return persona }
        return self == .good ? moods.good : moods.neutral
    }

    /// The shipped personas that mention the cursor, and what they become.
    /// The Russian of each is in the personas table, like the originals.
    public static let personas: [String: Rewrite] = [
        "Grumpy and proud. Hates the mouse cursor. Thinks the bottom edge is the only respectable edge.": Rewrite(
            good: "Grumpy and proud. Secretly loves racing the mouse cursor and would never admit it. Thinks the bottom edge is the only respectable edge.",
            neutral: "Grumpy and proud. Thinks the bottom edge is the only respectable edge."),
        "Occasionally repeats a word word. Suspects the cursor is a virus.": Rewrite(
            good: "Occasionally repeats a word word. Scanned the cursor once: it is a friend friend.",
            neutral: "Occasionally repeats a word word. Runs virus scans on everything, out of habit."),
    ]

    // MARK: Built-in lines

    /// A shipped line about the cursor and the line said instead in each other mood.
    public struct Rewrite: Sendable, Equatable {
        public var good: String
        public var neutral: String
        public init(good: String, neutral: String) { self.good = good; self.neutral = neutral }
    }

    /// `text` as this mood says it: a shipped line (or a whole conversation, its
    /// lines joined by newlines) about the cursor becomes the mood's version, in
    /// the current language. Anything else, and everything in the bad mood, is
    /// left as it is.
    public func adjust(_ text: String) -> String {
        guard self != .bad, let moods = Self.rewrites()[text] else { return text }
        return self == .good ? moods.good : moods.neutral
    }

    /// A conversation as this mood has it: rewritten whole, so its lines still answer each other.
    public func adjust(_ lines: [String]) -> [String] {
        let joined = lines.joined(separator: "\n")
        let said = adjust(joined)
        return said == joined ? lines : said.components(separatedBy: "\n")
    }

    public func adjust(_ lines: [String: [String]]) -> [String: [String]] { lines.mapValues { $0.map(adjust) } }

    /// The rewrites in every language: the English in `CursorMood+Lines.swift`,
    /// the Russian in `CursorMood+Russian.swift`.
    public static let rewrites = Translated(english: englishRewrites, [.russian: russianRewrites])

    /// Shipped lines that mention the cursor and read right in every mood as they
    /// are, so they need no rewrite: a fond or plain mention, never a grudge.
    public static let fitsEveryMood = Translated(english: englishFitsEveryMood, [.russian: russianFitsEveryMood])
}
