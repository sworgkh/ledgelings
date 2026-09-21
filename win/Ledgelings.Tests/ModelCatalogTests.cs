namespace Ledgelings.Tests;

/// <summary>OpenRouter's model list, parsed, searched and ranked without a network.</summary>
public class ModelCatalogTests
{
    private const string Sample = """
        {"data":[
          {"id":"google/gemini-2.5-flash-lite","name":"Google: Gemini 2.5 Flash Lite","context_length":1048576,
           "pricing":{"prompt":"0.0000001","completion":"0.0000004"}},
          {"id":"anthropic/claude-haiku-4.5","name":"Anthropic: Claude Haiku 4.5","context_length":200000,
           "pricing":{"prompt":"0.000001","completion":"0.000005"}},
          {"id":"google/gemma-4-26b-a4b-it:free","name":"Google: Gemma 4 26B (free)","context_length":131072,
           "pricing":{"prompt":"0","completion":"0"}},
          {"id":"weird/no-price","name":"No Price"}
        ]}
        """;

    [Fact]
    public void PricesComeOutPerMillionTokens()
    {
        var models = ModelCatalog.Parse(Sample);
        Assert.Equal(4, models.Count);
        var lite = models.First(m => m.Id == "google/gemini-2.5-flash-lite");
        Assert.Equal("Google: Gemini 2.5 Flash Lite", lite.Name);
        Assert.Equal(0.1, lite.PromptPerMillion);
        Assert.Equal(0.4, lite.CompletionPerMillion);
        Assert.Equal(1_048_576, lite.Context);
        var free = models.First(m => m.Id.EndsWith(":free"));
        Assert.True(free.IsFree);
        var unpriced = models.First(m => m.Id == "weird/no-price");
        Assert.Null(unpriced.PromptPerMillion);
    }

    [Fact]
    public void ABanterExchangeIsPricedFromBothRates()
    {
        var lite = ModelCatalog.Parse(Sample).First(m => m.Id == "google/gemini-2.5-flash-lite");
        // Two calls of 300 tokens in and 80 out: 2 * (300 * 0.1 + 80 * 0.4) / 1e6 dollars.
        var cost = lite.ExchangeCost;
        Assert.NotNull(cost);
        Assert.True(Math.Abs(cost.Value - 0.000124) < 1e-9);
    }

    [Fact]
    public void SearchMatchesEveryWordAgainstIdOrName()
    {
        var catalog = new ModelCatalog(ModelCatalog.Parse(Sample));
        Assert.Equal(new[] { "google/gemini-2.5-flash-lite" }, catalog.Search("flash lite").Select(m => m.Id));
        Assert.Equal(new[] { "google/gemini-2.5-flash-lite", "google/gemma-4-26b-a4b-it:free" },
            catalog.Search("GOOGLE").Select(m => m.Id).OrderBy(id => id, StringComparer.Ordinal));
        Assert.Equal(new[] { "anthropic/claude-haiku-4.5" }, catalog.Search("haiku anthropic").Select(m => m.Id));
        Assert.Empty(catalog.Search("nothing-like-this"));
    }

    [Fact]
    public void EmptySearchRanksCheapestFirstWithUnpricedLast()
    {
        var catalog = new ModelCatalog(ModelCatalog.Parse(Sample));
        Assert.Equal(new[]
        {
            "google/gemma-4-26b-a4b-it:free", "google/gemini-2.5-flash-lite", "anthropic/claude-haiku-4.5", "weird/no-price",
        }, catalog.Search("").Select(m => m.Id));
    }

    [Fact]
    public void PriceLabelsReadAtAGlance()
    {
        var labels = ModelCatalog.Parse(Sample).ToDictionary(m => m.Id, m => m.PriceLabel);
        Assert.Equal("$0.10 in · $0.40 out per M", labels["google/gemini-2.5-flash-lite"]);
        Assert.Equal("free", labels["google/gemma-4-26b-a4b-it:free"]);
        Assert.Equal("price unknown", labels["weird/no-price"]);
    }
}
