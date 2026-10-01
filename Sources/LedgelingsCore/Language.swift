import Foundation
import Synchronization

/// The language the app speaks: its menus and settings, the creatures' built-in
/// lines, and the prompts that ask a model for new ones.
///
/// Two ways text follows it:
/// - Short text (a label, a status, a sentence of a prompt) is written in English
///   at the call site and passed through `tr`, which looks it up in the language's
///   table (`Strings`) and falls back to the English when there is no entry.
/// - Long text written per language (the built-in script, a character's letters,
///   a whole prompt) is a `Translated` value: the English, and the others beside it.
///
/// Adding a language: a case here with its `code`, `title` and `pluralForms`, its
/// table in `Strings.tables`, and its long texts beside the English ones. The
/// localisation tests then say what is still missing.
public enum Language: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case russian = "ru"

    /// The ISO 639-1 code, which is also what speech voices are tagged with (`ru-RU`).
    public var code: String { rawValue }

    /// The language's name in itself, as the menu shows it.
    public var title: String {
        switch self {
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// The language's name in English, for a prompt that has to name it.
    public var englishName: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        }
    }

    /// The language the system prefers, when the app has it; English otherwise.
    public static func preferred(_ identifiers: [String] = Locale.preferredLanguages) -> Language {
        for id in identifiers {
            let code = String(id.prefix { $0 != "-" && $0 != "_" }).lowercased()
            if let language = Language(rawValue: code) { return language }
        }
        return .english
    }

    // MARK: The current language

    private static let chosen = Mutex<Language>(.english)

    /// A language for the code running inside `$override.withValue`, whatever the
    /// app has chosen: how tests ask for Russian without touching the app's choice.
    @TaskLocal public static var override: Language?

    /// What everything speaks right now.
    public static var current: Language { override ?? chosen.withLock { $0 } }

    /// Set by the app from its settings, at launch and on every change.
    public static func choose(_ language: Language) { chosen.withLock { $0 = language } }

    // MARK: Plurals

    /// How many forms a counted noun has, and which one `n` takes.
    /// English: one, other. Russian: one (1, 21), few (2–4, 22–24), many (5–20, 0).
    public var pluralForms: Int {
        switch self {
        case .english: 2
        case .russian: 3
        }
    }

    public func pluralIndex(_ n: Int) -> Int {
        let n = abs(n)
        switch self {
        case .english:
            return n == 1 ? 0 : 1
        case .russian:
            if n % 10 == 1 && n % 100 != 11 { return 0 }
            if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return 1 }
            return 2
        }
    }
}

/// `english` in the current language: its entry in that language's table, or the
/// English itself. With `arguments` the result is a format (`%@`, `%d`, `%1$@`).
public func tr(_ english: String, _ arguments: any CVarArg...) -> String {
    let text = Strings.lookup(english, in: .current)
    return arguments.isEmpty ? text : String(format: text, arguments: arguments)
}

/// `n` and its noun, in the current language: `trCount(3, "minute", "minutes")`
/// is "3 minutes", or "3 минуты". The table entry for `"minute|minutes"` holds the
/// language's forms joined by `|`; `%d` in a form places the number, otherwise
/// it goes in front.
public func trCount(_ n: Int, _ one: String, _ other: String) -> String {
    let language = Language.current
    let forms = Strings.lookup(one + "|" + other, in: language).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let index = forms.count == language.pluralForms ? language.pluralIndex(n) : Language.english.pluralIndex(n)
    let form = forms.indices.contains(index) ? forms[index] : (n == 1 ? one : other)
    return form.contains("%d") ? String(format: form, n) : "\(n) \(form)"
}

/// Text written out in full in each language, the English always there.
public struct Translated<Value: Sendable>: Sendable {
    public let english: Value
    public let others: [Language: Value]

    public init(english: Value, _ others: [Language: Value] = [:]) {
        self.english = english
        self.others = others
    }

    /// The text in `language` (the current one by default), English when it has none.
    public func callAsFunction(_ language: Language = .current) -> Value {
        language == .english ? english : others[language] ?? english
    }

    /// Every language's version, English first.
    public var all: [Value] { [english] + Language.allCases.compactMap { $0 == .english ? nil : others[$0] } }
}

/// The tables of short text, one per language other than English, keyed by the English.
public enum Strings {
    public static let tables: [Language: [String: String]] = [
        .russian: russian,
    ]

    public static func lookup(_ english: String, in language: Language) -> String {
        guard language != .english, let found = tables[language]?[english], !found.isEmpty else { return english }
        return found
    }

    /// Several tables (one per area of the app) as one; a key in two of them is a mistake the tests catch.
    static func merged(_ parts: [[String: String]]) -> [String: String] {
        parts.reduce(into: [:]) { all, part in all.merge(part) { first, _ in first } }
    }
}
