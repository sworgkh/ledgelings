import AppKit
import Combine
import LedgelingsCore

/// The chat log as the app sees it: a folder under Application Support, a
/// counter that ticks whenever something is written so a view can refresh,
/// and the two ways of opening the folder.
@MainActor
final class ChatHistory: ObservableObject {
    let log: ChatLog
    /// Goes up by one for every exchange written; observe it to reload.
    @Published private(set) var version = 0

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Ledgelings/chats", isDirectory: true)
    }

    /// What each character said lately, from every exchange written, and at
    /// launch from the last days on disk, so a relaunch does not reset it.
    private(set) var memory = LineMemory(limit: 0)

    init(directory: URL = ChatHistory.defaultDirectory) { log = ChatLog(directory: directory) }

    /// Remember `limit` lines per character; the first call reads them back from disk.
    func remember(_ limit: Int) {
        guard limit != memory.limit else { return }
        if limit < memory.limit { memory.trim(to: limit); return }
        memory = LineMemory(limit: limit)
        let days = ((try? log.days()) ?? []).prefix(2).reversed()
        for day in days { for exchange in (try? log.exchanges(on: day)) ?? [] { memory.remember(exchange) } }
    }

    var directory: URL { log.directory }

    func record(_ exchange: ChatLog.Exchange) {
        do {
            try log.append(exchange)
            memory.remember(exchange)
            version += 1
        } catch {
            FileHandle.standardError.write(Data("Ledgelings chat log: \(error)\n".utf8))
        }
    }

    func recordVoice(_ charge: ChatLog.VoiceCharge) {
        do {
            try log.appendVoice(charge)
            version += 1
        } catch {
            FileHandle.standardError.write(Data("Ledgelings chat log: \(error)\n".utf8))
        }
    }

    func voiceTotals(on day: String, for exchanges: [ChatLog.Exchange]) -> [Int: ChatLog.VoiceTotal] {
        ChatLog.voiceTotals(log.voiceCharges(on: day), for: exchanges)
    }

    func days() -> [String] { (try? log.days()) ?? [] }
    func exchanges(on day: String) -> [ChatLog.Exchange] { (try? log.exchanges(on: day)) ?? [] }

    /// Make sure the folder exists before handing it to another app.
    private func prepared() -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func revealInFinder() { NSWorkspace.shared.open(prepared()) }

    func openInTerminal() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([prepared()], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
