import Foundation
import Testing
@testable import Ledgelings

/// OpenRouter's speech endpoint: what goes out, and what comes back, without a network.
@Suite struct SpeechClientTests {
    func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theRequestAsksForMP3WithTheKeyVoiceAndSpeed() throws {
        let request = try SpeechClient(key: "sk-or-test", model: "hexgrad/kokoro-82m").request(text: "Hello", voice: "am_puck", speed: 1.25)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/audio/speech")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
        let body = try json(request)
        #expect(body["model"] as? String == "hexgrad/kokoro-82m")
        #expect(body["input"] as? String == "Hello")
        #expect(body["voice"] as? String == "am_puck")
        #expect(body["response_format"] as? String == "mp3")
        #expect(body["speed"] as? Double == 1.25)
    }

    @Test func anEmptyVoiceIsLeftForTheModelToChoose() throws {
        let request = try SpeechClient(key: "k", model: "m").request(text: "Hi", voice: "", speed: 1)
        let body = try json(request)
        #expect(body["voice"] == nil)
    }

    @Test func audioComesBackAsIsAndAComplaintBecomesAnError() throws {
        let mp3 = Data([0xFF, 0xF3, 0x44, 0xC4])
        #expect(try SpeechClient.audio(mp3, contentType: "audio/mpeg") == mp3)
        #expect(throws: ChatClient.Failure.self) {
            try SpeechClient.audio(Data(#"{"error":{"message":"No voice","code":400}}"#.utf8), contentType: "application/json")
        }
        #expect(throws: ChatClient.Failure.self) { try SpeechClient.audio(Data(), contentType: "audio/mpeg") }
    }

    @Test func speechModelsComeWithVoicesCheapestFirst() throws {
        let models = try SpeechClient.parseModels(Data("""
        {"data":[
          {"id":"hexgrad/kokoro-82m","name":"Kokoro","pricing":{"prompt":"0.000004","completion":"0"},"supported_voices":["af_bella","am_puck"]},
          {"id":"deepgram/flux-tts:free","name":"Flux (free)","pricing":{"prompt":"0","completion":"0"},"supported_voices":["flux-kit-en"]},
          {"id":"fish-audio/s1","pricing":{"prompt":"0.000015","completion":"0"},"supported_voices":null}
        ]}
        """.utf8))
        #expect(models.map(\.id) == ["deepgram/flux-tts:free", "hexgrad/kokoro-82m", "fish-audio/s1"])
        #expect(models[0].priceLabel == "free")
        #expect(models[1].voices == ["af_bella", "am_puck"])
        #expect(models[1].priceLabel == "$4.00 per M chars")
        #expect(models[2].voices.isEmpty && models[2].name == "fish-audio/s1")
    }

    @Test func thePriceOfACallIsReadFromItsGeneration() {
        let usage = SpeechClient.parseGeneration(Data(#"{"data":{"model":"hexgrad/kokoro-82m","tokens_prompt":11,"tokens_completion":null,"usage":0.00002542,"api_type":"tts"}}"#.utf8))
        #expect(usage?.cost == 0.00002542)
        #expect(usage?.promptTokens == 11)
        #expect(SpeechClient.parseGeneration(Data(#"{"error":{"message":"Generation not found","code":404}}"#.utf8)) == nil)
    }
}
