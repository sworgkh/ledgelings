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
}
