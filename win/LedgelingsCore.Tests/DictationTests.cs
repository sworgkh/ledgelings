using System.Text.Json;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.13, the Mac's <c>DictationTests.swift</c>: the recording's states, the request to the model,
/// which models can listen, the WAV, the meter and the microphone's pixels.</summary>
public class DictationTests
{
    // The recording

    [Fact]
    public void APressStartsASecondPressSends()
    {
        var r = new Dictation.Recorder(120);
        Assert.IsType<Dictation.Step.Start>(r.Press(10));
        Assert.True(r.IsRecording);
        Assert.Equal(3.5, r.Seconds(13.5));
        Assert.Equal(new Dictation.Step.Send(4, false), r.Press(14));
        Assert.Equal(Dictation.Stage.Transcribing, r.State);
        Assert.IsType<Dictation.Step.None>(r.Press(15));
        r.Done();
        Assert.IsType<Dictation.Step.Start>(r.Press(20));
    }

    [Fact]
    public void EnterSendsEscapeSendsNothing()
    {
        var r = new Dictation.Recorder();
        Assert.IsType<Dictation.Step.None>(r.Enter(0));
        Assert.IsType<Dictation.Step.None>(r.Cancel());
        r.Press(0);
        Assert.Equal(new Dictation.Step.Send(2, false), r.Enter(2));
        r.Done();
        r.Press(5);
        Assert.Equal(new Dictation.Step.Discard(false), r.Cancel());
        Assert.Equal(Dictation.Stage.Idle, r.State);
    }

    [Fact]
    public void TooShortIsThrownAway()
    {
        var r = new Dictation.Recorder();
        r.Press(0);
        Assert.Equal(new Dictation.Step.Discard(true), r.Press(0.2));
        Assert.Equal(Dictation.Stage.Idle, r.State);
        r.Press(1);
        Assert.Equal(new Dictation.Step.Send(0.5, false), r.Press(1.5));
    }

    [Fact]
    public void AtTheLongestLengthItStopsByItself()
    {
        var r = new Dictation.Recorder(120);
        r.Press(0);
        Assert.IsType<Dictation.Step.None>(r.Tick(119.9));
        Assert.Equal(new Dictation.Step.Send(120, true), r.Tick(120));
        Assert.IsType<Dictation.Step.None>(r.Tick(121));
        var late = new Dictation.Recorder(10);
        late.Press(0);
        Assert.Equal(new Dictation.Step.Send(10, false), late.Press(30));
    }

    [Fact]
    public void HoldingToTalkTheReleaseSends()
    {
        var r = new Dictation.Recorder();
        Assert.IsType<Dictation.Step.Start>(r.Press(0, hold: true));
        Assert.IsType<Dictation.Step.None>(r.Press(1, hold: true));
        Assert.Equal(new Dictation.Step.Send(3, false), r.Release(3, hold: true));
        r.Done();
        r.Press(10);
        Assert.IsType<Dictation.Step.None>(r.Release(12, hold: false));
        r = new Dictation.Recorder();
        r.Press(0, hold: true);
        Assert.Equal(new Dictation.Step.Discard(true), r.Release(0.1, hold: true));
    }

    // The model

    [Fact]
    public void TheInstructionSaysWhatToWriteAndNeverAnswers()
    {
        var auto = Dictation.Instruction(Dictation.Spoken.Auto, true);
        Assert.Contains("transcript only", auto);
        Assert.Contains("never answer it", auto);
        Assert.Contains("language it is spoken in", auto);
        Assert.Contains("filler sounds", auto);
        var russian = Dictation.Instruction(Dictation.Spoken.Russian, false);
        Assert.Contains("spoken in Russian", russian);
        Assert.Contains("filler words too", russian);
        Assert.DoesNotContain("filler sounds", russian);
        Assert.Equal(Dictation.Spoken.Russian, Dictation.SpokenFrom("russian"));
        Assert.Null(Dictation.SpokenFrom("klingon"));
    }

    [Fact]
    public void TheRequestCarriesTheAudioAndAsksForThePrice()
    {
        var wav = Dictation.Wav(new short[] { 0, 1000, -1000, 0 });
        using var doc = JsonDocument.Parse(Dictation.RequestBody("google/gemini-2.5-flash-lite", "Transcribe.", wav));
        var json = doc.RootElement;
        Assert.Equal("google/gemini-2.5-flash-lite", json.GetProperty("model").GetString());
        Assert.Equal(0, json.GetProperty("temperature").GetDouble());
        Assert.True(json.GetProperty("usage").GetProperty("include").GetBoolean());
        var messages = json.GetProperty("messages");
        Assert.Equal(1, messages.GetArrayLength());
        Assert.Equal("user", messages[0].GetProperty("role").GetString());
        var parts = messages[0].GetProperty("content");
        Assert.Equal(new[] { "text", "input_audio" }, parts.EnumerateArray().Select(p => p.GetProperty("type").GetString()));
        Assert.Equal("Transcribe.", parts[0].GetProperty("text").GetString());
        var audio = parts[1].GetProperty("input_audio");
        Assert.Equal("wav", audio.GetProperty("format").GetString());
        Assert.Equal(wav, Convert.FromBase64String(audio.GetProperty("data").GetString()!));
        Assert.True(json.GetProperty("max_tokens").GetInt32() >= Dictation.MaxTokens(600));
    }

    [Fact]
    public void TheTranscriptComesOutOfQuotesAndFences()
    {
        Assert.Equal("Send me the file.", Dictation.Cleaned("  Send me the file.\n"));
        Assert.Equal("Send me the file.", Dictation.Cleaned("\"Send me the file.\""));
        Assert.Equal("Пришли файл.", Dictation.Cleaned("«Пришли файл.»"));
        Assert.Equal("ls -la", Dictation.Cleaned("```text\nls -la\n```"));
        Assert.Equal("He said \"no\" and \"yes\"", Dictation.Cleaned("He said \"no\" and \"yes\""));
        Assert.Equal("", Dictation.Cleaned("   "));
    }

    private const string Models = """
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
    """;

    [Fact]
    public void OnlyModelsThatListenAndWriteAreOfferedCheapestFirst()
    {
        var models = Dictation.ListeningModels(Models);
        Assert.Equal(new[] { "google/gemini-2.5-flash-lite", "openai/gpt-audio-mini", "google/gemini-2.5-pro" }, models.Select(m => m.Id));
        var lite = models[0];
        Assert.True(Math.Abs((lite.MinuteCost ?? 0) - (1_920 * 0.0000003 + 250 * 0.0000004)) < 1e-12);
        Assert.Contains("a minute", lite.PriceLabel);
        Assert.Null(models[1].MinuteCost);
        Assert.Contains("per M audio", models[1].PriceLabel);
        Assert.Equal("google/gemini-2.5-flash-lite", Dictation.DefaultModel);
    }

    [Fact]
    public void ADictationIsPricedAsDictation()
    {
        var now = DateTimeOffset.Now;
        var records = new[]
        {
            new Spend.Record(now, "OpenRouter", Dictation.DefaultModel, new Spend.Usage(380, 22, 0.00012), Spend.Purpose.Dictation),
            new Spend.Record(now, "OpenRouter", Dictation.DefaultModel, new Spend.Usage(90, 0, 0.00003), Spend.Purpose.Dictation),
        };
        var s = Spend.Summarise(records, now);
        Assert.Equal(new[] { "Dictation" }, s.ByPurpose.Select(p => p.Purpose));
        Assert.Equal(2, s.ByPurpose[0].Total.Calls);
        Assert.True(Math.Abs(s.ByPurpose[0].Total.Cost - 0.00015) < 1e-12);
        Assert.Equal("dictation", Spend.Purpose.Dictation.Raw());
    }

    // The audio

    [Fact]
    public void TheWavIsSixteenKilohertzMonoSixteenBit()
    {
        var wav = Dictation.Wav(new short[] { 1, -1, 300 });
        Assert.Equal(44 + 6, wav.Length);
        Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(wav, 0, 4));
        Assert.Equal("WAVE", System.Text.Encoding.ASCII.GetString(wav, 8, 4));
        Assert.Equal(36u + 6, BitConverter.ToUInt32(wav, 4));
        Assert.Equal(1, BitConverter.ToUInt16(wav, 20));
        Assert.Equal(1, BitConverter.ToUInt16(wav, 22));
        Assert.Equal(16_000u, BitConverter.ToUInt32(wav, 24));
        Assert.Equal(32_000u, BitConverter.ToUInt32(wav, 28));
        Assert.Equal(2, BitConverter.ToUInt16(wav, 32));
        Assert.Equal(16, BitConverter.ToUInt16(wav, 34));
        Assert.Equal(6u, BitConverter.ToUInt32(wav, 40));
        Assert.Equal(new byte[] { 1, 0, 0xFF, 0xFF, 44, 1 }, wav[44..]);
    }

    [Fact]
    public void TheMeterFollowsTheVoiceAndSinksSlowly()
    {
        Assert.Equal(0, Dictation.Level(0));
        Assert.True(Dictation.Level(0.001) < 0.1);
        Assert.True(Math.Abs(Dictation.Level(0.0316) - 0.5) < 0.01);
        Assert.Equal(1, Dictation.Level(1));
        Assert.Equal(0.5, Dictation.Rms(new float[] { 0.5f, -0.5f, 0.5f, -0.5f }), 6);
        Assert.Equal(0.9, Dictation.Meter(0.2, 0.9, 0.05));
        Assert.True(Math.Abs(Dictation.Meter(0.9, 0, 0.05) - 0.82) < 1e-9);
        Assert.Equal(new[] { 0, 1, 3, 5 }, new[] { 0, 0.1, 0.5, 1 }.Select(Dictation.Bars));
    }

    // Words on screen

    [Fact]
    public void TheClockAndTheBubble()
    {
        Assert.Equal("0:07", Dictation.Clock(7.9));
        Assert.Equal("1:59", Dictation.Clock(119));
        Assert.Equal("0:00", Dictation.Clock(-1));
        Assert.Equal("Copied: Send me the file", Dictation.CopiedBubble("Send me the file"));
        Assert.Equal("Copied: Remind me to water the ferns…", Dictation.CopiedBubble("Remind me to water the ferns on Friday please"));
        Assert.True(Dictation.CopiedBubble(new string('a', 60)).Length <= "Copied: ".Length + 41);
        Assert.Contains("OpenRouter key", new Dictation.Trouble(Dictation.TroubleKind.NoKey).Line);
        Assert.NotEmpty(new Dictation.Trouble(Dictation.TroubleKind.Network, "offline").Line);
    }

    // The microphone

    [Fact]
    public void TheMicrophoneIsDrawnInBlockysStyle()
    {
        var mic = Dictation.Microphone(3);
        Assert.Equal(14, mic.GetLength(0));
        Assert.Equal(18, mic.GetLength(1));
        for (int c = 1; c <= 7; c++) { Assert.Equal(Dictation.Ink.Outline, mic[0, c]); Assert.Equal(Dictation.Ink.Outline, mic[6, c]); }
        for (int r = 0; r <= 6; r++) { Assert.Equal(Dictation.Ink.Outline, mic[r, 1]); Assert.Equal(Dictation.Ink.Outline, mic[r, 7]); }
        Assert.Equal(Dictation.Ink.Light, mic[1, 3]);
        Assert.Equal(Dictation.Ink.Light, mic[3, 2]);
        Assert.Equal(Dictation.Ink.Shade, mic[5, 4]);
        Assert.Equal(Dictation.Ink.Shade, mic[3, 6]);
        Assert.Equal(Dictation.Ink.Grille, mic[3, 4]);
        var columns = new[] { 9, 11, 13, 15, 17 };
        Assert.Equal(new[] { 2, 4, 6, 8, 10 }, columns.Select(c => Enumerable.Range(0, 14).Count(r => mic[r, c] is Dictation.Ink.Lit or Dictation.Ink.Unlit)));
        Assert.Equal(new[] { Dictation.Ink.Lit, Dictation.Ink.Lit, Dictation.Ink.Lit, Dictation.Ink.Unlit, Dictation.Ink.Unlit }, columns.Select(c => mic[13, c]));
        var quiet = Dictation.Microphone(0);
        Assert.DoesNotContain(Dictation.Ink.Lit, quiet.Cast<Dictation.Ink>());
        var thinking = Dictation.Microphone(0, thinking: true, tick: 1);
        Assert.Equal(Dictation.Ink.Lit, thinking[8, 12]);
        Assert.Equal(Dictation.Ink.Unlit, thinking[8, 9]);
        Assert.Equal(Dictation.Ink.Unlit, thinking[8, 15]);
    }
}
