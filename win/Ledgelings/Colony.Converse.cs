using Ledgelings.Core;

namespace Ledgelings;

/// <summary>One conversation with a model, from the opening line to the log entry.</summary>
public sealed partial class Colony
{
    /// <summary>The model half of <see cref="Talk"/>: the pair is already busy. Nothing came of the model
    /// (LM Studio not running, the internet down, an empty line): the pair says built-in
    /// lines instead of standing mute.</summary>
    private async Task Converse(ChatClient service, int speaker, int listener, string situation, string? flower)
    {
        var a = CharacterFor(speaker);
        var b = CharacterFor(listener);
        string aKind = KindOf(speaker), bKind = KindOf(listener);
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = a.Name, ["speakerKind"] = Banter.Spoken(aKind), ["speakerPersona"] = Banter.Persona(a.Persona),
            ["listener"] = b.Name, ["listenerKind"] = Banter.Spoken(bKind), ["listenerPersona"] = Banter.Persona(b.Persona),
            ["situation"] = situation, ["line"] = "",
        };
        string system = Settings.SystemPrompt, linePrompt = Settings.LinePrompt, replyPrompt = Settings.ReplyPrompt;
        var bubbleSeconds = Settings.BubbleSeconds;
        // How the two get on, and the story between them, from each one's side.
        string aSide = Relationship(speaker, listener), bSide = Relationship(listener, speaker);
        // What each said lately, so the model says something new.
        List<string> aLately = History.Memory.Recent(a.Name), bLately = History.Memory.Recent(b.Name);
        var plot = PlotLabel(speaker, listener);
        var started = DateTimeOffset.Now;
        var spoken = new List<ChatLog.Line>();
        var used = new List<Spend.Usage>();
        // Whatever was actually said goes to the log, with what it cost, even a one-sided exchange.
        void Keep()
        {
            if (spoken.Count == 0) return;
            var priced = used.Where(u => u.Cost is not null).Select(u => u.Cost!.Value).ToList();
            History.Record(new ChatLog.Exchange
            {
                Time = started, Situation = situation, Provider = service.ProviderTitle, Model = service.Model, Lines = spoken,
                Cost = priced.Count == 0 ? null : priced.Sum(),
                Tokens = used.Count == 0 ? null : used.Sum(u => u.PromptTokens + u.CompletionTokens),
                Plot = plot,
            });
        }
        // Every call goes to the spend file, even one whose line turned out empty.
        void Charge(ChatClient.Answer answer)
        {
            if (answer.Usage is not Spend.Usage usage) return;
            if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;                // a local model is free
            used.Add(usage);
            Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Talk);
        }

        var voiced = IsVoiced;
        if (voiced) voicedDialogues += 1;
        var fallBack = false;
        try
        {
            await service.CheckModel();
            var opening = await service.Line(LineMemory.WithRecent(Core.Bonds.WithRelationship(system, vars, aSide), aLately),
                                             Banter.Render(linePrompt, vars));
            Charge(opening);
            var first = Banter.CleanLine(opening.Text, a.Name, cut: opening.Cut);
            if (first.Length == 0) { TalkStatus = L10n.Tr("the model sent an empty line"); fallBack = true; return; }
            var firstSaid = Say(first, speaker);
            spoken.Add(new ChatLog.Line(a.Name, first));
            TalkStatus = $"{a.Name}: {first}";

            // Swap seats for the answer.
            vars["speaker"] = b.Name; vars["speakerKind"] = Banter.Spoken(bKind); vars["speakerPersona"] = Banter.Persona(b.Persona);
            vars["listener"] = a.Name; vars["listenerKind"] = Banter.Spoken(aKind); vars["listenerPersona"] = Banter.Persona(a.Persona);
            vars["line"] = first;
            var answer = await service.Line(LineMemory.WithRecent(Core.Bonds.WithRelationship(system, vars, bSide), bLately),
                                            Banter.Render(replyPrompt, vars));
            Charge(answer);
            var reply = Banter.CleanLine(answer.Text, b.Name, cut: answer.Cut);
            if (reply.Length == 0) { await Said(firstSaid); return; }
            if (IsVoiced)
            {
                // Out loud, the answer comes a beat after the first line ends, its
                // sound fetched meanwhile, not on the silent-bubble clock.
                VoicePrefetch(reply, b.Name, false);
                await Said(firstSaid);
                await Task.Delay(TimeSpan.FromSeconds(TurnPause));
            }
            else
            {
                await Task.Delay(TimeSpan.FromSeconds(Banter.ShowTime(first, bubbleSeconds) * 0.6));
            }
            var replySaid = Say(reply, listener);
            spoken.Add(new ChatLog.Line(b.Name, reply));
            TalkStatus = $"{b.Name}: {reply}";
            await Said(replySaid);          // the pair stays face to face until it is said
        }
        catch (Exception e)          // any error, as the Mac catches: the pair still says built-in lines
        {
            TalkStatus = e.Message;
            Console.Error.WriteLine("Ledgelings talk: " + e.Message);
            fallBack = spoken.Count == 0;
        }
        finally
        {
            if (voiced) voicedDialogues -= 1;
            busy.Remove(speaker); busy.Remove(listener);
            Keep();
            Talked(a.Name, b.Name, spoken);
            var recited = fallBack && speaker < creatures.Count && listener < creatures.Count
                && Recite(speaker, listener, flower, situation);
            if (!recited) EndChat(speaker, listener, 1.2);
        }
    }
}
