using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Deeds (SPEC §6.5.2.2): what creatures say turns into what they do. A conversation or a
/// letter's prompt offers the deeds possible right now (<see cref="DeedOptions"/>); the line
/// that comes back may carry a <c>DO:</c> tag (<see cref="Deeds.Split"/>), which is checked and
/// taken (<see cref="Took"/>). An invitation waits for its answer; a yes, or a deed of its
/// own, waits for both creatures to be free and is then done through the same
/// doors the rest of the app uses: <see cref="StartPlay(Plays.Kind, int[], string?)"/>, <see cref="StartTea"/>,
/// the gifts, <see cref="ThrowPlane"/>. Nothing here calls a model. The Mac's <c>Colony+Deeds</c>.</summary>
public sealed partial class Colony
{
    /// <summary>A deed agreed on, waiting for both to be free. <c>By</c> does it, with <c>With</c>: for a game or
    /// tea, the one who asked leads. <c>Asked</c>: whose invitation it answers. <c>Leapt</c>: the other has
    /// already leapt over, so the two can start.</summary>
    private sealed class AgreedDeed
    {
        public required Deeds.Deed Deed;
        public required int By;
        public required int With;
        public required double Until;
        public string? Asked;
        public bool Leapt;
    }

    /// <summary>Invitations waiting for their answer.</summary>
    private readonly List<Deeds.Invitation> invitations = new();
    /// <summary>Deeds agreed on, waiting for both to be free.</summary>
    private List<AgreedDeed> agreed = new();
    /// <summary>The deeds done lately, against the owner's limits.</summary>
    private readonly Deeds.Ledger deedLedger = new();
    /// <summary>Who follows whom, until when; who is walking over to whom.</summary>
    private readonly Dictionary<int, (int Leader, double Until)> following = new();
    private readonly Dictionary<int, (int Host, double Until)> visiting = new();
    /// <summary>The next conversation or letter opens with this invitation (the Mac's <c>--converse --invite</c>).</summary>
    internal Deeds.Offer? ForcedOffer { get; set; }
    /// <summary>The next built-in answer to an invitation is this, whatever chance says.</summary>
    internal bool? ForcedAnswer { get; set; }
    /// <summary>Deeds agreed on and not yet done, for whoever waits on them.</summary>
    public int AgreedCount => agreed.Count;

    private string Name(int i) => CharacterFor(i).Name;

    private bool DeedsOn => Settings.DeedsEnabled && Settings.TalkEnabled && !hideout.IsActive;

    /// <summary>What creature <paramref name="i"/> may do now with <paramref name="j"/>. <paramref name="letter"/>: it is writing to
    /// <paramref name="j"/>, not standing face to face, so only invitations and a visit make sense.</summary>
    private Deeds.Options DeedOptions(int i, int j, bool letter)
    {
        var o = new Deeds.Options();
        if (!DeedsOn || i < 0 || j < 0 || i >= creatures.Count || j >= creatures.Count || i == j) return o;
        string a = Name(i), b = Name(j);
        var now = Elapsed;
        var limits = Settings.DeedLimits;
        bool Allowed(string verb) => deedLedger.RefusalFor(verb, a, b, now, limits) is null;
        o.Answering = invitations.LastOrDefault(v => v.From == b && v.To == a);
        var asked = invitations.Any(v => (v.From == a && v.To == b) || (v.From == b && v.To == a));
        if (Allowed("invite") && !asked)
        {
            if (Settings.DeedGames && Settings.PlayEnabled && !IsNight && play is null)
            {
                var due = BallGamesDue;
                o.Games = Deeds.Invitable.Where(k => Settings.EnabledPlays.Contains(k) && (!k.IsTeamGame() || due.Contains(k))).ToList();
            }
            o.Tea = Settings.DeedTea && Settings.TeaPartiesEnabled && teaParty is null && teaInvite is null;
        }
        if (letter)
        {
            if (Settings.DeedVisit && Allowed("visit")) o.Visit = new() { b };
        }
        else
        {
            o.Flower = Settings.DeedFlower && Allowed("flower") && gifts.CurrentFlight is null && gifts.Hat(j) is null;
            o.Letter = Settings.DeedLetter && Settings.PlanesEnabled && Allowed("letter");
            o.Follow = Settings.DeedFollow && Allowed("follow");
            if (Settings.DeedVisit && Allowed("visit"))
            {
                // The three nearest who are awake: a short list, a short prompt.
                var me = creatures[i].Position;
                o.Visit = Enumerable.Range(0, creatures.Count)
                    .Where(k => k != i && k != j && !creatures[k].LooksAsleep && !hideout.IsInside(k))
                    .OrderBy(k => creatures[k].Position.DistanceTo(me)).Take(3).Select(Name).ToList();
            }
        }
        o.Sleep = Settings.DeedSleep && IsNight && !creatures[i].IsSleeping && Allowed("sleep");
        return o;
    }

    /// <summary>What the prompt of <paramref name="i"/>, speaking to <paramref name="j"/>, says about deeds and notes; "" when nothing is offered.</summary>
    private string DeedPrompt(Deeds.Options options, int j)
    {
        var notes = Settings.MemoryEnabled && Settings.MemoryNotes && Settings.MemoryFacts > 0;
        var text = Deeds.Prompt(options, notes, j >= 0 && j < creatures.Count ? Name(j) : "");
        // Only for a forced invitation: this time, it is sure to come.
        if (ForcedOffer is Deeds.Offer offer && options.Answering is null && Deeds.Check(Deeds.Deed.Invite(offer), options) is null)
            text += $" This time you do invite them: end with DO: invite {offer.Tag}.";
        return text;
    }

    /// <summary><see cref="Relationship"/> with what the prompt says about deeds after it.</summary>
    private string Side(int i, int j, Deeds.Options options) =>
        string.Join("\n", new[] { Relationship(i, j), DeedPrompt(options, j) }.Where(s => s.Length > 0));

    /// <summary>What creature <paramref name="i"/>'s line said it does, to <paramref name="j"/>: a fact to remember, an
    /// invitation, an answer, a deed of its own. Anything not offered, or over
    /// the limits, is traced and left.</summary>
    private void Took(Deeds.Tagged tagged, int i, int j, Deeds.Options options, bool byLetter)
    {
        if (i < 0 || j < 0 || i >= creatures.Count || j >= creatures.Count) return;
        string a = Name(i), b = Name(j);
        if (tagged.Note is string note && Settings.MemoryEnabled && Settings.MemoryNotes)
        {
            Bonds.Change(book => book.Remember(a, b, note, "note", Settings.MemoryFacts));
            Trace?.Invoke($"memory {Core.Bonds.Key(a, b)}: {a} notes \"{note}\"");
        }
        if (tagged.Unknown is string unknown) Trace?.Invoke($"deed ignored: {a} \"{unknown}\"");
        if (tagged.Deed is not Deeds.Deed deed) return;
        if ((Deeds.Check(deed, options) ?? deedLedger.RefusalFor(deed.Verb, a, b, Elapsed, Settings.DeedLimits)) is Deeds.Refusal refusal)
        {
            Trace?.Invoke($"deed refused: {a} {deed.Tag}: {refusal.Text()}");
            return;
        }
        switch (deed.Verb)
        {
            case "invite" when deed.Offered is Deeds.Offer offer:
                invitations.RemoveAll(v => v.From == a && v.To == b);
                invitations.Add(new Deeds.Invitation(a, b, offer, Elapsed, byLetter));
                deedLedger.Record("invite", a, b, Elapsed);
                if (ForcedOffer == offer) ForcedOffer = null;
                Trace?.Invoke($"deed {a} asks {b}: {offer.Tag}{(byLetter ? " (letter)" : "")}");
                break;
            case "accept" or "decline":
            {
                var k = invitations.FindLastIndex(v => v.From == b && v.To == a);
                if (k < 0) return;
                var invitation = invitations[k];
                invitations.RemoveAt(k);
                if (deed.Verb == "accept")
                {
                    Trace?.Invoke($"deed {a} accepts {invitation.Offer.Tag} from {b}");
                    Agree(Deeds.Deed.Invite(invitation.Offer), j, i, b);
                }
                else
                {
                    Trace?.Invoke($"deed {a} declines {invitation.Offer.Tag} from {b}");
                    Remember(a, b, L10n.Tr("%1$@ said no to %2$@'s invitation: %3$@", a, b, invitation.Offer.Title), "deed");
                }
                break;
            }
            default:
                Agree(deed, i, j, null);
                break;
        }
    }

    private void Agree(Deeds.Deed deed, int by, int with, string? asked) =>
        agreed.Add(new AgreedDeed { Deed = deed, By = by, With = with, Until = Elapsed + Settings.DeedWaitMinutes * 60, Asked = asked });

    /// <summary>A fact for the pair, when memory is kept.</summary>
    private void Remember(string a, string b, string text, string source)
    {
        if (!Settings.MemoryEnabled) return;
        Bonds.Change(book => book.Remember(a, b, text, source, Settings.MemoryFacts));
        Trace?.Invoke($"memory {Core.Bonds.Key(a, b)}: {text}");
    }

    // MARK: Every frame

    private void UpdateDeeds()
    {
        var open = Settings.InviteOpenMinutes * 60;
        foreach (var invitation in invitations.Where(v => Elapsed - v.At > open).ToList())
        {
            Trace?.Invoke($"deed {invitation.From}'s invitation to {invitation.To} lapsed");
            if (invitation.ByLetter)
                Remember(invitation.From, invitation.To,
                         L10n.Tr("%1$@'s invitation (%2$@) got no answer from %3$@", invitation.From, invitation.Offer.Title, invitation.To), "deed");
        }
        invitations.RemoveAll(v => Elapsed - v.At > open);
        if (agreed.Count > 0)
        {
            var waiting = new List<AgreedDeed>();
            foreach (var d in agreed.Where(d => d.By < creatures.Count && d.With < creatures.Count).ToList())
            {
                if (Perform(d)) continue;
                if (Elapsed > d.Until)
                {
                    Trace?.Invoke($"deed {d.Deed.Tag} by {Name(d.By)} lapsed: {Deeds.Refusal.Lapsed.Text()}");
                    if (d.Deed is { Verb: "invite", Offered: Deeds.Offer offer })
                        Remember(Name(d.By), Name(d.With), L10n.Tr("%1$@ and %2$@ agreed on %3$@, but never got to it", Name(d.By), Name(d.With), offer.Title), "deed");
                    continue;
                }
                waiting.Add(d);
            }
            agreed = waiting;
        }
        SteerVisitors();
    }

    /// <summary>Free for a deed: awake, on an edge, in nothing else.</summary>
    private bool FreeForDeed(int i)
    {
        if (i < 0 || i >= creatures.Count) return false;
        var c = creatures[i];
        return !busy.Contains(i) && !ExpectsPlane(i) && !c.IsJumping && !c.IsHeld && !c.LooksAsleep
            && !hideout.IsInside(i) && !letters.Contains(i) && CurrentGrab?.Index != i && held?.Index != i && !chats.Any(ch => ch.Involves(i));
    }

    /// <summary>Do <paramref name="d"/> if both are ready; true once it is done (or can never be).</summary>
    private bool Perform(AgreedDeed d)
    {
        string a = Name(d.By), b = Name(d.With);
        bool Done(string verb)
        {
            deedLedger.Record(verb, a, b, Elapsed);
            Trace?.Invoke($"deed {a} & {b} start: {d.Deed.Tag}");
            return true;
        }
        switch (d.Deed.Verb)
        {
            case "invite" when d.Deed.Offered is { Kind: Plays.Kind kind }:
                if (!Settings.PlayEnabled || IsNight) { Trace?.Invoke($"deed {kind.Raw()} refused: no games now"); return true; }
                if (play is not null || !FreeToPlay(d.By) || !FreeToPlay(d.With)) return false;
                if (StartPlay(kind, new[] { d.By, d.With }, d.Asked)) return Done("play");
                // Not on one outline, or no room here: the other comes over, and they try again.
                if (!d.Leapt)
                {
                    d.Leapt = true;
                    BringOver(d.With, d.By);
                }
                return false;
            case "invite":
                if (teaParty is not null || teaInvite is not null || !FreeForDeed(d.By) || !FreeForDeed(d.With)) return false;
                if (creatures[d.By].Spot.Loop == creatures[d.With].Spot.Loop && creatures[d.By].Segment == creatures[d.With].Segment)
                {
                    Hold(d.By, d.With);
                    if (StartTea(d.By, d.With)) return Done("tea");
                    EndChat(d.By, d.With, 0);
                }
                BringOver(d.With, d.By);
                teaInvite = (d.By, d.With, Elapsed + 5);
                return Done("tea");
            case "flower":
            {
                if (busy.Contains(d.By) || gifts.CurrentFlight is not null) return false;
                var flower = rng.Pick(Gifts.Flowers);
                if (!gifts.Give(flower, d.By, d.With, Elapsed)) return false;
                Shared(d.By, d.With, Core.Bonds.MomentKind.Flower, flower);
                return Done("flower");
            }
            case "letter":
                if (airmail is not null || !CanHandleMail(d.By) || !CanHandleMail(d.With)) return false;
                ThrowPlane(d.By, d.With, null);
                return Done("letter");
            case "visit":
            {
                var host = Enumerable.Range(0, creatures.Count).Cast<int?>()
                    .FirstOrDefault(k => string.Equals(Name(k!.Value), d.Deed.Name, StringComparison.OrdinalIgnoreCase));
                if (host is not int k) return true;
                if (!FreeForDeed(d.By)) return false;
                visiting[d.By] = (k, Elapsed + 60);
                return Done("visit");
            }
            case "follow":
                if (!FreeForDeed(d.By)) return false;
                following[d.By] = (d.With, Elapsed + Settings.FollowSeconds);
                return Done("follow");
            case "sleep":
                if (busy.Contains(d.By)) return false;
                if (!creatures[d.By].IsSleeping) creatures[d.By].ToggleNap(rng);
                return Done("sleep");
            default:
                return true;
        }
    }

    /// <summary><paramref name="guest"/> leaps to just in front of <paramref name="host"/>.</summary>
    private void BringOver(int guest, int host)
    {
        var h = creatures[host];
        var along = h.Loop.Direction(h.Segment);
        var gap = atlas.BodyHalfSize * (sizes[host] + sizes[guest]) * 1.5;
        var landing = new Pt(h.Position.X + along.Dx * h.Direction * gap, h.Position.Y + along.Dy * h.Direction * gap);
        creatures[guest].Leap(creatures[guest].World.Nearest(landing));
        Trace?.Invoke($"deed {Name(guest)} jumps over to {Name(host)}");
    }

    /// <summary>Walking over to someone, and trailing someone, every frame.</summary>
    private void SteerVisitors()
    {
        foreach (var (i, v) in visiting.ToList())
        {
            if (i >= creatures.Count || v.Host >= creatures.Count || Elapsed >= v.Until || busy.Contains(i)) { visiting.Remove(i); continue; }
            if (creatures[i].Spot.Loop != creatures[v.Host].Spot.Loop)
            {
                BringOver(i, v.Host);
                visiting.Remove(i);
            }
            else
            {
                // Walking up is enough: when the two touch, they meet as anyone does.
                creatures[i].HeadToward(creatures[v.Host].Spot.T, atlas.BodyHalfSize * (sizes[i] + sizes[v.Host]));
            }
        }
        foreach (var (i, f) in following.ToList())
        {
            if (i >= creatures.Count || f.Leader >= creatures.Count || Elapsed >= f.Until) { following.Remove(i); continue; }
            if (busy.Contains(i) || busy.Contains(f.Leader)) continue;
            creatures[i].Follow(creatures[f.Leader], (sizes[i] + sizes[f.Leader]) / 2 + 16);
        }
    }

    // MARK: Without a model

    /// <summary>A built-in invitation from <paramref name="i"/> to <paramref name="j"/>, if one is due: the share of letters and
    /// talks the owner set, to something offered (a rematch first). Null otherwise.</summary>
    private Deeds.Offer? BuiltInInvitation(int i, int j, Deeds.Options options)
    {
        if (ForcedOffer is Deeds.Offer offer && Deeds.Check(Deeds.Deed.Invite(offer), options) is null) return offer;
        if (rng.NextDouble() * 100 >= Settings.BuiltInInviteShare) return null;
        var rematch = Core.Bonds.LastLost(Name(i), Bonds.Bond(Name(i), Name(j)));
        return Deeds.BuiltInOffer(options, rng, rematch);
    }

    /// <summary>Whether the built-in answer of <paramref name="i"/> to <paramref name="j"/> is yes.</summary>
    private bool BuiltInYes(int i, int j) => ForcedAnswer ?? Deeds.BuiltInYes(Closeness(i, j), Settings.BuiltInAcceptChance, rng);
}
