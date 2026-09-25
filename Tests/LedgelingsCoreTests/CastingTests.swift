import Testing
@testable import LedgelingsCore

@Suite struct CastingTests {
    let blocky = "a small square creature"

    @Test func theShippedDescriptionsSayHowTheyShouldSound() {
        let mortimer = Casting.traits(persona: "Old and philosophical. Speaks slowly, quotes wisdom he made up, sighs a lot.", kind: blocky)
        #expect(mortimer.wants[.old, default: 0] >= 2 && mortimer.wants[.male, default: 0] > 0)
        #expect(mortimer.pitch < 1 && mortimer.speed < 1)

        let dot = Casting.traits(persona: "Tiny, fast and sarcastic. Brags about speed. Calls everyone else a boulder.", kind: blocky)
        #expect(dot.pitch > 1 && dot.speed > 1)

        let pip = Casting.traits(persona: "Cheerful and easily impressed. Loves the ceiling. Laughs at everything, including insults.", kind: blocky)
        #expect(pip.wants[.bright, default: 0] >= 2 && pip.pitch > 1)

        let unit7 = Casting.traits(persona: "Literal and precise. Reports its own status in numbers.", kind: "a boxy little robot with an antenna")
        #expect(unit7.wants[.robot, default: 0] >= 3)

        let wisp = Casting.traits(persona: "Wistful and poetic. Remembers monitors that are gone.", kind: "a little round ghost with a wavy hem, hovering")
        #expect(wisp.wants[.whisper, default: 0] >= 2)
    }

    @Test func shortWordsMustMatchWholeSoTheIsNotHe() {
        let t = Casting.traits(persona: "Thinks the edge is theirs. Other creatures bother them.", kind: "")
        #expect(t.wants[.male] == nil && t.wants[.female] == nil)
    }

    @Test func pitchAndSpeedStayInTheirRange() {
        let t = Casting.traits(persona: "tiny tiny little small wee fast quick hyper cheerful giggly anxious nervous", kind: "")
        #expect(Casting.pitchRange.contains(t.pitch) && Casting.speedRange.contains(t.speed))
        #expect(Casting.traits(persona: "", kind: "") == .neutral)
    }

    @Test func voicesAreTaggedFromWhatTheirNamesSay() {
        #expect(Casting.tags(ofVoice: "com.apple.eloquence.en-US.Grandpa", name: "Grandpa") == [.old, .male, .deep])
        #expect(Casting.tags(ofVoice: "af_nicole").isSuperset(of: [.female, .whisper]))
        #expect(Casting.tags(ofVoice: "bm_daniel") == [.male])
        #expect(Casting.tags(ofVoice: "English_ManWithDeepVoice").isSuperset(of: [.male, .deep]))
        #expect(Casting.tags(ofVoice: "English_Whispering_girl").isSuperset(of: [.female, .whisper, .young]))
        #expect(Casting.tags(ofVoice: "English_Wiselady").isSuperset(of: [.female, .old]))
        #expect(Casting.tags(ofVoice: "leo") == [.male])
    }

    @Test func eachCharacterGetsTheVoiceThatFitsIt() {
        let pool = ["Grandpa", "Zarvox", "Whisper", "Junior", "Kathy", "Ralph"]
        let tags = Dictionary(uniqueKeysWithValues: pool.map { ($0, Casting.tags(ofVoice: $0)) })
        let traits = [
            "Mortimer": Casting.traits(persona: "Old and philosophical. Speaks slowly, quotes wisdom he made up.", kind: blocky),
            "Unit 7": Casting.traits(persona: "Literal and precise.", kind: "a boxy little robot"),
            "Wisp": Casting.traits(persona: "Wistful and poetic.", kind: "a little round ghost"),
            "Pip": Casting.traits(persona: "Cheerful. Laughs at everything.", kind: blocky),
            "Croak": Casting.traits(persona: "Grumpy. Finds the screen edge too dry.", kind: "a fat green frog"),
        ]
        let cast = Casting.assign(Array(traits.keys), traits: traits, pool: pool, tags: tags)
        #expect(cast["Mortimer"] == "Grandpa")
        #expect(cast["Unit 7"] == "Zarvox")
        #expect(cast["Wisp"] == "Whisper")
        #expect(cast["Pip"] == "Junior")
        #expect(cast["Croak"] == "Ralph")
        #expect(Set(cast.values).count == 5, "nobody shares while voices last")
    }

    @Test func nobodyIsGivenARobotOrAWhisperUnasked() {
        let pool = ["Zarvox", "Whisper", "Kathy"]
        let tags = Dictionary(uniqueKeysWithValues: pool.map { ($0, Casting.tags(ofVoice: $0)) })
        let plain = ["Ruth": Casting.traits(persona: "Bossy, organised, keeps count of everything.", kind: blocky)]
        #expect(Casting.assign(["Ruth"], traits: plain, pool: pool, tags: tags)["Ruth"] == "Kathy")
    }

    @Test func handPickedVoicesStayAndAreNotHandedOut() {
        let pool = ["Grandpa", "Kathy"]
        let tags = Dictionary(uniqueKeysWithValues: pool.map { ($0, Casting.tags(ofVoice: $0)) })
        let traits = ["Mortimer": Casting.traits(persona: "Old and wise.", kind: ""), "Pip": .neutral]
        let cast = Casting.assign(["Mortimer", "Pip"], traits: traits, pool: pool, tags: tags, fixed: ["Pip": "Grandpa"])
        #expect(cast["Pip"] == "Grandpa" && cast["Mortimer"] == "Kathy")
    }

    @Test func theSameCastEveryTime() {
        let pool = ["a", "b", "c", "d"]
        let traits = ["X": Casting.Traits.neutral, "Y": .neutral, "Z": .neutral]
        let one = Casting.assign(["X", "Y", "Z"], traits: traits, pool: pool, tags: [:])
        let two = Casting.assign(["Z", "X", "Y"], traits: traits, pool: pool, tags: [:])
        #expect(one == two)
    }

    @Test func theModelIsToldWhoTheCharacterIsAndWhatToChooseFrom() {
        let prompt = Casting.modelPrompt(name: "Mortimer", persona: "Old and philosophical.", kind: "a small square creature",
                                         voices: [("Grandpa", "old, male"), ("Kathy", "")], cartoon: true)
        #expect(prompt.contains("Mortimer, a small square creature"))
        #expect(prompt.contains("- Grandpa: old, male\n- Kathy\n"), "a voice with nothing known is listed bare")
        #expect(prompt.contains("cartoon"))
    }

    @Test func theModelsPickIsReadEvenWrappedInChatter() {
        let pick = Casting.parsePick("Sure! ```json\n{\"voice\": \"Grandpa\", \"pitch\": 0.9, \"speed\": \"0.8\", \"why\": \"old and slow\"}\n```")
        #expect(pick == Casting.Pick(voice: "Grandpa", pitch: 0.9, speed: 0.8, why: "old and slow"))
        #expect(Casting.parsePick(#"{"voice": "x", "pitch": 9}"#)?.pitch == 2, "clamped")
        #expect(Casting.parsePick("no json here") == nil)
        #expect(Casting.parsePick(#"<think>maybe {"voice": "Kathy"}? no.</think>{"voice": "Grandpa"}"#)?.voice == "Grandpa",
                "the reasoning before </think> is not the answer")
        #expect(Casting.parsePick(#"{"pitch": 1}"#) == nil, "no voice, no pick")
    }

    @Test func anAloofCatOrAPoetIsNotGivenTheWhisper() {
        let pool = ["Whisper", "Kathy", "Reed"]
        let tags = Dictionary(uniqueKeysWithValues: pool.map { ($0, Casting.tags(ofVoice: $0)) })
        let traits = [
            "Whiskers": Casting.traits(persona: "Aloof. Pretends not to care, then asks what you are doing.", kind: "a small square cat"),
            "Poet": Casting.traits(persona: "Wistful and poetic.", kind: "a small square creature"),
        ]
        let cast = Casting.assign(["Whiskers", "Poet"], traits: traits, pool: pool, tags: tags)
        #expect(cast["Whiskers"] != "Whisper" && cast["Poet"] != "Whisper")
    }
}
