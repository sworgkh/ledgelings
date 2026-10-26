using System.Net.Http;
using System.Text;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The one call dictation makes (SPEC §7.13), the Mac's <c>DictationClient.swift</c>: the recording, as a
/// WAV in the request, to an OpenRouter model that listens, and its transcript back with its price.</summary>
public sealed partial class ChatClient
{
    public HttpRequestMessage DictationRequest(byte[] wav, string instruction)
    {
        var request = Authorised(new HttpRequestMessage(HttpMethod.Post, BaseUrl + "/chat/completions"));
        request.Content = new StringContent(Dictation.RequestBody(Model, instruction, wav), Encoding.UTF8, "application/json");
        return request;
    }

    /// <summary>The transcript and what it used. A dropped connection is tried once more, a second later; a refusal
    /// (bad key, no credit, unknown model) is not. The audio has to go up first, so the wait grows with it.</summary>
    public async Task<Answer> Transcribe(byte[] wav, string instruction, double seconds)
    {
        var timeout = TimeSpan.FromSeconds(30 + seconds / 2);
        Failure? last = null;
        for (int attempt = 0; attempt < 2; attempt++)
        {
            string json;
            try { json = await Fetch(DictationRequest(wav, instruction), timeout); }
            catch (Failure e)
            {
                last = e;
                if (attempt == 0) await Task.Delay(1000);
                continue;
            }
            return ParseReply(json);
        }
        throw last ?? Failure.ServerDown("");
    }

    /// <summary>The models that listen, from OpenRouter's public list (no key needed).</summary>
    public static async Task<List<Dictation.Model>> ListeningModels()
    {
        var json = await Fetch(new HttpRequestMessage(HttpMethod.Get, OpenRouterPublic.ModelsUrl), TimeSpan.FromSeconds(15));
        if (ServerError(json) is string message) throw Failure.Refused(message);
        return Dictation.ListeningModels(json);
    }
}
