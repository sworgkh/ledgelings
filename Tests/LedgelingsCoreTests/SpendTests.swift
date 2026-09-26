import Foundation
import Testing
@testable import LedgelingsCore

/// What the creatures' talking costs: one record per model call, summed by day, month and model.
@Suite struct SpendTests {
    static let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12))!

    func record(_ hoursAgo: Double, model: String = "google/gemini-2.5-flash-lite", cost: Double? = 0.0004, prompt: Int = 300, completion: Int = 40) -> Spend.Record {
        Spend.Record(time: Self.noon.addingTimeInterval(-hoursAgo * 3600), provider: "OpenRouter", model: model,
                     usage: Spend.Usage(promptTokens: prompt, completionTokens: completion, cost: cost))
    }

    @Test func todayThisMonthAndAllTimeAreSummedFromTheRecords() {
        let records = [record(1), record(3, cost: 0.0006), record(30, model: "anthropic/claude-haiku-4.5", cost: 0.002),
                       record(24 * 25, cost: 0.001), record(24 * 400, cost: 0.5)]
        let s = Spend.summarise(records, now: Self.noon)
        #expect(s.today.calls == 2 && abs(s.today.cost - 0.001) < 1e-9 && s.today.promptTokens == 600 && s.today.completionTokens == 80)
        #expect(s.month.calls == 3 && abs(s.month.cost - 0.003) < 1e-9)
        #expect(s.allTime.calls == 5 && abs(s.allTime.cost - 0.504) < 1e-9)
        #expect(s.byModel.map(\.model) == ["google/gemini-2.5-flash-lite", "anthropic/claude-haiku-4.5"], "dearest model first")
        #expect(s.byModel[0].total.calls == 4)
    }

    @Test func aCallWithoutAPriceIsCountedButFlagged() {
        let s = Spend.summarise([record(1, cost: nil), record(2)], now: Self.noon)
        #expect(s.today.calls == 2 && s.today.unpriced == 1 && abs(s.today.cost - 0.0004) < 1e-9)
        #expect(Spend.summarise([], now: Self.noon).allTime == Spend.Total())
    }

    @Test func moneyIsShownToTheCentOrToTheTenthOfACent() {
        #expect(Spend.label(0) == "$0.00")
        #expect(Spend.label(0.00004) == "<$0.001")
        #expect(Spend.label(0.0042) == "$0.004")
        #expect(Spend.label(0.037) == "$0.037")
        #expect(Spend.label(1.5) == "$1.50")
        #expect(Spend.label(12.345) == "$12.35")
    }

    @Test func theLedgerKeepsRecordsOnDiskInOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-spend-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = Spend.Ledger(directory: dir)
        #expect(try ledger.records() == [])
        try ledger.append(record(2))
        try ledger.append(record(1, cost: nil))
        let back = try ledger.records()
        #expect(back.count == 2 && back[0].usage.cost == 0.0004 && back[1].usage.cost == nil)
        #expect(abs(back[0].time.timeIntervalSince(record(2).time)) < 1)
        #expect(ledger.file.lastPathComponent == "spend.jsonl")
    }

    @Test func costsAreSummedByFeatureAndOldRecordsAreShownAsUnlabelled() {
        func r(_ purpose: Spend.Purpose?, _ cost: Double) -> Spend.Record {
            Spend.Record(time: Self.noon, provider: "OpenRouter", model: "m",
                         usage: Spend.Usage(promptTokens: 10, completionTokens: 0, cost: cost), purpose: purpose)
        }
        let s = Spend.summarise([r(.voice, 0.002), r(.voice, 0.001), r(.talk, 0.0005), r(.casting, 0.0001), r(nil, 0.01)], now: Self.noon)
        #expect(s.byPurpose.map(\.purpose) == [Spend.Purpose.unlabelled, "Voice", "Talk", "Voice casting"])
        #expect(s.byPurpose[1].total.calls == 2 && abs(s.byPurpose[1].total.cost - 0.003) < 1e-12)
    }

    @Test func aRecordFromBeforeFeaturesWereLabelledStillReads() throws {
        let old = #"{"time":"2026-09-25T19:44:03Z","provider":"OpenRouter","usage":{"cost":0.00033,"promptTokens":4,"completionTokens":0},"model":"microsoft/mai-voice-2"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(Spend.Record.self, from: Data(old.utf8))
        #expect(record.purpose == nil && Spend.Purpose.title(of: record.purpose) == Spend.Purpose.unlabelled)
        #expect(Spend.Purpose.title(of: "dreams") == "dreams", "a purpose from a newer build keeps its name")
    }

    @Test func reminderNotesAreTheirOwnLineInTheCosts() {
        let usage = Spend.Usage(promptTokens: 120, completionTokens: 30, cost: 0.0001)
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: "m", usage: usage, purpose: .reminders)]
        let s = Spend.summarise(records, now: Date())
        #expect(s.byPurpose.map(\.purpose) == ["Reminders"])
        #expect(s.byPurpose[0].total.calls == 1)
    }
}
