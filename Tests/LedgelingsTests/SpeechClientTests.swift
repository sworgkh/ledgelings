import Foundation
import Testing
@testable import Ledgelings

/// OpenRouter's speech endpoint: what goes out, and what comes back, without a network.
@Suite struct SpeechClientTests {
    func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theRequestAsksForPCMWithTheKeyVoiceAndSpeed() throws {
        let request = try SpeechClient(key: "sk-or-test", model: "hexgrad/kokoro-82m").request(text: "Hello", voice: "am_puck", speed: 1.25)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/audio/speech")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
        let body = try json(request)
        #expect(body["model"] as? String == "hexgrad/kokoro-82m")
        #expect(body["input"] as? String == "Hello")
        #expect(body["voice"] as? String == "am_puck")
        #expect(body["response_format"] as? String == "pcm", "Gemini refuses anything else")
        #expect(body["speed"] as? Double == 1.25)
    }

    @Test func aModelThatRefusesAFormatIsAskedForTheOneItNames() throws {
        #expect(SpeechClient.otherFormat(after: #"MiniMax TTS only supports response_format="mp3" for streaming. Got "pcm"."#, tried: "pcm") == "mp3")
        #expect(SpeechClient.otherFormat(after: #"Gemini TTS only supports response_format="pcm". Got "mp3"."#, tried: "mp3") == "pcm")
        #expect(SpeechClient.otherFormat(after: "No such voice", tried: "pcm") == nil)
        let body = try json(try SpeechClient(key: "k", model: "m").request(text: "Hi", voice: nil, speed: 9, format: "mp3"))
        #expect(body["response_format"] as? String == "mp3")
        #expect(body["speed"] as? Double == 4, "clamped to what OpenRouter takes")
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

    @Test func rawPCMGetsAWAVHeaderFromItsContentType() throws {
        let samples = Data([0x01, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0x09])     // three samples and a stray byte
        let wav = try SpeechClient.audio(samples, contentType: "audio/pcm;rate=22050;channels=2")
        #expect(wav.count == 44 + 6)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        func u32(_ at: Int) -> Int { Int(wav[at]) | Int(wav[at + 1]) << 8 | Int(wav[at + 2]) << 16 | Int(wav[at + 3]) << 24 }
        func u16(_ at: Int) -> Int { Int(wav[at]) | Int(wav[at + 1]) << 8 }
        #expect(u32(4) == 36 + 6)                       // RIFF size
        #expect(u16(20) == 1 && u16(22) == 2)           // PCM, two channels
        #expect(u32(24) == 22_050 && u32(28) == 22_050 * 4)
        #expect(u16(32) == 4 && u16(34) == 16)          // block align, bits per sample
        #expect(u32(40) == 6 && wav.suffix(6) == samples.prefix(6))
        // No parameters: OpenRouter's usual 24 kHz mono.
        let plain = try SpeechClient.audio(samples, contentType: "audio/pcm")
        #expect(u32At(plain, 24) == 24_000 && plain[22] == 1)
    }

    func u32At(_ d: Data, _ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 | Int(d[at + 2]) << 16 | Int(d[at + 3]) << 24 }

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
