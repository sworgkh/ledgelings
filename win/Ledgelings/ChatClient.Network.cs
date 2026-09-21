using System.Net.Http;
using System.Text.Json;

namespace Ledgelings;

/// <summary>The part of the client that goes over the wire.</summary>
public sealed partial class ChatClient
{
    public async Task<List<string>> ListModels() => (await Catalog()).Models.Select(m => m.Id).ToList();

    /// <summary>Everything the provider offers, with names and prices where it gives them.</summary>
    public async Task<ModelCatalog> Catalog() =>
        new(ModelCatalog.Parse(await Fetch(Authorised(new HttpRequestMessage(HttpMethod.Get, ModelsUrl)), TimeSpan.FromSeconds(15))));

    public async Task CheckModel()
    {
        var models = await ListModels();
        if (!models.Contains(Model)) throw Failure.ModelMissing(Model, models);
    }

    /// <summary>OpenRouter only: the key's label and how much it has spent, or a refusal if the key is bad.</summary>
    public async Task<string> DescribeKey()
    {
        var json = await Fetch(Authorised(new HttpRequestMessage(HttpMethod.Get, BaseUrl + "/auth/key")), TimeSpan.FromSeconds(10));
        if (ServerError(json) is string message) throw Failure.Refused(message);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var data = doc.RootElement.GetProperty("data");
            var parts = new List<string> { data.TryGetProperty("label", out var l) && l.ValueKind == JsonValueKind.String ? l.GetString()! : "key" };
            if (data.TryGetProperty("usage", out var usage) && usage.ValueKind == JsonValueKind.Number) parts.Add($"spent ${usage.GetDouble():0.00}");
            if (data.TryGetProperty("limit", out var limit) && limit.ValueKind == JsonValueKind.Number) parts.Add($"of ${limit.GetDouble():0.00}");
            return string.Join(" ", parts);
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw Failure.BadReply(Head(json, 120));
        }
    }

    /// <summary>One completion. <paramref name="system"/> is who the speaker is; <paramref name="user"/> is the moment.</summary>
    public async Task<Answer> Reply(string system, string user, int maxTokens = 80, double temperature = 0.9) =>
        ParseReply(await Fetch(Request(system, user, maxTokens, temperature), TimeSpan.FromSeconds(60)));

    private static async Task<string> Fetch(HttpRequestMessage request, TimeSpan timeout)
    {
        try
        {
            using var cts = new CancellationTokenSource(timeout);
            using var response = await http.SendAsync(request, cts.Token);
            return await response.Content.ReadAsStringAsync(cts.Token);
        }
        catch (HttpRequestException e) { throw Failure.ServerDown(e.Message); }
        catch (TaskCanceledException) { throw Failure.ServerDown("timed out"); }
    }
}
