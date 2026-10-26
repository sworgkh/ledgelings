import Foundation
import Testing
@testable import LedgelingsCore

/// Dictation (§7.13): the recording's states, the request to the model, which
/// models can listen, the WAV, the meter and the microphone's pixels.
@Suite struct DictationTests {
    // MARK: The recording

    @Test func aPressStartsASecondPressSends() {
        var r = Dictation.Recorder(maxSeconds: 120)
        #expect(r.press(at: 10) == .start)
        #expect(r.isRecording && r.seconds(at: 13.5) == 3.5)
        #expect(r.press(at: 14) == .send(seconds: 4, cut: false))
        #expect(r.state == .transcribing)
        #expect(r.press(at: 15) == .none, "a press while it is written down waits for nothing")
        r.done()
        #expect(r.state == .idle && r.press(at: 20) == .start)
    }

    @Test func enterSendsEscapeSendsNothing() {
        var r = Dictation.Recorder()
        #expect(r.enter(at: 0) == .none && r.cancel() == .none, "nothing to stop")
        _ = r.press(at: 0)
        #expect(r.enter(at: 2) == .send(seconds: 2, cut: false))
        r.done()
        _ = r.press(at: 5)
        #expect(r.cancel() == .discard(tooShort: false))
        #expect(r.state == .idle)
    }

    @Test func tooShortIsThrownAway() {
        var r = Dictation.Recorder()
        _ = r.press(at: 0)
        #expect(r.press(at: 0.2) == .discard(tooShort: true))
        #expect(r.state == .idle)
        _ = r.press(at: 1)
        #expect(r.press(at: 1.5) == .send(seconds: 0.5, cut: false), "half a second is sent")
    }

    @Test func atTheLongestLengthItStopsByItself() {
        var r = Dictation.Recorder(maxSeconds: 120)
        _ = r.press(at: 0)
        #expect(r.tick(at: 119.9) == .none)
        #expect(r.tick(at: 120) == .send(seconds: 120, cut: true))
        #expect(r.tick(at: 121) == .none)
        var late = Dictation.Recorder(maxSeconds: 10)
        _ = late.press(at: 0)
        #expect(late.press(at: 30) == .send(seconds: 10, cut: false), "never more than the longest is counted")
    }

    @Test func holdingToTalkTheReleaseSends() {
        var r = Dictation.Recorder()
        #expect(r.press(at: 0, hold: true) == .start)
        #expect(r.press(at: 1, hold: true) == .none, "a key repeating while held changes nothing")
        #expect(r.release(at: 3, hold: true) == .send(seconds: 3, cut: false))
        r.done()
        _ = r.press(at: 10)
        #expect(r.release(at: 12, hold: false) == .none, "in toggle mode letting go does nothing")
        r = Dictation.Recorder()
        _ = r.press(at: 0, hold: true)
        #expect(r.release(at: 0.1, hold: true) == .discard(tooShort: true), "a tap is not a recording")
    }

    // MARK: The model

    @Test func theInstructionSaysWhatToWriteAndNeverAnswers() {
        let auto = Dictation.instruction(language: .auto, cleanUp: true)
        #expect(auto.contains("transcript only"))
        #expect(auto.contains("never answer it"))
        #expect(auto.contains("language it is spoken in"))
        #expect(auto.contains("filler sounds"))
        let russian = Dictation.instruction(language: .russian, cleanUp: false)
        #expect(russian.contains("spoken in Russian"))
        #expect(russian.contains("filler words too") && !russian.contains("filler sounds"))
    }

    @Test func theRequestCarriesTheAudioAndAsksForThePrice() throws {
        let wav = Dictation.wav([0, 1000, -1000, 0])
        let body = try Dictation.requestBody(model: "google/gemini-2.5-flash-lite", instruction: "Transcribe.", wav: wav)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "google/gemini-2.5-flash-lite")
        #expect(json["temperature"] as? Double == 0)
        #expect((json["usage"] as? [String: Any])?["include"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1 && messages[0]["role"] as? String == "user")
        let parts = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(parts.map { $0["type"] as? String } == ["text", "input_audio"])
        #expect(parts[0]["text"] as? String == "Transcribe.")
        let audio = try #require(parts[1]["input_audio"] as? [String: Any])
        #expect(audio["format"] as? String == "wav")
        #expect(Data(base64Encoded: audio["data"] as? String ?? "") == wav)
        #expect((json["max_tokens"] as? Int ?? 0) >= Dictation.maxTokens(seconds: 600))
    }

    @Test func theTranscriptComesOutOfQuotesAndFences() {
        #expect(Dictation.cleaned("  Send me the file.\n") == "Send me the file.")
        #expect(Dictation.cleaned("\"Send me the file.\"") == "Send me the file.")
        #expect(Dictation.cleaned("«Пришли файл.»") == "Пришли файл.")
        #expect(Dictation.cleaned("```text\nls -la\n```") == "ls -la")
        #expect(Dictation.cleaned("He said \"no\" and \"yes\"") == "He said \"no\" and \"yes\"", "quotes inside are kept")
        #expect(Dictation.cleaned("   ").isEmpty)
    }

    static let models = """
    {"data": [
      {"id": "google/gemini-2.5-flash-lite", "name": "Gemini 2.5 Flash Lite",
       "architecture": {"input_modalities": ["text", "image", "audio"], "output_modalities": ["text"]},
       "pricing": {"prompt": "0.0000001", "completion": "0.0000004", "audio": "0.0000003"}},
      {"id": "google/gemini-2.5-pro", "name": "Gemini 2.5 Pro",
       "architecture": {"input_modalities": ["text", "audio"], "output_modalities": ["text"]},
       "pricing": {"prompt": "0.00000125", "completion": "0.00001", "audio": "0.00000125"}},
      {"id": "google/gemini-2.5-flash-lite:batch", "name": "batch",
       "architecture": {"input_modalities": ["audio"], "output_modalities": ["text"]},
       "pricing": {"prompt": "0.00000005", "completion": "0.0000002", "audio": "0.00000015"}},
      {"id": "openrouter/auto", "name": "Auto",
       "architecture": {"input_modalities": ["text", "audio"], "output_modalities": ["text"]},
       "pricing": {"prompt": "-1", "completion": "-1"}},
      {"id": "openai/gpt-audio-mini", "name": "GPT Audio Mini",
       "architecture": {"input_modalities": ["text", "audio"], "output_modalities": ["text", "audio"]},
       "pricing": {"prompt": "0.0000006", "completion": "0.0000024", "audio": "0.0000006"}},
      {"id": "anthropic/claude", "name": "Text only",
       "architecture": {"input_modalities": ["text", "image"], "output_modalities": ["text"]},
       "pricing": {"prompt": "0.000003", "completion": "0.000015"}},
      {"id": "some/speaker", "name": "Speaks only",
       "architecture": {"input_modalities": ["audio"], "output_modalities": ["audio"]},
       "pricing": {"prompt": "0.000001", "completion": "0.000001"}}
    ]}
    """

    @Test func onlyModelsThatListenAndWriteAreOfferedCheapestFirst() throws {
        let models = try Dictation.listeningModels(in: Data(Self.models.utf8))
        #expect(models.map(\.id) == ["google/gemini-2.5-flash-lite", "openai/gpt-audio-mini", "google/gemini-2.5-pro"])
        let lite = models[0]
        // 1 920 audio tokens a minute at $0.30 a million, plus 250 written at $0.40 a million.
        #expect(abs((lite.minuteCost ?? 0) - (1_920 * 0.0000003 + 250 * 0.0000004)) < 1e-12)
        #expect(lite.priceLabel.contains("a minute"))
        #expect(models[1].minuteCost == nil && models[1].priceLabel.contains("per M audio"), "other makers count audio their own way")
        #expect(Dictation.defaultModel == "google/gemini-2.5-flash-lite")
    }

    @Test func aDictationIsPricedAsDictation() {
        let records = [Spend.Record(time: Date(), provider: "OpenRouter", model: Dictation.defaultModel,
                                    usage: Spend.Usage(promptTokens: 380, completionTokens: 22, cost: 0.00012), purpose: .dictation),
                       Spend.Record(time: Date(), provider: "OpenRouter", model: Dictation.defaultModel,
                                    usage: Spend.Usage(promptTokens: 90, completionTokens: 0, cost: 0.00003), purpose: .dictation)]
        let s = Spend.summarise(records, now: Date())
        #expect(s.byPurpose.map(\.purpose) == ["Dictation"])
        #expect(s.byPurpose[0].total.calls == 2, "an empty answer was paid for too")
        #expect(abs(s.byPurpose[0].total.cost - 0.00015) < 1e-12)
    }

    // MARK: The audio

    @Test func theWAVIsSixteenKilohertzMonoSixteenBit() {
        let wav = Dictation.wav([1, -1, 300])
        #expect(wav.count == 44 + 6)
        #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF" && String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        func u32(_ at: Int) -> UInt32 { wav[at..<(at + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
        func u16(_ at: Int) -> UInt16 { UInt16(wav[at]) | UInt16(wav[at + 1]) << 8 }
        #expect(u32(4) == 36 + 6)
        #expect(u16(20) == 1 && u16(22) == 1, "PCM, one channel")
        #expect(u32(24) == 16_000 && u32(28) == 32_000 && u16(32) == 2 && u16(34) == 16)
        #expect(u32(40) == 6)
        #expect(wav[44] == 1 && wav[45] == 0 && wav[46] == 0xFF && wav[47] == 0xFF && wav[48] == 44 && wav[49] == 1)
    }

    @Test func theMeterFollowsTheVoiceAndSinksSlowly() {
        #expect(Dictation.level(rms: 0) == 0)
        #expect(Dictation.level(rms: 0.001) < 0.1, "a quiet room barely moves it")
        #expect(abs(Dictation.level(rms: 0.0316) - 0.5) < 0.01, "-30 dB is half way")
        #expect(Dictation.level(rms: 1) == 1)
        #expect(Dictation.rms([0.5, -0.5, 0.5, -0.5]) == 0.5)
        #expect(Dictation.meter(previous: 0.2, heard: 0.9, dt: 0.05) == 0.9, "up at once")
        #expect(abs(Dictation.meter(previous: 0.9, heard: 0, dt: 0.05) - 0.82) < 1e-9, "down slowly")
        #expect(Dictation.bars(level: 0) == 0 && Dictation.bars(level: 0.1) == 1 && Dictation.bars(level: 0.5) == 3 && Dictation.bars(level: 1) == 5)
    }

    // MARK: Words on screen

    @Test func theClockAndTheBubble() {
        #expect(Dictation.clock(7.9) == "0:07" && Dictation.clock(119) == "1:59" && Dictation.clock(-1) == "0:00")
        #expect(Dictation.copiedBubble("Send me the file") == "Copied: Send me the file")
        #expect(Dictation.copiedBubble("Remind me to water the ferns on Friday please") == "Copied: Remind me to water the ferns…")
        #expect(Dictation.copiedBubble(String(repeating: "a", count: 60)).count <= "Copied: ".count + 41)
        #expect(Dictation.Trouble.noKey.line.contains("OpenRouter key"))
        #expect(!Dictation.Trouble.microphoneRefused.line.isEmpty && !Dictation.Trouble.network("offline").line.isEmpty)
    }

    // MARK: The microphone

    @Test func theMicrophoneIsDrawnInBlockysStyle() {
        let mic = Dictation.microphone(bars: 3)
        #expect(mic.count == 14 && mic.allSatisfy { $0.count == 18 }, "the letter's 18×14 cell")
        // The head: a 1-pixel outline all round, light along the top and left, shade along the bottom and right.
        #expect((1...7).allSatisfy { mic[0][$0] == .outline && mic[6][$0] == .outline })
        #expect((0...6).allSatisfy { mic[$0][1] == .outline && mic[$0][7] == .outline })
        #expect(mic[1][3] == .light && mic[3][2] == .light && mic[5][4] == .shade && mic[3][6] == .shade)
        #expect(mic[3][4] == .grille)
        // The bars: five, rising left to right, the first three lit.
        let columns = [9, 11, 13, 15, 17]
        let heights = columns.map { c in (0..<14).filter { mic[$0][c] == .lit || mic[$0][c] == .unlit }.count }
        #expect(heights == [2, 4, 6, 8, 10])
        #expect(columns.map { mic[13][$0] } == [.lit, .lit, .lit, .unlit, .unlit])
        let quiet = Dictation.microphone(bars: 0)
        #expect(quiet.joined().allSatisfy { $0 != .lit })
        let thinking = Dictation.microphone(bars: 0, thinking: true, tick: 1)
        #expect(thinking[8][12] == .lit && thinking[8][9] == .unlit && thinking[8][15] == .unlit, "the second of three dots")
    }
}
