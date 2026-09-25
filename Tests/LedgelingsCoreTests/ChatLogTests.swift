import Foundation
import Testing
@testable import LedgelingsCore

/// Conversations on disk: one JSON-lines file per day.
@Suite struct ChatLogTests {
    func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-chats-\(UUID().uuidString)")
        return dir
    }

    func exchange(at time: Date, first: String = "Move, boulder.", reply: String? = "Says the pebble.") -> ChatLog.Exchange {
        var lines = [ChatLog.Line(speaker: "Dot", text: first)]
        if let reply { lines.append(ChatLog.Line(speaker: "Blocky", text: reply)) }
        return ChatLog.Exchange(time: time, situation: "It is day. Dot is on the bottom edge. Blocky is on the bottom edge.",
                                provider: "LM Studio", model: "google/gemma-3-1b", lines: lines)
    }

    @Test func anExchangeMayCarryWhatItCostAndOldLinesStillRead() throws {
        let log = ChatLog(directory: temp())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12))!
        var priced = exchange(at: noon)
        priced.cost = 0.0007; priced.tokens = 410
        try log.append(priced)
        let old = #"{"time":"2026-09-20T13:00:00Z","situation":"s","provider":"LM Studio","model":"m","lines":[]}"#
        let handle = try FileHandle(forWritingTo: log.file(for: "2026-09-20"))
        try handle.seekToEnd(); try handle.write(contentsOf: Data((old + "\n").utf8)); try handle.close()
        let back = try log.exchanges(on: "2026-09-20")
        #expect(back.count == 2)
        #expect(back[0].cost == 0.0007 && back[0].tokens == 410)
        #expect(back[1].cost == nil && back[1].tokens == nil)
    }

    @Test func aDayIsNamedByTheLocalCalendarDate() {
        var parts = DateComponents(); parts.year = 2026; parts.month = 9; parts.day = 18; parts.hour = 23; parts.minute = 59
        let late = Calendar.current.date(from: parts)!
        #expect(ChatLog.day(of: late) == "2026-09-18")
    }

    @Test func exchangesAppendToTheDaysFileAndComeBackInOrder() throws {
        let log = ChatLog(directory: temp())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))!
        try log.append(exchange(at: noon))
        try log.append(exchange(at: noon.addingTimeInterval(600), first: "Still here?", reply: nil))
        let back = try log.exchanges(on: "2026-09-18")
        #expect(back.count == 2)
        #expect(back[0].lines.map(\.text) == ["Move, boulder.", "Says the pebble."])
        #expect(back[1].lines.count == 1 && back[1].time > back[0].time)
        #expect(back[0].model == "google/gemma-3-1b" && back[0].provider == "LM Studio")
        #expect(FileManager.default.fileExists(atPath: log.directory.appendingPathComponent("2026-09-18.jsonl").path))
    }

    @Test func daysAreListedNewestFirstAndOnlyRealLogsCount() throws {
        let log = ChatLog(directory: temp())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        try log.append(exchange(at: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!))
        try log.append(exchange(at: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 9))!))
        try log.append(exchange(at: Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 9))!))
        try Data("junk".utf8).write(to: log.directory.appendingPathComponent("notes.txt"))
        #expect(try log.days() == ["2026-09-18", "2026-09-01", "2026-08-30"])
    }

    @Test func aBrokenLineIsSkippedNotFatal() throws {
        let log = ChatLog(directory: temp())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))!
        try log.append(exchange(at: noon))
        let file = log.directory.appendingPathComponent("2026-09-18.jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json\n".utf8))
        try handle.close()
        try log.append(exchange(at: noon.addingTimeInterval(60)))
        #expect(try log.exchanges(on: "2026-09-18").count == 2)
    }

    @Test func anEmptyOrMissingFolderHasNoDays() throws {
        let log = ChatLog(directory: temp())
        #expect(try log.days().isEmpty)
        #expect(try log.exchanges(on: "2026-01-01").isEmpty)
    }

    @Test func voiceChargesLiveInASideFileTheDayListIgnores() throws {
        let log = ChatLog(directory: temp())
        defer { try? FileManager.default.removeItem(at: log.directory) }
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))     // the file keeps whole seconds
        try log.append(ChatLog.Exchange(time: now, situation: "", provider: "Built-in lines", model: "",
                                        lines: [.init(speaker: "Blocky", text: "Hi.")]))
        let charge = ChatLog.VoiceCharge(time: now, speaker: "Blocky", text: "Hi.", model: "hexgrad/kokoro-82m", cost: 0.00003)
        try log.appendVoice(charge)
        #expect(log.voiceCharges(on: ChatLog.day(of: now)) == [charge])
        #expect(try log.days() == [ChatLog.day(of: now)], "the .voice.jsonl file is not a day of its own")
        #expect(try log.exchanges(on: ChatLog.day(of: now)).count == 1)
    }

    @Test func eachVoiceChargeGoesToTheLatestConversationWithThatLine() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func talk(_ at: Double, _ lines: [(String, String)]) -> ChatLog.Exchange {
            ChatLog.Exchange(time: t0.addingTimeInterval(at), situation: "", provider: "", model: "",
                             lines: lines.map { ChatLog.Line(speaker: $0.0, text: $0.1) })
        }
        let exchanges = [
            talk(0, [("Blocky", "*sighs* Nice edge."), ("Pip", "Thanks!")]),
            talk(600, [("Blocky", "*sighs* Nice edge."), ("Pip", "Again?")]),         // the script repeats itself
        ]
        func said(_ at: Double, _ who: String, _ text: String, _ cost: Double?, kept: Bool = false) -> ChatLog.VoiceCharge {
            .init(time: t0.addingTimeInterval(at), speaker: who, text: text, model: "m", cost: cost, kept: kept)
        }
        let totals = ChatLog.voiceTotals([
            said(1, "Blocky", "Nice edge.", 0.002),       // words as spoken: no stage direction
            said(5, "Pip", "Thanks!", nil),
            said(601, "Blocky", "Nice edge.", 0, kept: true),
            said(605, "Pip", "Again?", 0.001),
            said(700, "Zed", "Nobody wrote this down.", 0.5),
        ], for: exchanges)
        #expect(totals[0]?.lines == 2 && totals[0]?.cost == 0.002 && totals[0]?.unpriced == 1 && totals[0]?.kept == 0)
        #expect(totals[1]?.lines == 1 && totals[1]?.cost == 0.001 && totals[1]?.kept == 1)
        #expect(totals.count == 2, "a line with no conversation is left out")
    }

    @Test func aModelConversationWrittenDownAfterItsLinesStillGetsThem() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let x = ChatLog.Exchange(time: t0.addingTimeInterval(20), situation: "", provider: "", model: "",
                                 lines: [.init(speaker: "Dot", text: "Hm.")])
        let totals = ChatLog.voiceTotals([.init(time: t0, speaker: "Dot", text: "Hm.", model: "m", cost: 0.01)], for: [x])
        #expect(totals[0]?.cost == 0.01)
    }
}
