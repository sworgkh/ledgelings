import Foundation
import Testing
@testable import LedgelingsCore

/// Read aloud's part with no sound: the parts and their languages, the presets,
/// what is never sent, the price before sending, the voices that speak a
/// language, the buttons, the file name, the Tools screen tile and the costs line.
@Suite struct ReadAloudTests {
    typealias R = ReadAloud

    // MARK: Parts

    @Test func aShortTextIsOnePartAndParagraphsEndWithARest() {
        let one = R.parts("Hello there. How are you?")
        #expect(one == [R.Part(text: "Hello there. How are you?", language: Translate.english, paragraphEnd: true)])
        let three = R.parts("First line.\n\nSecond line.\nThird line.")
        #expect(three.map(\.text) == ["First line.", "Second line.", "Third line."])
        #expect(three.allSatisfy { $0.paragraphEnd }, "a line with words on it is a paragraph")
        #expect(R.parts("   \n\n  ").isEmpty)
        #expect(R.parts("**Bold** and *sighs* 🎉 # heading").map(\.text) == ["Bold and heading"], "markdown and emoji are not read out")
    }

    @Test func aLongParagraphIsCutAfterASentenceAndTheFirstPartIsShort() {
        let sentence = "This sentence is about forty-five letters long. "
        let text = String(repeating: sentence, count: 60).trimmingCharacters(in: .whitespaces)
        let parts = R.parts(text)
        #expect(parts.count > 3)
        #expect(parts[0].text.count <= R.firstPartSize, "the first sound comes quickly")
        #expect(parts.dropFirst().allSatisfy { $0.text.count <= R.partSize })
        #expect(parts.allSatisfy { $0.text.hasSuffix(".") }, "cut after a sentence, never inside one")
        #expect(parts.dropLast().allSatisfy { !$0.paragraphEnd } && parts.last?.paragraphEnd == true, "the rest only at the paragraph's end")
        #expect(parts.map(\.text).joined(separator: " ") == text, "nothing lost, nothing doubled")
    }

    @Test func noSentenceEndMeansACommaThenASpace() {
        let words = String(repeating: "word ", count: 120).trimmingCharacters(in: .whitespaces)
        let parts = R.parts(words, first: 100, size: 200)
        #expect(parts.allSatisfy { !$0.text.hasPrefix(" ") && !$0.text.hasSuffix(" ") && !$0.text.hasSuffix("wor") })
        #expect(parts.map(\.text).joined(separator: " ") == words)
        let commas = R.parts(String(repeating: "one, two, three, four ", count: 20), first: 60, size: 120)
        #expect(commas.dropLast().allSatisfy { $0.text.hasSuffix(",") })
    }

    @Test func eachPartsLanguageIsToldByItsLetters() {
        let parts = R.parts("Good morning, everyone.\nДоброе утро всем.\nבוקר טוב לכולם.\n42 / 17\nAnd back to English.")
        #expect(parts.map { $0.language?.code } == ["en", "ru", "he", "he", "en"], "a part with no letters keeps the language before it")
        let forced = R.parts("Good morning.\nДоброе утро.", forced: Translate.russian)
        #expect(forced.allSatisfy { $0.language == Translate.russian }, "a preset's language reads everything as it")
    }

    // MARK: Never sent

    @Test func emptyProtectedAndTooLongAreRefused() {
        let book = Self.book(protecting: "hunter two password")
        #expect(R.refusal("", snippets: book) == .empty)
        #expect(R.refusal("  \n\t ", snippets: book) == .empty)
        #expect(R.refusal("🎉🎉", snippets: book) == .empty, "nothing sayable left")
        #expect(R.refusal("hunter two password", snippets: book) == .protected, "typed by hand")
        let copy = Clipboard.Clip(text: "hunter two password", copiedAt: Date())
        #expect(R.refusal(copy, snippets: book) == .protected, "a copy of its words")
        #expect(R.refusal(book.all[0].snippet, snippets: book) == .protected)
        #expect(R.refusal(book.all[1].snippet, snippets: book) == nil, "an ordinary snippet may be read")
        #expect(R.refusal(String(repeating: "a", count: R.hardCap + 1), snippets: book) == .tooLong)
        #expect(R.refusal("Read me, please.", snippets: book) == nil)
        #expect(R.refusal("42", snippets: book) == nil, "a number can be read")
    }

    static func book(protecting words: String) -> Clipboard.SnippetBook {
        var snippet = Clipboard.Snippet(title: "Wi-Fi", text: "", protected: true)
        snippet.seal(words)
        return Clipboard.SnippetBook(folders: [Clipboard.Folder(title: "Secrets", snippets: [snippet, Clipboard.Snippet(title: "Hi", text: "Hello there")])])
    }

    // MARK: Presets

    @Test func theShippedPresetsAreTheOnesAskedFor() {
        let p = R.defaultPresets
        #expect(p.map(\.name) == ["Narrator", "Quick skim", "Bedtime", "Robot", "Russian"])
        #expect(p[0].character.isEmpty && p[0].speed == 1 && p[0].id == R.defaultPresetID, "the narrator, calm, 1×, is the default")
        #expect(p[1].speed == 1.6)
        #expect(p[2].character == "Zed" && p[2].speed == 0.8 && p[2].voice.isEmpty, "Zed's sleepy voice, cast from his persona")
        #expect(p[3].character == "Unit 7" && p[3].speed == 1.1)
        #expect(p[4].language == "ru" && p[4].forcedLanguage == Translate.russian)
        #expect(p.allSatisfy { $0.engine == .openRouter && $0.modelOrDefault == R.defaultModel })
        #expect(Set(p.map(\.id)).count == p.count)
    }

    @Test func aSavedPresetIsReadLenientlyAndClamped() throws {
        let json = #"[{"id":"6E61722D-0000-4000-8000-0000000000AA","name":"  Fast ","engine":"warp","speed":9,"pause":-1,"language":"xx"},{"name":"Bare"}]"#
        let presets = try JSONDecoder().decode([R.Preset].self, from: Data(json.utf8))
        #expect(presets[0].name == "Fast" && presets[0].engine == .openRouter && presets[0].speed == 2 && presets[0].pause == 0 && presets[0].language.isEmpty)
        #expect(presets[1].speed == 1 && presets[1].pause == R.defaultPause && presets[1].character.isEmpty)
        let again = try JSONDecoder().decode([R.Preset].self, from: JSONEncoder().encode(presets))
        #expect(again == presets, "what is saved is read back the same")
    }

    @Test func cleanedKeepsEachPresetOnceAndNeverNone() {
        #expect(R.cleaned([]) == R.defaultPresets)
        let one = R.defaultPresets[0]
        #expect(R.cleaned([one, one]).count == 1)
        let many = (0..<14).map { R.Preset(name: "P\($0)") }
        #expect(R.cleaned(many).count == R.mostPresets, "each keeps a number key")
        #expect(R.freeName("My preset", among: R.defaultPresets) == "My preset")
        #expect(R.freeName("Narrator", among: R.defaultPresets) == "Narrator 2")
    }

    @Test func thePaceStepsAndLabels() {
        #expect(R.step(1, by: 1) == 1.1 && R.step(1, by: -1) == 0.9)
        #expect(R.step(1.95, by: 1) == 2 && R.step(0.5, by: -1) == 0.5, "inside the range")
        #expect(R.speedLabel(1) == "1×" && R.speedLabel(1.6) == "1.6×")
        #expect(R.clock(65.9) == "1:05" && R.clock(0) == "0:00" && R.clock(-3) == "0:00")
    }

    // MARK: The price before sending

    @Test func thePriceIsEstimatedFromTheListPrice() throws {
        // Gemini 3.8 Flash Lite TTS: $0.50 per M in, $6 per M of sound out, 25 sound tokens a second.
        let gemini = try #require(R.estimate(characters: 1_500, promptPerToken: 0.5e-6, completionPerToken: 6e-6))
        #expect(gemini > 0.01 && gemini < 0.02, "about a cent for a page")
        let kokoro = try #require(R.estimate(characters: 1_500, promptPerToken: 0.62e-6, completionPerToken: 0))
        #expect(abs(kokoro - 0.00093) < 0.00001, "per character only")
        #expect(R.estimate(characters: 100, promptPerToken: nil, completionPerToken: nil) == nil)
        #expect(abs(R.seconds(characters: 150) - 10) < 0.001 && abs(R.seconds(characters: 150, speed: 2) - 5) < 0.001)
    }

    // MARK: Voices that speak a language

    @Test func aVoiceIsFoundForEachLanguageOrNone() {
        let gemini = ["Kore", "Puck", "Charon"]
        for language in Translate.languages { #expect(R.voices(gemini, speaking: language) == gemini, "unmarked voices speak every language") }
        let kokoro = ["af_bella", "am_adam", "bf_emma", "ef_dora", "jf_alpha"]
        #expect(R.voices(kokoro, speaking: Translate.english) == ["af_bella", "am_adam", "bf_emma"])
        #expect(R.voices(kokoro, speaking: Translate.russian).isEmpty, "Kokoro has no Russian: the Mac reads it")
        let mai = ["en-US-Harper:MAI-Voice-2.1-Flash", "ru-RU-Lev:MAI-Voice-2.1-Flash", "de-DE-Klaus:MAI-Voice-2.1-Flash"]
        #expect(R.voices(mai, speaking: Translate.russian) == ["ru-RU-Lev:MAI-Voice-2.1-Flash"])
        #expect(R.voices(mai, speaking: Translate.hebrew).isEmpty)
        #expect(R.voices(["he-IL-Avri:X", "en-US-Ava:X"], speaking: Translate.hebrew) == ["he-IL-Avri:X"])
    }

    // MARK: Buttons, the file, the tile, the costs

    /// AGENTS rule 4: every control is a picture, and its tag names its key.
    @Test func everyButtonHasItsPictureAndATooltipNamingItsKey() {
        for button in R.Button.allCases {
            #expect(button.icon.count == 11 && button.icon.allSatisfy { $0.count == 11 && $0.allSatisfy { ".#".contains($0) } }, "\(button)")
            #expect(button.icon.joined().contains("#"))
            #expect(!button.key.isEmpty && button.tooltip.contains("(\(button.key))"), "\(button)")
        }
        let sheet = R.Button.allCases.filter { $0 != .readRow }
        #expect(Set(sheet.map(\.icon)).count == sheet.count, "each its own picture")
        #expect(Set(sheet.map(\.tooltip)).count == sheet.count)
    }

    @Test func theFileIsNamedByItsTimeAndFirstWords() {
        let date = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 11, day: 1, hour: 14, minute: 32, second: 5).date!
        Language.$override.withValue(.english) {
            let name = R.fileName(for: "Hello: the/world? said \"Zed\" softly and then slept", at: date, format: .m4a)
            #expect(name == "Read aloud 2026-11-01 14.32.05 – Hello the world said Zed softly.m4a")
            #expect(R.fileName(for: "🎉", at: date, format: .wav) == "Read aloud 2026-11-01 14.32.05.wav")
        }
    }

    @Test func theToolsScreenHasReadAloudAndAnArrangedListGetsItOnce() {
        #expect(Tools.Tool.readAloud.page == .readAloud && Tools.Tool.readAloud.icon == R.Button.speaker)
        #expect(Tools.defaultShown.contains("readAloud"))
        #expect(Tools.Tool.allCases.last == .readAloud, "last, so every older tile keeps its number key")
        #expect(Tools.withNew(["dictation", "translate"], known: nil) == ["dictation", "translate", "readAloud"], "at the end of an arranged list")
        #expect(Tools.withNew(["dictation", "nonsense"], known: ["dictation"]) == Array(["dictation"] + Tools.defaultShown.filter { $0 != "dictation" }), "every tool not known then")
        #expect(Tools.withNew(["dictation"], known: Tools.defaultShown) == ["dictation"], "switched off after it was known, it stays off")
        #expect(SettingsPage.readAloud.group == .tools && SettingsPage.named("readaloud") == .readAloud)
        #expect(Shortcut.readAloud == Shortcut(keyCode: 15, modifiers: [.control, .option]), "⌃⌥R")
    }

    @Test func everyReadingIsPricedUnderReadAloud() {
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: R.defaultModel, usage: Spend.Usage(promptTokens: 80, completionTokens: 300, cost: 0.0019), purpose: .readAloud),
                       Spend.Record(time: Date(), provider: "OpenRouter", model: R.defaultModel, usage: Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil), purpose: .readAloud)]
        let s = Spend.summarise(records, now: Date())
        #expect(s.byPurpose.map(\.purpose) == ["Read aloud"])
        #expect(s.byPurpose[0].total.calls == 2, "a call whose price never came is still counted")
    }

    @Test func readAloudSpeaksRussian() {
        Language.$override.withValue(.russian) {
            #expect(Spend.Purpose.readAloud.title != "Read aloud" && SettingsPage.readAloud.title != "Read aloud")
            #expect(Tools.Tool.readAloud.title != "READ ALOUD" && Tools.Tool.readAloud.does != "Paste text and hear it read")
            for button in R.Button.allCases { #expect(button.tooltip != Language.$override.withValue(.english) { button.tooltip }, "\(button)") }
            #expect(R.defaultPresets.allSatisfy { $0.title != $0.name }, "the shipped names are translated")
            for refusal in [R.Refusal.empty, .protected, .tooLong] { #expect(refusal.line != Language.$override.withValue(.english) { refusal.line }) }
        }
    }
}
