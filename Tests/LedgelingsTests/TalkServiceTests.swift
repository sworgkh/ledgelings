import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Talks to a real LM Studio. Opt in with LEDGELINGS_LIVE=1, otherwise skipped.
@Suite struct TalkServiceTests {
    static let live = ProcessInfo.processInfo.environment["LEDGELINGS_LIVE"] == "1"

    @Test(.enabled(if: live)) func gemmaAnswersInCharacterThroughTheDefaultPrompts() async throws {
        let service = TalkService(baseURL: URL(string: "http://localhost:1234")!, model: "google/gemma-3-1b")
        try await service.checkModel()

        let a = Banter.defaultCharacters[0], b = Banter.defaultCharacters[1]
        var vars = ["speaker": a.name, "speakerPersona": a.persona, "listener": b.name, "listenerPersona": b.persona,
                    "situation": "It is night. \(a.name) is on the bottom edge. \(b.name) is asleep on the ceiling.", "line": ""]
        let first = Banter.cleanLine(try await service.line(system: Banter.render(Banter.defaultSystemPrompt, vars),
                                                            user: Banter.render(Banter.defaultLinePrompt, vars)), speaker: a.name)
        print("\(a.name): \(first)")
        #expect(!first.isEmpty && first.count < 200)

        vars["speaker"] = b.name; vars["speakerPersona"] = b.persona
        vars["listener"] = a.name; vars["listenerPersona"] = a.persona; vars["line"] = first
        let reply = Banter.cleanLine(try await service.line(system: Banter.render(Banter.defaultSystemPrompt, vars),
                                                            user: Banter.render(Banter.defaultReplyPrompt, vars)), speaker: b.name)
        print("\(b.name): \(reply)")
        #expect(!reply.isEmpty && reply.count < 200)
    }

    @Test(.enabled(if: live)) func aMissingModelIsRefusedInsteadOfSilentlySwapped() async {
        let service = TalkService(baseURL: URL(string: "http://localhost:1234")!, model: "nobody/no-such-model")
        await #expect(throws: TalkService.Failure.self) { try await service.checkModel() }
    }
}
