import Testing
@testable import LedgelingsCore

@Suite struct VoicesTests {
    let pool = ["a", "b", "c", "d", "e"]

    @Test func everyCharacterGetsItsOwnVoiceWhileThePoolLasts() {
        let names = ["Blocky", "Pip", "Mortimer", "Ribbit"]
        let voices = Voices.assign(names, pool: pool)
        #expect(Set(voices.keys) == Set(names))
        #expect(Set(voices.values).count == names.count)
    }

    @Test func theSameNameKeepsItsVoiceWhateverOrderTheCastComesIn() {
        let one = Voices.assign(["Blocky", "Pip", "Mortimer"], pool: pool)
        let two = Voices.assign(["Mortimer", "Blocky", "Pip", "Pip"], pool: pool)
        #expect(one == two)
    }

    @Test func voicesAreSharedOnlyOnceThePoolRunsOut() {
        let voices = Voices.assign(["A", "B", "C"], pool: ["x", "y"])
        #expect(Set(voices.values) == ["x", "y"])
        #expect(Voices.assign(["A"], pool: []).isEmpty)
    }

    @Test func theHashIsTheSameEveryLaunch() {
        // FNV-1a of "a", a published test vector.
        #expect(Voices.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect((0.9...1.1).contains(Voices.pitchNudge(for: "Blocky")))
        #expect(Voices.pitchNudge(for: "Blocky") == Voices.pitchNudge(for: "Blocky"))
    }

    @Test func englishVoicesAreKeptWhenTheNamesSayWhichTheyAre() {
        #expect(Voices.englishFirst(["af_bella", "jf_alpha", "bm_george", "zf_xiaobei"]) == ["af_bella", "bm_george"])
        #expect(Voices.englishFirst(["flux-kit-en", "flux-x-de"]) == ["flux-kit-en"])
        #expect(Voices.englishFirst(["en_paul_happy", "fr_marie_sad", "gb_jane_sad"]) == ["en_paul_happy", "gb_jane_sad"])
        #expect(Voices.englishFirst(["English_Comedian", "Chinese_Man"]) == ["English_Comedian"])
        // Names that say nothing about language: keep them all.
        #expect(Voices.englishFirst(["Puck", "Kore"]) == ["Puck", "Kore"])
    }

    @Test func stageDirectionsEmojiAndMarkdownAreNotReadOut() {
        #expect(Voices.speakable("*sighs* Fine. 🌸 Take the **ceiling**.") == "Fine. Take the ceiling.")
        #expect(Voices.speakable("Hello — it's 5:00 & #1!") == "Hello — it's 5:00 & 1!")
        #expect(Voices.speakable("🙂👍") == "")
    }

    @Test func cartoonVoicesSqueakHigherEachAtItsOwnHeight() {
        let heights = ["Blocky", "Pip", "Mortimer", "Zed"].map(Voices.cartoonPitch(for:))
        #expect(heights.allSatisfy { (1.15...1.6).contains($0) })
        #expect(Set(heights).count == 4)
        #expect(Voices.cartoonPitch(for: "Pip") == Voices.cartoonPitch(for: "Pip"))
    }

    @Test func playfulVoicesArePickedFirstWhenThereAreEnough() {
        let minimax = ["English_expressive_narrator", "English_AnimeCharacter", "English_Trustworth_Man", "English_PlayfulGirl"]
        #expect(Voices.cartoonFirst(minimax) == ["English_AnimeCharacter", "English_PlayfulGirl"])
        #expect(Voices.cartoonFirst(["en_paul_neutral", "en_paul_excited", "en_paul_cheerful"]) == ["en_paul_excited", "en_paul_cheerful"])
        #expect(Voices.cartoonFirst(["Puck", "Kore"]) == ["Puck", "Kore"], "nothing says playful: keep them all")
        #expect(Voices.cartoonFirst(["am_santa", "am_adam"]) == ["am_santa", "am_adam"], "one is not enough to go round")
    }
}
