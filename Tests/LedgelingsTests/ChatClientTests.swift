import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The client builds requests and reads replies without a network; those parts are tested here.
@Suite struct ChatClientTests {
    @Test func lmStudioAsksTheLocalServerWithNoKey() throws {
        let client = ChatClient.lmStudio(server: URL(string: "http://localhost:1234")!, model: "google/gemma-3-1b")
        let request = try client.request(system: "You are Pip.", user: "Say hi.")
        #expect(request.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["model"] as? String == "google/gemma-3-1b")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "You are Pip."], ["role": "user", "content": "Say hi."]])
        #expect(body["max_tokens"] as? Int == 80)
    }

    @Test func openRouterSendsTheKeyAndNamesTheApp() throws {
        let client = ChatClient.openRouter(key: "sk-or-test", model: "anthropic/claude-haiku-4.5")
        let request = try client.request(system: "s", user: "u", maxTokens: 300, temperature: 0.2)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Ledgelings")
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["max_tokens"] as? Int == 300)
        #expect(body["temperature"] as? Double == 0.2)
    }

    @Test func modelListsComeFromEachProvidersOwnPath() {
        #expect(ChatClient.lmStudio(server: URL(string: "http://localhost:1234")!, model: "m").modelsURL.absoluteString == "http://localhost:1234/v1/models")
        #expect(ChatClient.openRouter(key: "k", model: "m").modelsURL.absoluteString == "https://openrouter.ai/api/v1/models")
    }

    @Test func aReplyIsTheFirstChoicesText() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello there."}}]}"#.utf8)
        let answer = try ChatClient.parseReply(data)
        #expect(answer.text == "Hello there." && answer.usage == nil)
    }

    @Test func aReplyCarriesWhatItCostWhenTheServerSaysSo() throws {
        let data = Data(#"{"choices":[{"message":{"content":"Hi."}}],"usage":{"prompt_tokens":312,"completion_tokens":18,"total_tokens":330,"cost":0.00042}}"#.utf8)
        let answer = try ChatClient.parseReply(data)
        #expect(answer.usage == Spend.Usage(promptTokens: 312, completionTokens: 18, cost: 0.00042))
        let local = Data(#"{"choices":[{"message":{"content":"Hi."}}],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}"#.utf8)
        #expect(try ChatClient.parseReply(local).usage == Spend.Usage(promptTokens: 5, completionTokens: 2, cost: nil))
    }

    @Test func aThinkingModelThatRanOutOfRoomIsAnEmptyAnswerThatStillCosts() throws {
        let data = Data(#"{"choices":[{"finish_reason":"length","message":{"content":null,"reasoning":null}}],"usage":{"prompt_tokens":200,"completion_tokens":160,"cost":0.0001}}"#.utf8)
        let answer = try ChatClient.parseReply(data)
        #expect(answer.text == "" && answer.usage == Spend.Usage(promptTokens: 200, completionTokens: 160, cost: 0.0001))
    }

    @Test func onlyOpenRouterIsToldHowHardToThink() throws {
        func body(_ c: ChatClient, _ r: String?) throws -> [String: Any] {
            try #require(try c.request(system: "s", user: "u", reasoning: r).httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }
        let openRouter = ChatClient.openRouter(key: "k", model: "m")
        #expect((try body(openRouter, "low")["reasoning"] as? [String: Any])?["effort"] as? String == "low")
        #expect(try body(openRouter, nil)["reasoning"] == nil, "left to the model unless asked")
        #expect(try body(.lmStudio(server: URL(string: "http://localhost:1234")!, model: "m"), "low")["reasoning"] == nil)
    }

    @Test func openRouterIsAskedToReportTheCostAndLMStudioIsNot() throws {
        let remote = try ChatClient.openRouter(key: "k", model: "m").request(system: "s", user: "u")
        let body = try #require(remote.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect((body["usage"] as? [String: Bool]) == ["include": true])
        let local = try ChatClient.lmStudio(server: URL(string: "http://localhost:1234")!, model: "m").request(system: "s", user: "u")
        let localBody = try #require(local.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(localBody["usage"] == nil)
    }

    @Test func aServerErrorIsReportedInItsOwnWords() {
        let data = Data(#"{"error":{"message":"No endpoints found for nobody/no-such-model.","code":404}}"#.utf8)
        #expect(throws: ChatClient.Failure.self) { try ChatClient.parseReply(data) }
        do { _ = try ChatClient.parseReply(data) } catch {
            #expect("\(error)" == "the server refused: No endpoints found for nobody/no-such-model.")
        }
    }

    @Test func garbageIsReportedAsAnUnexpectedReply() {
        do { _ = try ChatClient.parseReply(Data("<html>nope".utf8)) } catch {
            #expect("\(error)".hasPrefix("unexpected reply"))
        }
    }

    @Test func modelListParsesTheSharedShape() throws {
        let data = Data(#"{"data":[{"id":"a/one","name":"One"},{"id":"b/two"}]}"#.utf8)
        #expect(try ChatClient.parseModels(data) == ["a/one", "b/two"])
    }
}

/// Real servers. LM Studio needs LEDGELINGS_LIVE=1; OpenRouter needs OPENROUTER_API_KEY.
@Suite struct ChatClientLiveTests {
    static let lmStudio = ProcessInfo.processInfo.environment["LEDGELINGS_LIVE"] == "1"
    static let openRouterKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]

    @Test(.enabled(if: lmStudio)) func lmStudioAnswers() async throws {
        let client = ChatClient.lmStudio(server: URL(string: "http://localhost:1234")!, model: "google/gemma-3-1b")
        try await client.checkModel()
        let text = try await client.reply(system: "You are a cheerful sprite. Answer in one short sentence.", user: "Say hello.").text
        print("LM Studio: \(text)")
        #expect(!text.isEmpty)
    }

    @Test(.enabled(if: lmStudio)) func lmStudioRefusesAMissingModel() async {
        let client = ChatClient.lmStudio(server: URL(string: "http://localhost:1234")!, model: "nobody/no-such-model")
        await #expect(throws: ChatClient.Failure.self) { try await client.checkModel() }
    }

    @Test(.enabled(if: openRouterKey != nil)) func openRouterAnswers() async throws {
        let client = ChatClient.openRouter(key: Self.openRouterKey!, model: "anthropic/claude-haiku-4.5")
        try await client.checkModel()
        let answer = try await client.reply(system: "You are a cheerful sprite. Answer in one short sentence.", user: "Say hello.")
        print("OpenRouter: \(answer.text) — \(String(describing: answer.usage))")
        #expect(!answer.text.isEmpty)
        #expect(answer.usage?.cost != nil, "OpenRouter prices the call when asked with usage.include")
    }

    @Test(.enabled(if: openRouterKey != nil)) func openRouterDescribesTheKey() async throws {
        let client = ChatClient.openRouter(key: Self.openRouterKey!, model: "anthropic/claude-haiku-4.5")
        let key = try await client.describeKey()
        print("OpenRouter key: \(key)")
        #expect(!key.isEmpty)
    }
}
