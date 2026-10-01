using System.Globalization;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// OpenRouter's text-to-speech: <c>POST /audio/speech</c> with a model, a voice and
/// the text, and audio back. It uses the same key as the brain.
///
/// It asks for raw PCM first: Gemini sends nothing else. MiniMax, the other way
/// round, sends only MP3; a refusal that names the other format is answered
/// with <see cref="OtherFormat"/>, and the caller remembers it per model. A PCM reply says its format in its type,
/// <c>audio/pcm;rate=24000;channels=1</c>, 16-bit little-endian samples, and gets a
/// WAV header in front so the player can play it.
///
/// The reply is audio, not JSON, so it carries no price. The price comes from
/// <c>GET /generation?id=…</c> with the id from the <c>X-Generation-Id</c> header, which
/// OpenRouter fills in a few seconds after the call.
/// </summary>
public sealed class SpeechClient
{
    /// <summary>A speech model from OpenRouter's list, with the voices it has.
    /// Dollars per million input tokens (roughly characters) and per million
    /// output tokens; most speech models charge only for the input.</summary>
    public sealed record SpeechModel(string Id, string Name, double? InputPerMillion, double? OutputPerMillion, IReadOnlyList<string> Voices)
    {
        public string PriceLabel
        {
            get
            {
                if (InputPerMillion is not double input) return L10n.Tr("price unknown");
                if (input == 0 && (OutputPerMillion ?? 0) == 0) return L10n.Tr("free");
                if (OutputPerMillion is double output && output > 0)
                    return L10n.Tr("$%.2f in · $%.2f out per M", input, output);
                return L10n.Tr("$%.2f per M chars", input);
            }
        }
    }

    /// <summary>Every request goes through this; tests hand it a pretend server.</summary>
    public static HttpClient Http { get; set; } = new() { Timeout = System.Threading.Timeout.InfiniteTimeSpan };

    public string Key { get; }
    public string Model { get; }
    /// <summary>A local server's <c>/v1</c> root (Kokoro-FastAPI, LMS Speaks…); null is OpenRouter.
    /// A local server takes no key and reports no price.</summary>
    public string? Server { get; }
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(30);

    public SpeechClient(string key, string model, string? server = null)
    {
        Key = key; Model = model; Server = server?.TrimEnd('/');
    }

    private string Base => Server ?? ChatClient.OpenRouterUrl;

    public static string ModelsUrl => ChatClient.OpenRouterUrl + "/models?output_modalities=speech";

    // MARK: Requests and replies, no network

    /// <summary>Speech speeds OpenRouter accepts.</summary>
    public const double SpeedMin = 0.25, SpeedMax = 4.0;

    /// <summary><paramref name="speed"/> null leaves it out, for models that refuse it (Qwen).</summary>
    public HttpRequestMessage Request(string text, string? voice, double? speed, string format = "pcm")
    {
        var body = new JsonObject { ["model"] = Model, ["input"] = text };
        if (!string.IsNullOrEmpty(voice)) body["voice"] = voice;
        body["response_format"] = format;
        if (speed is double s) body["speed"] = Math.Min(Math.Max(s, SpeedMin), SpeedMax);
        var request = Authorised(new HttpRequestMessage(HttpMethod.Post, Base + "/audio/speech"));
        request.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        return request;
    }

    /// <summary>Audio the player can play, or the server's complaint when it sent
    /// JSON instead. Raw PCM gets a WAV header; MP3 or WAV pass as they are.</summary>
    public static byte[] Audio(byte[] data, string? contentType)
    {
        var type = (contentType ?? "").ToLowerInvariant();
        if (type.Contains("json") || (data.Length > 0 && data[0] == (byte)'{'))
        {
            var text = Encoding.UTF8.GetString(data);
            if (ChatClient.ServerError(text) is string message) throw ChatClient.Failure.Refused(message);
            throw ChatClient.Failure.BadReply(ChatClient.Head(text, 160));
        }
        if (data.Length == 0) throw ChatClient.Failure.BadReply(L10n.Tr("no audio"));
        // Text or a web page is not a clip, whatever the status said; it would fail on every replay once kept.
        if (type.Length > 0 && !type.StartsWith("audio/", StringComparison.Ordinal) && !type.StartsWith("application/octet-stream", StringComparison.Ordinal))
            throw ChatClient.Failure.BadReply(L10n.Tr("%@, not audio: %@", type.Split(';')[0], ChatClient.Head(Encoding.UTF8.GetString(data), 120)));
        if (!type.StartsWith("audio/pcm", StringComparison.Ordinal) && !type.StartsWith("audio/l16", StringComparison.Ordinal)) return data;
        int? Parameter(string name)
        {
            foreach (var part in type.Split(';'))
            {
                var pair = part.Split('=', 2).Select(p => p.Trim()).ToArray();
                if (pair.Length == 2 && pair[0] == name && int.TryParse(pair[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var v)) return v;
            }
            return null;
        }
        return Wav(data, Parameter("rate") ?? 24_000, Parameter("channels") ?? 1);
    }

    /// <summary>A 44-byte RIFF header for 16-bit little-endian PCM, then the samples.</summary>
    public static byte[] Wav(byte[] pcm, int rate, int channels)
    {
        var count = pcm.Length % 2 == 0 ? pcm.Length : pcm.Length - 1;     // whole samples only
        using var out_ = new MemoryStream(44 + count);
        using var w = new BinaryWriter(out_);
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write((uint)(36 + count)); w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16u); w.Write((ushort)1); w.Write((ushort)channels);
        w.Write((uint)rate); w.Write((uint)(rate * channels * 2)); w.Write((ushort)(channels * 2)); w.Write((ushort)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write((uint)count);
        w.Write(pcm, 0, count);
        w.Flush();
        return out_.ToArray();
    }

    public static List<SpeechModel> ParseModels(string json)
    {
        if (ChatClient.ServerError(json) is string message) throw ChatClient.Failure.Refused(message);
        var models = new List<SpeechModel>();
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array) throw new JsonException();
            static string? Str(JsonElement e, string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
            static double? PerMillion(string? raw) =>
                double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? Math.Round(d * 1_000_000 * 1_000_000) / 1_000_000 : null;
            foreach (var row in data.EnumerateArray())
            {
                var id = Str(row, "id") ?? throw new JsonException();
                string? prompt = null, completion = null;
                if (row.TryGetProperty("pricing", out var pricing) && pricing.ValueKind == JsonValueKind.Object)
                {
                    prompt = Str(pricing, "prompt"); completion = Str(pricing, "completion");
                }
                var voices = row.TryGetProperty("supported_voices", out var v) && v.ValueKind == JsonValueKind.Array
                    ? v.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!).ToList()
                    : new List<string>();
                models.Add(new SpeechModel(id, Str(row, "name") ?? id, PerMillion(prompt), PerMillion(completion), voices));
            }
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException)
        {
            throw ChatClient.Failure.BadReply(ChatClient.Head(json, 120));
        }
        return models.OrderBy(m => m.InputPerMillion ?? double.PositiveInfinity).ThenBy(m => m.Id, StringComparer.Ordinal).ToList();
    }

    /// <summary>A local server's voice list, <c>GET /audio/voices</c>: <c>{"voices": ["af_bella", …]}</c>,
    /// or the same with objects carrying an <c>id</c> or <c>name</c>, or a bare array.</summary>
    public static List<string> ParseVoices(string json)
    {
        if (ChatClient.ServerError(json) is string message) throw ChatClient.Failure.Refused(message);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var list = root.ValueKind == JsonValueKind.Array ? root
                : root.ValueKind == JsonValueKind.Object && root.TryGetProperty("voices", out var v) && v.ValueKind == JsonValueKind.Array ? v
                : throw new JsonException();
            var ids = new List<string>();
            foreach (var entry in list.EnumerateArray())
            {
                if (entry.ValueKind == JsonValueKind.String) { ids.Add(entry.GetString()!); continue; }
                if (entry.ValueKind != JsonValueKind.Object) throw new JsonException();
                var id = entry.TryGetProperty("id", out var i) && i.ValueKind == JsonValueKind.String ? i.GetString()
                    : entry.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : null;
                if (id is not null) ids.Add(id);
            }
            return ids;
        }
        catch (JsonException) { throw ChatClient.Failure.BadReply(ChatClient.Head(json, 120)); }
    }

    /// <summary>What <c>/generation</c> says one call cost; null while OpenRouter has not filled it in yet.</summary>
    public static Spend.Usage? ParseGeneration(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("data", out var row) || row.ValueKind != JsonValueKind.Object) return null;
            static double? Number(JsonElement e, string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
            static int Int(JsonElement e, string key) => e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i) ? i : 0;
            if ((Number(row, "total_cost") ?? Number(row, "usage")) is not double cost) return null;
            return new Spend.Usage(Int(row, "tokens_prompt"), Int(row, "tokens_completion"), cost);
        }
        catch (JsonException) { return null; }
    }

    /// <summary>The format to try after a refusal of <paramref name="tried"/>, when the refusal names it:
    /// <c>MiniMax TTS only supports response_format="mp3"</c> after PCM gives MP3.</summary>
    public static string? OtherFormat(string refusal, string tried)
    {
        var other = tried == "pcm" ? "mp3" : "pcm";
        return refusal.Contains("response_format", StringComparison.Ordinal) && refusal.ToLowerInvariant().Contains("\"" + other + "\"", StringComparison.Ordinal) ? other : null;
    }

    /// <summary>True when a refusal is about the speed parameter itself:
    /// <c>Alibaba Qwen TTS does not support the speed parameter … omit it or set it to 1.</c></summary>
    public static bool RefusesSpeed(string refusal)
    {
        var r = refusal.ToLowerInvariant();
        return r.Contains("speed") && (r.Contains("not support") || r.Contains("omit") || r.Contains("unsupported"));
    }

    // MARK: Network

    /// <summary>Every speech model OpenRouter offers. Public: no key needed.</summary>
    public static async Task<List<SpeechModel>> Models()
    {
        var reply = await Send(new HttpRequestMessage(HttpMethod.Get, ModelsUrl), TimeSpan.FromSeconds(15));
        return ParseModels(Encoding.UTF8.GetString(reply.Body));
    }

    /// <summary>The local server's voices.</summary>
    public async Task<List<string>> Voices()
    {
        var reply = await Send(Authorised(new HttpRequestMessage(HttpMethod.Get, Base + "/audio/voices")), TimeSpan.FromSeconds(10));
        return ParseVoices(Encoding.UTF8.GetString(reply.Body));
    }

    /// <summary>The line as playable audio, and the id to ask its price by.</summary>
    public async Task<(byte[] Audio, string? Generation)> Speak(string text, string? voice, double? speed, string format = "pcm", CancellationToken cancel = default)
    {
        var reply = await Send(Request(text, voice, speed, format), Timeout, cancel);
        return (Audio(reply.Body, reply.Type), reply.Generation);
    }

    /// <summary>What the call cost, asked a few times because the answer lands late.
    /// Null if it never did; the call is then recorded without a price.</summary>
    public async Task<Spend.Usage?> Cost(string generation, int tries = 4)
    {
        var url = ChatClient.OpenRouterUrl + "/generation?id=" + Uri.EscapeDataString(generation);
        for (int attempt = 0; attempt < tries; attempt++)
        {
            await Task.Delay(TimeSpan.FromSeconds(attempt == 0 ? 3 : 5));
            try
            {
                var reply = await Send(Authorised(new HttpRequestMessage(HttpMethod.Get, url)), TimeSpan.FromSeconds(20));
                if (ParseGeneration(Encoding.UTF8.GetString(reply.Body)) is Spend.Usage usage) return usage;
            }
            catch (ChatClient.Failure) { }
        }
        return null;
    }

    /// <summary>What came back: the body, its type, and OpenRouter's id for the call.</summary>
    private sealed record Reply(byte[] Body, string? Type, string? Generation);

    /// <summary>One request, its reply read whole. A failed status with no JSON complaint in the body
    /// (a proxy's HTML page, a crashed server) is the server being down, not audio; a JSON complaint
    /// is left for the reader, which says what the server refused.</summary>
    private static async Task<Reply> Send(HttpRequestMessage request, TimeSpan timeout, CancellationToken cancel = default)
    {
        using var sent = request;
        using var limit = CancellationTokenSource.CreateLinkedTokenSource(cancel);
        limit.CancelAfter(timeout);
        try
        {
            using var response = await Http.SendAsync(sent, limit.Token);
            var body = await response.Content.ReadAsByteArrayAsync(limit.Token);
            if (!response.IsSuccessStatusCode && ChatClient.ServerError(Encoding.UTF8.GetString(body)) is null)
                throw ChatClient.Failure.ServerDown($"HTTP {(int)response.StatusCode}");
            var generation = response.Headers.TryGetValues("X-Generation-Id", out var ids) ? ids.FirstOrDefault() : null;
            return new Reply(body, response.Content.Headers.ContentType?.ToString(), generation);
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested) { throw; }
        catch (OperationCanceledException) { throw ChatClient.Failure.ServerDown(L10n.Tr("it took too long")); }
        catch (Exception e) when (e is not ChatClient.Failure) { throw ChatClient.Failure.ServerDown(e.Message); }
    }

    /// <summary>OpenRouter's key and headers; a local server gets neither.</summary>
    private HttpRequestMessage Authorised(HttpRequestMessage request) =>
        Server is null ? ChatClient.OpenRouter(Key, Model).Authorised(request) : request;
}
