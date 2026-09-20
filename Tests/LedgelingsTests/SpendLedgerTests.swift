import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The ledger as the app uses it: records land on disk, the summary refreshes, local calls are free.
@MainActor
@Suite struct SpendLedgerTests {
    @Test func recordingUpdatesTheSummaryAndLocalCallsCostNothing() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-spend-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = SpendLedger(directory: dir)
        #expect(ledger.summary.allTime.calls == 0)
        ledger.record(provider: .openRouter, model: "m", usage: Spend.Usage(promptTokens: 10, completionTokens: 5, cost: 0.001))
        ledger.record(provider: .lmStudio, model: "local", usage: Spend.Usage(promptTokens: 10, completionTokens: 5, cost: nil))
        #expect(ledger.summary.allTime.calls == 2 && ledger.summary.allTime.unpriced == 0)
        #expect(abs(ledger.summary.allTime.cost - 0.001) < 1e-9, "LM Studio is free, so its call is priced at zero")
        #expect(ledger.summary.byModel.map(\.model) == ["m", "local"])
        #expect(SpendLedger(directory: dir).summary.allTime.calls == 2, "read back from disk on the next launch")
    }
}
