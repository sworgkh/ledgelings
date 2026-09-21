using Ledgelings.Core;

namespace Ledgelings;

/// <summary>One conversation, from the opening line to the log entry.</summary>
public sealed partial class Colony
{
    private async Task Converse(ChatClient service, int speaker, int listener, Character a, Character b, string aKind, string bKind, string situation)
    {
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = a.Name, ["speakerKind"] = aKind, ["speakerPersona"] = a.Persona,
            ["listener"] = b.Name, ["listenerKind"] = bKind, ["listenerPersona"] = b.Persona,
            ["situation"] = situation, ["line"] = "",
        };
        string system = Settings.SystemPrompt, linePrompt = Settings.LinePrompt, replyPrompt = Settings.ReplyPrompt;
        var bubbleSeconds = Settings.BubbleSeconds;
        var started = DateTimeOffset.Now;
        var spoken = new List<ChatLog.Line>();
        var used = new List<Spend.Usage>();
        // Every call goes to the spend file, even one whose line turned out empty.
        void Charge(ChatClient.Answer answer)
        {
            if (answer.Usage is not Spend.Usage usage) return;
            if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;                // a local model is free
            used.Add(usage);
            Spend.Record(service.Kind, service.Model, usage);
        }
        try
        {
            await service.CheckModel();
            var opening = await service.Reply(Banter.Render(system, vars), Banter.Render(linePrompt, vars));
            Charge(opening);
            var first = Banter.CleanLine(opening.Text, a.Name);
            if (first.Length == 0) { TalkStatus = "the model sent an empty line"; return; }
            Say(first, speaker);
            spoken.Add(new ChatLog.Line(a.Name, first));
            TalkStatus = $"{a.Name}: {first}";

            // Swap seats for the answer.
            vars["speaker"] = b.Name; vars["speakerKind"] = bKind; vars["speakerPersona"] = b.Persona;
            vars["listener"] = a.Name; vars["listenerKind"] = aKind; vars["listenerPersona"] = a.Persona;
            vars["line"] = first;
            var answer = await service.Reply(Banter.Render(system, vars), Banter.Render(replyPrompt, vars));
            Charge(answer);
            var reply = Banter.CleanLine(answer.Text, b.Name);
            await Task.Delay(TimeSpan.FromSeconds(Banter.ShowTime(first, bubbleSeconds) * 0.6));
            if (reply.Length == 0) return;
            Say(reply, listener);
            spoken.Add(new ChatLog.Line(b.Name, reply));
            TalkStatus = $"{b.Name}: {reply}";
        }
        catch (ChatClient.Failure e)
        {
            TalkStatus = e.Message;
            Console.Error.WriteLine("Ledgelings talk: " + e.Message);
        }
        finally
        {
            busy.Remove(speaker); busy.Remove(listener);
            EndChat(speaker, listener, 1.2);
            // Whatever was actually said goes to the log, with what it cost, even a one-sided exchange.
            if (spoken.Count > 0)
            {
                var priced = used.Where(u => u.Cost is not null).Select(u => u.Cost!.Value).ToList();
                History.Record(new ChatLog.Exchange
                {
                    Time = started, Situation = situation, Provider = service.ProviderTitle, Model = service.Model, Lines = spoken,
                    Cost = priced.Count == 0 ? null : priced.Sum(),
                    Tokens = used.Count == 0 ? null : used.Sum(u => u.PromptTokens + u.CompletionTokens),
                });
            }
        }
    }
}
