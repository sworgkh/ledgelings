using System.Drawing;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Reminders: when one comes due, a creature stops, folds it into a paper
/// plane and throws it at the user. The plane swirls across the sky to the
/// middle of the screen, growing as it comes, turns head-on and rushes at you,
/// then unfolds into a letter: your reminder, a note from the thrower in its
/// own voice, its signature. A click folds the letter back into a plane that
/// flies off; so does time, but only while you are at the computer.</summary>
public sealed partial class Colony
{
    private sealed class Delivery
    {
        public abstract record Phase
        {
            /// <summary>Looking for someone free to throw it, since then.</summary>
            public sealed record Finding(double Since) : Phase;
            /// <summary>The thrower has stopped and is winding up.</summary>
            public sealed record Windup(double Until) : Phase;
            public sealed record Flying : Phase;
            /// <summary>Over the middle: turns head-on and comes at you, from where and how big it was.</summary>
            public sealed record Arriving(double Since, Pt From, double Scale) : Phase;
            /// <summary>Head-on in the middle, waiting for the model's note (a few seconds at most).</summary>
            public sealed record Hovering(double Since) : Phase;
            public sealed record Opening(double Since) : Phase;
            /// <summary>The letter is up; <c>Shown</c> counts only the time the user was at the computer.</summary>
            public sealed record Open(double Since, double Shown) : Phase;
            public sealed record Closing(double Since) : Phase;
            /// <summary>Folded again, flying off the screen.</summary>
            public sealed record Leaving(double Since) : Phase;
        }

        public int Id;
        public Reminders.Reminder Reminder = null!;
        /// <summary>The creature throwing it; null when nobody could, and it comes in from below.</summary>
        public int? Thrower;
        /// <summary>Who signs the letter.</summary>
        public string Writer = L10n.Tr("The Ledgelings");
        public Bitmap? Stamp;
        public PaperPlane Plane = null!;
        /// <summary>The middle of the screen the user is on, and that screen.</summary>
        public Pt Target;
        public Rect Screen;
        public double StartDistance = 1;
        public double BaseScale = 2.5;
        public Phase Now = null!;
        public string? Note;
        /// <summary>The letter's top line, decided as it opens.</summary>
        public string Title = "";
        public bool Writing;
        public string Provider = AppSettings.BrainTitle(BrainKind.Script);
        public string Model = "";
        public double? Cost;
        public int? Tokens;
        /// <summary>Where the plane is drawn outside the physics: arriving, hovering, opening.</summary>
        public Pt ShownAt = Pt.Zero;
        public double ShownScale = 2;
    }

    private const double ReminderWindup = 0.6;
    private const double ReminderArrive = 0.6;
    private const double ReminderOpen = 0.55;
    private const double ReminderClose = 0.3;
    /// <summary>Longest a thrower is looked for before anyone at all will do.</summary>
    private const double ReminderFindFor = 3.0;
    /// <summary>Longest the plane hovers in the middle waiting for the model's note.</summary>
    private const double ReminderModelWait = 4.0;
    /// <summary>Longest a reminder plane flies before it is pulled to the middle anyway.</summary>
    private const double ReminderFlightLimit = 7.0;
    /// <summary>How close to the middle counts as there.</summary>
    private const double ReminderReach = 40;
    /// <summary>The plane head-on is this many times its flying size when it opens.</summary>
    private const double ReminderZoom = 3.2;
    /// <summary>The user counts as away after this long without touching anything.</summary>
    public const double AwayAfter = 30.0;

    private ReminderBook? reminderBook;
    /// <summary>What the user asked to be reminded of, and when: <c>reminders.json</c> beside the
    /// spend file unless the app hands its own book over.</summary>
    public ReminderBook ReminderBook
    {
        get => reminderBook ??= new ReminderBook(Spend.Ledger.Directory);
        set => reminderBook = value;
    }

    /// <summary>The reminder on its way to the user, or open on the screen; one at a time.</summary>
    private Delivery? delivery;
    /// <summary>Reminders that came due while another was being delivered, oldest first.</summary>
    private readonly List<Reminders.Reminder> deliveryQueue = new();
    /// <summary>How many reminders have gone up, so a late model answer finds the right one.</summary>
    private int deliveryCount;
    /// <summary>Reminders are looked at once a second, not every frame.</summary>
    private double nextReminderCheck;
    /// <summary>Seconds since the user last touched the mouse or keyboard; an open letter waits for them.</summary>
    public Func<double> UserIdleSeconds { get; set; } = Desktop.IdleSeconds;

    /// <summary>A reminder is on its way or open on the screen.</summary>
    public bool IsDelivering => delivery is not null;

    // MARK: Checking the clock

    partial void UpdateReminders(double dt)
    {
        if (Elapsed >= nextReminderCheck)
        {
            nextReminderCheck = Elapsed + 1;
            if (Settings.RemindersEnabled)
            {
                var at = Now();
                var queued = deliveryQueue.Select(r => r.Id).ToHashSet();
                if (delivery is not null) queued.Add(delivery.Reminder.Id);
                foreach (var reminder in ReminderBook.Book.Due(at).Where(r => !queued.Contains(r.Id)))
                {
                    deliveryQueue.Add(reminder with { });
                    ReminderBook.MarkSent(reminder.Id, at);
                }
            }
        }
        if (delivery is null && deliveryQueue.Count > 0) StartDelivery(TakeFirstQueued());
        StepDelivery(dt);
    }

    private Reminders.Reminder TakeFirstQueued()
    {
        var first = deliveryQueue[0];
        deliveryQueue.RemoveAt(0);
        return first;
    }

    /// <summary>Someone on screen to peek over the paper note: awake if anyone is, with its idle frame.</summary>
    public (string Name, Bitmap? Face)? NoteKeeper()
    {
        var there = Enumerable.Range(0, creatures.Count).Where(i => !hideout.IsInside(i)).ToList();
        var awake = there.Where(i => !creatures[i].LooksAsleep).ToList();
        var pool = awake.Count > 0 ? awake : there;
        if (pool.Count == 0 || frames.Count <= pool.Max()) return null;
        var i = rng.Pick(pool);
        return (CharacterFor(i).Name, frames[i].Frame("idle", 0));
    }

    /// <summary>Deliver <paramref name="reminder"/> now, whatever its time: the Send Now button, the test letter.</summary>
    public void DeliverNow(Reminders.Reminder reminder)
    {
        deliveryQueue.Add(reminder);
        if (delivery is null) StartDelivery(TakeFirstQueued());
    }

    /// <summary>The screen the cursor is on.</summary>
    private Rect TargetScreen()
    {
        var cursor = Desktop.Cursor();
        return (monitors.FirstOrDefault(m => m.Frame.Contains(cursor)) ?? monitors.FirstOrDefault())?.Frame ?? new Rect(0, -900, 1440, 900);
    }

    private void StartDelivery(Reminders.Reminder reminder)
    {
        var screen = TargetScreen();
        var target = new Pt(screen.X + screen.Width / 2, screen.Y + screen.Height / 2);
        deliveryCount += 1;
        delivery = new Delivery
        {
            Id = deliveryCount, Reminder = reminder, Thrower = null, Writer = L10n.Tr("The Ledgelings"),
            Plane = new PaperPlane(-1, -1, target, new Vec(0, 1), target),
            Target = target, Screen = screen, BaseScale = 2.5, Now = new Delivery.Phase.Finding(Elapsed),
        };
    }

    /// <summary>Anyone free to throw; after a few seconds, anyone on screen at all; null when nobody is.</summary>
    private int? PickThrower(bool desperate)
    {
        var free = Enumerable.Range(0, creatures.Count).Where(i => CanHandleMail(i) && !ExpectsPlane(i)).ToList();
        if (free.Count > 0) return rng.Pick(free);
        if (!desperate) return null;
        var there = Enumerable.Range(0, creatures.Count).Where(i => !hideout.IsInside(i) && !creatures[i].IsHeld).ToList();
        foreach (var i in there) if (!creatures[i].LooksAsleep) return i;
        return there.Count == 0 ? null : rng.Pick(there);
    }

    /// <summary>The thrower stops, and the plane leaves its head in weather of its own.</summary>
    private void Launch(Delivery mail, int? thrower)
    {
        mail.Thrower = thrower;
        var start = new Pt(mail.Target.X + rng.Range(-200, 200), mail.Screen.MinY - 16);
        var inward = new Vec(0, 1);
        if (thrower is int i)
        {
            creatures[i].Meet(creatures[i].Direction, ReminderWindup + 0.6);
            start = Head(i);
            inward = creatures[i].Loop.Inward(creatures[i].Segment);
            mail.Writer = CharacterFor(i).Name;
            mail.BaseScale = sizes[i];
            mail.Stamp = i < frames.Count ? frames[i].Frame("idle", 0) : null;
        }
        var plane = PaperPlane.Thrown(thrower ?? -1, -1, start, inward, mail.Target, rng);
        // A reminder is in a hurry: less swirl, quicker to the middle.
        plane.Swirl *= 0.5;
        plane.Cruise = Math.Max(plane.Cruise, 420);
        // It grows as it nears the middle: kept in by its largest size.
        KeepOnScreen(plane, mail.BaseScale * 1.8);
        mail.Plane = plane;
        mail.StartDistance = Math.Max(1, plane.DistanceTo(mail.Target));
        mail.ShownScale = mail.BaseScale;
        if (Settings.TalkEnabled && thrower is not null) WriteReminderNote(mail);
    }

    // MARK: Every frame

    private void StepDelivery(double dt)
    {
        if (delivery is not { } mail) return;
        if (mail.Thrower is int t && t >= creatures.Count) mail.Thrower = null;
        switch (mail.Now)
        {
            case Delivery.Phase.Finding(var since):
            {
                var desperate = Elapsed - since >= ReminderFindFor || hideout.IsActive;
                if (PickThrower(desperate) is int thrower)
                {
                    Launch(mail, thrower);
                    mail.Now = new Delivery.Phase.Windup(Elapsed + ReminderWindup);
                }
                else if (desperate)
                {
                    Launch(mail, null);
                    mail.Now = new Delivery.Phase.Flying();
                }
                break;
            }

            case Delivery.Phase.Windup(var until):
                if (Elapsed >= until) mail.Now = new Delivery.Phase.Flying();
                break;

            case Delivery.Phase.Flying:
            {
                mail.Plane.Fly(dt, mail.Target, Elapsed);
                var progress = 1 - Math.Min(1, mail.Plane.DistanceTo(mail.Target) / mail.StartDistance);
                // Coming closer to you: it grows as it nears the middle.
                mail.ShownScale = mail.BaseScale * (1 + 0.8 * progress * progress);
                if (mail.Plane.Passed(ReminderReach, mail.Target) || mail.Plane.Age > ReminderFlightLimit)
                    mail.Now = new Delivery.Phase.Arriving(Elapsed, mail.Plane.Position, mail.ShownScale);
                break;
            }

            case Delivery.Phase.Arriving(var since, var from, var scale):
            {
                mail.Plane.FadeTrail(dt);
                var k = Math.Min(1, (Elapsed - since) / ReminderArrive);
                var ease = k * k;                     // speeding up as it comes at you
                mail.ShownAt = new Pt(from.X + (mail.Target.X - from.X) * k, from.Y + (mail.Target.Y - from.Y) * k);
                mail.ShownScale = scale + (mail.BaseScale * ReminderZoom - scale) * ease;
                if (k >= 1)
                {
                    if (mail.Writing) mail.Now = new Delivery.Phase.Hovering(Elapsed);
                    else BeginOpening(mail);
                }
                break;
            }

            case Delivery.Phase.Hovering(var since):
                mail.Plane.FadeTrail(dt);
                mail.ShownAt = new Pt(mail.Target.X, mail.Target.Y + 6 * Math.Sin((Elapsed - since) * 4));
                if (!mail.Writing || Elapsed - since > ReminderModelWait) BeginOpening(mail);
                break;

            case Delivery.Phase.Opening(var since):
                mail.Plane.FadeTrail(dt);
                mail.ShownAt = mail.Target;
                if (Elapsed - since >= ReminderOpen) mail.Now = new Delivery.Phase.Open(Elapsed, 0);
                break;

            case Delivery.Phase.Open(var since, var shown):
            {
                // The clock only runs while someone is there to read it.
                var here = UserIdleSeconds() < AwayAfter;
                var now = shown + (here ? dt : 0);
                mail.Now = now >= Settings.ReminderLetterSeconds ? new Delivery.Phase.Closing(Elapsed) : new Delivery.Phase.Open(since, now);
                break;
            }

            case Delivery.Phase.Closing(var since):
                if (Elapsed - since >= ReminderClose)
                {
                    // Folded again: off it goes, up and away over the top of the screen.
                    var away = new Pt(mail.Target.X + (rng.Coin() ? 1 : -1) * mail.Screen.Width * 0.7,
                                      mail.Screen.MaxY + mail.Screen.Height * 0.4);
                    var plane = PaperPlane.Thrown(-1, -1, mail.Target, new Vec(0, 1), away, rng);
                    plane.Swirl *= 0.3;
                    plane.Cruise = 700;
                    mail.Plane = plane;
                    mail.Now = new Delivery.Phase.Leaving(Elapsed);
                }
                break;

            case Delivery.Phase.Leaving(var since):
            {
                var gone = !mail.Screen.InsetBy(-80, -80).Contains(mail.Plane.Position) || Elapsed - since > 3;
                if (gone)
                {
                    // Off the screen: only its trail is left, fading.
                    mail.Plane.FadeTrail(dt);
                    if (mail.Plane.Trail.Count == 0) { delivery = null; return; }
                }
                else
                {
                    var away = new Pt(mail.Target.X, mail.Screen.MaxY + mail.Screen.Height);
                    mail.Plane.Fly(dt, away, Elapsed);
                    var k = Math.Min(1, (Elapsed - since) / 1.2);
                    mail.ShownScale = mail.BaseScale * (ReminderZoom - (ReminderZoom - 1) * k);
                }
                break;
            }
        }
    }

    /// <summary><paramref name="writer"/> reads <paramref name="note"/> out loud as the letter opens, in its own voice
    /// and with no bubble (Mac: <c>voice?.say(note, as:, builtIn:)</c>). The voice port fills it; it is only
    /// called with voice on, Read Aloud on, and a creature (not nobody) throwing the plane.</summary>
    partial void ReadReminderAloud(string note, string writer, bool builtIn);

    /// <summary>The plane starts to unfold: the note is decided, logged with the chats, and read out loud if asked.</summary>
    private void BeginOpening(Delivery mail)
    {
        var modelWrote = mail.Note is not null;
        var note = mail.Note ?? Core.Reminders.Note(mail.Writer, mail.Reminder.Text, rng);
        mail.Note = note;
        mail.Writing = false;
        mail.Now = new Delivery.Phase.Opening(Elapsed);
        var now = Now();
        var late = (now - mail.Reminder.Time).TotalSeconds > 120;
        mail.Title = late
            ? L10n.Tr("REMINDER · for %@", Core.Reminders.When(mail.Reminder.Time, now))
            : L10n.Tr("REMINDER · %@", mail.Reminder.Time.ToLocalTime().ToString("HH:mm", System.Globalization.CultureInfo.InvariantCulture));
        TalkStatus = L10n.Tr("%@ delivered a reminder: %@", mail.Writer, mail.Reminder.Text);
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now,
            Situation = L10n.Tr("%@ brought you a reminder by paper plane: \"%@\".", mail.Writer, mail.Reminder.Text),
            Provider = modelWrote ? mail.Provider : AppSettings.BrainTitle(BrainKind.Script), Model = modelWrote ? mail.Model : "",
            Lines = new List<ChatLog.Line> { new(mail.Writer, note) },
            Cost = mail.Cost, Tokens = mail.Tokens,
        });
        if (Settings.ReminderReadAloud && IsVoiced && mail.Thrower is not null) ReadReminderAloud(note, mail.Writer, !modelWrote);
    }

    /// <summary>Fold the letter away now (a click on it).</summary>
    public void CloseLetter()
    {
        if (delivery is not { Now: Delivery.Phase.Open } mail) return;
        mail.Now = new Delivery.Phase.Closing(Elapsed);
    }

    /// <summary>With a model: the note, in the thrower's voice, while the plane is in the air.</summary>
    private void WriteReminderNote(Delivery mail)
    {
        if (Settings.Brain == BrainKind.Script || Settings.ChatClient() is not ChatClient service || mail.Thrower is not int i) return;
        var me = CharacterFor(i);
        var vars = new Dictionary<string, string>
        {
            ["speaker"] = me.Name, ["speakerKind"] = Banter.Spoken(KindOf(i)), ["speakerPersona"] = Banter.Persona(me.Persona),
            ["listener"] = L10n.Tr("you"), ["listenerKind"] = L10n.Tr("the person at the computer"),
            ["listenerPersona"] = L10n.Tr("The person whose screen you all live on."),
            ["situation"] = AlmanacSentence, ["reminder"] = mail.Reminder.Text,
        };
        var system = Core.Bonds.WithRelationship(Settings.SystemPrompt, vars, "");
        var user = Banter.Render(Core.Reminders.NotePrompt, vars).Trim();
        var id = mail.Id;
        mail.Writing = true;
        mail.Provider = service.ProviderTitle;
        mail.Model = service.Model;
        TalkStatus = L10n.Tr("%@ is writing a reminder via %@…", me.Name, service.Model);
        _ = Write();

        async Task Write()
        {
            string? note = null;
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
                    Spend.Record(service.Kind, service.Model, usage, Core.Spend.Purpose.Reminders);
                    cost = usage.Cost;
                    tokens = usage.PromptTokens + usage.CompletionTokens;
                }
                var line = Banter.CleanLine(answer.Text, me.Name, cut: answer.Cut);
                if (line.Length > 0) note = line;
            }
            catch (ChatClient.Failure e)
            {
                TalkStatus = e.Message;
                Console.Error.WriteLine("Ledgelings reminder: " + e.Message);
            }
            if (delivery is not { } current || current.Id != id || !current.Writing) return;
            current.Note = note;
            current.Cost = cost;
            current.Tokens = tokens;
            current.Writing = false;
        }
    }

    // MARK: Drawing

    private ReminderSnapshot? DeliverySnapshot()
    {
        if (delivery is not { } mail) return null;
        var life = mail.Plane.PuffLife;
        var puffs = mail.Plane.Trail.Select(p => (p.Position, (float)Math.Max(0, 1 - p.Age / life) * 0.8f)).ToList();
        var puffSize = Math.Max(2, Math.Round(mail.BaseScale * 1.5));
        PlaneSnapshot Plane(Bitmap? image, Pt at, double heading, double scale, bool flipped = false, float opacity = 1) =>
            new(image, at, heading, flipped, scale, opacity, puffs, puffSize);
        PlaneSnapshot Nothing() => Plane(null, mail.Target, 0, 0, opacity: 0);
        switch (mail.Now)
        {
            case Delivery.Phase.Finding or Delivery.Phase.Windup:
                return null;
            case Delivery.Phase.Flying or Delivery.Phase.Leaving:
            {
                var (view, flipped) = mail.Plane.CurrentView;
                return new ReminderSnapshot(Plane(PlaneImage(view), mail.Plane.Position, mail.Plane.Heading, mail.ShownScale, flipped), null);
            }
            case Delivery.Phase.Arriving(var since, _, _):
            {
                // Half-way in it turns to face you, levelling its roll as it swings round.
                var k = (Elapsed - since) / ReminderArrive;
                var heading = k < 0.5 ? mail.Plane.Heading * (1 - k * 2) : 0;
                var (view, flipped) = PaperPlane.ViewAt(mail.Plane.Roll * Math.Max(0, 1 - k * 2));
                return new ReminderSnapshot(Plane(k < 0.5 ? PlaneImage(view) : PlaneFrames.Frame("front", 0),
                    mail.ShownAt, heading, mail.ShownScale, k < 0.5 && flipped), null);
            }
            case Delivery.Phase.Hovering:
                return new ReminderSnapshot(Plane(PlaneFrames.Frame("front", 0), mail.ShownAt, 0, mail.ShownScale), null);
            case Delivery.Phase.Opening(var since):
            {
                var k = (Elapsed - since) / ReminderOpen;
                if (k < 0.3) return new ReminderSnapshot(Plane(PlaneFrames.Frame("opening", 0), mail.Target, 0, mail.ShownScale), null);
                if (k < 0.6) return new ReminderSnapshot(Plane(PlaneFrames.Frame("letter", 0), mail.Target, 0, mail.ShownScale * (1 + (k - 0.3) * 2)), null);
                // The sheet spreads out to its full size, a touch past it, and settles.
                var spread = (k - 0.6) / 0.4;
                return new ReminderSnapshot(Nothing(), Letter(mail, 0.3 + 0.78 * spread, 1));
            }
            case Delivery.Phase.Open(var since, _):
            {
                var settle = Math.Min(1, (Elapsed - since) / 0.15);
                return new ReminderSnapshot(Nothing(), Letter(mail, 1.08 - 0.08 * settle, 1));
            }
            case Delivery.Phase.Closing(var since):
            {
                var k = Math.Min(1, (Elapsed - since) / ReminderClose);
                return new ReminderSnapshot(Nothing(), Letter(mail, 1 - 0.8 * k, (float)(1 - k)));
            }
        }
        return null;
    }

    private static LetterSnapshot Letter(Delivery mail, double grow, float opacity) =>
        new(mail.Id, mail.Target, grow, opacity, mail.Title, mail.Reminder.Text, mail.Note ?? "", "— " + mail.Writer,
            mail.Stamp, L10n.Tr("click to fold it away"));

    /// <summary>The open letter is under <paramref name="point"/>.</summary>
    private bool LetterContains(Pt point) =>
        delivery is { Now: Delivery.Phase.Open } && overlays.Any(o => o.LetterFrame is Rect frame && frame.Contains(point));
}
