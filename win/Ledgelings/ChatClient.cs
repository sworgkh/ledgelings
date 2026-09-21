using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// One language model behind an OpenAI-style chat endpoint. LM Studio on this
/// PC and OpenRouter on the internet both speak that dialect, so one client
/// serves both; only the address, the key and the model differ.
///
/// One trap this guards against: ask LM Studio for a model that is not
/// installed and it silently answers with whatever model happens to be loaded.
/// So <see cref="CheckModel"/> compares the id against the server's list before any
/// line is asked for.
/// </summary>
public sealed partial class ChatClient
{
    public enum Provider { LmStudio, OpenRouter }

    public static string Title(Provider provider) => provider == Provider.LmStudio ? "LM Studio" : "OpenRouter";

    public sealed class Failure : Exception
    {
        public Failure(string message) : base(message) { }
        public static Failure ServerDown(string why) => new("the server is not answering: " + why);
        public static Failure ModelMissing(string model, IReadOnlyList<string> available) =>
            new($"model {model} is not available" + (available.Count == 0 ? "" : " (have: " + string.Join(", ", available.Take(8)) + ")"));
        public static Failure Refused(string message) => new("the server refused: " + message);
        public static Failure BadReply(string what) => new("unexpected reply: " + what);
    }

    public const string OpenRouterUrl = "https://openrouter.ai/api/v1";

    private static readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(60) };

    public Provider Kind { get; }
    /// <summary>The <c>/v1</c> root: <c>http://localhost:1234/v1</c> or <c>https://openrouter.ai/api/v1</c>.</summary>
    public string BaseUrl { get; }
    public string? ApiKey { get; }
    public string Model { get; }
    public string ProviderTitle => Title(Kind);

    private ChatClient(Provider kind, string baseUrl, string? apiKey, string model)
    {
        Kind = kind; BaseUrl = baseUrl.TrimEnd('/'); ApiKey = apiKey; Model = model;
    }

    public static ChatClient LmStudio(Uri server, string model) => new(Provider.LmStudio, server.ToString().TrimEnd('/') + "/v1", null, model);

    public static ChatClient OpenRouter(string key, string model) => new(Provider.OpenRouter, OpenRouterUrl, key, model);

    /// <summary>Enough to read OpenRouter's public model list; it needs no key.</summary>
    public static readonly ChatClient OpenRouterPublic = new(Provider.OpenRouter, OpenRouterUrl, null, "");

    public string ModelsUrl => BaseUrl + "/models";

    // MARK: Requests and replies, no network

    public HttpRequestMessage Request(string system, string user, int maxTokens = 80, double temperature = 0.9)
    {
        var body = new JsonObject
        {
            ["model"] = Model,
            ["messages"] = new JsonArray(
                new JsonObject { ["role"] = "system", ["content"] = system },
                new JsonObject { ["role"] = "user", ["content"] = user }),
            ["temperature"] = temperature,
            ["max_tokens"] = maxTokens,
        };
        // OpenRouter puts the price of the call in the reply when asked.
        if (Kind == Provider.OpenRouter) body["usage"] = new JsonObject { ["include"] = true };
        var request = Authorised(new HttpRequestMessage(HttpMethod.Post, BaseUrl + "/chat/completions"));
        request.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        return request;
    }

    /// <summary>The text of a completion and, when the server reported it, what it used.</summary>
    public sealed record Answer(string Text, Spend.Usage? Usage);

    public static Answer ParseReply(string json)
    {
        if (ServerError(json) is string message) throw Failure.Refused(message);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (!root.TryGetProperty("choices", out var choices) || choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0)
                throw Failure.BadReply(Head(json, 160));
            var content = choices[0].GetProperty("message").TryGetProperty("content", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString() : null;
            if (content is null) throw Failure.BadReply(Head(json, 160));
            Spend.Usage? usage = null;
            if (root.TryGetProperty("usage", out var u) && u.ValueKind == JsonValueKind.Object)
                usage = new Spend.Usage(
                    u.TryGetProperty("prompt_tokens", out var pt) && pt.TryGetInt32(out var p) ? p : 0,
                    u.TryGetProperty("completion_tokens", out var ct) && ct.TryGetInt32(out var q) ? q : 0,
                    u.TryGetProperty("cost", out var cost) && cost.ValueKind == JsonValueKind.Number ? cost.GetDouble() : null);
            return new Answer(content, usage);
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw Failure.BadReply(Head(json, 160));
        }
    }

    public static List<string> ParseModels(string json) => ModelCatalog.Parse(json).Select(m => m.Id).ToList();

    /// <summary>Both servers report trouble as <c>{"error": {"message": ...}}</c>.</summary>
    public static string? ServerError(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind == JsonValueKind.Object && doc.RootElement.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String)
                return m.GetString();
        }
        catch (JsonException) { }
        return null;
    }

    internal static string Head(string text, int length) => text.Length <= length ? text : text[..length];

    private HttpRequestMessage Authorised(HttpRequestMessage request)
    {
        if (ApiKey is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", ApiKey);
        if (Kind == Provider.OpenRouter)
        {
            // OpenRouter asks callers to say who they are; it shows up in their usage page.
            request.Headers.TryAddWithoutValidation("HTTP-Referer", "https://github.com/sworgkh/ledgelings");
            request.Headers.TryAddWithoutValidation("X-Title", "Ledgelings");
        }
        return request;
    }
}
