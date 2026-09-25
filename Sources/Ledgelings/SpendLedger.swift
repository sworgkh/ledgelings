import AppKit
import Combine
import LedgelingsCore

/// The spend file as the app sees it: `spend.jsonl` next to the chats, a summary
/// that refreshes whenever a call is recorded, and a way to open the file.
@MainActor
final class SpendLedger: ObservableObject {
    let ledger: Spend.Ledger
    @Published private(set) var summary = Spend.Summary()
    /// The latest calls, newest first, for the Costs tab.
    @Published private(set) var recent: [Spend.Record] = []
    static let recentCount = 200

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Ledgelings", isDirectory: true)
    }

    init(directory: URL = SpendLedger.defaultDirectory) {
        ledger = Spend.Ledger(directory: directory)
        reload()
    }

    var file: URL { ledger.file }

    /// One model call, and the feature that made it. A local server is free, so
    /// its cost is zero, not unknown. `purpose` has no default on purpose: a new
    /// feature that calls a model must say which it is (see AGENTS.md).
    func record(provider: ChatClient.Provider, model: String, usage: Spend.Usage, purpose: Spend.Purpose, at time: Date = Date()) {
        var usage = usage
        if provider == .lmStudio { usage.cost = 0 }
        do {
            try ledger.append(Spend.Record(time: time, provider: provider.title, model: model, usage: usage, purpose: purpose))
            reload()
        } catch {
            FileHandle.standardError.write(Data("Ledgelings spend: \(error)\n".utf8))
        }
    }

    func reload() {
        let records = (try? ledger.records()) ?? []
        summary = Spend.summarise(records)
        recent = Array(records.suffix(Self.recentCount).reversed())
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: ledger.directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        else { NSWorkspace.shared.open(ledger.directory) }
    }
}
