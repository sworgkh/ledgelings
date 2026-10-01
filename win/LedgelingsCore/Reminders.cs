using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ledgelings.Core;

/// <summary>
/// Things the user asked to be reminded of. When one comes due, a creature
/// folds it into a paper plane and throws it at the user: the plane flies to
/// the middle of the screen, grows as it comes at you, and opens into a letter.
///
/// A reminder keeps the time of its next delivery. A one-off is finished once
/// sent; a repeating one moves on to its next time after now, so a computer that
/// slept through three mornings gets one letter, not three.
///
/// The Mac's <c>Calendar</c> is a <see cref="TimeZoneInfo"/> here (Gregorian, the zone's
/// wall clock); null means the local zone.
/// </summary>
public static partial class Reminders
{
    [JsonConverter(typeof(RepeatConverter))]
    public enum Repeat { Once, Daily, Weekdays, Weekly }

    public static readonly IReadOnlyList<Repeat> AllRepeats = new[] { Repeat.Once, Repeat.Daily, Repeat.Weekdays, Repeat.Weekly };

    public static string Title(this Repeat repeat) => repeat switch
    {
        Repeat.Once => "Once",
        Repeat.Daily => "Every day",
        Repeat.Weekdays => "Every weekday",
        _ => "Every week",
    };

    /// <summary>How a repeat is written in <c>reminders.json</c>: the Mac's raw values.</summary>
    public static string Key(this Repeat repeat) => repeat switch
    {
        Repeat.Once => "once", Repeat.Daily => "daily", Repeat.Weekdays => "weekdays", _ => "weekly",
    };

    public sealed record Reminder
    {
        // Declared in key order: the file is written with sorted keys, as the Mac writes it.
        [JsonConverter(typeof(UpperGuidConverter))]
        public Guid Id { get; init; } = Guid.NewGuid();
        public Repeat Repeats { get; set; } = Repeat.Once;
        /// <summary>When it was last delivered; a one-off with this set is finished.</summary>
        public DateTimeOffset? SentAt { get; set; }
        /// <summary>What to be reminded of, in the user's words: "Stretch", "Call mom".</summary>
        public string Text { get; set; } = "";
        /// <summary>When it is next delivered.</summary>
        public DateTimeOffset Time { get; set; }

        public Reminder() { }

        public Reminder(string text, DateTimeOffset time, Repeat repeats = Repeat.Once, DateTimeOffset? sentAt = null, Guid? id = null)
        {
            Id = id ?? Guid.NewGuid(); Text = text; Time = time; Repeats = repeats; SentAt = sentAt;
        }

        [JsonIgnore] public bool IsFinished => Repeats == Repeat.Once && SentAt is not null;

        public bool IsDue(DateTimeOffset now) => !IsFinished && Time <= now;

        /// <summary>The first time after <paramref name="date"/> this reminder repeats at, keeping its hour
        /// and minute (and its weekday, weekly). Null for a one-off.</summary>
        public DateTimeOffset? Next(DateTimeOffset date, TimeZoneInfo? calendar = null)
        {
            var zone = calendar ?? TimeZoneInfo.Local;
            if (Repeats == Repeat.Once) return null;
            var wall = TimeZoneInfo.ConvertTime(Time, zone);
            var from = TimeZoneInfo.ConvertTime(date, zone).Date;
            // Nine days always reach the next weekday, the next week and the next day.
            for (int k = 0; k < 9; k++)
            {
                var day = from.AddDays(k);
                if (Repeats == Repeat.Weekly && day.DayOfWeek != wall.DayOfWeek) continue;
                if (Repeats == Repeat.Weekdays && day.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday) continue;
                var at = Instant(day.AddHours(wall.Hour).AddMinutes(wall.Minute), zone);
                if (at > date) return at;
            }
            return null;
        }

        /// <summary>Delivered at <paramref name="now"/>: a one-off is finished, a repeat moves to its next time after now.</summary>
        public void MarkSent(DateTimeOffset now, TimeZoneInfo? calendar = null)
        {
            SentAt = now;
            if (Next(now > Time ? now : Time, calendar) is DateTimeOffset next) Time = next;
        }

        /// <summary>"Today 14:30", "Tomorrow 09:00", "Mon 3 Oct 18:00", plus the repeat.</summary>
        public string Describe(DateTimeOffset now, TimeZoneInfo? calendar = null)
        {
            var when = When(Time, now, calendar);
            return Repeats == Repeat.Once ? when : $"{Repeats.Title()}, next {when}";
        }
    }

    /// <summary>A wall-clock time in <paramref name="zone"/> as an instant. A time the clocks skip
    /// over (spring forward) is the first one after the gap; one they pass twice, the first.</summary>
    public static DateTimeOffset Instant(DateTime wall, TimeZoneInfo zone)
    {
        var local = DateTime.SpecifyKind(wall, DateTimeKind.Unspecified);
        while (zone.IsInvalidTime(local)) local = local.AddMinutes(1);
        var offset = zone.IsAmbiguousTime(local) ? zone.GetAmbiguousTimeOffsets(local).Max() : zone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset);
    }

    /// <summary>Every reminder the user set, finished ones included until cleared.</summary>
    public sealed class Book
    {
        public List<Reminder> Reminders { get; set; } = new();

        public Book() { }
        public Book(IEnumerable<Reminder> reminders) { Reminders = reminders.ToList(); }

        /// <summary>Waiting ones by time, then finished ones, the latest sent first.</summary>
        [JsonIgnore]
        public List<Reminder> Sorted =>
            Reminders.Where(r => !r.IsFinished).OrderBy(r => r.Time)
                .Concat(Reminders.Where(r => r.IsFinished).OrderByDescending(r => r.SentAt ?? r.Time)).ToList();

        /// <summary>The ones due at <paramref name="now"/>, the oldest first.</summary>
        public List<Reminder> Due(DateTimeOffset now) => Reminders.Where(r => r.IsDue(now)).OrderBy(r => r.Time).ToList();

        /// <summary>The next one still to come.</summary>
        [JsonIgnore]
        public Reminder? Upcoming => Reminders.Where(r => !r.IsFinished).MinBy(r => r.Time);

        public void Add(Reminder reminder) => Reminders.Add(reminder);
        public void Remove(Guid id) => Reminders.RemoveAll(r => r.Id == id);
        public void ClearFinished() => Reminders.RemoveAll(r => r.IsFinished);

        public void MarkSent(Guid id, DateTimeOffset now, TimeZoneInfo? calendar = null) =>
            Reminders.FirstOrDefault(r => r.Id == id)?.MarkSent(now, calendar);

        /// <summary>Same reminders, same order.</summary>
        public bool SameAs(Book other) => Reminders.SequenceEqual(other.Reminders);

        public Book Copy() => new(Reminders.Select(r => r with { }));
    }

    /// <summary>The book on disk: <c>reminders.json</c> in a folder, rewritten whole on each save,
    /// in the Mac's format (sorted keys, ISO-8601 dates, upper-case ids).</summary>
    public sealed class Store
    {
        public string Directory { get; }
        public Store(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "reminders.json");

        private static readonly JsonSerializerOptions options = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = true,
            Converters = { new IsoTimeConverter() },
        };

        public Book Load()
        {
            try
            {
                if (!System.IO.File.Exists(File)) return new Book();
                return JsonSerializer.Deserialize<Book>(System.IO.File.ReadAllText(File), options) ?? new Book();
            }
            catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException or FormatException) { return new Book(); }
        }

        public void Save(Book book)
        {
            System.IO.Directory.CreateDirectory(Directory);
            var temp = File + ".tmp";
            System.IO.File.WriteAllText(temp, JsonSerializer.Serialize(book, options), new System.Text.UTF8Encoding(false));
            System.IO.File.Move(temp, File, overwrite: true);
        }
    }

    private static readonly CultureInfo british = CultureInfo.GetCultureInfo("en-GB");

    /// <summary>"Today 14:30", "Tomorrow 09:00", "Yesterday 18:00", else "Mon 3 Oct 18:00".</summary>
    public static string When(DateTimeOffset date, DateTimeOffset now, TimeZoneInfo? calendar = null) =>
        $"{Day(date, now, calendar)} {Clock(date, calendar)}";

    /// <summary>"Today", "Tomorrow", "Yesterday", else "Mon 3 Oct".</summary>
    public static string Day(DateTimeOffset date, DateTimeOffset now, TimeZoneInfo? calendar = null)
    {
        var zone = calendar ?? TimeZoneInfo.Local;
        var day = TimeZoneInfo.ConvertTime(date, zone).Date;
        var today = TimeZoneInfo.ConvertTime(now, zone).Date;
        if (day == today) return "Today";
        if (day == today.AddDays(1)) return "Tomorrow";
        if (day == today.AddDays(-1)) return "Yesterday";
        return TimeZoneInfo.ConvertTime(date, zone).ToString("ddd d MMM", british);
    }

    /// <summary>"14:30", on the 24-hour clock.</summary>
    public static string Clock(DateTimeOffset date, TimeZoneInfo? calendar = null) =>
        TimeZoneInfo.ConvertTime(date, calendar ?? TimeZoneInfo.Local).ToString("HH:mm", british);

    // MARK: Picking a time on the paper note

    /// <summary><paramref name="date"/> moved <paramref name="minutes"/> on (or back, negative) to the next line of a clock
    /// ruled every <paramref name="minutes"/>: 14:07 + 15 is 14:15, 14:07 − 15 is 14:00, 14:15 + 15
    /// is 14:30. Seconds are dropped. Days roll over.</summary>
    public static DateTimeOffset Step(DateTimeOffset date, int minutes, TimeZoneInfo? calendar = null)
    {
        var size = Math.Max(1, Math.Abs(minutes));
        var wall = TimeZoneInfo.ConvertTime(date, calendar ?? TimeZoneInfo.Local);
        var now = wall.Hour * 60 + wall.Minute;
        var onLine = now % size == 0 && wall.Second == 0;
        var target = minutes > 0 ? (now / size + 1) * size : (onLine ? now - size : now / size * size);
        // Offsets are whole minutes, so dropping the seconds of the instant drops them on the wall clock too.
        var whole = date.AddTicks(-(date.UtcTicks % TimeSpan.TicksPerMinute));
        return whole.AddMinutes(target - now);
    }

    // MARK: The letter

    /// <summary>One pixel of the letter's paper, in blocky's rules: a dark rim, flat
    /// paper, a light line top-left, a shade line bottom-right, a folded-down
    /// corner bottom-right, and the faint creases of a plane unfolded.
    /// The Mac's <c>Reminders.Paper</c>; its letters are <see cref="Letter"/>.</summary>
    public enum Ink { Rim, Paper, Light, Shade, DeepShade, Crease }

    /// <summary>The one-letter names the Mac gives each ink.</summary>
    public static char Letter(this Ink ink) => ink switch
    {
        Ink.Rim => 'o', Ink.Paper => 'w', Ink.Light => 'L', Ink.Shade => 's', Ink.DeepShade => 'S', _ => 'c',
    };

    /// <summary>The corner fold, in pixels along each side.</summary>
    public static int CornerSize(int width, int height) => Math.Max(4, Math.Min(width, height) / 8);

    /// <summary>The letter as rows of pixels, top row first; null is transparent (the cut-off corner).</summary>
    public static Ink?[][] Paper(int width, int height)
    {
        int w = Math.Max(width, 8), h = Math.Max(height, 8);
        var fold = CornerSize(w, h);
        var rows = Enumerable.Range(0, h).Select(_ => Enumerable.Repeat<Ink?>(Ink.Paper, w).ToArray()).ToArray();
        // Creases: the plane's centre fold, and the two wing folds a quarter in.
        for (int x = 2; x < w - 2; x++) rows[h / 2][x] = Ink.Crease;
        for (int y = 2; y < h - 2; y++) rows[y][w / 2] = Ink.Crease;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                var fromCorner = (w - 1 - x) + (h - 1 - y);         // 0 at the bottom-right pixel
                if (fromCorner < fold - 1) { rows[y][x] = null; continue; }
                if (fromCorner == fold - 1) { rows[y][x] = Ink.Rim; continue; }  // the fold's diagonal edge
                if (x == 0 || y == 0 || x == w - 1 || y == h - 1) { rows[y][x] = Ink.Rim; continue; }
                if (y == 1 || x == 1) { rows[y][x] = Ink.Light; continue; }
                if (y == h - 2 || x == w - 2) { rows[y][x] = Ink.Shade; continue; }
            }
        // The folded-down flap sits inside the corner: a stepped triangle in deep shade.
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                var fromCorner = (w - 1 - x) + (h - 1 - y);
                var insideFlap = x >= w - fold && y >= h - fold && fromCorner >= fold;
                if (insideFlap) rows[y][x] = x == w - fold || y == h - fold ? Ink.Rim : Ink.DeepShade;
            }
        return rows;
    }

    // MARK: The note that comes with it

    /// <summary>What each built-in character writes above your reminder, in its own
    /// voice. <c>{reminder}</c> is what you asked to be reminded of. A character the
    /// user invented uses <see cref="Anyone"/>.</summary>
    public static readonly IReadOnlyList<string> Anyone = new[]
    {
        "It's time: {reminder}. You asked me to tell you, so I'm telling you.",
        "Knock knock. {reminder}. That's the whole joke. Go on.",
    };

    public static readonly IReadOnlyDictionary<string, IReadOnlyList<string>> Notes = new Dictionary<string, IReadOnlyList<string>>
    {
        // blocky's cast
        ["Blocky"] = new[]
        {
            "Stop staring at the cursor. It's time: {reminder}. I have a list, and you're on it.",
            "Official notice from the bottom edge: {reminder}. Now. Don't make me jump.",
        },
        ["Pip"] = new[]
        {
            "It's time it's time it's TIME! {reminder}! I folded this upside down just for you!",
            "Guess what?! {reminder}! You can do it! I believe in you so much!",
        },
        ["Mortimer"] = new[]
        {
            "An old saying: the hour you set is the hour that sets you. {reminder}, young one.",
            "*sighs* Time has come round again, as it does. {reminder}.",
        },
        ["Zed"] = new[]
        {
            "*yawns* woke up just to tell you... {reminder}. Right. Back to sleep.",
            "Psst. {reminder}. I'd do it for you, but. Nap.",
        },
        ["Dot"] = new[]
        {
            "Got here first, obviously. {reminder}. Try to keep up, boulder.",
            "Fastest plane on the screen, and it says: {reminder}. You're welcome.",
        },
        ["Ruth"] = new[]
        {
            "By my count, it is now exactly time for: {reminder}. I checked twice.",
            "Item one of one: {reminder}. Counted, folded, delivered. No jumping about it.",
        },
        // cat
        ["Whiskers"] = new[]
        {
            "Not that I care, but... {reminder}. What are you doing, anyway?",
            "I happened to notice the time. {reminder}. Don't thank me.",
        },
        ["Mittens"] = new[]
        {
            "Purrr... sorry to wake you, warm one. {reminder}. Then come back to the sunny side.",
            "Mrrrp. It's time for {reminder}. I kept the note warm for you.",
        },
        ["Sir Pounce"] = new[]
        {
            "The hunt begins! Target sighted: {reminder}! Pounce on it NOW!",
            "I have stalked the clock for hours and caught it: {reminder}!",
        },
        // frog
        ["Hopper"] = new[]
        {
            "I threw this ALL the way across the screen! {reminder}! Best throw ever!",
            "RIBBIT! {reminder}! I'd jump over there and tell you, but. Plane was faster.",
        },
        ["Mossy"] = new[]
        {
            "The pond waits for no frog. {reminder}.",
            "Slow ripples reach the shore at last: {reminder}.",
        },
        ["Croak"] = new[]
        {
            "Too dry up here to shout, so I wrote it: {reminder}. Go.",
            "Grumble. {reminder}. There. Happy?",
        },
        // ghost
        ["Boo"] = new[]
        {
            "BOO! ...did I scare you? No? Well, {reminder}!",
            "Boo boo boo! It's time: {reminder}! Spooky, right?",
        },
        ["Wisp"] = new[]
        {
            "Like a monitor I once knew, this moment will pass. Before it does: {reminder}.",
            "The hour drifted by and whispered: {reminder}.",
        },
        ["Sheet"] = new[]
        {
            "I floated this over. Technically, I didn't walk. {reminder}.",
            "Reminder: {reminder}. That is all. I am, technically, a sheet.",
        },
        // mushroom
        ["Morel"] = new[]
        {
            "Patience has its end, like the rain... {reminder}.",
            "Slowly, from the damp corner... it is time... {reminder}.",
        },
        ["Puff"] = new[]
        {
            "Hee hee! {reminder}! Go before I spore everywhere!",
            "Eee! It's time! {reminder}! *puff*",
        },
        ["Cap"] = new[]
        {
            "In my day, we didn't need planes to remember things. {reminder}.",
            "In my day we wrote on bark. Anyway: {reminder}.",
        },
        // robot
        ["Unit 7"] = new[]
        {
            "Scheduled task at 100% due: {reminder}. Delay recommended: 0 seconds.",
            "Status: 1 reminder delivered. Content: {reminder}. Compliance expected: 100%.",
        },
        ["Sprocket"] = new[]
        {
            "Maintenance window open! Item: {reminder}. I've oiled the plane for you!",
            "Time to tighten up the schedule: {reminder}!",
        },
        ["Glitch"] = new[]
        {
            "Reminder reminder: {reminder}. The cursor did NOT send this.",
            "It's time time for: {reminder}. Scanned for viruses. Clean.",
        },
        // slime
        ["Goop"] = new[]
        {
            "Nice! Sticky! It's time: {reminder}!",
            "Hi hi! {reminder}! That's nice, right?",
        },
        ["Puddle"] = new[]
        {
            "Sorry, sorry, I hope this isn't too late — {reminder}. Please don't step on the plane.",
            "Oh no, it's time. {reminder}. I'm drying out just thinking about it.",
        },
        ["Blorp"] = new[]
        {
            "Blorp! {reminder}! Zoom!",
            "Splat. {reminder}. Blorp did good.",
        },
        // triangle
        ["Spike"] = new[]
        {
            "Point is: {reminder}. Now.",
            "Let me be sharp about it: {reminder}.",
        },
        ["Wedge"] = new[]
        {
            "I will not be tipped over on this one: {reminder}. No arguing.",
            "It's decided and it stays decided: {reminder}.",
        },
        ["Delta"] = new[]
        {
            "Something changed since last time: now it's time for {reminder}.",
            "Difference noticed: the clock moved. {reminder}.",
        },    };

    /// <summary>The note <paramref name="writer"/> sends with <paramref name="reminder"/>.</summary>
    public static string Note(string writer, string reminder, Random rng) =>
        Fill(rng.Pick(Notes.TryGetValue(writer, out var own) ? own : Anyone), reminder);

    /// <summary><c>{reminder}</c> filled in; mid-sentence ("Well, call mom!", "time for stretching")
    /// its first letter goes small, unless it reads like "I" or an acronym.</summary>
    public static string Fill(string line, string reminder)
    {
        var at = line.IndexOf("{reminder}", StringComparison.Ordinal);
        if (at < 0) return line;
        var before = line[..at];
        var midSentence = before.EndsWith(", ", StringComparison.Ordinal) || before.EndsWith("for ", StringComparison.Ordinal);
        var first = reminder.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        var shout = first == "I" || (first.Length > 1 && first == first.ToUpperInvariant());
        var shown = midSentence && !shout && reminder.Length > 0 ? reminder[..1].ToLowerInvariant() + reminder[1..] : reminder;
        return Banter.Render(line, new Dictionary<string, string> { ["reminder"] = shown });
    }

    /// <summary>The model writes the note as the creature throwing the plane.</summary>
    public const string NotePrompt =
        "{situation}\n" +
        "The person whose screen you live on asked to be reminded, right now, of: \"{reminder}\". " +
        "You fold it into a paper plane and throw it to them. Write the note that goes with it: " +
        "one line in your own voice telling them it is time for it. " +
        "At most 20 words. Output only the note: no quotes, no signature.";

    internal sealed class RepeatConverter : JsonConverter<Repeat>
    {
        public override Repeat Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            reader.GetString() switch
            {
                "daily" => Repeat.Daily, "weekdays" => Repeat.Weekdays, "weekly" => Repeat.Weekly, "once" => Repeat.Once,
                var other => throw new JsonException("repeat " + other),
            };

        public override void Write(Utf8JsonWriter writer, Repeat value, JsonSerializerOptions options) => writer.WriteStringValue(value.Key());
    }

    /// <summary>Swift writes a UUID in capitals.</summary>
    internal sealed class UpperGuidConverter : JsonConverter<Guid>
    {
        public override Guid Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            Guid.Parse(reader.GetString() ?? throw new JsonException("id"));

        public override void Write(Utf8JsonWriter writer, Guid value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.ToString("D").ToUpperInvariant());
    }
}
