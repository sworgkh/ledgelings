using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Complaints: chase a creature with the cursor, or pick it up, too many times
/// in a row and it turns round and tells you off, in its own voice.</summary>
public sealed partial class Colony
{
    /// <summary>How often each creature has been chased or carried lately; too often and it complains.</summary>
    private readonly Annoyance annoyance = new();
    public Annoyance Annoyance => annoyance;
    /// <summary>Creatures whose complaint the model is writing.</summary>
    private readonly HashSet<int> complaining = new();

    partial void ForgetAnnoyance()
    {
        annoyance.Forget(creatures.Count);
        annoyance.Limit = Settings.ComplainAfter;
        annoyance.CalmAfter = Settings.ComplainCalmSeconds;
    }

    /// <summary>Creature <paramref name="i"/> was just chased off its edge by the cursor, or picked up.</summary>
    partial void Bothered(int i)
    {
        // Counted first: a creature remarking on its count does not complain over it.
        var remarked = Hunted(i);
        if (!Settings.ComplainEnabled || i < 0 || i >= creatures.Count) return;
        if (!annoyance.Bothered(i, Elapsed) || remarked) return;
        Complain(i);
    }

    /// <summary>Say the complaint. In the middle of a conversation it waits: the streak is
    /// kept, so the next chase complains instead.</summary>
    private void Complain(int i)
    {
        if (i < 0 || i >= creatures.Count || busy.Contains(i) || complaining.Contains(i)) return;
        var times = annoyance.Streak(i, Elapsed);
        annoyance.Forgive(i);
        var me = CharacterFor(i);
        var situation = string.Join(" ", new[] { AlmanacSentence, Describe(i) + ".", L10n.Tr("%@ has been chased or picked up by the user's cursor %d times in a row.", me.Name, times),
                                             HuntSentence(new[] { i }, always: true) }
            .Where(s => s.Length > 0));
        var service = Settings.TalkEnabled && Settings.Brain != BrainKind.Script ? Settings.ChatClient() : null;
        if (service is null)
        {
            var tally = HuntLineInstead(i);
            var line = tally ?? Complaints.Line(me.Name, times, rng);
            Say(line, i, builtIn: tally is null);
            RecordComplaint(line, me.Name, situation);
            return;
        }
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = me.Name, ["speakerKind"] = Banter.Spoken(KindOf(i)), ["speakerPersona"] = Banter.Persona(me.Persona),
            ["listener"] = L10n.Tr("you"), ["listenerKind"] = L10n.Tr("the person at the computer"),
            ["listenerPersona"] = L10n.Tr("The person whose screen you all live on."),
            ["situation"] = situation, ["times"] = times.ToString(),
        };
        var system = LineMemory.WithRecent(Core.Bonds.WithRelationship(Settings.SystemPrompt, vars, ""), History.Memory.Recent(me.Name));
        var user = Banter.Render(Complaints.Prompt, vars).Trim();
        complaining.Add(i);
        TalkStatus = L10n.Format(CursorMoods.Current.SpeakingUp(), new object[] { me.Name, service.Model });
        _ = WriteComplaint(service, i, me, times, situation, system, user);
    }

    private async Task WriteComplaint(ChatClient service, int i, Character me, int times, string situation, string system, string user)
    {
        var line = "";
        double? cost = null;
        int? tokens = null;
        try
        {
            await service.CheckModel();
            var answer = await service.Line(system, user);
            // Paid for, whatever comes back.
            if (answer.Usage is Spend.Usage usage)
            {
                if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
                Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Complaints);
                cost = usage.Cost;
                tokens = usage.PromptTokens + usage.CompletionTokens;
            }
            line = Banter.CleanLine(answer.Text, me.Name, cut: answer.Cut);
        }
        catch (Exception e)       // any failure: a built-in line takes its place
        {
            TalkStatus = e.Message;
            Console.Error.WriteLine("Ledgelings complaint: " + e.Message);
        }
        finally
        {
            complaining.Remove(i);
        }
        // Gone, or talking by now: the moment has passed.
        if (i >= creatures.Count || CharacterFor(i).Name != me.Name || busy.Contains(i)) return;
        var modelWrote = line.Length > 0;
        if (!modelWrote) line = HuntLineInstead(i) ?? Complaints.Line(me.Name, times, rng);
        Say(line, i, builtIn: !modelWrote);
        RecordComplaint(line, me.Name, situation, modelWrote ? service.ProviderTitle : null, service.Model, cost, tokens);
    }

    /// <summary>Into the Chats tab, with what it cost when a model wrote it.</summary>
    private void RecordComplaint(string line, string name, string situation,
                                 string? provider = null, string model = "", double? cost = null, int? tokens = null)
    {
        TalkStatus = L10n.Format(CursorMoods.Current.SpokeUp(), new object[] { name, line });
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = situation,
            Provider = provider ?? AppSettings.BrainTitle(BrainKind.Script), Model = provider is null ? "" : model,
            Lines = new List<ChatLog.Line> { new(name, line) }, Cost = cost, Tokens = tokens,
        });
    }
}
