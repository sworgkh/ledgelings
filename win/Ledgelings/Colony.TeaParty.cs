using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Tea parties: now and then a bump does not end in a word in passing. The two
/// step back, a little table with a teapot and two cups comes up between them,
/// and they sit and tell each other stories from their lives, one each in turn,
/// for a few minutes (<see cref="Core.TeaParty"/>). One party at a time.</summary>
public sealed partial class Colony
{
    /// <summary>The tea party's table, steaming.</summary>
    private static readonly SpriteAtlas teaSheet = SpriteAtlas.Named("tea");
    private readonly SpriteAtlas.Frames teaFrames = teaSheet.MakeFrames();
    private Size TeaCell => teaSheet.CellSize;
    /// <summary>The one tea party going on, if any, and the table it is laid on.</summary>
    private TeaParty? teaParty;
    public TeaParty? CurrentTeaParty => teaParty;
    /// <summary>A party is on, or a guest is on its way to one.</summary>
    public bool IsTeaOn => teaParty is not null || teaInvite is not null;
    private (Pt Floor, double Rotation, double Scale)? teaTable;
    /// <summary>What has been said at it so far, and the built-in stories already told there.</summary>
    private List<ChatLog.Line> teaLines = new();
    private HashSet<string> teaTold = new();
    /// <summary>Counts parties, so a round finishing late knows whether its party is still on.</summary>
    private int teaCount;
    /// <summary>When the built-in round being said silently is over, on the colony's clock.</summary>
    private double? teaRoundEnds;
    /// <summary>"Have a Tea Party" from the menu, when nobody shares an edge: the guest jumping over to the host.</summary>
    private (int Host, int Guest, double Until)? teaInvite;

    /// <summary>Seat <paramref name="i"/> and <paramref name="j"/>, who are already stopped face to face, at a table between
    /// them. False when there is no room: a table would stick round a corner.</summary>
    private bool StartTea(int i, int j)
    {
        if (teaParty is not null || i < 0 || j < 0 || i >= creatures.Count || j >= creatures.Count || i == j) return false;
        if (!creatures[i].IsChatting || !creatures[j].IsChatting) return false;
        if (creatures[i].Spot.Loop != creatures[j].Spot.Loop || creatures[i].Segment != creatures[j].Segment) return false;
        var scale = (sizes[i] + sizes[j]) / 2;
        var half = TeaCell.Width / 2.0 * scale;
        var pi = creatures[i].Position;
        var pj = creatures[j].Position;
        var between = new Pt((pi.X + pj.X) / 2, (pi.Y + pj.Y) / 2);
        var seats = new List<(int Who, double T)>();
        foreach (var k in new[] { i, j })
        {
            var ck = creatures[k];
            var middleK = ck.Loop.Point(ck.Loop.Nearest(between).T);
            // Tucked in two sheet pixels, so the table's ends sit just under their bodies.
            var reach = half + atlas.BodyHalfSize * sizes[k] - 2 * scale;
            if (TeaParty.Seat(ck.Loop, ck.Segment, middleK, ck.Direction, reach) is not double seat) return false;
            seats.Add((k, seat));
        }
        var c = creatures[i];
        var middle = c.Loop.Point(c.Loop.Nearest(between).T);
        var up = c.Loop.Inward(c.Segment);
        var lift = atlas.BodyHalfSize * sizes[i];
        teaTable = (new Pt(middle.X - up.Dx * lift, middle.Y - up.Dy * lift), c.RestingRotation, scale);
        foreach (var (k, seat) in seats) creatures[k].Sit(seat, creatures[k].Direction);
        teaCount += 1;
        teaRoundEnds = null;
        teaParty = new TeaParty(i, j, Elapsed, Settings.TeaPartyMinutes * 60, Settings.TeaSipSeconds);
        teaLines = new();
        teaTold = new();
        busy.Add(i); busy.Add(j);
        TalkStatus = L10n.Tr("%@ and %@ are having tea", CharacterFor(i).Name, CharacterFor(j).Name);
        return true;
    }

    /// <summary>"Have a Tea Party": the closest two who share an edge sit down now; if
    /// nobody does, one jumps over to another and they sit down once it lands.</summary>
    public void TeaNow()
    {
        if (teaParty is not null || teaInvite is not null || hideout.IsActive) return;
        var free = Enumerable.Range(0, creatures.Count).Where(i =>
        {
            var c = creatures[i];
            return !busy.Contains(i) && !ExpectsPlane(i) && !c.IsJumping && !c.IsHeld && !c.IsChatting && !c.IsSleeping;
        }).ToList();
        if (free.Count < 2) { TalkStatus = L10n.Tr("needs two creatures who are awake and free"); return; }
        double Apart(int i, int j) => creatures[i].Position.DistanceTo(creatures[j].Position);
        var pairs = new List<(int I, int J)>();
        foreach (var i in free) foreach (var j in free) if (j > i) pairs.Add((i, j));
        var neighbours = pairs.Where(p => creatures[p.I].Spot.Loop == creatures[p.J].Spot.Loop && creatures[p.I].Segment == creatures[p.J].Segment);
        foreach (var (i, j) in neighbours.OrderBy(p => Apart(p.I, p.J)).ToList())
        {
            Hold(i, j);
            if (StartTea(i, j)) return;
            EndChat(i, j, 0);
        }
        // Nobody shares an edge: the guest jumps to just in front of the host.
        var (host, guest) = pairs.MinBy(p => Apart(p.I, p.J));
        var h = creatures[host];
        var along = h.Loop.Direction(h.Segment);
        var gap = TeaCell.Width * (sizes[host] + sizes[guest]) / 2;
        var landing = new Pt(h.Position.X + along.Dx * h.Direction * gap, h.Position.Y + along.Dy * h.Direction * gap);
        creatures[guest].Leap(creatures[guest].World.Nearest(landing));
        teaInvite = (host, guest, Elapsed + 5);
    }

    /// <summary>Every frame: the invited guest landing, the party's own clock, and
    /// breaking it up when one of them is no longer sitting there.</summary>
    partial void UpdateTeaParty()
    {
        if (teaInvite is { } invite)
        {
            var ok = invite.Host < creatures.Count && invite.Guest < creatures.Count;
            if (!ok || Elapsed > invite.Until) teaInvite = null;
            else if (creatures[invite.Guest].HasArrived)
            {
                teaInvite = null;
                var h = creatures[invite.Host];
                // The host got caught up in something else meanwhile: the guest, left
                // waiting where it landed, just walks on.
                if (busy.Contains(invite.Host) || h.IsChatting || h.IsJumping || h.IsHeld || h.LooksAsleep)
                {
                    var g = creatures[invite.Guest];
                    creatures[invite.Guest].Emerge(g.Spot, g.Direction, rng);
                    return;
                }
                Hold(invite.Host, invite.Guest);
                // Landed round a corner from the host after all: a word instead.
                if (!StartTea(invite.Host, invite.Guest) && !Talk(invite.Guest, invite.Host))
                    EndChat(invite.Host, invite.Guest, 2);
            }
        }
        if (teaParty is not TeaParty party) return;
        if (teaRoundEnds is double ends && ends <= Elapsed)
        {
            teaRoundEnds = null;
            party.RoundDone(Elapsed);
        }
        var pair = new[] { party.A, party.B };
        var sitting = pair.All(k => k < creatures.Count && creatures[k].IsChatting);
        if (party.IsOn && !sitting) BreakUpTea();
        if (teaParty?.CurrentPhase == TeaParty.Phase.Seating && pair.All(k => creatures[k].IsSeated)) teaParty.Seated(Elapsed);
        foreach (var e in teaParty?.Update(Elapsed) ?? new List<TeaParty.Event>())
        {
            switch (e)
            {
                case TeaParty.Event.Round round: TeaRound(round.Teller, round.Listener); break;
                case TeaParty.Event.Finished:
                    WrapUpTea();
                    EndChat(party.A, party.B, 0.5);
                    break;
            }
        }
        if (teaParty?.IsOver == true) { teaParty = null; teaTable = null; }
    }

    /// <summary>End the party now: the table packs away, and the pair goes once quiet.</summary>
    private void BreakUpTea()
    {
        if (teaParty is not TeaParty party || !party.IsOn) return;
        party.End(Elapsed);
        teaRoundEnds = null;
        // A scripted answer still to come goes unsaid: its speaker has left the table.
        scheduled.RemoveAll(l => party.Involves(l.Speaker));
        WrapUpTea();
        EndChat(party.A, party.B, 0.5);
        if (party.IsOver) { teaParty = null; teaTable = null; }
    }

    /// <summary>The pair is free again, and the whole party counts as one conversation between them.</summary>
    private void WrapUpTea()
    {
        if (teaParty is not TeaParty party) return;
        busy.Remove(party.A); busy.Remove(party.B);
        var lines = teaLines;
        teaLines = new();
        if (lines.Count == 0 || party.A >= creatures.Count || party.B >= creatures.Count) return;
        Talked(CharacterFor(party.A).Name, CharacterFor(party.B).Name, lines);
    }

    /// <summary>The party this round belongs to is still going.</summary>
    private bool TeaGoesOn(int count) => teaCount == count && teaParty?.IsOn == true;

    private string TeaSituation(int teller, int listener)
    {
        var a = CharacterFor(teller).Name;
        var b = CharacterFor(listener).Name;
        var situation = TimeOfDay + " "
            + L10n.Tr("%@ and %@ have put a little table out %@ and are sitting down to tea together.", a, b, OnEdge(creatures[teller]));
        var almanac = AlmanacSentence;
        if (almanac.Length > 0) situation = almanac + " " + situation;
        var counts = HuntSentence(new[] { teller, listener });
        if (counts.Length > 0) situation += " " + counts;
        return situation;
    }

    /// <summary>One round: <paramref name="teller"/> tells a story from its life, <paramref name="listener"/> answers it.</summary>
    private void TeaRound(int teller, int listener)
    {
        if (!Settings.TalkEnabled) { teaParty?.RoundDone(Elapsed); return; }       // they only sip
        // Out loud there is one voice to go round: sip until the other conversation is over.
        if (VoiceIsTakenNow) { teaParty?.Postpone(Elapsed); return; }
        var service = Settings.Brain != BrainKind.Script ? Settings.ChatClient() : null;
        if (service is null) { BuiltInTeaRound(teller, listener); return; }
        _ = TeaRoundByModel(service, teller, listener);
    }

    private async Task TeaRoundByModel(ChatClient service, int teller, int listener)
    {
        var count = teaCount;
        var a = CharacterFor(teller);
        var b = CharacterFor(listener);
        var aKind = KindOf(teller);
        var bKind = KindOf(listener);
        var situation = TeaSituation(teller, listener);
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = a.Name, ["speakerKind"] = Banter.Spoken(aKind), ["speakerPersona"] = Banter.Persona(a.Persona),
            ["listener"] = b.Name, ["listenerKind"] = Banter.Spoken(bKind), ["listenerPersona"] = Banter.Persona(b.Persona),
            ["situation"] = situation, ["party"] = Tea.Transcript(teaLines), ["line"] = "",
        };
        string aSide = Relationship(teller, listener), bSide = Relationship(listener, teller);
        List<string> aLately = History.Memory.Recent(a.Name), bLately = History.Memory.Recent(b.Name);
        var plot = PlotLabel(teller, listener);
        var started = DateTimeOffset.Now;
        var spoken = new List<ChatLog.Line>();
        var used = new List<Spend.Usage>();
        void Charge(ChatClient.Answer answer)
        {
            if (answer.Usage is not Spend.Usage usage) return;
            if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;                // a local model is free
            used.Add(usage);
            Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.TeaParties);
        }
        // Into the Chats tab with what it cost, whatever got said.
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
        TalkStatus = L10n.Tr("%@ is telling %@ a story via %@…", a.Name, b.Name, service.Model);
        var voiced = IsVoiced;
        if (voiced) voicedDialogues += 1;
        var fallBack = false;
        try
        {
            await service.CheckModel();
            var opening = await service.Line(LineMemory.WithRecent(Core.Bonds.WithRelationship(Tea.SystemPrompt, vars, aSide), aLately),
                                             Banter.Render(Tea.StoryPrompt, vars));
            Charge(opening);
            if (!TeaGoesOn(count)) return;
            var first = Banter.CleanLine(opening.Text, a.Name, cut: opening.Cut);
            var firstBuiltIn = first.Length == 0;
            if (firstBuiltIn) { first = Tea.Story(a.Name, teaTold, rng); teaTold.Add(first); }
            var firstSaid = Say(first, teller, firstBuiltIn);
            spoken.Add(new ChatLog.Line(a.Name, first));
            teaLines.Add(spoken[0]);
            TalkStatus = $"{a.Name}: {first}";

            // Swap seats for the answer.
            vars["speaker"] = b.Name; vars["speakerKind"] = Banter.Spoken(bKind); vars["speakerPersona"] = Banter.Persona(b.Persona);
            vars["listener"] = a.Name; vars["listenerKind"] = Banter.Spoken(aKind); vars["listenerPersona"] = Banter.Persona(a.Persona);
            vars["line"] = first;
            vars["party"] = Tea.Transcript(teaLines);
            var answer = await service.Line(LineMemory.WithRecent(Core.Bonds.WithRelationship(Tea.SystemPrompt, vars, bSide), bLately),
                                            Banter.Render(Tea.ReplyPrompt, vars));
            Charge(answer);
            var reply = Banter.CleanLine(answer.Text, b.Name, cut: answer.Cut);
            var replyBuiltIn = reply.Length == 0;
            if (replyBuiltIn) reply = Tea.Reply(b.Name, a.Name, rng);
            if (IsVoiced)
            {
                VoicePrefetch(reply, b.Name, replyBuiltIn);
                await Said(firstSaid);
                await Task.Delay(TimeSpan.FromSeconds(TurnPause));
            }
            else
            {
                await Task.Delay(TimeSpan.FromSeconds(Banter.ShowTime(first, Settings.BubbleSeconds) * 0.6));
            }
            if (!TeaGoesOn(count)) return;
            var replySaid = Say(reply, listener, replyBuiltIn);
            spoken.Add(new ChatLog.Line(b.Name, reply));
            teaLines.Add(spoken[1]);
            TalkStatus = $"{b.Name}: {reply}";
            await Said(replySaid);
            // Silent, the answer stays up to be read before the next story starts.
            if (!IsVoiced) await Task.Delay(TimeSpan.FromSeconds(Banter.ShowTime(reply, Settings.BubbleSeconds)));
        }
        catch (Exception e)
        {
            TalkStatus = e.Message;
            Console.Error.WriteLine("Ledgelings tea: " + e.Message);
            // Nothing said yet: the built-in lines take this round instead.
            fallBack = spoken.Count == 0;
        }
        finally
        {
            if (voiced) voicedDialogues -= 1;
            Keep();
            if (TeaGoesOn(count))
            {
                if (fallBack) BuiltInTeaRound(teller, listener); else teaParty?.RoundDone(Elapsed);
            }
        }
    }

    /// <summary>A round from the built-in lines: a story this teller has not told at this party yet, and an answer.</summary>
    private void BuiltInTeaRound(int teller, int listener)
    {
        var count = teaCount;
        var a = CharacterFor(teller).Name;
        var b = CharacterFor(listener).Name;
        var story = HuntLineInstead(teller) ?? Tea.Story(a, teaTold, rng);
        teaTold.Add(story);
        var reply = Tea.Reply(b, a, rng);
        var lines = new[] { (Who: teller, Text: story, BuiltIn: true), (Who: listener, Text: reply, BuiltIn: true) };
        var spoken = new List<ChatLog.Line> { new(a, story), new(b, reply) };
        teaLines.AddRange(spoken);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = TeaSituation(teller, listener),
            Provider = AppSettings.BrainTitle(BrainKind.Script), Model = "", Lines = spoken,
        });
        TalkStatus = L10n.Tr("%@ is telling %@ a story", a, b);
        if (IsVoiced)
        {
            _ = SayInTurns(lines, () =>
            {
                if (TeaGoesOn(count)) teaParty?.RoundDone(Elapsed);
            });
            return;
        }
        // On the colony's clock, like the scripted talk: the answer when the story
        // has been up a while, the round over once the answer has been read.
        Say(story, teller, true);
        var answerAt = Elapsed + Banter.ShowTime(story, Settings.BubbleSeconds) * 0.6;
        scheduled.Add(new ScheduledLine(answerAt, listener, reply, null));
        teaRoundEnds = answerAt + Banter.ShowTime(reply, Settings.BubbleSeconds);
    }

    private TeaTableSnapshot? TeaTableSnapshot()
    {
        if (teaParty is not TeaParty party || teaTable is not { } table) return null;
        var grown = party.Scale(Elapsed);
        if (grown <= 0) return null;
        return new TeaTableSnapshot(teaFrames.Frame("steam", Elapsed), table.Floor, table.Rotation, table.Scale * grown);
    }
}
