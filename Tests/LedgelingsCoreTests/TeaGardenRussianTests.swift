import Foundation
import Testing
@testable import LedgelingsCore

/// Tea, the garden and the flowers in Russian: the same shape as the English,
/// so a party, a planting or a gift goes the same way in either language.
@Suite struct TeaGardenRussianTests {
    static var placeholder: Regex<AnyRegexOutput> { try! Regex("\\{[A-Za-z]+\\}") }

    static func placeholders(_ text: String) -> [String] {
        text.matches(of: placeholder).map { String(text[$0.range]) }.sorted()
    }

    static func placeholderSet(_ text: String) -> Set<String> { Set(placeholders(text)) }

    @Test func everyCharacterTellsAsManyStoriesInRussian() {
        #expect(Set(Tea.russianStories.keys) == Set(Tea.englishStories.keys))
        for (name, english) in Tea.englishStories {
            let russian = Tea.russianStories[name] ?? []
            #expect(russian.count == english.count, "\(name)")
            #expect(Set(russian).count == russian.count, "\(name) tells a story twice")
            for (e, r) in zip(english, russian) { #expect(Self.placeholders(e) == Self.placeholders(r), "\(name): \(r)") }
        }
        #expect(Tea.russianAnyoneStories.count == Tea.englishAnyoneStories.count)
    }

    @Test func everyCharacterAnswersAsOftenInRussian() {
        #expect(Set(Tea.russianReplies.keys) == Set(Tea.englishReplies.keys))
        for (name, english) in Tea.englishReplies {
            let russian = Tea.russianReplies[name] ?? []
            #expect(russian.count == english.count, "\(name)")
            for (e, r) in zip(english, russian) { #expect(Self.placeholders(e) == Self.placeholders(r), "\(name): \(r)") }
        }
        #expect(Tea.russianAnyoneReplies.count == Tea.englishAnyoneReplies.count)
        for (e, r) in zip(Tea.englishAnyoneReplies, Tea.russianAnyoneReplies) { #expect(Self.placeholders(e) == Self.placeholders(r)) }
    }

    @Test func theRussianIsWhatTheyTellInRussian() {
        Language.$override.withValue(.russian) {
            var rng = SystemRandomNumberGenerator()
            #expect(Tea.russianStories["Blocky"]!.contains(Tea.story(by: "Blocky", avoiding: [], using: &rng)))
            #expect(Tea.russianAnyoneStories.contains(Tea.story(by: "Someone New", avoiding: [], using: &rng)))
            let reply = Tea.reply(by: "Pip", to: "Zed", using: &rng)
            #expect(Tea.russianReplies["Pip"]!.contains { Banter.render($0, ["other": "Zed"]) == reply })
            #expect(Tea.transcript([]).contains("чай"))
        }
        Language.$override.withValue(.english) {
            #expect(Tea.stories["Blocky"] == Tea.englishStories["Blocky"])
            #expect(Tea.transcript([]).contains("just been poured"))
        }
    }

    @Test func theRussianPromptsCarryTheSamePlaceholders() {
        let pairs = [(Tea.englishSystemPrompt, Tea.russianSystemPrompt), (Tea.englishStoryPrompt, Tea.russianStoryPrompt),
                     (Tea.englishReplyPrompt, Tea.russianReplyPrompt)]
        for (english, russian) in pairs {
            #expect(Self.placeholderSet(english) == Self.placeholderSet(russian), "\(russian)")
            for name in Self.placeholderSet(russian) {
                #expect(Tea.placeholders.contains(String(name.dropFirst().dropLast())), "\(name)")
            }
        }
        #expect(Tea.russianSystemPrompt.contains("по-русски"))
        Language.$override.withValue(.russian) {
            #expect(Tea.systemPrompt == Tea.russianSystemPrompt)
            #expect(Tea.storyPrompt == Tea.russianStoryPrompt && Tea.replyPrompt == Tea.russianReplyPrompt)
        }
        Language.$override.withValue(.english) { #expect(Tea.systemPrompt == Tea.englishSystemPrompt) }
    }

    @Test func everyFlowerHasARussianName() {
        for flower in Gifts.flowers {
            let name = Gifts.russianNames[flower]
            #expect(name != nil && name != flower && !(name ?? "").isEmpty, "\(flower)")
        }
        #expect(Set(Gifts.russianNames.keys) == Set(Gifts.flowers))
        #expect(Set(Gifts.russianNames.values).count == Gifts.flowers.count)
        Language.$override.withValue(.russian) { #expect(Gifts.name(of: "poppy") == "мак") }
        Language.$override.withValue(.english) {
            for flower in Gifts.flowers { #expect(Gifts.name(of: flower) == flower) }
        }
    }

    @Test func thePlantingSentenceIsRussianButTheRulesStillReadEnglish() {
        let blocky = Banter.defaultCharacters.first { $0.name == "Blocky" }!
        let temper = Garden.temper(persona: blocky.persona, kind: Banter.defaultKind)
        // The persona stays English data: the rules read it the same in either language.
        let russian = Language.$override.withValue(.russian) { Garden.temper(persona: blocky.persona, kind: Banter.defaultKind) }
        #expect(russian == temper && temper.likes.first == .floor)
        Language.$override.withValue(.russian) {
            for place in Garden.Place.allCases {
                #expect(place.phrase.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil, "\(place)")
            }
            let described = Garden.describe(temper)
            #expect(described.contains("на нижнем краю") && described.contains(" или "), "\(described)")
            #expect(Garden.describe(Garden.Temper(keep: 0, likes: [])) == "Сразу, там, где стоит.")
        }
    }
}
