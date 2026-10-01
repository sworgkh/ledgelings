using System.Text;
using System.Text.Json;

namespace Ledgelings.Tests;

/// <summary>OpenRouter's speech endpoint: what goes out, and what comes back, without a network.</summary>
public class SpeechClientTests
{
    private static JsonElement Json(System.Net.Http.HttpRequestMessage request) =>
        JsonDocument.Parse(request.Content!.ReadAsStringAsync().Result).RootElement;

    private static string? Header(System.Net.Http.HttpRequestMessage request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? string.Join(",", values) : null;

    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    [Fact]
    public void TheRequestAsksForPCMWithTheKeyVoiceAndSpeed()
    {
        var request = new SpeechClient("sk-or-test", "hexgrad/kokoro-82m").Request("Hello", "am_puck", 1.25);
        Assert.Equal("https://openrouter.ai/api/v1/audio/speech", request.RequestUri!.ToString());
        Assert.Equal("POST", request.Method.Method);
        Assert.Equal("Bearer sk-or-test", request.Headers.Authorization?.ToString());
        var body = Json(request);
        Assert.Equal("hexgrad/kokoro-82m", body.GetProperty("model").GetString());
        Assert.Equal("Hello", body.GetProperty("input").GetString());
        Assert.Equal("am_puck", body.GetProperty("voice").GetString());
        Assert.Equal("pcm", body.GetProperty("response_format").GetString());      // Gemini refuses anything else
        Assert.Equal(1.25, body.GetProperty("speed").GetDouble());
    }

    [Fact]
    public void AModelThatRefusesAFormatIsAskedForTheOneItNames()
    {
        Assert.Equal("mp3", SpeechClient.OtherFormat("MiniMax TTS only supports response_format=\"mp3\" for streaming. Got \"pcm\".", "pcm"));
        Assert.Equal("pcm", SpeechClient.OtherFormat("Gemini TTS only supports response_format=\"pcm\". Got \"mp3\".", "mp3"));
        Assert.Null(SpeechClient.OtherFormat("No such voice", "pcm"));
        var body = Json(new SpeechClient("k", "m").Request("Hi", null, 9, "mp3"));
        Assert.Equal("mp3", body.GetProperty("response_format").GetString());
        Assert.Equal(4, body.GetProperty("speed").GetDouble());       // clamped to what OpenRouter takes
    }

    [Fact]
    public void AModelThatRefusesSpeedIsAskedWithoutIt()
    {
        Assert.True(SpeechClient.RefusesSpeed("Alibaba Qwen TTS does not support the speed parameter. Got 0.56; omit it or set it to 1."));
        Assert.False(SpeechClient.RefusesSpeed("No such voice"));
        Assert.False(SpeechClient.RefusesSpeed("only supports response_format=\"mp3\""));
        var body = Json(new SpeechClient("k", "qwen/qwen-audio-3.0-tts-flash").Request("Hi", null, null));
        Assert.False(body.TryGetProperty("speed", out _));
    }

    [Fact]
    public void ALocalServerIsAskedWithoutAKeyOrOpenRoutersHeaders()
    {
        var local = new SpeechClient("", "kokoro", "http://localhost:8880/v1");
        var request = local.Request("Hi", "af_bella", 1, "wav");
        Assert.Equal("http://localhost:8880/v1/audio/speech", request.RequestUri!.ToString());
        Assert.Null(request.Headers.Authorization);
        Assert.Null(Header(request, "X-Title"));
        Assert.Equal("wav", Json(request).GetProperty("response_format").GetString());
    }

    [Fact]
    public void ALocalServersVoicesAreReadInAnyOfItsShapes()
    {
        Assert.Equal(new[] { "af_bella", "am_puck" }, SpeechClient.ParseVoices("{\"voices\":[\"af_bella\",\"am_puck\"]}"));
        Assert.Equal(new[] { "a", "b" }, SpeechClient.ParseVoices("{\"voices\":[{\"id\":\"a\"},{\"name\":\"b\"}]}"));
        Assert.Equal(new[] { "x", "y" }, SpeechClient.ParseVoices("[\"x\",\"y\"]"));
        Assert.Throws<ChatClient.Failure>(() => SpeechClient.ParseVoices("<html>"));
    }

    [Fact]
    public void AnEmptyVoiceIsLeftForTheModelToChoose()
    {
        var body = Json(new SpeechClient("k", "m").Request("Hi", "", 1));
        Assert.False(body.TryGetProperty("voice", out _));
    }

    [Fact]
    public void AudioComesBackAsIsAndAComplaintBecomesAnError()
    {
        var mp3 = new byte[] { 0xFF, 0xF3, 0x44, 0xC4 };
        Assert.Equal(mp3, SpeechClient.Audio(mp3, "audio/mpeg"));
        var refused = Assert.Throws<ChatClient.Failure>(() => SpeechClient.Audio(Bytes("{\"error\":{\"message\":\"No voice\",\"code\":400}}"), "application/json"));
        Assert.Equal("No voice", refused.Refusal);
        Assert.Throws<ChatClient.Failure>(() => SpeechClient.Audio(Array.Empty<byte>(), "audio/mpeg"));
        // A proxy's error page is not a clip, and must never be kept as one.
        Assert.Throws<ChatClient.Failure>(() => SpeechClient.Audio(Bytes("<html>502 Bad Gateway</html>"), "text/html; charset=utf-8"));
        Assert.Equal(mp3, SpeechClient.Audio(mp3, "application/octet-stream"));
    }

    private static int U32(byte[] d, int at) => d[at] | d[at + 1] << 8 | d[at + 2] << 16 | d[at + 3] << 24;
    private static int U16(byte[] d, int at) => d[at] | d[at + 1] << 8;

    [Fact]
    public void RawPCMGetsAWAVHeaderFromItsContentType()
    {
        var samples = new byte[] { 0x01, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0x09 };     // three samples and a stray byte
        var wav = SpeechClient.Audio(samples, "audio/pcm;rate=22050;channels=2");
        Assert.Equal(44 + 6, wav.Length);
        Assert.Equal("RIFF", Encoding.ASCII.GetString(wav, 0, 4));
        Assert.Equal("WAVEfmt ", Encoding.ASCII.GetString(wav, 8, 8));
        Assert.Equal(36 + 6, U32(wav, 4));                        // RIFF size
        Assert.True(U16(wav, 20) == 1 && U16(wav, 22) == 2);      // PCM, two channels
        Assert.True(U32(wav, 24) == 22_050 && U32(wav, 28) == 22_050 * 4);
        Assert.True(U16(wav, 32) == 4 && U16(wav, 34) == 16);     // block align, bits per sample
        Assert.Equal(6, U32(wav, 40));
        Assert.Equal(samples.Take(6), wav.Skip(44));
        // No parameters: OpenRouter's usual 24 kHz mono.
        var plain = SpeechClient.Audio(samples, "audio/pcm");
        Assert.True(U32(plain, 24) == 24_000 && plain[22] == 1);
    }

    [Fact]
    public void SpeechModelsComeWithVoicesCheapestFirst()
    {
        var models = SpeechClient.ParseModels("""
        {"data":[
          {"id":"hexgrad/kokoro-82m","name":"Kokoro","pricing":{"prompt":"0.000004","completion":"0"},"supported_voices":["af_bella","am_puck"]},
          {"id":"deepgram/flux-tts:free","name":"Flux (free)","pricing":{"prompt":"0","completion":"0"},"supported_voices":["flux-kit-en"]},
          {"id":"fish-audio/s1","pricing":{"prompt":"0.000015","completion":"0"},"supported_voices":null}
        ]}
        """);
        Assert.Equal(new[] { "deepgram/flux-tts:free", "hexgrad/kokoro-82m", "fish-audio/s1" }, models.Select(m => m.Id));
        Assert.Equal("free", models[0].PriceLabel);
        Assert.Equal(new[] { "af_bella", "am_puck" }, models[1].Voices);
        Assert.Equal("$4.00 per M chars", models[1].PriceLabel);
        Assert.True(models[2].Voices.Count == 0 && models[2].Name == "fish-audio/s1");
    }

    [Fact]
    public void ThePriceOfACallIsReadFromItsGeneration()
    {
        var usage = SpeechClient.ParseGeneration("{\"data\":{\"model\":\"hexgrad/kokoro-82m\",\"tokens_prompt\":11,\"tokens_completion\":null,\"usage\":0.00002542,\"api_type\":\"tts\"}}");
        Assert.Equal(0.00002542, usage?.Cost);
        Assert.Equal(11, usage?.PromptTokens);
        Assert.Null(SpeechClient.ParseGeneration("{\"error\":{\"message\":\"Generation not found\",\"code\":404}}"));
    }

    [Fact]
    public void ATapeSpeedsAClipUpAndRaisesItInOneGo()
    {
        var samples = Enumerable.Range(0, 1000).Select(i => (short)(i * 10)).ToArray();
        var pcm = new WaveTape.Pcm(24_000, 1, samples);
        var back = WaveTape.Read(WaveTape.Write(pcm));
        Assert.NotNull(back);
        Assert.Equal(samples, back!.Samples);
        var fast = WaveTape.Speed(pcm, 2);
        Assert.Equal(500, fast.Frames);
        Assert.Equal(24_000, fast.Rate);                       // its own rate: played back, it is twice as high
        Assert.Equal(pcm.Duration / 2, fast.Duration, 3);
        Assert.Equal(samples[2], fast.Samples[1]);
        Assert.Same(pcm, WaveTape.Speed(pcm, 1));
        Assert.Null(WaveTape.Read(new byte[] { 0xFF, 0xF3, 0x44, 0xC4 }));       // MP3 is not a tape
    }
}
