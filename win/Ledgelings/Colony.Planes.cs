using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Paper planes: every so often one creature folds a note and throws it to
/// another across the screen. Its own wind and swirl carry it about, a dotted
/// trail behind it; the catcher stops, reads the note out, says something to
/// itself about it, and throws one answer back. An answer is read and thought
/// about, never answered. Words come from <see cref="Letters"/>, or from the model.</summary>
public sealed partial class Colony
{
    /// <summary>One plane's life, from the throw to the last puff of its trail.</summary>
    private sealed class Airmail
    {
        public abstract record Phase
        {
            public sealed record Flying : Phase;
            /// <summary>Caught, but the model is still writing: the letter is in hand, unread.</summary>
            public sealed record Waiting(double Since) : Phase;
            public sealed record Reading(double MusingAt, double DoneAt, bool MusingSaid) : Phase;
            /// <summary>Missed: the catcher fell asleep or went home. The plane fades where it is.</summary>
            public sealed record Dropped(double Since) : Phase;
            /// <summary>Read and put away; only the trail is still fading.</summary>
            public sealed record Done : Phase;
        }

        public int Id;
        public PaperPlane Plane = null!;
        public Phase Now = new Phase.Flying();
        /// <summary>An answer to an earlier plane: read, thought about, not answered again.</summary>
        public bool IsReply;
        /// <summary>Written by the model while the plane flies; null means use <see cref="Letters"/>.</summary>
        public string? Note;
        public string? Musing;
        public bool Writing;
        public string Provider = AppSettings.BrainTitle(BrainKind.Script);
        public string Model = "";
        public double? Cost;
        public int? Tokens;
    }

    /// <summary>Someone who just read a letter owes its sender one answer.</summary>
    /// <param name="Note">The note being answered, for the model.</param>
    /// <param name="Until">Give up if the two cannot be free for it by then.</param>
    private sealed record ReplyDue(int From, int To, string Note, double Until);

    private const double PlaneFade = 0.6;
    /// <summary>How long an owed answer waits for both ends to be free.</summary>
    private const double ReplyPatience = 20.0;
    private const double PlaneGivesUpAfter = 30.0;
    /// <summary>Longest the catcher holds an unread letter waiting for the model.</summary>
    private const double ModelWait = 8.0;

    /// <summary>The paper plane in the air, or being read; one at a time.</summary>
    private Airmail? airmail;
    /// <summary>How many planes have gone up, so a late model answer finds the right one.</summary>
    private int planeCount;
    /// <summary>Counts the time since the last plane, to know when the next is due.</summary>
    private readonly Post post = new(0);
    /// <summary>An answer owed once a letter has been read.</summary>
    private ReplyDue? replyDue;
    /// <summary>Creatures holding an open letter.</summary>
    private readonly HashSet<int> letters = new();
    /// <summary>The paper plane, and the letter it opens into: the plane sheet.</summary>
    private SpriteAtlas.Frames? planeSheet;
    private System.Drawing.Size planeCell;

    private SpriteAtlas.Frames PlaneFrames
    {
        get
        {
            if (planeSheet is null)
            {
                var plane = SpriteAtlas.Named("plane");
                planeSheet = plane.MakeFrames();
                planeCell = plane.CellSize;
            }
            return planeSheet;
        }
    }

    // MARK: Taking turns out loud (Colony.Talk)

    /// <summary>Out loud, someone is mid-conversation: a plane that lands waits to be read rather
    /// than talking over them. Filled by the talk (<c>VoiceIsTakenNow</c>); left false, the letter is read at once.</summary>
    partial void VoiceIsTaken(ref bool taken);

    private bool IsVoiceTaken()
    {
        var taken = false;
        VoiceIsTaken(ref taken);
        return taken;
    }

    // MARK: Sending

    /// <summary>Throw a plane now, from anyone free to anyone free. False when nobody can.</summary>
    public bool SendPlane()
    {
        if (airmail is not null) { TalkStatus = "a paper plane is already in the air"; return false; }
        if (hideout.IsActive) return false;
        var free = new Dictionary<int, Pt>();
        for (int i = 0; i < creatures.Count; i++) if (CanHandleMail(i)) free[i] = creatures[i].Position;
        if (Post.PickPair(free, rng) is not (int from, int to)) { TalkStatus = "nobody free to throw or catch a plane"; return false; }
        ThrowPlane(from, to, null);
        post.Stir(Elapsed);
        return true;
    }

    /// <summary>The throw itself: a short stop facing the catcher, then the plane, in
    /// weather of its own. <paramref name="answering"/>: the note this plane answers, if any.</summary>
    private void ThrowPlane(int from, int to, string? answering)
    {
        creatures[from].Meet(Facing(from, to), 0.9);
        var inward = creatures[from].Loop.Inward(creatures[from].Segment);
        planeCount += 1;
        var mail = new Airmail
        {
            Id = planeCount,
            Plane = PaperPlane.Thrown(from, to, Head(from), inward, Head(to), rng),
            IsReply = answering is not null,
        };
        KeepOnScreen(mail.Plane, sizes[to]);
        airmail = mail;
        if (Settings.TalkEnabled) WriteWithModel(from, to, planeCount, answering);
    }

    /// <summary>The plane flies over the screens only, no wingtip past an outer edge,
    /// drawn at <paramref name="scale"/>.</summary>
    private void KeepOnScreen(PaperPlane plane, double scale)
    {
        _ = PlaneFrames;
        plane.Sky = monitors.Select(m => m.Frame).ToList();
        plane.Margin = Math.Sqrt(planeCell.Width * planeCell.Width + planeCell.Height * planeCell.Height) * scale / 2;
    }

    /// <summary>A plane is on its way to <paramref name="i"/>: it keeps out of conversations so it is free to catch it.</summary>
    public bool ExpectsPlane(int i) => airmail is { Now: Airmail.Phase.Flying } mail && mail.Plane.To == i;

    /// <summary>Creature <paramref name="i"/> is holding a letter open, reading it.</summary>
    public bool HoldsLetter(int i) => letters.Contains(i);

    /// <summary>Awake, on an edge, not talking, not in the hand, not in the house.</summary>
    private bool CanHandleMail(int i)
    {
        var c = creatures[i];
        return !busy.Contains(i) && !hideout.IsInside(i) && !c.IsJumping && !c.IsHeld && !c.LooksAsleep && !c.IsChatting;
    }

    /// <summary>With a model: the note as the sender, then the reader's thought about it,
    /// both while the plane is still in the air.</summary>
    private void WriteWithModel(int from, int to, int id, string? answering)
    {
        if (Settings.Brain == BrainKind.Script || Settings.ChatClient() is not ChatClient service) return;
        var a = CharacterFor(from);
        var b = CharacterFor(to);
        string aKind = KindOf(from), bKind = KindOf(to);
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = a.Name, ["speakerKind"] = aKind, ["speakerPersona"] = a.Persona,
            ["listener"] = b.Name, ["listenerKind"] = bKind, ["listenerPersona"] = b.Persona,
            ["situation"] = AlmanacSentence, ["line"] = answering ?? "",
        };
        var system = Settings.SystemPrompt;
        string aSide = Relationship(from, to), bSide = Relationship(to, from);
        List<string> aLately = History.Memory.Recent(a.Name), bLately = History.Memory.Recent(b.Name);
        airmail!.Writing = true;
        airmail.Provider = service.ProviderTitle;
        airmail.Model = service.Model;
        TalkStatus = $"{a.Name} is writing {(answering is null ? "a letter" : "back")} via {service.Model}…";
        var prompt = answering is null ? Letters.NotePrompt : Letters.ReplyPrompt;
        var used = new List<Spend.Usage>();
        // Every call goes to the spend file, even one whose line turned out empty.
        void Charge(ChatClient.Answer answer)
        {
            if (answer.Usage is not Spend.Usage usage) return;
            if (service.Kind == ChatClient.Provider.LmStudio) usage.Cost = 0;
            used.Add(usage);
            Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Planes);
        }
        _ = Write();

        async Task Write()
        {
            string? note = null, musing = null;
            try
            {
                await service.CheckModel();
                var written = await service.Line(LineMemory.WithRecent(Core.Bonds.WithRelationship(system, vars, aSide), aLately),
                                                 Banter.Render(prompt, vars).Trim());
                Charge(written);
                var line = Banter.CleanLine(written.Text, a.Name, cut: written.Cut);
                if (line.Length > 0)
                {
                    note = line;
                    // Swap seats: now the reader thinks.
                    vars["speaker"] = b.Name; vars["speakerKind"] = bKind; vars["speakerPersona"] = b.Persona;
                    vars["listener"] = a.Name; vars["listenerKind"] = aKind; vars["listenerPersona"] = a.Persona;
                    vars["line"] = line;
                    var thought = await service.Line(LineMemory.WithRecent(Core.Bonds.WithRelationship(system, vars, bSide), bLately),
                                                     Banter.Render(Letters.MusingPrompt, vars));
                    Charge(thought);
                    var said = Banter.CleanLine(thought.Text, b.Name, cut: thought.Cut);
                    if (said.Length > 0) musing = said;
                }
            }
            catch (ChatClient.Failure e)
            {
                TalkStatus = e.Message;
                Console.Error.WriteLine("Ledgelings letter: " + e.Message);
            }
            if (airmail is not { } mail || mail.Id != id) return;
            mail.Note = note;
            mail.Musing = musing;
            mail.Writing = false;
            var priced = used.Where(u => u.Cost is not null).Select(u => u.Cost!.Value).ToList();
            mail.Cost = priced.Count == 0 ? null : priced.Sum();
            mail.Tokens = used.Count == 0 ? null : used.Sum(u => u.PromptTokens + u.CompletionTokens);
        }
    }

    // MARK: Every frame

    partial void UpdatePost(double dt)
    {
        post.QuietFor = Settings.PlanesEnabled ? Settings.PlaneMinutes * 60 : 0;
        if (airmail is null && replyDue is { } due)
        {
            if (Elapsed > due.Until || due.From >= creatures.Count || due.To >= creatures.Count || hideout.IsActive || IsNight)
                replyDue = null;
            else if (CanHandleMail(due.From) && CanHandleMail(due.To))
            {
                replyDue = null;
                ThrowPlane(due.From, due.To, due.Note);
            }
        }
        if (airmail is null && replyDue is null && post.IsDue(Elapsed))
        {
            if (IsNight || hideout.IsActive || !SendPlane()) post.Retry(Elapsed, 10);
        }
        if (airmail is not { } mail) return;
        int from = mail.Plane.From, to = mail.Plane.To;
        if (from >= creatures.Count || to >= creatures.Count)
        {
            letters.Clear(); airmail = null; busy.Remove(to); return;
        }

        switch (mail.Now)
        {
            case Airmail.Phase.Flying:
                if (hideout.IsActive || hideout.IsInside(to)) { mail.Now = new Airmail.Phase.Dropped(Elapsed); break; }
                var target = Head(to);
                mail.Plane.Fly(dt, target, Elapsed);
                var reach = atlas.BodyHalfSize * sizes[to] + 10;
                if (mail.Plane.Passed(reach, target))
                {
                    if (CanHandleMail(to)) mail.Now = CatchPlane(mail);
                    else if (creatures[to].LooksAsleep) mail.Now = new Airmail.Phase.Dropped(Elapsed);
                }
                if (mail.Now is Airmail.Phase.Flying && mail.Plane.Age > PlaneGivesUpAfter) mail.Now = new Airmail.Phase.Dropped(Elapsed);
                break;

            case Airmail.Phase.Waiting(var since):
                mail.Plane.FadeTrail(dt);
                // Out loud, a landed plane also waits for the conversation in progress
                // to end, up to a minute.
                var ready = !mail.Writing || Elapsed - since > ModelWait;
                if (ready && (!IsVoiceTaken() || Elapsed - since > 60)) mail.Now = StartReading(mail);
                break;

            case Airmail.Phase.Reading(var musingAt, var doneAt, var musingSaid):
                mail.Plane.FadeTrail(dt);
                if (!musingSaid && Elapsed >= musingAt)
                {
                    if (Settings.TalkEnabled && mail.Musing is string musing) Say(musing, to);
                    mail.Now = new Airmail.Phase.Reading(musingAt, doneAt, true);
                }
                else if (Elapsed >= doneAt)
                {
                    letters.Remove(to);
                    busy.Remove(to);
                    creatures[to].WalkOn(rng);
                    mail.Now = new Airmail.Phase.Done();
                    if (!mail.IsReply && mail.Note is string note) replyDue = new ReplyDue(to, from, note, Elapsed + ReplyPatience);
                }
                break;

            case Airmail.Phase.Dropped(var since):
                mail.Plane.FadeTrail(dt);
                if (Elapsed - since >= PlaneFade && mail.Plane.Trail.Count == 0) { airmail = null; return; }
                break;

            case Airmail.Phase.Done:
                mail.Plane.FadeTrail(dt);
                if (mail.Plane.Trail.Count == 0) { airmail = null; return; }
                break;
        }
    }

    /// <summary>The catcher stops and holds the letter; it reads as soon as the words are there.</summary>
    private Airmail.Phase CatchPlane(Airmail mail)
    {
        var to = mail.Plane.To;
        creatures[to].Meet(creatures[to].Direction, 120);
        busy.Add(to);
        letters.Add(to);
        return mail.Writing || IsVoiceTaken() ? new Airmail.Phase.Waiting(Elapsed) : StartReading(mail);
    }

    /// <summary>The note is read out, the thought follows, and it all goes in the chat history.</summary>
    private Airmail.Phase StartReading(Airmail mail)
    {
        int from = mail.Plane.From, to = mail.Plane.To;
        string a = CharacterFor(from).Name, b = CharacterFor(to).Name;
        bool modelWrote = mail.Note is not null, modelMused = mail.Musing is not null;
        var note = mail.Note ?? (mail.IsReply ? Letters.Reply(a, b, rng, History.Memory) : Letters.Note(a, b, rng, History.Memory));
        var musing = mail.Musing ?? Letters.Musing(b, a, rng, History.Memory);
        mail.Note = note;
        mail.Musing = musing;
        if (!Settings.TalkEnabled) return new Airmail.Phase.Reading(Elapsed, Elapsed + 3, true);

        var read = Letters.Reading(note, a);
        TalkStatus = $"{b} got {(mail.IsReply ? "an answer" : "a paper plane")} from {a}";
        var exchange = new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now,
            Situation = mail.IsReply ? $"{a} wrote back to {b} by paper plane." : $"{a} sent {b} a paper plane.",
            Provider = modelWrote ? mail.Provider : AppSettings.BrainTitle(BrainKind.Script), Model = modelWrote ? mail.Model : "",
            Lines = new List<ChatLog.Line> { new(a, note), new(b, musing) },
            Cost = mail.Cost, Tokens = mail.Tokens,
        };
        if (IsVoiced)
        {
            // Out loud: the thought follows a beat after the note is read, and the
            // catcher walks on a second after the thought, whenever that is.
            History.Record(exchange);
            var plane = planeCount;
            _ = SayInTurns(new[] { (to, read, !modelWrote), (to, musing, !modelMused) }, () =>
            {
                if (planeCount != plane || airmail is not { Now: Airmail.Phase.Reading } current) return;
                current.Now = new Airmail.Phase.Reading(Elapsed, Elapsed + 1, true);
            });
            return new Airmail.Phase.Reading(double.PositiveInfinity, double.PositiveInfinity, true);
        }
        Say(read, to, builtIn: !modelWrote);
        var musingAt = Elapsed + Banter.ShowTime(read, Settings.BubbleSeconds) * 0.6;
        var doneAt = musingAt + Banter.ShowTime(musing, Settings.BubbleSeconds) * 0.6 + 1;
        History.Record(exchange);
        return new Airmail.Phase.Reading(musingAt, doneAt, false);
    }

    // MARK: Drawing

    private PlaneSnapshot? MailSnapshot()
    {
        if (airmail is not { } mail) return null;
        var to = mail.Plane.To;
        var scale = to < sizes.Count ? sizes[to] : 2;
        var opacity = mail.Now switch
        {
            Airmail.Phase.Flying => 1f,
            Airmail.Phase.Dropped(var since) => (float)Math.Max(0, 1 - (Elapsed - since) / PlaneFade),
            _ => 0f,
        };
        var life = mail.Plane.PuffLife;
        var (view, flipped) = mail.Plane.CurrentView;
        return new PlaneSnapshot(PlaneImage(view), mail.Plane.Position, mail.Plane.Heading, flipped, scale, opacity,
            mail.Plane.Trail.Select(p => (p.Position, (float)Math.Max(0, 1 - p.Age / life) * 0.8f)).ToList(),
            Math.Max(2, Math.Round(scale * 1.5)));
    }

    /// <summary>The plane drawn at one roll; the side view if the sheet has no such drawing.</summary>
    private System.Drawing.Bitmap? PlaneImage(PaperPlane.View view) =>
        PlaneFrames.Frame(PaperPlane.Animation(view), 0) ?? PlaneFrames.Frame("fly", 0);

    /// <summary>The unfolded note creature <paramref name="i"/> holds out while it reads, if any.</summary>
    private System.Drawing.Bitmap? LetterImage(int i) => letters.Contains(i) ? PlaneFrames.Frame("letter", 0) : null;
}
