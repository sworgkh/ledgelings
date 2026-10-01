import Testing
@testable import LedgelingsCore

/// Voices that speak the app's language: Russian lines go to Russian voices
/// when a model's voice names say which those are.
@Suite struct VoicesLanguageTests {
    @Test func englishIsEnglishFirstAsBefore() {
        let lists = [["af_bella", "jf_alpha", "bm_george"], ["flux-kit-en", "flux-x-de"], ["Puck", "Kore"],
                     ["tara", "leah", "jess", "leo", "dan", "mia", "zac", "zoe", "pierre"]]
        for voices in lists { #expect(Voices.inLanguage(voices, .english) == Voices.englishFirst(voices)) }
    }

    @Test func russianVoicesAreKeptWhenTheNamesSayWhichTheyAre() {
        let mixed = ["af_bella", "ru_dmitri", "ru-RU-SvetlanaNeural", "Russian_Girl", "en_paul_happy", "voice-ru", "pierre"]
        #expect(Voices.inLanguage(mixed, .russian) == ["ru_dmitri", "ru-RU-SvetlanaNeural", "Russian_Girl", "voice-ru"])
        // No Russian marks: every voice is kept, as unmarked voices speak every language.
        #expect(Voices.inLanguage(["alloy", "echo", "nova"], .russian) == ["alloy", "echo", "nova"])
        #expect(Voices.inLanguage(["af_bella", "bm_george"], .russian) == ["af_bella", "bm_george"])
        #expect(Voices.inLanguage([], .russian).isEmpty)
    }

    @Test func languageFirstFollowsTheCurrentLanguage() {
        let voices = ["en_paul", "ru_olga"]
        #expect(Language.$override.withValue(.russian) { Voices.languageFirst(voices) } == ["ru_olga"])
        #expect(Language.$override.withValue(.english) { Voices.languageFirst(voices) } == ["en_paul"])
    }

    @Test func aVoiceOfAnotherLanguageDoesNotSpeakIt() {
        let voices = ["en_paul", "ru_olga", "ru_ivan"]
        #expect(!Voices.speaks("en_paul", .russian, among: voices))
        #expect(Voices.speaks("ru_olga", .russian, among: voices))
        #expect(Voices.speaks("ru_olga(2)+ru_ivan(1)", .russian, among: voices), "a blend of Russian voices")
        #expect(!Voices.speaks("ru_olga+en_paul", .russian, among: voices))
        // Nothing marked, or nothing known: any voice will do.
        #expect(Voices.speaks("alloy", .russian, among: ["alloy", "echo"]))
        #expect(Voices.speaks("anything", .russian, among: []))
        #expect(Voices.speaks("en_paul", .english, among: voices))
    }

    @Test func cyrillicIsSaidAsWritten() {
        #expect(Voices.speakable("*вздыхает* Ну ладно. 🌸 Бери **потолок**.") == "Ну ладно. Бери потолок.")
        #expect(Voices.speakable("Ёжик, привет — это 5:00!") == "Ёжик, привет — это 5:00!")
    }

    @Test func everyFeatureHasARussianTitleOnTheCostsTab() {
        for purpose in Spend.Purpose.allCases {
            let english = Language.$override.withValue(.english) { purpose.title }
            let russian = Language.$override.withValue(.russian) { purpose.title }
            #expect(russian != english && !russian.isEmpty, "\(purpose)")
        }
        #expect(Language.$override.withValue(.russian) { Spend.Purpose.unlabelled } != "Earlier, unlabelled")
    }
}
