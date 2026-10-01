using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using Ledgelings.Native;

namespace Ledgelings.Tests;

/// <summary>A pretend local speech server at <c>line-voices.test</c>, counting what it is asked to say.</summary>
internal sealed class FakeSpeechServer : HttpMessageHandler
{
    private readonly object gate = new();
    private readonly List<string> spoken = new();
    public IReadOnlyList<string> Spoken { get { lock (gate) return spoken.ToList(); } }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        if (request.RequestUri!.AbsolutePath.EndsWith("audio/voices", StringComparison.Ordinal))
            return Reply(Encoding.UTF8.GetBytes("{\"voices\":[\"af_bella\"]}"), "application/json");
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
        var text = JsonDocument.Parse(body).RootElement.GetProperty("input").GetString() ?? "";
        lock (gate) spoken.Add(text);
        return Reply(Encoding.UTF8.GetBytes("RIFF-" + text), "audio/wav");
    }

    private static HttpResponseMessage Reply(byte[] body, string type)
    {
        var content = new ByteArrayContent(body);
        content.Headers.TryAddWithoutValidation("Content-Type", type);
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
    }
}

/// <summary>The built-in lines are made once in each voice, then played from disk.</summary>
[Collection("speech server")]
public sealed class LineVoicesTests : IDisposable
{
    private readonly string dir = Path.Combine(Path.GetTempPath(), "ledgelings-line-voices-" + Guid.NewGuid());
    private readonly FakeSpeechServer server = new();
    private readonly HttpClient before = SpeechClient.Http;
    private readonly AppSettings settings;

    public LineVoicesTests()
    {
        settings = new AppSettings(new MemorySettingsStore(), new MemorySecretStore())
        {
            VoiceEngine = VoiceEngine.Local,
            LocalVoiceServer = "http://line-voices.test",
        };
        SpeechClient.Http = new HttpClient(server);
    }

    public void Dispose()
    {
        SpeechClient.Http = before;
        try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private Voice MakeVoice() =>
        new(settings, new SpendLedger(Path.Combine(dir, "spend")), archive: Path.Combine(dir, "voices"), lineArchive: Path.Combine(dir, "line-voices"));

    [Fact]
    public async Task ABuiltInLineIsMadeOnceAndThenPlayedFromDiskEvenAfterARelaunch()
    {
        var first = await MakeVoice().Sound("Move that cursor, Zed.", "Blocky", builtIn: true);
        Assert.NotNull(first);
        Assert.False(first!.Value.Kept);
        Assert.Equal(new[] { "Move that cursor, Zed." }, server.Spoken);
        var again = await MakeVoice().Sound("Move that cursor, Zed.", "Blocky", builtIn: true);
        Assert.NotNull(again);
        Assert.True(again!.Value.Kept);                              // the saved copy, from a fresh start
        Assert.Equal(first.Value.Audio, again.Value.Audio);
        Assert.Single(server.Spoken);                                // the server was not asked twice
        Assert.Single(MakeVoice().LineClips);
    }

    [Fact]
    public async Task AModelsLineAndAnySpeechWithSavingOffAreMadeEveryTime()
    {
        var voice = MakeVoice();
        await voice.Sound("Something new.", "Blocky", builtIn: false);
        await voice.Sound("Something new.", "Blocky", builtIn: false);
        Assert.Equal(2, server.Spoken.Count);                        // a model's words rarely come round again
        Assert.Empty(voice.LineClips);
        settings.ReuseLineVoices = false;
        await voice.Sound("Hello.", "Blocky", builtIn: true);
        await voice.Sound("Hello.", "Blocky", builtIn: true);
        Assert.Equal(4, server.Spoken.Count);
        Assert.Empty(voice.LineClips);
    }

    [Fact]
    public async Task ClearingForgetsTheSavedLines()
    {
        var voice = MakeVoice();
        await voice.Sound("Hello.", "Blocky", builtIn: true);
        voice.ClearLineArchive();
        Assert.Empty(voice.LineClips);
        Assert.Empty(MakeVoice().LineClips);
        var again = await voice.Sound("Hello.", "Blocky", builtIn: true);
        Assert.False(again!.Value.Kept);
        Assert.Equal(2, server.Spoken.Count);
    }
}
