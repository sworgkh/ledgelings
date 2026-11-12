using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// Chat with the creatures (SPEC §7.18), from the colony's side, the Mac's <c>Colony+OwnerChat.swift</c>: who can be
/// written to, who answers a message to everyone and in what order, each answer from the brain model in the creature's
/// persona and kind, its thinking dots, its bubble and its voice, its turn to face the window, its cost
/// (<see cref="Spend.Purpose.Chat"/>) and its place in the Chats tab; and each one's memory of the owner.
/// </summary>
public sealed partial class Colony
{
    /// <summary>Someone on screen the owner can write to.</summary>
    public sealed record ChatTarget(string Name, System.Drawing.Bitmap? Portrait);

    /// <summary>What happens while they answer, for the window.</summary>
    public abstract record ChatEvent
    {
        public sealed record Thinking(string Name) : ChatEvent;
        public sealed record Answer(string Name, string Text, double? Cost) : ChatEvent;
        /// <summary>It had nothing to say (an empty answer, or trouble); the call, if any, was still paid for.</summary>
        public sealed record Quiet(string Name, string Why) : ChatEvent;
        public sealed record Trouble(string Why) : ChatEvent;
    }

    /// <summary>A stand-in for the model: (who, what the owner wrote, what the ones before said) → the answer.</summary>
    public delegate string ChatFake(string name, string message, IReadOnlyList<(string Name, string Text)> earlier);

    private OwnerChatBook? ownerChats;
    /// <summary>What each creature remembers of chatting with the owner: <c>owner-chats.json</c> beside the bonds.</summary>
    public OwnerChatBook OwnerChats => ownerChats ??= new OwnerChatBook(Spend.Ledger.Directory);

    /// <summary>Creatures writing an answer to the owner, by when they started: dots over them.</summary>
    private readonly Dictionary<int, double> chatThinking = new();
    /// <summary>Creatures turned to face the chat window while they answer, and the ones the chat made busy.</summary>
    private readonly HashSet<int> chatFacing = new(), chatBusy = new();
    public bool IsChatThinking => chatThinking.Count > 0;

    /// <summary>Everyone on screen, each name once, in the order they live.</summary>
    public IReadOnlyList<ChatTarget> ChatTargets()
    {
        var seen = new HashSet<string>();
        var list = new List<ChatTarget>();
        for (var i = 0; i < creatures.Count; i++)
        {
            var name = CharacterFor(i).Name;
            if (seen.Add(name)) list.Add(new ChatTarget(name, i < frames.Count ? frames[i].Frame("idle", 0) : null));
        }
        return list;
    }

    public int? CreatureNamed(string name)
    {
        for (var i = 0; i < creatures.Count; i++) if (CharacterFor(i).Name == name) return i;
        return null;
    }

    /// <summary>Answer the owner's <paramref name="message"/>: <paramref name="to"/> one name, or null for everyone (up to
    /// <c>ChatEveryone</c> of them, one after another, each hearing the ones before). Each faces <paramref name="window"/>
    /// (the colony's points) while it thinks and talks. Done once the last has finished saying its answer.</summary>
    public async Task AnswerOwner(string message, string? to, Pt window, ChatFake? fake, Action<ChatEvent> told)
    {
        var service = fake is null ? Settings.ChatClient() : null;
        if (fake is null && service is null) { told(new ChatEvent.Trouble(OwnerChat.NoModel)); return; }
        var everyone = to is null;
        IReadOnlyList<string> order;
        if (to is not null) order = CreatureNamed(to) is null ? Array.Empty<string>() : new[] { to };
        else
        {
            var candidates = ChatTargets().Select(t => CreatureNamed(t.Name) is int i ? new OwnerChat.Candidate(t.Name, creatures[i].LooksAsleep) : null)
                                          .OfType<OwnerChat.Candidate>();
            order = OwnerChat.Answerers(candidates, Settings.ChatEveryone, rng);
        }
        if (order.Count == 0) { told(new ChatEvent.Trouble(L10n.Tr("Nobody is on screen to answer."))); return; }
        Trace?.Invoke($"chat {(everyone ? "everyone" : "to " + order[0])}: \"{message}\", {(order.Count == 1 ? "1 answers" : $"{order.Count} answer in turn: {string.Join(", ", order)}")}");
        var started = DateTimeOffset.Now;
        var length = Settings.ChatLength;
        var lines = new List<ChatLog.Line> { new(L10n.Tr("You"), message) };
        var used = new List<Spend.Usage>();
        var earlier = new List<(string Name, string Text)>();
        var situation = "";
        try
        {
            for (var turn = 0; turn < order.Count; turn++)
            {
                var who = order[turn];
                if (CreatureNamed(who) is not int i) continue;
                if (turn > 0) await Task.Delay(TimeSpan.FromSeconds(IsVoiced ? TurnPause : 0.6));
                var character = CharacterFor(i);
                situation = string.Join(" ", new[] { AlmanacSentence, TimeOfDay, Describe(i) + "." }.Where(s => s.Length > 0));
                var memory = Settings.ChatRemember ? OwnerChat.MemoryBlock(OwnerChats.MemoryOf(who), DateTimeOffset.Now) : "";
                var values = OwnerChat.Values(who, KindOf(i), character.Persona, length, memory, situation, message, everyone, earlier);
                var prompt = OwnerChat.Prompt(values);
                StartChatTurn(i, window);
                told(new ChatEvent.Thinking(who));
                Trace?.Invoke($"chat {who} is thinking, about {Core.Bonds.Tokens(prompt.System + prompt.User)} tokens to send" + (memory.Length == 0 ? "" : $", memory {Core.Bonds.Tokens(memory)}"));
                var asked = DateTimeOffset.Now;
                string text = "";
                double? cost = null;
                if (fake is not null)
                {
                    await Task.Delay(800);
                    text = OwnerChat.Clean(fake(who, message, earlier), who, length);
                }
                else if (service is not null)
                {
                    try
                    {
                        var answer = await service.Reply(prompt.System, prompt.User, length.MaxTokens(), reasoning: "low");
                        if (answer.Usage is Spend.Usage usage)
                        {
                            if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;     // a local model is free
                            used.Add(usage);
                            cost = usage.Cost;
                            Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Chat);
                        }
                        text = OwnerChat.Clean(answer.Text, who, length, answer.Cut);
                    }
                    catch (Exception e) when (e is ChatClient.Failure or HttpRequestException or TaskCanceledException or IOException)
                    {
                        EndChatThinking(i);
                        Trace?.Invoke($"chat {who}: {e.Message}");
                        told(new ChatEvent.Quiet(who, e.Message));
                        continue;
                    }
                }
                EndChatThinking(i);
                if (i >= creatures.Count) continue;
                if (text.Length == 0) { told(new ChatEvent.Quiet(who, L10n.Tr("%@ had nothing to say.", who))); continue; }
                Trace?.Invoke($"chat {who} answers after {(DateTimeOffset.Now - asked).TotalSeconds:0.0} s{(cost is double c ? ", " + Core.Spend.Label(c) : fake is not null ? ", fake" : ", unpriced")}: {text}");
                told(new ChatEvent.Answer(who, text, cost));
                lines.Add(new ChatLog.Line(who, text));
                earlier.Add((who, text));
                RememberChat(who, message, text, everyone, KindOf(i));
                await SayChatAnswer(text, i);
            }
        }
        finally
        {
            // The talk goes to the Chats tab, with what its calls cost; the voice's own cost is put beside it there.
            if (lines.Count > 1 || used.Count > 0)
            {
                var priced = used.Where(u => u.Cost is not null).Select(u => u.Cost!.Value).ToList();
                History.Record(new ChatLog.Exchange
                {
                    Time = started, Situation = L10n.Tr("Chat with you.") + " " + situation,
                    Provider = service?.ProviderTitle ?? L10n.Tr("Stand-in answers"), Model = service?.Model ?? "", Lines = lines,
                    Cost = priced.Count == 0 ? null : priced.Sum(),
                    Tokens = used.Count == 0 ? null : used.Sum(u => u.PromptTokens + u.CompletionTokens),
                });
            }
            EndChatTurns();
        }
    }

    // MARK: On screen

    /// <summary>It stops, turns to the window and is left alone while it answers.</summary>
    private void StartChatTurn(int i, Pt point)
    {
        if (i >= creatures.Count) return;
        if (busy.Add(i)) chatBusy.Add(i);
        var c = creatures[i];
        if (!c.IsChatting && !c.IsPlaying && !c.IsHeld && !c.LooksAsleep)
        {
            var dir = c.Loop.Direction(c.Segment);
            var along = dir.Dx * (point.X - c.Position.X) + dir.Dy * (point.Y - c.Position.Y);
            c.Meet(along >= 0 ? 1 : -1, 90);
            chatFacing.Add(i);
            Trace?.Invoke($"chat {CharacterFor(i).Name} turns to the window, facing {(along >= 0 ? "+" : "-")}");
        }
        chatThinking[i] = Elapsed;
    }

    private void EndChatThinking(int i)
    {
        if (!chatThinking.Remove(i)) return;
        if (bubbles.TryGetValue(i, out var b) && b.Text.All(ch => ch == '•')) bubbles.Remove(i);
    }

    /// <summary>Everyone who answered walks on.</summary>
    private void EndChatTurns()
    {
        foreach (var i in chatFacing) if (i < creatures.Count && creatures[i].IsChatting) creatures[i].WalkOn(rng);
        foreach (var i in chatBusy) busy.Remove(i);
        chatFacing.Clear();
        chatBusy.Clear();
        chatThinking.Clear();
    }

    /// <summary>Every frame: one, two, three dots over whoever is writing an answer, never said.</summary>
    private void UpdateOwnerChat()
    {
        foreach (var (i, since) in chatThinking)
        {
            if (i >= creatures.Count || !Settings.ChatBubbles) continue;
            var dots = new string('•', (int)((Elapsed - since) * 3) % 3 + 1);
            if (!bubbles.TryGetValue(i, out var b) || b.Text != dots)
            {
                bubbleSerial += 1;
                bubbles[i] = new Bubble { Text = dots, Until = Elapsed + 1, Serial = bubbleSerial };
            }
            if (chatFacing.Contains(i)) creatures[i].KeepChatting(30);
        }
    }

    /// <summary>The answer in a bubble over it and in its voice, as the settings say; back once it is said.</summary>
    private async Task SayChatAnswer(string text, int i)
    {
        if (i >= creatures.Count) return;
        var speak = Settings.ChatSpeak && IsVoiced;
        if (chatFacing.Contains(i)) creatures[i].KeepChatting(60);
        if (Settings.ChatBubbles)
        {
            var serial = Say(text, i, voiced: speak);
            if (voicedLines.Contains(serial)) await Said(serial);
            else await Task.Delay(TimeSpan.FromSeconds(Banter.ShowTime(text, Settings.BubbleSeconds) * 0.5));
        }
        else if (speak && voice is not null)
        {
            var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var name = CharacterFor(i).Name;
            if (!voice.Say(text, name, false, cue => { if (cue is Voice.Cue.Done or Voice.Cue.Dropped) done.TrySetResult(); })) done.TrySetResult();
            await done.Task;
        }
    }

    // MARK: Memory

    /// <summary>One exchange into <paramref name="name"/>'s memory; what falls out of it is folded into its summary.</summary>
    private void RememberChat(string name, string said, string answer, bool everyone, string kind)
    {
        if (!Settings.ChatRemember) return;
        IReadOnlyList<OwnerChat.Exchange> dropped = Array.Empty<OwnerChat.Exchange>();
        OwnerChats.Change(b => dropped = b.Remember(name, new OwnerChat.Exchange { Time = DateTimeOffset.Now, Said = said, Answer = answer, Everyone = everyone },
                                                   Settings.ChatMemoryExchanges));
        Trace?.Invoke($"chat memory {name}: {OwnerChats.MemoryOf(name)?.Exchanges.Count ?? 0} kept" + (dropped.Count == 0 ? "" : $", {dropped.Count} to the summary"));
        if (dropped.Count > 0) _ = SummariseChat(name, dropped, kind);
    }

    /// <summary>The summary rewritten to take in <paramref name="dropped"/>: one call, priced as Chat with you, whatever comes back.</summary>
    private async Task SummariseChat(string name, IReadOnlyList<OwnerChat.Exchange> dropped, string kind)
    {
        if (Settings.ChatClient() is not { } service) return;
        var prompt = OwnerChat.SummaryPromptFor(name, kind, OwnerChats.MemoryOf(name)?.Summary, dropped, DateTimeOffset.Now);
        double? cost = null;
        string? summary = null;
        try
        {
            var answer = await service.Reply(Core.Bonds.DiarySystemPrompt, prompt, OwnerChat.SummaryMaxTokens, reasoning: "low");
            if (answer.Usage is Spend.Usage usage)
            {
                if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
                cost = usage.Cost;
                Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Chat);
            }
            summary = OwnerChat.CleanSummary(answer.Text);
        }
        catch (Exception e) when (e is ChatClient.Failure or HttpRequestException or TaskCanceledException or IOException)
        {
            Console.Error.WriteLine("Ledgelings chat memory: " + e.Message);
        }
        OwnerChats.Change(b => b.Summarised(name, summary, DateTimeOffset.Now, cost));
        Trace?.Invoke($"chat memory {name}: summary {summary ?? "-"}");
    }

    /// <summary>Each character's memory of the owner, for <c>--memory</c>.</summary>
    public IReadOnlyList<string> OwnerChatDump(string? only = null)
    {
        var out_ = new List<string>();
        foreach (var name in OwnerChats.Book.Names)
        {
            if (only is not null && !name.Contains(only, StringComparison.OrdinalIgnoreCase)) continue;
            if (OwnerChats.MemoryOf(name) is not { } memory) continue;
            var key = L10n.Tr("you") + " & " + name;
            out_.Add($"memory {key}: summary: {memory.Summary ?? "-"}" + (memory.SummaryCost is double c ? $" ({Core.Spend.Label(c)})" : ""));
            foreach (var e in memory.Exchanges)
                out_.Add($"memory {key}: {OwnerChat.When(e.Time, DateTimeOffset.Now)}{(e.Everyone ? " (to everyone)" : "")}: \"{e.Said}\" → \"{e.Answer}\"");
            var block = OwnerChat.MemoryBlock(memory, DateTimeOffset.Now);
            out_.Add($"memory {key}: {name} remembers ({Core.Bonds.Tokens(block)} tokens, {memory.Exchanges.Count} of {Settings.ChatMemoryExchanges} exchanges kept): {block}");
        }
        return out_;
    }
}
