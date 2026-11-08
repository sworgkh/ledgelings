namespace Ledgelings.Core;

/// <summary>
/// Who is in the gang, and the plot twist when that changes (SPEC §6.5.2.4). The Mac's <c>Gang</c>,
/// kept in <c>bonds.json</c> under <c>gang</c> in the same shape.
///
/// The <b>roster</b> keeps every character who has ever been on screen, with when it was first and
/// last seen. When the gang changes it records an <b>event</b>: a newcomer <b>joined</b>, someone
/// <b>left</b>, or someone who left <b>came back</b>. A change counts once it has held for
/// <see cref="Settle"/> seconds, so dragging the count up and down again is nobody's arrival.
/// Sleeping, hiding in the house or moving to another monitor keeps a character on screen.
///
/// On the first look everyone on screen is already known, and so is everyone the bonds remember:
/// no twist about the whole gang on day one. For a few days after an event the others talk about it:
/// the <b>news</b> rides in the prompts already sent, now and then, the chance fading as it gets old.
/// </summary>
public static partial class Gang
{
    /// <summary>A change of the gang counts once it has held this long, in seconds.</summary>
    public const double Settle = 120;
    /// <summary>Events kept, newest last.</summary>
    public const int EventsKept = 40;

    /// <summary>The kinds of event, as written in <c>bonds.json</c>.</summary>
    public static class EventKind
    {
        public const string Joined = "joined", Left = "left", Returned = "returned";
    }

    public sealed record Member
    {
        public string Name { get; set; } = "";
        /// <summary>Its species' <c>kind</c>, as last seen.</summary>
        public string? Kind { get; set; }
        public DateTimeOffset FirstSeen { get; set; }
        public DateTimeOffset LastSeen { get; set; }
        /// <summary>Just arrived, not yet on screen for <see cref="Settle"/>: not a member until then.</summary>
        public bool Pending { get; set; }
        /// <summary>Gone since, when it has left the gang.</summary>
        public DateTimeOffset? Away { get; set; }
        /// <summary>Back on screen since, while a return is settling.</summary>
        public DateTimeOffset? BackSince { get; set; }
    }

    public sealed record Event
    {
        public string Kind { get; set; } = EventKind.Joined;
        public string Name { get; set; } = "";
        /// <summary>Its species' <c>kind</c>.</summary>
        public string? Species { get; set; }
        public DateTimeOffset Time { get; set; }
        /// <summary>For a return: when it had left.</summary>
        public DateTimeOffset? AwaySince { get; set; }

        public Event() { }
        public Event(string kind, string name, string? species, DateTimeOffset time, DateTimeOffset? awaySince = null)
        {
            Kind = kind; Name = name; Species = species; Time = time; AwaySince = awaySince;
        }
    }

    public sealed class Roster
    {
        public Dictionary<string, Member> Members { get; set; } = new();
        public List<Event> Events { get; set; } = new();
        /// <summary>The first look, when everyone then on screen became known without a twist.</summary>
        public DateTimeOffset? Started { get; set; }

        public override bool Equals(object? obj) => obj is Roster o && o.Started == Started && o.Events.SequenceEqual(Events)
            && o.Members.Count == Members.Count && o.Members.All(kv => Members.TryGetValue(kv.Key, out var m) && m == kv.Value);
        public override int GetHashCode() => HashCode.Combine(Members.Count, Events.Count, Started);

        /// <summary>The characters on screen now (name → its species' kind): who arrived, who left and who
        /// came back, once each change has held <paramref name="settle"/> seconds. <paramref name="known"/>: names
        /// the bonds remember, taken as old members on the first look.</summary>
        public List<Event> Observe(IReadOnlyDictionary<string, string> present, DateTimeOffset now,
                                   IEnumerable<string>? known = null, double settle = Settle)
        {
            if (Started is null)
            {
                Started = now;
                foreach (var (name, kind) in present) Members[name] = new Member { Name = name, Kind = kind, FirstSeen = now, LastSeen = now };
                foreach (var name in known ?? Enumerable.Empty<string>())
                    if (!present.ContainsKey(name) && !Members.ContainsKey(name))
                        Members[name] = new Member { Name = name, FirstSeen = now, LastSeen = now, Away = now };
                return new();
            }
            var output = new List<Event>();
            foreach (var (name, kind) in present)
            {
                if (!Members.TryGetValue(name, out var m))
                {
                    Members[name] = new Member { Name = name, Kind = kind, FirstSeen = now, LastSeen = now, Pending = settle > 0 };
                    if (settle <= 0) output.Add(new Event(EventKind.Joined, name, kind, now));
                    continue;
                }
                m.Kind = kind;
                if (m.Pending && (now - m.FirstSeen).TotalSeconds >= settle)
                {
                    m.Pending = false;
                    output.Add(new Event(EventKind.Joined, name, kind, m.FirstSeen));
                }
                if (m.Away is DateTimeOffset away)
                {
                    var since = m.BackSince ?? now;
                    m.BackSince = since;
                    if ((now - since).TotalSeconds >= settle)
                    {
                        output.Add(new Event(EventKind.Returned, name, kind, since, away));
                        m.Away = null; m.BackSince = null;
                    }
                }
                m.LastSeen = now;
            }
            foreach (var (name, m) in Members.ToList())
            {
                if (present.ContainsKey(name)) continue;
                if (m.Pending) { Members.Remove(name); continue; }
                m.BackSince = null;
                if (m.Away is null && (now - m.LastSeen).TotalSeconds >= settle)
                {
                    m.Away = m.LastSeen;
                    output.Add(new Event(EventKind.Left, name, m.Kind, m.LastSeen));
                }
            }
            output = output.OrderBy(e => e.Time).ThenBy(e => e.Name, StringComparer.Ordinal).ToList();
            Record(output);
            return output;
        }

        /// <summary>An event made by hand (<c>--twist</c>), the member's state to match.</summary>
        public Event Fake(string kind, string name, string? species, DateTimeOffset now)
        {
            Started ??= now;
            if (!Members.TryGetValue(name, out var m)) Members[name] = m = new Member { Name = name, Kind = species, FirstSeen = now, LastSeen = now };
            Event e;
            switch (kind)
            {
                case EventKind.Joined:
                    m.FirstSeen = now; m.Pending = false; m.Away = null;
                    e = new Event(EventKind.Joined, name, species ?? m.Kind, now);
                    break;
                case EventKind.Left:
                    m.Away = now; m.BackSince = null;
                    e = new Event(EventKind.Left, name, species ?? m.Kind, now);
                    break;
                default:
                    var since = m.Away ?? now.AddDays(-3);
                    m.Away = null; m.BackSince = null;
                    e = new Event(EventKind.Returned, name, species ?? m.Kind, now, since);
                    break;
            }
            m.LastSeen = now;
            Record(new[] { e });
            return e;
        }

        private void Record(IReadOnlyCollection<Event> fresh)
        {
            if (fresh.Count == 0) return;
            Events = Events.Concat(fresh).TakeLast(EventsKept).ToList();
        }

        /// <summary>The news still fresh: each character's newest event from the last <paramref name="days"/>
        /// days, oldest first. <paramref name="departures"/> false: leaving and coming back are left out.</summary>
        public List<Event> Fresh(int days, DateTimeOffset now, bool departures = true)
        {
            var window = Math.Max(0, days) * 86_400.0;
            var newest = new Dictionary<string, Event>();
            foreach (var e in Events)
            {
                if ((now - e.Time).TotalSeconds >= window || e.Time > now.AddSeconds(60)) continue;
                if (newest.TryGetValue(e.Name, out var had) && had.Time > e.Time) continue;
                newest[e.Name] = e;
            }
            return newest.Values.Where(e => departures || e.Kind == EventKind.Joined)
                .OrderBy(e => e.Time).ThenBy(e => e.Name, StringComparer.Ordinal).ToList();
        }

        /// <summary>The newcomers still fresh: a joined event in the last <paramref name="days"/> days.</summary>
        public HashSet<string> Newcomers(int days, DateTimeOffset now) =>
            Fresh(days, now).Where(e => e.Kind == EventKind.Joined).Select(e => e.Name).ToHashSet();

        public void ForgetNews() => Events = new();
    }

    // MARK: How often it comes up

    /// <summary>The chance this conversation brings the news up: <paramref name="chance"/> (0..1) while the newest
    /// event is new, fading to nothing once it is <paramref name="days"/> days old.</summary>
    public static double Chance(double chance, IReadOnlyList<Event> events, int days, DateTimeOffset now)
    {
        if (events.Count == 0 || days <= 0) return 0;
        var window = days * 86_400.0;
        var age = Math.Max(0, (now - events.Max(e => e.Time)).TotalSeconds);
        if (age >= window) return 0;
        return Math.Clamp(chance, 0, 1) * (1 - age / window);
    }

    // MARK: The news, for a prompt

    /// <summary>The news as <paramref name="speaker"/> hears it (null: told of the pair, for a story or a diary):
    /// who arrived, left or came back and when, with what the speaker remembers of a leaver or a returner.
    /// "" without fresh news.</summary>
    public static string News(IReadOnlyList<Event> events, string? speaker, Bonds.Book? book, DateTimeOffset now)
    {
        if (events.Count == 0) return "";
        var said = new List<string>();
        foreach (var e in events)
        {
            var when = Bonds.Ago(e.Time, now);
            var mine = speaker == e.Name;
            switch (e.Kind)
            {
                case EventKind.Joined:
                    if (mine) said.Add(L10n.Tr("You are new here: you joined the gang %@, and everyone is still new to you; be shy, curious or show off, as you would.", when));
                    else if (e.Species is { Length: > 0 } species) said.Add(L10n.Tr("%@, %@, is new to the gang: arrived %@.", e.Name, Banter.Spoken(species), when));
                    else said.Add(L10n.Tr("%@ is new to the gang: arrived %@.", e.Name, when));
                    break;
                case EventKind.Left:
                    said.Add(L10n.Tr("%1$@ has left the gang (%2$@); nobody has seen %1$@ since, or knows where to.", e.Name, when));
                    break;
                default:
                    var since = e.AwaySince is DateTimeOffset a ? Bonds.Day(a) : L10n.Tr("a while");
                    said.Add(mine ? L10n.Tr("You are back in the gang %@, after being away since %@; the others remember you.", when, since)
                                  : L10n.Tr("%@ came back to the gang %@, after being away since %@.", e.Name, when, since));
                    break;
            }
            if (!mine && speaker is not null && e.Kind != EventKind.Joined && book?.Bond(speaker, e.Name)?.Summary is string summary)
                said.Add(L10n.Tr("You and %@: %@", e.Name, summary));
        }
        var close = speaker is null
            ? L10n.Tr("It may touch their story.")
            : L10n.Tr("If it suits you, bring it up in your own way (a welcome, suspicion, gossip, missing someone, a rumour), in a word or two; never explain it.");
        return L10n.Tr("News in the gang: %@", string.Join(" ", said)) + " " + close;
    }

    /// <summary>Put <paramref name="news"/> after a rendered prompt, unless it is empty.</summary>
    public static string WithNews(string prompt, string news) => news.Length == 0 ? prompt : prompt + "\n" + news;

    // MARK: Built-in lines

    /// <summary>A built-in line about <paramref name="e"/>, said by <paramref name="speaker"/> in its own voice: about
    /// someone new, someone gone, someone back, or (its own arrival or return) about itself.</summary>
    public static string Line(Event e, string speaker, Random rng)
    {
        IReadOnlyList<string> pool;
        if (e.Name == speaker)
            pool = e.Kind == EventKind.Returned ? BackSelfAnyone : ArrivalLines.TryGetValue(speaker, out var own) ? new[] { own } : ArrivalAnyone;
        else
        {
            var (lines, anyone) = e.Kind switch
            {
                EventKind.Joined => (NewLines, NewAnyone),
                EventKind.Left => (GoneLines, GoneAnyone),
                _ => (BackLines, BackAnyone),
            };
            pool = lines.TryGetValue(speaker, out var own) ? new[] { own } : anyone;
        }
        return Banter.Render(rng.Pick(pool), new Dictionary<string, string> { ["name"] = e.Name });
    }

    public static IReadOnlyDictionary<string, string> NewLines => LinesIn(Languages.Current, s => s.GangNew, EnglishNewLines);
    public static IReadOnlyDictionary<string, string> GoneLines => LinesIn(Languages.Current, s => s.GangGone, EnglishGoneLines);
    public static IReadOnlyDictionary<string, string> BackLines => LinesIn(Languages.Current, s => s.GangBack, EnglishBackLines);
    public static IReadOnlyDictionary<string, string> ArrivalLines => LinesIn(Languages.Current, s => s.GangArrival, EnglishArrivalLines);
    public static IReadOnlyList<string> NewAnyone => Translated.List(Shared.Current?.GangNewAnyone, EnglishNewAnyone);
    public static IReadOnlyList<string> GoneAnyone => Translated.List(Shared.Current?.GangGoneAnyone, EnglishGoneAnyone);
    public static IReadOnlyList<string> BackAnyone => Translated.List(Shared.Current?.GangBackAnyone, EnglishBackAnyone);
    public static IReadOnlyList<string> ArrivalAnyone => Translated.List(Shared.Current?.GangArrivalAnyone, EnglishArrivalAnyone);
    public static IReadOnlyList<string> BackSelfAnyone => Translated.List(Shared.Current?.GangBackSelfAnyone, EnglishBackSelfAnyone);

    /// <summary>Every character of <paramref name="english"/>, with its line in <paramref name="l"/> when it has one there.</summary>
    public static IReadOnlyDictionary<string, string> LinesIn(Language l, Func<Shared, Dictionary<string, string>> table,
                                                            IReadOnlyDictionary<string, string> english)
    {
        if (Shared.In(l) is not Shared s || table(s).Count == 0) return english;
        var t = table(s);
        return english.ToDictionary(kv => kv.Key, kv => t.TryGetValue(kv.Key, out var line) && line.Length > 0 ? line : kv.Value);
    }
}
