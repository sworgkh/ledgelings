import Foundation
import Testing
@testable import LedgelingsCore

/// The cursor mood: what the creatures make of the cursor, in the prompts, the
/// built-in lines and the complaints, in every language.
@Suite struct CursorMoodTests {
    /// Words that mean the cursor in a shipped line.
    static func aboutCursor(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["cursor", "arrow", "pointer", "курсор", "стрелк"].contains { lower.contains($0) }
    }

    /// Every shipped line or conversation a creature can say, by language: the
    /// script's conversations joined by newlines, everything else line by line.
    static func shipped(_ l: Language) -> [String] {
        let script = try! Script.parse(Script.builtInTexts(l)).conversations.map { $0.lines.joined(separator: "\n") }
        let letters = ([Letters.anyones(l)] + Array(Letters.voiceSets(l).values)).flatMap { $0.notes + $0.musings + $0.replies }
        let tea: [String] = Tea.storyBooks(l).values.flatMap { $0 } + Tea.replyBooks(l).values.flatMap { $0 } + Tea.anyoneStoryBooks(l) + Tea.anyoneReplyBooks(l)
        let reminders: [String] = Reminders.noteSets(l).values.flatMap { $0 } + Reminders.anyones(l)
        return script + letters + tea + reminders
    }

    @Test func everyShippedLineAboutTheCursorHasAVersionForEachMood() {
        for l in Language.allCases {
            let rewrites = CursorMood.rewrites(l), fine = CursorMood.fitsEveryMood(l)
            let aboutCursor = Set(Self.shipped(l).filter { Self.aboutCursor($0) })
            for text in aboutCursor {
                #expect(rewrites[text] != nil || fine.contains(text), "\(l.code): no good or neutral version of \"\(text)\"")
            }
            // No rewrite of a line that does not ship (a typo would leave the original in place).
            for key in rewrites.keys { #expect(aboutCursor.contains(key), "\(l.code): rewrite of a line that does not ship: \"\(key)\"") }
            for key in fine { #expect(aboutCursor.contains(key), "\(l.code): \"\(key)\" does not ship") }
        }
    }

    @Test func aRewrittenConversationKeepsItsLinesAndPlaceholders() {
        for l in Language.allCases {
            for (text, r) in CursorMood.rewrites(l) {
                let n = text.components(separatedBy: "\n").count
                for version in [r.good, r.neutral] {
                    #expect(version.components(separatedBy: "\n").count == n, "\(l.code): \"\(version)\" has \(n) lines")
                    for slot in ["{reader}", "{reminder}", "{flower}", "{other}"] where text.contains(slot) {
                        #expect(version.contains(slot), "\(l.code): \"\(version)\" keeps \(slot)")
                    }
                    #expect(version != text)
                }
                #expect(r.good != r.neutral)
            }
        }
    }

    @Test func eachMoodSaysItsOwnLinesAndBadSaysTheOriginals() {
        let original = "The cursor chased me into a corner once. I stared it down. It blinked first."
        CursorMood.$override.withValue(.bad) {
            #expect(Tea.stories["Blocky"]?.contains(original) == true)
            #expect(CursorMood.current.adjust(["Rate the cursor out of ten.", "Minus four.", "Generous."]) == ["Rate the cursor out of ten.", "Minus four.", "Generous."])
        }
        CursorMood.$override.withValue(.good) {
            #expect(Tea.stories["Blocky"]?.contains(original) == false)
            #expect(Tea.stories["Blocky"]?.contains { $0.contains("tagged it back") } == true)
            #expect(CursorMood.current.adjust(["Rate the cursor out of ten.", "Minus four.", "Generous."])[1].hasPrefix("Eleven"))
            #expect(Letters.voice(of: "Glitch").notes.contains("The cursor is a friend friend. Click. Click. It likes it."))
            #expect(Reminders.notes["Blocky"]?.first?.hasPrefix("Stop playing with the cursor") == true)
        }
        CursorMood.$override.withValue(.neutral) {
            #expect(CursorMood.current.adjust(["Rate the cursor out of ten.", "Minus four.", "Generous."])[1] == "Five. It's a cursor.")
            #expect(Letters.voice(of: "Glitch").notes.contains { $0.contains("virus virus") } == false)
        }
        // A line the user wrote stays as written in every mood.
        for mood in CursorMood.allCases { #expect(mood.adjust("I hate the cursor, says me.") == "I hate the cursor, says me.") }
    }

    @Test func russianLinesFollowTheMoodToo() {
        Language.$override.withValue(.russian) {
            CursorMood.$override.withValue(.good) {
                #expect(Tea.stories["Blocky"]?.contains { $0.contains("осалил") } == true)
            }
            CursorMood.$override.withValue(.neutral) {
                #expect(Letters.voice(of: "Glitch").notes.contains("Курсор — это вирус вирус. Не кликай. Не кликай.") == false)
            }
        }
    }

    @Test func aModelHearsTheMoodThroughThePersona() {
        let blocky = Banter.defaultCharacters.first { $0.name == "Blocky" }!.persona
        CursorMood.$override.withValue(.bad) {
            #expect(Banter.persona(blocky) == blocky, "bad is how Blocky was written")
            #expect(Banter.persona("A user's own creature.") == "A user's own creature.")
        }
        CursorMood.$override.withValue(.good) {
            let said = Banter.persona(blocky)
            #expect(said.contains("Secretly loves racing the mouse cursor") && said.contains("game of tag"))
            #expect(!said.contains("Hates"))
            #expect(Banter.persona("A user's own creature.").hasSuffix(CursorMood.good.note), "a user's character hears the mood too")
            let filled = Banter.render(Banter.systemPrompts(.english), ["speakerPersona": said])
            #expect(filled.contains("game of tag"), "the system prompt carries it")
        }
        CursorMood.$override.withValue(.neutral) {
            let said = Banter.persona(blocky)
            #expect(said.hasPrefix("Grumpy and proud. Thinks the bottom edge") && said.contains("means nothing to them"))
        }
        Language.$override.withValue(.russian) {
            CursorMood.$override.withValue(.good) {
                let said = Banter.persona(blocky)
                #expect(said.contains("Втайне обожает") && said.contains("догонялки"), "in Russian: \(said)")
            }
        }
    }

    @Test func everyRewrittenPersonaIsInRussian() {
        for (_, r) in CursorMood.personas {
            for p in [r.good, r.neutral] { #expect(Strings.lookup(p, in: .russian) != p, "no Russian for \"\(p)\"") }
        }
        for mood in CursorMood.allCases where mood != .bad {
            #expect(!CursorMood.notes(mood).english.isEmpty && CursorMood.notes(mood)(.russian) != CursorMood.notes(mood).english)
        }
    }

    @Test func complaintsBecomeATeaseOrARemark() {
        let everyone = Set(Complaints.lineSets.english.keys)
        for mood in CursorMood.allCases {
            for l in Language.allCases {
                let sets = Complaints.lineSets(for: mood)(l)
                #expect(Set(sets.keys) == everyone, "\(mood) \(l.code): everyone has their own lines")
                for (name, lines) in sets {
                    #expect(lines.count >= 2 && lines.contains { $0.contains("{times}") }, "\(mood) \(l.code) \(name)")
                }
                #expect(!Complaints.anyones(for: mood)(l).isEmpty)
                #expect(Complaints.prompts(for: mood)(l).contains("{times}") && Complaints.prompts(for: mood)(l).contains("{situation}"))
            }
        }
        #expect(Complaints.prompts(for: .good).english.contains("game of tag"))
        #expect(Complaints.prompts(for: .neutral).english.contains("neither pleased nor annoyed"))
        #expect(Complaints.prompts(for: .bad).english.contains("You have had enough"))
        var rng = SystemRandomNumberGenerator()
        CursorMood.$override.withValue(.good) {
            #expect(Complaints.prompt == Complaints.englishGoodPrompt)
            let line = Complaints.line(by: "Pip", times: 5, using: &rng)
            #expect(Complaints.englishGoodLines["Pip"]!.map { Banter.render($0, ["times": "5"]) }.contains(line))
        }
        CursorMood.$override.withValue(.neutral) {
            let line = Complaints.line(by: "Someone New", times: 5, using: &rng)
            #expect(Complaints.englishNeutralAnyone.map { Banter.render($0, ["times": "5"]) }.contains(line))
            #expect(CursorMood.current.spokeUp == "%@ said to you: %@")
        }
    }

    @Test func thePromptForWritingMoreLinesSaysTheMood() {
        CursorMood.$override.withValue(.good) {
            #expect(Script.englishAgentPrompt(cast: Banter.defaultCharacters).contains("play tag with the mouse cursor"))
            #expect(Script.englishAgentPrompt(cast: Banter.defaultCharacters).contains("Secretly loves racing"))
            Language.$override.withValue(.russian) {
                #expect(Script.agentPrompt(cast: []).contains("играют с курсором мыши в догонялки"))
            }
        }
        CursorMood.$override.withValue(.bad) {
            #expect(Script.englishAgentPrompt(cast: []).contains("flee the mouse cursor"))
        }
    }

    @Test func theAppStartsWithTheMenace() {
        #expect(CursorMood.current == .bad || CursorMood.override != nil)
        #expect(CursorMood.allCases.map(\.rawValue) == ["good", "neutral", "bad"])
    }
}
