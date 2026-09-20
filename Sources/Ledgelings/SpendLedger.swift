import AppKit
import Combine
import LedgelingsCore

/// The spend file as the app sees it: `spend.jsonl` next to the chats, a summary
/// that refreshes whenever a call is recorded, and a way to open the file.
@MainActor
final class SpendLedger: ObservableObject {
    let ledger: Spend.Ledger
    @Published private(set) var summary = Spend.Summary()

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

    /// One model call. A local server is free, so its cost is zero, not unknown.
    func record(provider: ChatClient.Provider, model: String, usage: Spend.Usage, at time: Date = Date()) {
        var usage = usage
        if provider == .lmStudio { usage.cost = 0 }
        do {
            try ledger.append(Spend.Record(time: time, provider: provider.title, model: model, usage: usage))
            reload()
        } catch {
            FileHandle.standardError.write(Data("Ledgelings spend: \(error)\n".utf8))
        }
    }

    func reload() { summary = Spend.summarise((try? ledger.records()) ?? []) }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: ledger.directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        else { NSWorkspace.shared.open(ledger.directory) }
    }
}
