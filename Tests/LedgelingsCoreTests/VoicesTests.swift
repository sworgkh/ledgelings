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

    @Test func aVoiceChosenByHandIsKeptAndTheOthersAvoidIt() {
        let pool = ["a", "b", "c"]
        let auto = Voices.assign(["Blocky", "Pip"], pool: pool)
        let pipsOwn = auto["Blocky"]!                  // give Pip the voice Blocky had
        let voices = Voices.assign(["Blocky", "Pip"], pool: pool, fixed: ["Pip": pipsOwn, "Nobody": "c"])
        #expect(voices["Pip"] == pipsOwn)
        #expect(voices["Blocky"] != pipsOwn)
        #expect(voices["Nobody"] == nil, "a setting for someone not on screen changes nothing")
        // Everything taken by hand: the rest share from the whole pool.
        #expect(Voices.assign(["A", "B"], pool: ["x"], fixed: ["A": "x"])["B"] == "x")
    }

    @Test func aCharacterWithNothingSetIsAutomatic() {
        #expect(CharacterVoice().isAutomatic)
        #expect(!CharacterVoice(pitch: 1.3).isAutomatic)
        #expect(!CharacterVoice(followPitch: false).isAutomatic, "even off by hand is a choice")
    }

    @Test func withSpeedFollowingPitchAVoiceIsNeverAskedToDrawl() {
        // Exact pace: a 1.6× lift means asking for 0.625×, slow enough to smear.
        #expect(abs(Voices.askedSpeed(speed: 1, pitch: 1.6, followPitch: false) - 0.625) < 1e-9)
        // Following: half the slowdown, and the line comes out a little quicker.
        let asked = Voices.askedSpeed(speed: 1, pitch: 1.44, followPitch: true)
        #expect(abs(asked - 1 / 1.2) < 1e-9)
        #expect(abs(asked * 1.44 - 1.2) < 1e-9, "played 1.44× faster: 1.2× the pace")
        #expect(Voices.askedSpeed(speed: 1.3, pitch: 1, followPitch: true) == 1.3, "no lift, nothing changes")
    }

    @Test func aBlendIsUsableWhenEveryVoiceInItIs() {
        #expect(Voices.blendParts("af_bella(2)+am_puck(1)") == ["af_bella", "am_puck"])
        #expect(Voices.blendParts(" am_santa + bf_emma ") == ["am_santa", "bf_emma"])
        #expect(Voices.blendParts("af_bella") == ["af_bella"])
        let voices = ["af_bella", "am_puck", "bf_emma"]
        #expect(Voices.isUsable("af_bella(2)+am_puck(1)", among: voices))
        #expect(!Voices.isUsable("af_bella+zz_nobody", among: voices), "one unknown voice spoils the blend")
        #expect(Voices.isUsable("anything", among: []), "no list to check against: let the server decide")
        #expect(!Voices.isUsable(" + ", among: voices))
    }
}
