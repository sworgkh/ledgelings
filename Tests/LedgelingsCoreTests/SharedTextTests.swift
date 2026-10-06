import Foundation
import Testing
@testable import LedgelingsCore

/// The Windows app speaks the same Russian as this one: everything written in
/// each language here is exported to `Sources/LedgelingsCore/l10n/<code>.json`
/// (`ru.json`), which the Windows build links. This test fails when the file is stale; rerun it with
/// `LEDGELINGS_WRITE_L10N=1` to write it afresh.
@Suite struct SharedTextTests {
    static func file(_ l: Language) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LedgelingsCore/l10n/\(l.code).json")
    }

    static func letter(_ v: Letters.Voice) -> [String: [String]] {
        ["topics": v.topics, "notes": v.notes, "musings": v.musings, "replies": v.replies]
    }

    static func export(_ l: Language) -> [String: Any] {
        [
            "language": l.code,
            "strings": Strings.tables[l] ?? [:],
            "script": Script.builtInTexts(l),
            "letters": ["anyone": letter(Letters.anyones(l)), "voices": Letters.voiceSets(l).mapValues(letter)],
            "tea": ["stories": Tea.storyBooks(l), "replies": Tea.replyBooks(l),
                    "anyoneStories": Tea.anyoneStoryBooks(l), "anyoneReplies": Tea.anyoneReplyBooks(l)],
            "complaints": ["anyone": Complaints.anyones(l), "lines": Complaints.lineSets(l)],
            "reminders": ["anyone": Reminders.anyones(l), "notes": Reminders.noteSets(l)],
            "cursorMood": [
                "rewrites": CursorMood.rewrites(l).mapValues { ["good": $0.good, "neutral": $0.neutral] },
                "fitsEveryMood": CursorMood.fitsEveryMood(l).sorted(),
                "notes": ["good": CursorMood.notes(.good)(l), "neutral": CursorMood.notes(.neutral)(l)],
                "agentPhrases": Dictionary(uniqueKeysWithValues: CursorMood.allCases.map { mood in
                    (mood.rawValue, Language.$override.withValue(l) { mood.agentPhrase }) }),
                "complaints": ["good": ["anyone": Complaints.anyones(for: .good)(l), "lines": Complaints.lineSets(for: .good)(l)],
                               "neutral": ["anyone": Complaints.anyones(for: .neutral)(l), "lines": Complaints.lineSets(for: .neutral)(l)]],
                "complaintPrompts": ["good": Complaints.prompts(for: .good)(l), "neutral": Complaints.prompts(for: .neutral)(l)],
            ],
            "holidays": Almanac.holidayNames[l] ?? [:],
            "flowers": Gifts.names(l),
            "prompts": [
                "system": Banter.systemPrompts(l), "line": Banter.linePrompts(l), "reply": Banter.replyPrompts(l),
                "plot": Bonds.plotPrompts(l), "plotSystem": Bonds.plotSystemPrompts(l),
                "planeNote": Letters.notePrompts(l), "planeReply": Letters.replyPrompts(l), "planeMusing": Letters.musingPrompts(l),
                "teaSystem": Tea.systemPrompts(l), "teaStory": Tea.storyPrompts(l), "teaReply": Tea.replyPrompts(l),
                "complaint": Complaints.prompts(l), "reminder": Reminders.notePrompts(l),
            ],
        ]
    }

    @Test func theExportIsUpToDate() throws {
        for language in Language.allCases where language != .english {
            let data = try JSONSerialization.data(withJSONObject: Self.export(language), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
            if ProcessInfo.processInfo.environment["LEDGELINGS_WRITE_L10N"] != nil { try data.write(to: Self.file(language)) }
            let saved = try Data(contentsOf: Self.file(language))
            #expect(saved == data, "\(language.code).json is stale: run LEDGELINGS_WRITE_L10N=1 swift test --filter SharedTextTests")
        }
    }
}
