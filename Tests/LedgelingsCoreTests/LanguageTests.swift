import Foundation
import Testing
@testable import LedgelingsCore

/// The app in more than one language: the lookup, the plurals, and a sweep of
/// the sources that every `tr("…")` has its translation.
@Suite struct LanguageTests {
    @Test func englishIsTheTextItself() {
        Language.$override.withValue(.english) {
            #expect(tr("Settings…") == "Settings…")
            #expect(tr("never heard of this one %d", 3) == "never heard of this one 3")
        }
    }

    @Test func russianComesFromItsTable() {
        Language.$override.withValue(.russian) {
            #expect(tr("Settings…") == "Настройки…")
            #expect(tr("never heard of this one") == "never heard of this one")
        }
    }

    @Test func russianPluralsHaveThreeForms() {
        let ru = Language.russian
        #expect([1, 21, 101].map(ru.pluralIndex) == [0, 0, 0])
        #expect([2, 3, 4, 22, 34].map(ru.pluralIndex) == [1, 1, 1, 1, 1])
        #expect([0, 5, 11, 12, 14, 20, 25, 111].map(ru.pluralIndex) == [2, 2, 2, 2, 2, 2, 2, 2])
        Language.$override.withValue(.russian) {
            #expect(trCount(1, "minute", "minutes") == "1 минута")
            #expect(trCount(3, "minute", "minutes") == "3 минуты")
            #expect(trCount(11, "minute", "minutes") == "11 минут")
        }
        Language.$override.withValue(.english) {
            #expect(trCount(1, "minute", "minutes") == "1 minute")
            #expect(trCount(2, "minute", "minutes") == "2 minutes")
        }
    }

    @Test func translatedFallsBackToEnglish() {
        let t = Translated(english: "hi", [.russian: "привет"])
        #expect(t(.english) == "hi")
        #expect(t(.russian) == "привет")
        #expect(Translated(english: "hi")(.russian) == "hi")
        #expect(Language.$override.withValue(.russian) { t() } == "привет")
    }

    @Test func thePreferredLanguageFollowsTheSystem() {
        #expect(Language.preferred(["ru-RU", "en-US"]) == .russian)
        #expect(Language.preferred(["he-IL", "ru"]) == .russian)
        #expect(Language.preferred(["he-IL", "fr-FR"]) == .english)
        #expect(Language.preferred([]) == .english)
    }

    // MARK: The sweep

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func sources() -> [(name: String, text: String)] {
        let dirs = ["Sources/Ledgelings", "Sources/LedgelingsCore"].map { root.appendingPathComponent($0) }
        return dirs.flatMap { dir -> [(String, String)] in
            let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            return files.filter { $0.pathExtension == "swift" && !$0.path.contains("/Russian/") }
                .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) } }
        }
    }

    /// A Swift string literal's body, `"` to `"`, with its escapes undone.
    static let literal = #""((?:[^"\\\n]|\\.)*)""#

    static func unescape(_ s: String) -> String {
        var out = "", escaped = false
        for c in s {
            if escaped {
                switch c {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(c)
                }
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// Every key the sources look up: `tr("…")` and `trCount(n, "…", "…")`.
    static func keys() -> [(file: String, key: String)] {
        let single = try! Regex("\\btr\\(" + literal)
        let counted = try! Regex("\\btrCount\\([^,]+,\\s*" + literal + "\\s*,\\s*" + literal + "\\s*\\)")
        return sources().flatMap { file in
            file.text.matches(of: single).compactMap { m in (m.output[1].substring).map { (file.name, unescape(String($0))) } }
                + file.text.matches(of: counted).compactMap { m -> (String, String)? in
                    guard let one = m.output[1].substring, let other = m.output[2].substring else { return nil }
                    return (file.name, unescape(String(one)) + "|" + unescape(String(other)))
                }
        }
    }

    @Test func theSweepFindsKeys() {
        #expect(Self.keys().count > 100)
    }

    @Test func noKeyIsInterpolated() {
        let bad = Self.keys().filter { $0.key.contains("\\(") || $0.key.contains("(\\") }
        #expect(bad.isEmpty, "a key with \\( never matches its table entry: use %@ and arguments: \(bad)")
    }

    /// `%@` in the English is `%@` (or `%1$@`…) in the translation, as many of each kind.
    @Test func formatsMatch() {
        let spec = try! Regex("%(?:\\d+\\$)?[@dif]|%\\.\\d+f|%(?:\\d+\\$)?ld")
        func kinds(_ s: String) -> [String] {
            s.matches(of: spec).map { String(s[$0.range]).replacing(/\d+\$/, with: "") }.sorted()
        }
        for (language, table) in Strings.tables {
            for (english, translated) in table where !english.contains("|") {
                #expect(kinds(english) == kinds(translated), "\(language.englishName): \(english) → \(translated)")
            }
        }
    }

    @Test func pluralEntriesHaveEveryForm() {
        for (language, table) in Strings.tables {
            for (english, translated) in table where english.contains("|") {
                #expect(translated.split(separator: "|", omittingEmptySubsequences: false).count == language.pluralForms,
                        "\(language.englishName): \(english) → \(translated)")
            }
        }
    }

    @Test func noKeyIsInTwoParts() {
        var seen: [String: String] = [:]
        for (part, table) in Strings.russianParts.sorted(by: { $0.key < $1.key }) {
            for key in table.keys {
                #expect(seen[key] == nil, "\"\(key)\" is in both \(seen[key] ?? "") and \(part)")
                seen[key] = part
            }
        }
    }

    /// SwiftUI takes a bare literal as a key into a bundle the app does not have:
    /// such text would stay English. Every title goes through `tr`.
    @Test func noBareLiteralsInViews() {
        let calls = ["Text", "Toggle", "Button", "Section", "Picker", "Label", "LabeledContent", "TextField",
                     "SecureField", "Stepper", "Link", "Menu", "SliderRow", "ColorPicker", "GroupBox", "DisclosureGroup", "help", "navigationTitle"]
        let pattern = try! Regex("(?:^|[^A-Za-z0-9_])(?:\\.)?(?:" + calls.joined(separator: "|") + ")\\(\\s*\"([^\"\\\\]|\\\\.)*[A-Za-z]")
        var found: [String] = []
        for file in Self.sources() where file.text.contains("import SwiftUI") {
            for (n, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(pattern) && !line.contains("verbatim:") {
                found.append("\(file.name):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(found.isEmpty, "untranslated titles:\n\(found.joined(separator: "\n"))")
    }
}
