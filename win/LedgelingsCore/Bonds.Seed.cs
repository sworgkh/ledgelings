using System.Globalization;

namespace Ledgelings.Core;

/// <summary>
/// The seed: a pair's starting memory, read from the chat log of the last few
/// weeks. Without a model the log gives the days their counts; with one, a
/// digest of it (the counts day by day and a sample of what was said) goes in
/// one call per pair, and the answer is written as the diary's would be. The Mac's <c>Bonds+Seed.swift</c>.
///
/// Only the creatures' own words and what kind of moment each was go into the
/// digest. The situation a conversation was had in is read to tell a letter
/// from a tea party from a flower, and never sent: it carries the user's clock,
/// holidays and cursor counts.
/// </summary>
public static partial class Bonds
{
    /// <summary>What the chat log holds about one pair over the seed's days.</summary>
    public sealed class SeedDigest
    {
        /// <summary>Day by day (<c>2026-10-19</c>): what they shared, by <see cref="MomentKind"/>.</summary>
        public Dictionary<string, Dictionary<string, int>> Days { get; } = new();
        /// <summary>The lines picked to show the model, by day, oldest first.</summary>
        public List<(string Day, ChatLog.Line Line)> Lines { get; set; } = new();
        /// <summary>Every conversation both spoke in.</summary>
        public int Exchanges { get; set; }
    }

    /// <summary>A tea party is one sitting: rounds this close together count once, in seconds.</summary>
    public const double TeaSitting = 15 * 60;

    /// <summary>What kind of moment a logged conversation was, from its situation, in either language.</summary>
    public static string Classify(string situation)
    {
        var s = situation.ToLowerInvariant();
        if (s.Contains("paper plane") || s.Contains("бумажн")) return MomentKind.Plane;
        if (s.Contains("tea") && (s.Contains("table") || s.Contains("sit down")) || s.Contains("столик") || s.Contains("пить чай")) return MomentKind.Tea;
        if (s.Contains("gave") && s.Contains("a ") && s.Contains("walked into") || s.Contains("дарит")) return MomentKind.Flower;
        return MomentKind.Talk;
    }

    /// <summary>The digest of <paramref name="a"/> and <paramref name="b"/>'s conversations in <paramref name="exchanges"/> between
    /// <paramref name="from"/> and <paramref name="to"/>: every day's counts, and about <paramref name="lines"/> lines spread across the
    /// days, letters first, then the first round of each tea party, then talks.</summary>
    public static SeedDigest Digest(IEnumerable<ChatLog.Exchange> exchanges, string a, string b, DateTimeOffset from, DateTimeOffset to, int lines)
    {
        var output = new SeedDigest();
        var shared = exchanges.Where(e => e.Time >= from && e.Time <= to && e.Lines.Any(l => l.Speaker == a) && e.Lines.Any(l => l.Speaker == b))
            .OrderBy(e => e.Time).ToList();
        output.Exchanges = shared.Count;
        var byDay = new Dictionary<string, List<(ChatLog.Exchange Exchange, int Rank)>>();
        DateTimeOffset? lastTea = null;
        void Count(string key, string kind)
        {
            if (!output.Days.TryGetValue(key, out var counts)) output.Days[key] = counts = new();
            counts[kind] = counts.GetValueOrDefault(kind) + 1;
        }
        foreach (var e in shared)
        {
            var kind = Classify(e.Situation);
            var key = DayKey(e.Time);
            var rank = 3;
            switch (kind)
            {
                case MomentKind.Plane: rank = 0; break;
                case MomentKind.Tea:
                    var newSitting = lastTea is not DateTimeOffset t || (e.Time - t).TotalSeconds > TeaSitting;
                    lastTea = e.Time;
                    if (newSitting) { Count(key, kind); rank = 1; } else rank = 4;
                    break;
                case MomentKind.Flower: rank = 2; break;
            }
            if (kind != MomentKind.Tea) Count(key, kind);
            if (!byDay.TryGetValue(key, out var list)) byDay[key] = list = new();
            list.Add((e, rank));
        }
        var keys = byDay.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();
        if (keys.Count == 0 || lines <= 0) return output;
        // An even share of lines for every day, the best-ranked conversations of each.
        var share = Math.Max(2, lines / keys.Count);
        var picked = new List<(string Day, DateTimeOffset Time, ChatLog.Line Line)>();
        foreach (var key in keys)
        {
            var taken = 0;
            foreach (var (e, _) in byDay[key].OrderBy(x => x.Rank).ThenBy(x => x.Exchange.Time))
            {
                if (taken >= share) break;
                foreach (var line in e.Lines)
                {
                    if (taken >= share) break;
                    picked.Add((key, e.Time, line));
                    taken++;
                }
            }
        }
        output.Lines = picked.OrderBy(p => p.Time).Take(lines).Select(p => (p.Day, p.Line)).ToList();
        return output;
    }

    /// <summary>The seed prompt's values for one pair.</summary>
    public static Dictionary<string, string> SeedValues(Bond bond, SeedDigest digest, (string Name, string Kind, string Persona) a,
                                                        (string Name, string Kind, string Persona) b, int days, int words, int facts)
    {
        var values = MemoryValues(bond, a, b, Array.Empty<ChatLog.Line>(), words, facts);
        values["days"] = days.ToString(CultureInfo.InvariantCulture);
        values["digest"] = string.Join("\n", digest.Days.Keys.OrderBy(k => k, StringComparer.Ordinal).Select(k => $"- {k}: " + Tallied(digest.Days[k])));
        values["lines"] = string.Join("\n", digest.Lines.Select(l => $"[{l.Day}] {l.Line.Speaker}: {l.Line.Text}"));
        return values;
    }

    public sealed partial class Book
    {
        /// <summary>The digest's counts written into the pair's days: a day already counted
        /// keeps the larger of the two, so a seed run twice counts nothing twice.</summary>
        public void SeedDays(string a, string b, SeedDigest digest, DateTimeOffset? at = null)
        {
            var now = at ?? DateTimeOffset.Now;
            Update(a, b, bond =>
            {
                foreach (var (key, counts) in digest.Days)
                {
                    if (bond.Days.FirstOrDefault(d => d.Day == key) is DayEntry day)
                    {
                        foreach (var (kind, n) in counts) day.Counts[kind] = Math.Max(day.Counts.GetValueOrDefault(kind), n);
                    }
                    else bond.Days.Add(new DayEntry(key) { Counts = new Dictionary<string, int>(counts) });
                }
                bond.Days = bond.Days.OrderBy(d => d.Day, StringComparer.Ordinal).ToList();
                bond.MemorySeeded = now;
            });
        }
    }
}
