using System.Globalization;
using System.Text.Json;

namespace Ledgelings;

/// <summary>The models a provider offers, with what OpenRouter says about each, and a
/// search over them for the settings window. LM Studio's list has ids only.</summary>
public sealed class ModelCatalog
{
    public sealed record Model(string Id, string Name, double? PromptPerMillion, double? CompletionPerMillion, int? Context)
    {
        public bool IsFree => PromptPerMillion == 0 && CompletionPerMillion == 0;

        /// <summary>Dollars for one creature meeting: two calls of about 300 tokens in and 80 out.</summary>
        public double? ExchangeCost =>
            PromptPerMillion is double p && CompletionPerMillion is double c ? 2 * (300 * p + 80 * c) / 1_000_000 : null;

        public string PriceLabel
        {
            get
            {
                if (PromptPerMillion is not double p || CompletionPerMillion is not double c) return "price unknown";
                if (IsFree) return "free";
                return string.Format(CultureInfo.InvariantCulture, "${0:0.00} in · ${1:0.00} out per M", p, c);
            }
        }
    }

    public IReadOnlyList<Model> Models { get; }

    public ModelCatalog(IReadOnlyList<Model> models) { Models = models; }

    /// <summary>OpenRouter's <c>/models</c>, which is also the OpenAI shape plus <c>name</c>, <c>pricing</c> and <c>context_length</c>.</summary>
    public static List<Model> Parse(string json)
    {
        if (ChatClient.ServerError(json) is string message) throw ChatClient.Failure.Refused(message);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var rows = doc.RootElement.GetProperty("data");
            var models = new List<Model>();
            foreach (var row in rows.EnumerateArray())
            {
                var id = row.GetProperty("id").GetString() ?? "";
                var name = row.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString()! : id;
                double? prompt = null, completion = null;
                if (row.TryGetProperty("pricing", out var pricing) && pricing.ValueKind == JsonValueKind.Object)
                {
                    prompt = PerMillion(pricing, "prompt");
                    completion = PerMillion(pricing, "completion");
                }
                int? context = row.TryGetProperty("context_length", out var ctx) && ctx.TryGetInt32(out var value) ? value : null;
                models.Add(new Model(id, name, prompt, completion, context));
            }
            return models;
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw ChatClient.Failure.BadReply(ChatClient.Head(json, 120));
        }
    }

    private static double? PerMillion(JsonElement pricing, string key)
    {
        if (!pricing.TryGetProperty(key, out var raw)) return null;
        var text = raw.ValueKind == JsonValueKind.String ? raw.GetString() : raw.ValueKind == JsonValueKind.Number ? raw.GetRawText() : null;
        if (text is null || !double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var perToken)) return null;
        return Math.Round(perToken * 1_000_000 * 1_000_000, MidpointRounding.AwayFromZero) / 1_000_000;
    }

    /// <summary>Every word must appear in the id or the name, any case. Cheapest first; unpriced last.</summary>
    public List<Model> Search(string query)
    {
        var words = query.ToLowerInvariant().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var hits = Models.Where(m =>
        {
            var haystack = (m.Id + " " + m.Name).ToLowerInvariant();
            return words.All(haystack.Contains);
        }).ToList();
        hits.Sort((a, b) =>
        {
            switch (a.ExchangeCost, b.ExchangeCost)
            {
                case (double x, double y) when x != y: return x.CompareTo(y);
                case (null, double): return 1;
                case (double, null): return -1;
                default: return string.CompareOrdinal(a.Id, b.Id);
            }
        });
        return hits;
    }
}
