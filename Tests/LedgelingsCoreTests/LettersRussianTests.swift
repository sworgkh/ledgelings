import Foundation
import Testing
@testable import LedgelingsCore

/// Paper-plane letters in Russian: everyone who writes in English writes in
/// Russian too, as many lines, with the same names filled in.
@Suite struct LettersRussianTests {
    static func placeholders(_ text: String) -> Set<String> {
        Set(text.matches(of: /\{[A-Za-z]+\}/).map { String(text[$0.range]) })
    }

    static func expectSameShape(_ english: Letters.Voice, _ russian: Letters.Voice, _ name: String) {
        #expect(russian.topics.count == english.topics.count, "\(name): topics")
        for (kind, en, ru) in [("notes", english.notes, russian.notes), ("musings", english.musings, russian.musings),
                               ("replies", english.replies, russian.replies)] {
            #expect(ru.count == en.count, "\(name): \(kind)")
            for (e, r) in zip(en, ru) {
                #expect(placeholders(r) == placeholders(e), "\(name) \(kind): \(r)")
                #expect(r != e, "\(name) \(kind) is still English: \(r)")
                #expect(r.split(separator: " ").count <= 22, "\(name) is too wordy: \(r)")
            }
        }
    }

    @Test func everyCharacterWithEnglishLettersHasRussianOnes() {
        #expect(Set(Letters.russianVoices.keys) == Set(Letters.englishVoices.keys))
        for (name, english) in Letters.englishVoices {
            guard let russian = Letters.russianVoices[name] else { continue }
            Self.expectSameShape(english, russian, name)
        }
        Self.expectSameShape(Letters.englishAnyone, Letters.russianAnyone, "anyone")
    }

    @Test func theLettersFollowTheLanguage() {
        Language.$override.withValue(.russian) {
            #expect(Letters.voices == Letters.russianVoices)
            #expect(Letters.anyone == Letters.russianAnyone)
            #expect(Letters.voice(of: "Blocky") == Letters.russianVoices["Blocky"])
            #expect(Letters.reading("Привет.", from: "Dot") == "*читает* «Привет.» — Dot")
        }
        Language.$override.withValue(.english) {
            #expect(Letters.voices == Letters.englishVoices)
        }
    }
}
