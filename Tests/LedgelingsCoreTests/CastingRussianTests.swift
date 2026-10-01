import Foundation
import Testing
@testable import LedgelingsCore

/// A persona written in Russian is cast as well as one in English, and every
/// shipped persona has a Russian version that reads the same way.
@Suite struct CastingRussianTests {
    @Test func russianWordsSayHowSomeoneSounds() {
        let old = Casting.traits(persona: "Старый философ. Говорит медленно, часто вздыхает.", kind: "маленькое квадратное существо")
        #expect((old.wants[.old] ?? 0) > 0 && old.speed < 1)
        let robot = Casting.traits(persona: "Буквальный и точный.", kind: "маленький угловатый робот с антенной")
        #expect((robot.wants[.robot] ?? 0) > 0)
        #expect((Casting.traits(persona: "Она весёлая и быстрая.", kind: "").wants[.female] ?? 0) > 0)
        #expect((Casting.traits(persona: "Он ворчит.", kind: "").wants[.male] ?? 0) > 0)
        #expect(Casting.traits(persona: "Обычный.", kind: "") == .neutral)
    }

    /// The Russian of a shipped persona and kind gives the same voice as its English, near enough:
    /// the same kinds of voice wanted, pitch and speed on the same side of neutral.
    @Test func russianPersonasCastLikeTheirEnglish() {
        for (english, russian) in Strings.ruPersonas {
            let en = Casting.traits(persona: english, kind: ""), ru = Casting.traits(persona: russian, kind: "")
            #expect(Set(en.wants.keys).isSubset(of: Set(ru.wants.keys).union([.male, .female, .deep, .young, .bright, .soft, .whisper])),
                    "\(english) → \(russian): \(en.wants) vs \(ru.wants)")
            #expect((en.wants[.robot] != nil) == (ru.wants[.robot] != nil), "\(russian)")
            #expect((en.wants[.old] != nil) == (ru.wants[.old] != nil), "\(russian)")
        }
    }
}

/// Prompts carry a shipped persona in the current language's words, a user's own as written.
@Suite struct SpokenPersonaTests {
    @Test func shippedPersonasAndKindsAreSpokenInRussian() {
        Language.$override.withValue(.russian) {
            for c in Banter.defaultCharacters { #expect(Banter.spoken(c.persona) != c.persona, "\(c.name)") }
            #expect(Banter.spoken(Banter.defaultKind) == "маленькое квадратное существо")
            #expect(Banter.spoken("My own words.") == "My own words.")
        }
        Language.$override.withValue(.english) {
            #expect(Banter.spoken(Banter.defaultCharacters[0].persona) == Banter.defaultCharacters[0].persona)
        }
    }

    /// Every shipped sheet's kind and cast has a Russian version.
    @Test func everyShippedSheetIsInTheTable() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Ledgelings/Resources/sprites")
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
            var texts = (meta["cast"] as? [[String: String]] ?? []).compactMap { $0["persona"] }
            if let kind = meta["kind"] as? String { texts.append(kind) }
            for text in texts { #expect(Strings.ruPersonas[text] != nil, "\(file.lastPathComponent): \(text)") }
        }
    }
}
