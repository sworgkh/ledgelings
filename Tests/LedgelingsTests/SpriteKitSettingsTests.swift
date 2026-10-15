import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The sprite kit's form is kept like any setting, and Refine with AI is there
/// only with an OpenRouter key, priced as its own feature even when its answer is no use.
@MainActor
@Suite(.serialized) struct SpriteKitSettingsTests {
    let name = "ledgelings-sprite-kit-settings-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        var values: [String: String] = [:]
        func get(_ account: String) -> String? { values[account] }
        func set(_ value: String?, for account: String) { values[account] = value }
    }

    func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func theFormStartsEmptyAndSurvivesARelaunch() {
        let d = defaults()
        defer { d.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: d, keychain: Secrets())
        #expect(s.spriteKitForm == SpriteKit.Form() && s.spriteKitForm.cast.count == 3)
        s.spriteKitForm.kind = "a boxy moss sprite"
        s.spriteKitForm.colour = "#55aa33"
        s.spriteKitForm.cast[1] = Character(name: "Bark", persona: "old, slow, grumpy")
        let again = AppSettings(defaults: d, keychain: Secrets())
        #expect(again.spriteKitForm.kind == "a boxy moss sprite" && again.spriteKitForm.colour == "#55aa33")
        #expect(again.spriteKitForm.cast[1].name == "Bark")
        // A colour that is not hex is dropped on load, and the cast kept to three.
        d.set(try! JSONEncoder().encode(SpriteKit.Form(colour: "greenish")), forKey: "spriteKitForm")
        #expect(AppSettings(defaults: d, keychain: Secrets()).spriteKitForm.colour == "")
    }

    @Test func refineIsOnlyThereWithAnOpenRouterKey() {
        let d = defaults()
        defer { d.removePersistentDomain(forName: name) }
        let secrets = Secrets()
        let s = AppSettings(defaults: d, keychain: secrets)
        s.brain = .script
        s.openRouterKey = "sk-or-test"
        #expect(!s.openRouterConnected && s.refineClient() == nil, "a key nobody uses is not read")
        s.voiceEngine = .openRouter
        #expect(s.openRouterConnected)
        s.voiceEngine = .system; s.brain = .lmStudio
        #expect(!s.openRouterConnected, "LM Studio is not OpenRouter")
        s.brain = .openRouter
        s.openRouterModel = "some/model"
        #expect(s.refineClient()?.model == "some/model" && s.refineClient()?.provider == .openRouter)
        s.openRouterKey = ""
        #expect(s.refineClient() == nil)
    }

    /// Answers chat calls to `refine.test` with whatever the test sets.
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var reply = ""
        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "refine.test" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let body: [String: Any] = ["choices": [["message": ["content": Self.reply], "finish_reason": "stop"]],
                                       "usage": ["prompt_tokens": 420, "completion_tokens": 180, "cost": 0.0004]]
            let data = try! JSONSerialization.data(withJSONObject: body)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test func refiningFillsTheFormAndIsPricedEvenWhenTheAnswerIsNoUse() async throws {
        URLProtocol.registerClass(Stub.self)
        defer { URLProtocol.unregisterClass(Stub.self) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-refine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spend = SpendLedger(directory: dir)
        let client = ChatClient(provider: .openRouter, baseURL: URL(string: "https://refine.test/api/v1")!, apiKey: "k", model: "m")

        Stub.reply = ##"{"name": "mossy", "kind": "a boxy moss block", "colour": "#4f9a3a", "characters": [{"name": "Fern", "persona": "tiny, fast, anxious, she"}]}"##
        let form = try await SpriteKitRefine.refine(SpriteKit.Form(kind: "moss"), client: client, spend: spend)
        #expect(form.name == "mossy" && form.kind == "a boxy moss block" && form.cast[0].name == "Fern")

        Stub.reply = "Sorry, I can only draw."
        await #expect(throws: ChatClient.Failure.self) {
            try await SpriteKitRefine.refine(SpriteKit.Form(kind: "moss"), client: client, spend: spend)
        }
        let line = spend.summary.byPurpose.first { $0.purpose == Spend.Purpose.creatureRefine.title }
        #expect(line?.total.calls == 2, "the unusable answer was paid for too")
        #expect(abs((line?.total.cost ?? 0) - 0.0008) < 1e-12)
    }
}
