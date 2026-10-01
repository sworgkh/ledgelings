import Foundation
import Testing
@testable import LedgelingsCore

/// The paper-plane prompts in Russian: the same placeholders, Banter's only, and the answer asked in Russian.
@Suite struct LettersRussianPromptsTests {
    @Test func thePromptsFollowTheLanguage() {
        Language.$override.withValue(.russian) {
            #expect(Letters.notePrompt == Letters.russianNotePrompt)
            #expect(Letters.replyPrompt == Letters.russianReplyPrompt)
            #expect(Letters.musingPrompt == Letters.russianMusingPrompt)
        }
        Language.$override.withValue(.english) {
            #expect(Letters.replyPrompt == Letters.englishReplyPrompt)
        }
    }

    @Test func russianPromptsKeepTheirPlaceholdersAndAskForRussian() {
        let pairs = [(Letters.englishNotePrompt, Letters.russianNotePrompt),
                     (Letters.englishReplyPrompt, Letters.russianReplyPrompt),
                     (Letters.englishMusingPrompt, Letters.russianMusingPrompt)]
        for (english, russian) in pairs {
            #expect(LettersRussianTests.placeholders(russian) == LettersRussianTests.placeholders(english), "\(russian)")
            #expect(russian.contains("по-русски"))
            var rest = russian
            for key in Banter.placeholders { rest = rest.replacingOccurrences(of: "{\(key)}", with: "") }
            #expect(!rest.contains("{"), "unknown placeholder in \(russian)")
        }
    }
}
