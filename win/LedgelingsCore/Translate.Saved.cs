using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ledgelings.Core;

public static partial class Translate
{
    // Saved translations

    /// <summary>A translation kept with the star (Ctrl+D), as Google Translate keeps its starred ones (SPEC
    /// §7.14.3), the Mac's <c>Translate.Saved</c>: the text and the language it was read as, the translation and
    /// the language it went into, when, and the app the text came from.</summary>
    public sealed record Saved(Guid Id, string Text, string From, string Translation, string To, DateTimeOffset SavedAt, string? App = null)
    {
        /// <summary>A new entry with an id of its own. (Not a second constructor: the file reads through the first.)</summary>
        public static Saved New(string text, string from, string translation, string to, DateTimeOffset savedAt, string? app = null) =>
            new(Guid.NewGuid(), text, from, translation, to, savedAt, app);

        /// <summary>The same text with the same pair of languages is one entry, whatever its translation.</summary>
        public bool Same(string text, string from, string to) => From == from && To == to && Key(Text) == Key(text);

        /// <summary>The text as it is compared: without the spaces and new lines at its edges.</summary>
        internal static string Key(string text) => text.Trim();

        /// <summary>"EN → RU", the small tag on its row.</summary>
        [JsonIgnore] public string Pair => $"{From.ToUpperInvariant()} → {To.ToUpperInvariant()}";
    }

    /// <summary>How many are kept; the oldest beyond it are dropped.</summary>
    public const int SavedLimitMin = 50, SavedLimitMax = 5_000, DefaultSavedLimit = 500;

    /// <summary>Every saved translation, newest first.</summary>
    public sealed class SavedBook
    {
        private List<Saved> entries = new();

        public SavedBook() { }
        public SavedBook(IEnumerable<Saved> entries) { Entries = entries.ToList(); }

        /// <summary>Newest first, whatever order they were given in.</summary>
        public List<Saved> Entries
        {
            get => entries;
            set => entries = value.OrderByDescending(e => e.SavedAt).ToList();
        }

        [JsonIgnore] public int Count => entries.Count;
        [JsonIgnore] public bool IsEmpty => entries.Count == 0;

        /// <summary>The entry for this text and pair, if it is saved.</summary>
        public Saved? Find(string text, string from, string to) => entries.FirstOrDefault(e => e.Same(text, from, to));

        /// <summary>Saves <paramref name="entry"/> at the top. The same text and pair saved before is replaced,
        /// keeping its id, so it is never there twice; then the oldest beyond <paramref name="limit"/> go.</summary>
        public void Save(Saved entry, int limit)
        {
            var old = entries.FindIndex(e => e.Same(entry.Text, entry.From, entry.To));
            if (old >= 0)
            {
                entry = entry with { Id = entries[old].Id, App = entry.App ?? entries[old].App };
                entries.RemoveAt(old);
            }
            entries.Insert(0, entry);
            Prune(limit);
        }

        /// <summary>The star pressed: saved when it was not, removed when it was. True when it is saved now.</summary>
        public bool Toggle(Saved entry, int limit)
        {
            if (Find(entry.Text, entry.From, entry.To) is { } old) { Remove(old.Id); return false; }
            Save(entry, limit);
            return true;
        }

        public void Remove(Guid id) => entries.RemoveAll(e => e.Id == id);
        public void Clear() => entries.Clear();

        /// <summary>The newest <paramref name="limit"/> stay.</summary>
        public void Prune(int limit)
        {
            limit = Math.Max(limit, 0);
            if (entries.Count > limit) entries.RemoveRange(limit, entries.Count - limit);
        }

        /// <summary>The entries whose text or translation holds every word of <paramref name="query"/>, in either case
        /// and with or without accents (ё as е); all of them for a blank one.</summary>
        public List<Saved> Search(string query)
        {
            var words = query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Select(Fold).ToList();
            if (words.Count == 0) return entries.ToList();
            return entries.Where(e =>
            {
                var haystack = Fold(e.Text) + "\n" + Fold(e.Translation);
                return words.All(w => haystack.Contains(w, StringComparison.Ordinal));
            }).ToList();
        }

        /// <summary>Lower case, without accents: "Отчёт" is "отчет", as the Mac's diacritic-insensitive folding.</summary>
        internal static string Fold(string text)
        {
            var decomposed = text.ToLowerInvariant().Normalize(NormalizationForm.FormD);
            var kept = new StringBuilder(decomposed.Length);
            foreach (var c in decomposed)
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) kept.Append(c);
            return kept.ToString().Normalize(NormalizationForm.FormC);
        }
    }

    /// <summary><c>translations.json</c> beside the clipboard history, in the Mac's format, saved on every change.</summary>
    public sealed class SavedStore
    {
        public string Directory { get; }
        public SavedStore(string directory) { Directory = directory; }
        public string File => Path.Combine(Directory, "translations.json");

        private static readonly JsonSerializerOptions options = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = true,
            Converters = { new IsoTimeConverter() },
        };

        /// <summary>The book on disk; an empty one when there is none, or it cannot be read.</summary>
        public SavedBook Load()
        {
            try { return System.IO.File.Exists(File) ? JsonSerializer.Deserialize<SavedBook>(System.IO.File.ReadAllText(File), options) ?? new SavedBook() : new SavedBook(); }
            catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException or FormatException) { return new SavedBook(); }
        }

        public void Save(SavedBook book)
        {
            System.IO.Directory.CreateDirectory(Directory);
            var temp = File + ".tmp";
            System.IO.File.WriteAllText(temp, JsonSerializer.Serialize(book, options), new UTF8Encoding(false));
            System.IO.File.Move(temp, File, overwrite: true);
        }
    }

    // The drawer

    /// <summary>Which side of the sheet the drawer of saved translations slides out of.</summary>
    public enum DrawerSide { Right, Left }

    /// <summary>Right, unless the drawer would run off that monitor there and fits on the left. The sheet's left
    /// edge and width, the drawer's width and the monitor's width, all in the same units.</summary>
    public static DrawerSide Side(double paperMinX, double paperWidth, double drawerWidth, double room)
    {
        var fitsRight = paperMinX + paperWidth + drawerWidth <= room;
        var fitsLeft = paperMinX - drawerWidth >= 0;
        return fitsRight || !fitsLeft ? DrawerSide.Right : DrawerSide.Left;
    }

    /// <summary>"11 Nov", or "11 Nov 2025" from another year, in the app's language.</summary>
    public static string SavedDate(DateTimeOffset date, DateTimeOffset now)
    {
        var culture = CultureInfo.GetCultureInfo(Ledgelings.Core.Languages.Current == Ledgelings.Core.Language.Russian ? "ru-RU" : "en-GB");
        var local = date.ToLocalTime();
        var day = local.ToString("d MMM", culture);
        return local.Year == now.ToLocalTime().Year ? day : day + " " + local.Year.ToString(CultureInfo.InvariantCulture);
    }
}
