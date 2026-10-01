import Foundation
import Testing
@testable import LedgelingsCore

/// The settings window's Creatures, Talk, Voice, Costs and Chats tabs in Russian.
@Suite struct SettingsARussianTests {
    static let files = ["SettingsView.swift", "TalkSettingsView.swift", "VoiceSettingsView.swift", "CostsSettingsView.swift", "ChatHistoryView.swift"]

    static func keys() -> [(file: String, key: String)] {
        LanguageTests.keys().filter { files.contains($0.file) }
    }

    @Test func everyKeyOfTheseTabsIsTranslated() {
        let keys = Self.keys()
        #expect(keys.count > 150)
        let missing = Set(keys.filter { Strings.russian[$0.key] == nil }.map { "\($0.file): \($0.key)" }).sorted()
        #expect(missing.isEmpty, "missing:\n\(missing.joined(separator: "\n"))")
    }

    /// A footer that names a control in quotes names it as the Russian control is labelled.
    @Test func footersNameControlsAsTheyAreLabelled() {
        let quoted = try! Regex("\"([^\"]+)\"")
        for (english, russian) in Strings.ruSettingsA {
            for match in english.matches(of: quoted) {
                let name = String(english[match.range].dropFirst().dropLast())
                guard let label = Strings.russian[name] else { continue }
                #expect(russian.contains("«\(label)»"), "\(english.prefix(40))… should name «\(label)»")
            }
        }
    }

    @Test func countsTakeTheirRussianForms() {
        Language.$override.withValue(.russian) {
            #expect(trCount(1, "line", "lines") == "1 реплика")
            #expect(trCount(3, "token", "tokens") == "3 токена")
            #expect(trCount(25, "call", "calls") == "25 вызовов")
            #expect(trCount(72, "voice", "voices") == "72 голоса")
        }
    }

    @Test func formatsFillInRussian() {
        Language.$override.withValue(.russian) {
            #expect(tr("%d conversations, %d with a flower, %d at night", 12, 3, 4) == "разговоров: 12, с цветком: 3, ночью: 4")
            #expect(tr("ready: %@ is installed", "gemma") == "готово: модель gemma установлена")
            #expect(tr("Colour %d", 2) == "Цвет 2")
        }
    }
}
