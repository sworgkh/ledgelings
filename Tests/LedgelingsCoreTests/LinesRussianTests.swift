import Foundation
import Testing
@testable import LedgelingsCore

/// The built-in lines and the prompts in Russian: the same structure as the
/// English, every placeholder and parser label kept.
@Suite struct LinesRussianTests {
    static func placeholders(_ text: String) -> Set<String> {
        Set(text.matches(of: /\{[A-Za-z]+\}/).map { String(text[$0.range]) })
    }

    static func tagCounts(_ script: Script) -> [Set<String>: Int] {
        script.conversations.reduce(into: [:]) { $0[$1.tags, default: 0] += 1 }
    }

    @Test func theRussianScriptParsesWithTheSameKindsOfTags() throws {
        let english = try Script.parse(Script.englishBuiltInText)
        let russian = try Script.parse(Script.russianBuiltInText)
        let en = Self.tagCounts(english), ru = Self.tagCounts(russian)
        #expect(Set(ru.keys) == Set(en.keys))
        for (tags, count) in en {
            #expect((ru[tags] ?? 0) >= count * 3 / 4, "\(tags): \(ru[tags] ?? 0) Russian blocks for \(count) English")
        }
        for c in russian.conversations {
            #expect(c.lines.count >= 2 && c.lines.count <= 4, Comment(rawValue: c.lines.joined(separator: " / ")))
            for line in c.lines {
                #expect(line.count <= 120, Comment(rawValue: line))
                #expect(!Script.fill(line, speaker: "x", listener: "y", flower: "z", holiday: "w").contains("{"), Comment(rawValue: line))
                if line.contains("{flower}") { #expect(c.tags.contains("flower"), Comment(rawValue: line)) }
                if line.contains("{holiday}") { #expect(c.tags.contains("holiday"), Comment(rawValue: line)) }
            }
        }
        #expect(Language.$override.withValue(.russian) { Script.builtInText } == Script.russianBuiltInText)
    }

    @Test func theRussianAgentPromptKeepsTheFormat() {
        let cast = [Character(name: "Blocky", persona: "Grumpy."), Character(name: "Pip", persona: "Cheerful.")]
        let english = Language.$override.withValue(.english) { Script.agentPrompt(cast: cast, count: 30) }
        let russian = Language.$override.withValue(.russian) { Script.agentPrompt(cast: cast, count: 30) }
        #expect(russian != english)
        #expect(russian.contains("30") && russian.contains("Blocky") && russian.contains("Grumpy."))
        #expect(Self.placeholders(russian) == Self.placeholders(english))
        for tag in ["[flower]", "[night]", "[holiday]", "[night, flower]"] { #expect(russian.contains(tag), "\(tag)") }
        #expect(russian.contains("по-русски"))
    }

    @Test func russianPromptsKeepEveryPlaceholder() {
        let pairs: [(String, Translated<String>)] = [
            ("system", Banter.systemPrompts), ("line", Banter.linePrompts), ("reply", Banter.replyPrompts),
            ("plot", Bonds.plotPrompts), ("complaint", Complaints.prompts), ("note", Reminders.notePrompts),
        ]
        for (name, prompt) in pairs {
            #expect(prompt(.russian) != prompt(.english), "\(name) has no Russian")
            #expect(Self.placeholders(prompt(.russian)) == Self.placeholders(prompt(.english)), "\(name)")
        }
        #expect(Bonds.plotSystemPrompts(.russian) != Bonds.plotSystemPrompts(.english))
    }

    @Test func theRussianPlotPromptKeepsTheLabelsTheParserReads() {
        let prompt = Bonds.plotPrompts(.russian)
        #expect(prompt.contains("\nBOND: ") && prompt.contains("\nPLOT: "))
        #expect(Bonds.parse("BOND: давние соперники\nPLOT: спорят, чей угол") == Bonds.Written(bond: "давние соперники", plot: "спорят, чей угол"))
    }

    @Test func theRelationshipAndDurationsReadInRussian() {
        var bond = Bonds.Bond(names: ["Blocky", "Pip"])
        bond.together = 3 * 3600
        bond.summary = "друзья"
        bond.plot = Bonds.Plot(text: "секрет", length: 2, started: Date())
        Language.$override.withValue(.russian) {
            #expect(Bonds.duration(20) == "совсем недолго")
            #expect(Bonds.duration(60) == "1 минута")
            #expect(Bonds.duration(3 * 60) == "3 минуты")
            #expect(Bonds.duration(3600 * 5) == "5 часов")
            #expect(Bonds.duration(3600 * 22) == "22 часа")
            #expect(Bonds.duration(86400 * 21) == "21 день")
            let context = Bonds.context(bond, speaker: "Blocky", other: "Pip")
            #expect(context.contains("Pip") && context.contains("3 часа") && context.contains("часть 1 из 2"))
            #expect(Bonds.plotValues(Bonds.Bond(names: ["A", "B"]), a: ("A", "k", "p"), b: ("B", "k", "p"), length: 3)["recent"] == "(пока ничего)")
        }
    }

    @Test func everyCharacterComplainsAndRemindsInRussian() {
        #expect(Set(Complaints.russianLines.keys) == Set(Complaints.englishLines.keys))
        #expect(Set(Reminders.russianNotes.keys) == Set(Reminders.englishNotes.keys))
        for (name, lines) in Complaints.englishLines {
            #expect(Complaints.russianLines[name]?.count == lines.count, "\(name)")
            #expect(Complaints.russianLines[name]?.contains { $0.contains("{times}") } == true, "\(name) never says how many times")
        }
        for (name, notes) in Reminders.englishNotes {
            #expect(Reminders.russianNotes[name]?.count == notes.count, "\(name)")
            #expect(Reminders.russianNotes[name]?.allSatisfy { $0.contains("{reminder}") } == true, "\(name)")
        }
        #expect(Reminders.russianAnyone.allSatisfy { $0.contains("{reminder}") })
        Language.$override.withValue(.russian) {
            var rng = SystemRandomNumberGenerator()
            #expect(Complaints.line(by: "Ruth", times: 5, using: &rng).contains { $0.isCyrillic })
            #expect(Reminders.note(by: "Unit 7", reminder: "Размяться", using: &rng).contains("Размяться"))
        }
    }

    @Test func remindersSayWhenInRussian() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = try #require(c.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12)))
        let at = { (d: Int, h: Int) in c.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: 5))! }
        Language.$override.withValue(.russian) {
            #expect(Reminders.when(at(26, 14), now: now, calendar: c) == "Сегодня 14:05")
            #expect(Reminders.when(at(27, 9), now: now, calendar: c) == "Завтра 09:05")
            #expect(Reminders.when(at(25, 18), now: now, calendar: c) == "Вчера 18:05")
            let later = Reminders.day(at(30, 9), now: now, calendar: c)
            #expect(later.contains("30") && later.contains("сент"), "\(later)")
            let daily = Reminders.Reminder(text: "x", time: at(27, 9), repeats: .daily)
            #expect(daily.describe(now: now, calendar: c) == "Каждый день, следующее: Завтра 09:05")
        }
    }

    @Test func everyHolidayHasARussianName() {
        for feast in Almanac.feasts {
            let russian = Almanac.holidayName(feast.name, in: .russian)
            #expect(russian != feast.name && russian.contains { $0.isCyrillic }, "\(feast.name)")
        }
        #expect(Set(Almanac.russianHolidayNames.keys) == Set(Almanac.feasts.map(\.name)), "a name for a holiday that does not exist")
    }

    @Test func theAlmanacSpeaksRussian() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let evening = try #require(c.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 22, minute: 40)))
        Language.$override.withValue(.russian) {
            let sentence = Almanac.sentence(at: evening, Almanac.Awareness(faiths: [.jewish], lookAhead: 0), calendar: c)
            #expect(sentence.hasPrefix("У человека за этим компьютером сейчас понедельник, 28 сентября 2026, поздний вечер (22:40)."), "\(sentence)")
            #expect(sentence.contains("Суккот") && sentence.contains("3-й день"), "\(sentence)")
            #expect(Almanac.today(evening, faiths: [.jewish], calendar: c) == "Суккот")
            let before = c.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 10))!
            let ahead = Almanac.sentence(at: before, Almanac.Awareness(timeOfDay: false, date: false, faiths: [.jewish], lookAhead: 3), calendar: c)
            #expect(ahead == "Ханука (иудейский праздник) — через 3 дня.")
        }
    }

    @Test func theSpritePromptKeepsTheFormat() {
        let english = Language.$override.withValue(.english) { SpriteText.prompt(example: ["..o."]) }
        let russian = Language.$override.withValue(.russian) { SpriteText.prompt(example: ["..o."]) }
        #expect(russian != english)
        for key in ["name:", "kind:", "colour:", "character:", "pose: idle", "pose: walk-0", ". o b l s k x"] {
            #expect(russian.contains(key), "\(key)")
        }
        #expect(russian.contains(SpriteText.poses.joined(separator: ", ")))
        #expect(Language.$override.withValue(.russian) { russian.contains(SpriteText.describePlaceholder) })
    }
}

private extension Swift.Character {
    var isCyrillic: Bool { unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }
}
