import Foundation
import Testing
@testable import LedgelingsCore

/// The settings window's pages, its sidebar groups and its search.
@Suite struct SettingsIndexTests {
    /// Every key `AppSettings` writes to the defaults.
    static func savedKeys() -> Set<String> {
        let source = try! String(contentsOf: LanguageTests.root.appendingPathComponent("Sources/Ledgelings/AppSettings.swift"), encoding: .utf8)
        let saved = try! Regex(#"save(?:JSON)?\([^\n]*?, "(\w+)"\)"#), set = try! Regex(#"defaults\.set\([^\n]*forKey: "(\w+)"\)"#)
        return Set((source.matches(of: saved) + source.matches(of: set)).compactMap { $0.output[1].substring.map(String.init) })
    }

    static var indexedKeys: Set<String> { Set(SettingsIndex.sections.flatMap(\.keys)) }

    @Test func scriptsNameEveryPageAndTheOldTabs() {
        for page in SettingsPage.allCases { #expect(SettingsPage.named(page.rawValue.lowercased()) == page) }
        #expect(SettingsPage.named("ballgames") == .ballGames)
        #expect(SettingsPage.named("productivity") == .reminders, "the old tools tab opens its first tool")
        #expect(SettingsPage.named("reminders") == .reminders)
        #expect(SettingsPage.named("clipboard") == .clipboard)
        #expect(SettingsPage.named("nonsense") == nil)
        #expect(SettingsPage.named("") == nil)
    }

    @Test func theFiveGroupsAreAsDrawn() {
        #expect(SettingsGroup.allCases.map { $0.pages } == [
            [.creatures, .actions, .sprites, .beds, .flowers, .calendar],
            [.chases, .play, .ballGames],
            [.talk, .voice, .bonds, .relationships],
            [.tools, .reminders, .clipboard, .screenshots, .dictation, .translate],
            [.costs, .chats],
        ])
    }

    @Test func everySavedSettingCanBeFound() {
        let saved = Self.savedKeys()
        #expect(saved.count > 150)
        let lost = saved.subtracting(Self.indexedKeys).subtracting(SettingsIndex.unshown.keys).sorted()
        #expect(lost.isEmpty, "saved but in no section of SettingsIndex, so search cannot find them: \(lost)")
    }

    @Test func theIndexNamesOnlyRealKeys() {
        let saved = Self.savedKeys()
        #expect(Self.indexedKeys.subtracting(saved).sorted().isEmpty)
        #expect(Set(SettingsIndex.unshown.keys).subtracting(saved).isEmpty)
        #expect(Set(SettingsIndex.unshown.keys).isDisjoint(with: Self.indexedKeys))
    }

    /// Each heading in the index is a heading on its page, and each heading drawn is in the index.
    @Test func theIndexMatchesTheHeadingsDrawn() {
        let header = try! Regex("SettingsHeader\\(" + LanguageTests.literal + "\\)")
        let drawn = Set(LanguageTests.sources().flatMap { $0.text.matches(of: header).compactMap { $0.output[1].substring.map { LanguageTests.unescape(String($0)) } } })
        let indexed = Set(SettingsIndex.sections.map(\.title))
        #expect(drawn.subtracting(indexed).sorted().isEmpty, "a section the search does not know")
        // Talk's first section and the Chats page have no heading of their own; they go by the page's name.
        #expect(indexed.subtracting(drawn).sorted() == ["Chats", "Talk"])
    }

    @Test func everyIndexedWordIsTranslated() {
        let words = SettingsIndex.sections.flatMap { [$0.title, $0.footer] + $0.labels }.filter { !$0.isEmpty }
        let missing = Set(words.filter { Strings.russian[$0] == nil }).sorted()
        #expect(missing.isEmpty, "not a table key, so a Russian search misses it: \(missing)")
    }

    @Test func aWordFindsItsSettingBestFirst() {
        Language.$override.withValue(.english) {
            let hits = SettingsIndex.search("pitch")
            #expect(hits.first == SettingsIndex.Hit(page: .voice, section: "Voice", text: "Pitch"))
            #expect(SettingsIndex.search("PAPER planes").contains { $0.page == .talk })
            #expect(SettingsIndex.search("kept images").contains { $0.page == .clipboard && $0.section == "History" }, "words in any order, anywhere in the section")
            #expect(SettingsIndex.search("   ").isEmpty)
            #expect(SettingsIndex.search("zzzqqq").isEmpty)
        }
    }

    @Test func aRussianSearchFindsTheRussianWords() {
        Language.$override.withValue(.russian) {
            let hits = SettingsIndex.search("громкость")
            #expect(hits.first?.page == .voice)
            #expect(hits.first?.text == Strings.russian["Volume"])
            // ё and е are the same letter to the search.
            #expect(SettingsIndex.search("ещё").count == SettingsIndex.search("еще").count)
            // The English still works in Russian.
            #expect(SettingsIndex.search("pitch").first?.page == .voice)
        }
    }
}
