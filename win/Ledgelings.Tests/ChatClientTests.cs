using System.Text.Json;

namespace Ledgelings.Tests;

/// <summary>The client builds requests and reads replies without a network; those parts are tested here.</summary>
public class ChatClientTests
{
    private static async Task<JsonDocument> Body(System.Net.Http.HttpRequestMessage request) =>
        JsonDocument.Parse(await request.Content!.ReadAsStringAsync());

    private static string? Header(System.Net.Http.HttpRequestMessage request, string name) =>
        request.Headers.TryGetValues(name, out var values) ? string.Join(",", values) : null;

    [Fact]
    public async Task LmStudioAsksTheLocalServerWithNoKey()
    {
        var client = ChatClient.LmStudio(new Uri("http://localhost:1234"), "google/gemma-3-1b");
        var request = client.Request("You are Pip.", "Say hi.");
        Assert.Equal("http://localhost:1234/v1/chat/completions", request.RequestUri!.ToString());
        Assert.Null(request.Headers.Authorization);
        using var body = await Body(request);
        Assert.Equal("google/gemma-3-1b", body.RootElement.GetProperty("model").GetString());
        var messages = body.RootElement.GetProperty("messages").EnumerateArray()
            .Select(m => (m.GetProperty("role").GetString()!, m.GetProperty("content").GetString()!)).ToList();
        Assert.Equal(new[] { ("system", "You are Pip."), ("user", "Say hi.") }, messages);
        Assert.Equal(80, body.RootElement.GetProperty("max_tokens").GetInt32());
    }

    [Fact]
    public async Task OpenRouterSendsTheKeyAndNamesTheApp()
    {
        var client = ChatClient.OpenRouter("sk-or-test", "anthropic/claude-haiku-4.5");
        var request = client.Request("s", "u", maxTokens: 300, temperature: 0.2);
        Assert.Equal("https://openrouter.ai/api/v1/chat/completions", request.RequestUri!.ToString());
        Assert.Equal("Bearer sk-or-test", request.Headers.Authorization?.ToString());
        Assert.Equal("Ledgelings", Header(request, "X-Title"));
        using var body = await Body(request);
        Assert.Equal(300, body.RootElement.GetProperty("max_tokens").GetInt32());
        Assert.Equal(0.2, body.RootElement.GetProperty("temperature").GetDouble());
    }

    [Fact]
    public void ModelListsComeFromEachProvidersOwnPath()
    {
        Assert.Equal("http://localhost:1234/v1/models", ChatClient.LmStudio(new Uri("http://localhost:1234"), "m").ModelsUrl);
        Assert.Equal("https://openrouter.ai/api/v1/models", ChatClient.OpenRouter("k", "m").ModelsUrl);
    }

    [Fact]
    public void AReplyIsTheFirstChoicesText()
    {
        var answer = ChatClient.ParseReply("""{"choices":[{"message":{"role":"assistant","content":"Hello there."}}]}""");
        Assert.Equal("Hello there.", answer.Text);
        Assert.Null(answer.Usage);
    }

    [Fact]
    public void AReplyCarriesWhatItCostWhenTheServerSaysSo()
    {
        var answer = ChatClient.ParseReply("""{"choices":[{"message":{"content":"Hi."}}],"usage":{"prompt_tokens":312,"completion_tokens":18,"total_tokens":330,"cost":0.00042}}""");
        Assert.Equal(new Spend.Usage(312, 18, 0.00042), answer.Usage);
        var local = ChatClient.ParseReply("""{"choices":[{"message":{"content":"Hi."}}],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}""");
        Assert.Equal(new Spend.Usage(5, 2, null), local.Usage);
    }

    [Fact]
    public async Task OpenRouterIsAskedToReportTheCostAndLMStudioIsNot()
    {
        var remote = ChatClient.OpenRouter("k", "m").Request("s", "u");
        using var body = await Body(remote);
        var usage = body.RootElement.GetProperty("usage");
        Assert.Single(usage.EnumerateObject());
        Assert.True(usage.GetProperty("include").GetBoolean());
        var local = ChatClient.LmStudio(new Uri("http://localhost:1234"), "m").Request("s", "u");
        using var localBody = await Body(local);
        Assert.False(localBody.RootElement.TryGetProperty("usage", out _));
    }

    [Fact]
    public void AServerErrorIsReportedInItsOwnWords()
    {
        const string json = """{"error":{"message":"No endpoints found for nobody/no-such-model.","code":404}}""";
        var error = Assert.Throws<ChatClient.Failure>(() => ChatClient.ParseReply(json));
        Assert.Equal("the server refused: No endpoints found for nobody/no-such-model.", error.Message);
    }

    [Fact]
    public void GarbageIsReportedAsAnUnexpectedReply()
    {
        var error = Assert.Throws<ChatClient.Failure>(() => ChatClient.ParseReply("<html>nope"));
        Assert.StartsWith("unexpected reply", error.Message);
    }

    [Fact]
    public void ModelListParsesTheSharedShape()
    {
        Assert.Equal(new[] { "a/one", "b/two" }, ChatClient.ParseModels("""{"data":[{"id":"a/one","name":"One"},{"id":"b/two"}]}"""));
    }
}

/// <summary>Real servers. LM Studio needs LEDGELINGS_LIVE=1; OpenRouter needs OPENROUTER_API_KEY.
/// Skipped here: xUnit 2 has no conditional enabling, and these need a server to be up.</summary>
public class ChatClientLiveTests
{
    private const string Why = "needs a live server (LEDGELINGS_LIVE=1 / OPENROUTER_API_KEY)";

    [Fact(Skip = Why)]
    public async Task LmStudioAnswers()
    {
        var client = ChatClient.LmStudio(new Uri("http://localhost:1234"), "google/gemma-3-1b");
        await client.CheckModel();
        var text = (await client.Reply("You are a cheerful sprite. Answer in one short sentence.", "Say hello.")).Text;
        Assert.NotEmpty(text);
    }

    [Fact(Skip = Why)]
    public async Task LmStudioRefusesAMissingModel()
    {
        var client = ChatClient.LmStudio(new Uri("http://localhost:1234"), "nobody/no-such-model");
        await Assert.ThrowsAsync<ChatClient.Failure>(() => client.CheckModel());
    }

    [Fact(Skip = Why)]
    public async Task OpenRouterAnswers()
    {
        var client = ChatClient.OpenRouter(Environment.GetEnvironmentVariable("OPENROUTER_API_KEY") ?? "", "anthropic/claude-haiku-4.5");
        await client.CheckModel();
        var answer = await client.Reply("You are a cheerful sprite. Answer in one short sentence.", "Say hello.");
        Assert.NotEmpty(answer.Text);
        Assert.NotNull(answer.Usage?.Cost);
    }

    [Fact(Skip = Why)]
    public async Task OpenRouterDescribesTheKey()
    {
        var client = ChatClient.OpenRouter(Environment.GetEnvironmentVariable("OPENROUTER_API_KEY") ?? "", "anthropic/claude-haiku-4.5");
        Assert.NotEmpty(await client.DescribeKey());
    }
}
