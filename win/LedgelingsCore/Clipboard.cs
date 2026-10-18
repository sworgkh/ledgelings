using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Xml;

namespace Ledgelings.Core;

/// <summary>
/// The clipboard manager (SPEC §7.11), the Mac's <c>Clipboard.swift</c>: what was copied lately (the
/// history) and the texts the user keeps to paste again (the snippets), searched together from one field.
///
/// The history is newest first. Copying the same text again moves its clip to the top instead of adding a
/// second one. Pinned clips stay whatever the limits say; the others go once there are more than the
/// limit of them, or once they are older than the days to keep. A copied picture is a clip too, labelled
/// "Image 1280×720"; its bytes are files in <c>clipboard-images</c> beside the history, one per clipboard format
/// it was copied as, so the JSON stays small. A protected snippet keeps no text here
/// at all: its words live in Windows' Credential Manager, fetched only when it is pasted; the book keeps a salted
/// fingerprint of them, so a copy of those words in the history is shown masked, <c>PWD:Wi-Fi: [16] chars</c>, and
/// searched by that label. It still pastes its own words.
///
/// Nothing in here is ever sent anywhere: no model sees a clip or a snippet.
/// </summary>
public static class Clipboard
{
    // MARK: Clips

    [JsonConverter(typeof(KindConverter))]
    public enum Kind { Text, Rich, Files, Image }

    /// <summary>A copied picture's size and the formats it was kept as, each a file beside the history.</summary>
    public sealed record Picture
    {
        public int Width { get; init; }
        public int Height { get; init; }
        /// <summary>Every kept format's bytes together.</summary>
        public int Bytes { get; init; }
        /// <summary>A fingerprint of the best format's bytes: the same picture copied again is the same clip.</summary>
        public string Digest { get; init; } = "";
        /// <summary>The formats kept, best first ("PNG", "DeviceIndependentBitmap"); each is a file.</summary>
        public List<string> Types { get; init; } = new();
    }

    /// <summary>What an image clip is called, in English, as its text: "Image 1280×720".</summary>
    public static string ImageLabel(int width, int height) => $"Image {width}×{height}";

    public sealed record Clip
    {
        [JsonConverter(typeof(Reminders.UpperGuidConverter))]
        public Guid Id { get; init; } = Guid.NewGuid();
        public Kind Kind { get; init; } = Kind.Text;
        /// <summary>What was copied, as plain text: the words, or the files' paths, one a line.</summary>
        public string Text { get; init; } = "";
        /// <summary>The formatting, for a rich clip; pasted unless plain text is asked for.</summary>
        public byte[]? Rtf { get; init; }
        public DateTimeOffset CopiedAt { get; init; }
        /// <summary>The app it was copied from, by name, for the picker.</summary>
        public string? App { get; init; }
        public bool Pinned { get; init; }
        /// <summary>An image clip's size and kept formats.</summary>
        public Picture? Picture { get; init; }

        /// <summary>A picture copied from <paramref name="app"/>, labelled by its size.</summary>
        public static Clip FromPicture(Picture picture, DateTimeOffset copiedAt, string? app = null) =>
            new() { Kind = Kind.Image, Text = ImageLabel(picture.Width, picture.Height), CopiedAt = copiedAt, App = app, Picture = picture };

        [JsonIgnore]
        public IReadOnlyList<string> Paths => Kind == Kind.Files ? Text.Split('\n', StringSplitOptions.RemoveEmptyEntries) : Array.Empty<string>();

        /// <summary>One line for a list: whitespace runs folded to one space, cut at <paramref name="limit"/> characters.</summary>
        public string Preview(int limit = 80) => Kind switch
        {
            Kind.Files => Clipboard.Preview(string.Join(", ", Paths.Select(LastComponent)), limit),
            Kind.Image when Picture is { } p => Clipboard.Preview(L10n.Tr("Image %d×%d", p.Width, p.Height), limit),
            _ => Clipboard.Preview(Text, limit),
        };

        private static string LastComponent(string path) => path.TrimEnd('/', '\\').Split('/', '\\').Last();
    }

    /// <summary>Longest text a clip keeps, in characters; a bigger copy is kept cut to this.</summary>
    public const int LongestClip = 100_000;
    /// <summary>Most RTF a rich clip keeps, in bytes; past it the clip keeps only its words.</summary>
    public const int LargestRtf = 512 * 1024;

    public sealed class History
    {
        /// <summary>Newest first.</summary>
        public List<Clip> Clips { get; set; } = new();

        /// <summary>A new copy: a clip at the top, or the clip with the same words (for a picture, the same bytes) moved
        /// there. Blank text is no copy.</summary>
        public bool Add(Clip clip)
        {
            if (string.IsNullOrWhiteSpace(clip.Text)) return false;
            if (clip.Text.Length > LongestClip) clip = clip with { Text = clip.Text[..LongestClip] };
            if (clip.Rtf is { Length: > LargestRtf }) clip = clip with { Rtf = null, Kind = Kind.Text };
            var at = Clips.FindIndex(c => c.Kind == clip.Kind && (clip.Kind == Kind.Image ? c.Picture?.Digest == clip.Picture?.Digest : c.Text == clip.Text));
            if (at >= 0)
            {
                var old = Clips[at];
                Clips.RemoveAt(at);
                clip = clip with { Id = old.Id, Pinned = old.Pinned, Rtf = clip.Rtf ?? (clip.Kind == old.Kind ? old.Rtf : null) };
                // Its files are under the old id, in the old formats.
                if (clip.Kind == Kind.Image) clip = clip with { Picture = old.Picture };
            }
            Clips.Insert(0, clip);
            return true;
        }

        /// <summary>Keeps the newest <paramref name="limit"/> unpinned clips copied within <paramref name="days"/> (0: however old).</summary>
        public void Prune(int limit, int days, DateTimeOffset now)
        {
            var oldest = days > 0 ? now.AddDays(-days) : DateTimeOffset.MinValue;
            var kept = 0;
            Clips = Clips.Where(c =>
            {
                if (c.Pinned) return true;
                if (c.CopiedAt < oldest || kept >= limit) return false;
                kept++;
                return true;
            }).ToList();
        }

        public void TogglePin(Guid id)
        {
            var i = Clips.FindIndex(c => c.Id == id);
            if (i >= 0) Clips[i] = Clips[i] with { Pinned = !Clips[i].Pinned };
        }

        public void Remove(Guid id) => Clips.RemoveAll(c => c.Id == id);

        /// <summary>Clear All: every clip but the pinned ones, unless <paramref name="pinnedToo"/>.</summary>
        public void Clear(bool pinnedToo = false) => Clips = pinnedToo ? new() : Clips.Where(c => c.Pinned).ToList();
    }

    // MARK: Snippets

    public sealed record Snippet
    {
        [JsonConverter(typeof(Reminders.UpperGuidConverter))]
        public Guid Id { get; init; } = Guid.NewGuid();
        public string Title { get; init; } = "";
        /// <summary>The words to paste; always empty for a protected snippet, whose words are in the secret store.</summary>
        public string Text { get; init; } = "";
        public bool Protected { get; init; }
        /// <summary>Its own shortcut from any app, as a virtual-key code and <see cref="ShortcutModifiers"/>; null: none.</summary>
        public int? KeyCode { get; init; }
        public int? Modifiers { get; init; }
        /// <summary>A protected snippet's words, fingerprinted: SHA-256 of <see cref="SecretSalt"/>'s bytes and then the
        /// words' UTF-8, so a copy of them in the history is told apart without the words on disk. The Mac's fields.</summary>
        public string? SecretSalt { get; init; }
        public string? SecretHash { get; init; }

        /// <summary>This snippet with <paramref name="words"/> fingerprinted under a fresh salt; null words forget the fingerprint.</summary>
        public Snippet Sealed(string? words)
        {
            if (string.IsNullOrEmpty(words)) return this with { SecretSalt = null, SecretHash = null };
            var salt = System.Security.Cryptography.RandomNumberGenerator.GetBytes(16);
            return this with { SecretSalt = Convert.ToBase64String(salt), SecretHash = Fingerprint(words, salt) };
        }

        /// <summary>Whether <paramref name="text"/> is this protected snippet's words.</summary>
        public bool Holds(string text)
        {
            if (!Protected || SecretHash is null || SecretSalt is null || text.Length > LongestSecret) return false;
            try { return Fingerprint(text, Convert.FromBase64String(SecretSalt)) == SecretHash; }
            catch (FormatException) { return false; }
        }

        public static Snippet Make(string title, string text = "", bool isProtected = false) =>
            new() { Title = title, Text = isProtected ? "" : text, Protected = isProtected };

        /// <summary>Its own shortcut, when it has a usable one.</summary>
        [JsonIgnore]
        public Shortcut? Shortcut
        {
            get => KeyCode is int k && Modifiers is int m && new Shortcut(k, (ShortcutModifiers)m) is { IsUsable: true } s ? s : null;
            init { KeyCode = value?.KeyCode; Modifiers = value is null ? null : (int)value.Value.Modifiers; }
        }

        /// <summary>The account its words are kept under in the secret store.</summary>
        [JsonIgnore]
        public string SecretAccount => "snippet." + Id.ToString("D").ToUpperInvariant();

        /// <summary>What the picker shows: the words, or dots for a protected one.</summary>
        public string Preview(int limit = 80) => Protected ? Mask : Clipboard.Preview(Text, limit);
    }

    /// <summary>What a protected snippet looks like until it is pasted.</summary>
    public const string Mask = "••••••••";

    /// <summary>Longest words compared with protected snippets: a password is short, a page of text is not one.</summary>
    public const int LongestSecret = 1024;

    internal static string Fingerprint(string words, byte[] salt) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(salt.Concat(Encoding.UTF8.GetBytes(words)).ToArray()));

    /// <summary>How a copy holding a protected snippet's words is shown: <c>PWD:Wi-Fi: [16] chars</c>.</summary>
    public static string MaskLabel(string title, int length) => $"PWD:{title}: [{length}] chars";

    public sealed record Folder
    {
        [JsonConverter(typeof(Reminders.UpperGuidConverter))]
        public Guid Id { get; init; } = Guid.NewGuid();
        public string Title { get; init; } = "";
        public List<Snippet> Snippets { get; init; } = new();
    }

    /// <summary>Every folder of snippets, in the user's order.</summary>
    public sealed class SnippetBook
    {
        public List<Folder> Folders { get; set; } = new();

        /// <summary>Every snippet with its folder, in order.</summary>
        [JsonIgnore]
        public IEnumerable<(Folder Folder, Snippet Snippet)> All => Folders.SelectMany(f => f.Snippets.Select(s => (f, s)));

        public Snippet? Find(Guid id) => All.FirstOrDefault(x => x.Snippet.Id == id).Snippet;
        public Folder? FolderOf(Guid id) => All.FirstOrDefault(x => x.Snippet.Id == id).Folder;

        /// <summary>The protected snippet whose words <paramref name="text"/> is, if any.</summary>
        public Snippet? SecretMatching(string text) => All.Select(x => x.Snippet).FirstOrDefault(s => s.Holds(text));

        /// <summary>What the picker shows for <paramref name="clip"/>: its mask when it holds a protected snippet's words, else null.</summary>
        public string? MaskFor(Clip clip) =>
            clip.Kind is Kind.Text or Kind.Rich && SecretMatching(clip.Text) is { } s ? MaskLabel(s.Title, clip.Text.Length) : null;

        public Guid AddFolder(string title)
        {
            var folder = new Folder { Title = title };
            Folders.Add(folder);
            return folder.Id;
        }

        /// <summary>A snippet at the end of <paramref name="folder"/>, or of the first folder; a folder is made when there is none.</summary>
        public Guid Add(Snippet snippet, Guid? folder = null)
        {
            if (Folders.Count == 0) AddFolder(L10n.Tr("Snippets"));
            var i = Folders.FindIndex(f => f.Id == folder);
            Folders[i < 0 ? 0 : i].Snippets.Add(snippet);
            return snippet.Id;
        }

        public void Update(Snippet snippet)
        {
            foreach (var f in Folders)
            {
                var s = f.Snippets.FindIndex(x => x.Id == snippet.Id);
                if (s >= 0) f.Snippets[s] = snippet.Protected ? snippet with { Text = "" } : snippet.Sealed(null);
            }
        }

        public void RenameFolder(Guid id, string title)
        {
            var i = Folders.FindIndex(f => f.Id == id);
            if (i >= 0) Folders[i] = Folders[i] with { Title = title };
        }

        /// <summary>Takes the folder or the snippet with this id out, whichever it is. Returns the snippets that
        /// went, so their secrets can go too.</summary>
        public List<Snippet> Remove(Guid id)
        {
            var i = Folders.FindIndex(f => f.Id == id);
            if (i >= 0) { var gone = Folders[i].Snippets; Folders.RemoveAt(i); return gone; }
            foreach (var f in Folders)
            {
                var s = f.Snippets.FindIndex(x => x.Id == id);
                if (s >= 0) { var gone = f.Snippets[s]; f.Snippets.RemoveAt(s); return new() { gone }; }
            }
            return new();
        }

        /// <summary>Moves the folder up (-1) or down (+1) among the folders, or the snippet within its folder,
        /// stepping into the next folder past either end.</summary>
        public void Move(Guid id, int step)
        {
            var i = Folders.FindIndex(f => f.Id == id);
            if (i >= 0)
            {
                var to = i + step;
                if (to < 0 || to >= Folders.Count) return;
                (Folders[i], Folders[to]) = (Folders[to], Folders[i]);
                return;
            }
            var fi = Folders.FindIndex(f => f.Snippets.Any(s => s.Id == id));
            if (fi < 0) return;
            var list = Folders[fi].Snippets;
            var si = list.FindIndex(s => s.Id == id);
            var target = si + step;
            if (target >= 0 && target < list.Count) (list[si], list[target]) = (list[target], list[si]);
            else if (fi + step >= 0 && fi + step < Folders.Count)
            {
                var snippet = list[si];
                list.RemoveAt(si);
                if (step < 0) Folders[fi + step].Snippets.Add(snippet); else Folders[fi + step].Snippets.Insert(0, snippet);
            }
        }

        /// <summary>The folders read from a file, added after the ones there.</summary>
        public void Merge(SnippetBook other) => Folders.AddRange(other.Folders);
    }

    // MARK: Search

    /// <summary>What the field matches, found in one go across the history and the snippets.</summary>
    public sealed record Found(IReadOnlyList<Clip> Clips, IReadOnlyList<Snippet> Snippets)
    {
        public bool IsEmpty => Clips.Count == 0 && Snippets.Count == 0;
    }

    /// <summary>Every clip and snippet holding every word of <paramref name="query"/>, in any order and any case,
    /// accents ignored. A clip matches on its text and its app (a picture on its label, in English and as shown; one
    /// holding a protected snippet's words only on its mask); a snippet on its title, its folder's title and
    /// its words, but a protected one only on its title and folder. An empty query finds everything: the
    /// pinned clips first, then the rest newest first.</summary>
    public static Found Search(string query, History history, SnippetBook snippets)
    {
        var words = Fold(query).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        bool Holds(string haystack)
        {
            var folded = Fold(haystack);
            return words.All(folded.Contains);
        }
        var clips = history.Clips.Where(c => words.Length == 0
            || (snippets.MaskFor(c) is { } mask ? Holds(mask + " " + (c.App ?? ""))
                : Holds(string.Join(" ", c.Text, c.App ?? "", c.Kind == Kind.Image ? c.Preview(200) : "")))).ToList();
        var ordered = clips.Where(c => c.Pinned).Concat(clips.Where(c => !c.Pinned)).ToList();
        var found = snippets.All.Where(x => words.Length == 0 || Holds(string.Join(" ", x.Snippet.Title, x.Folder.Title, x.Snippet.Protected ? "" : x.Snippet.Text)))
            .Select(x => x.Snippet).ToList();
        return new Found(ordered, found);
    }

    /// <summary>Case, accents and width folded away, as Foundation's folding does.</summary>
    internal static string Fold(string s)
    {
        var decomposed = s.Normalize(NormalizationForm.FormKD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var ch in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark) sb.Append(ch);
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    internal static string Preview(string text, int limit)
    {
        var line = string.Join(" ", text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return line.Length > limit ? line[..Math.Max(limit - 1, 0)] + "…" : line;
    }

    // MARK: What not to keep

    /// <summary>Pasteboard types that mark a copy as not for keeping (nspasteboard.org), as the Mac reads them.</summary>
    public static readonly IReadOnlySet<string> ConcealedTypes = new HashSet<string>
    {
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping",
        "Pasteboard generator type", "net.antelle.keeweb",
    };

    /// <summary>Clipboard formats Windows uses for the same. <c>CanIncludeInClipboardHistory</c> set to 0 is
    /// checked by its value, by the app, not by its name.</summary>
    public static readonly IReadOnlySet<string> WindowsConcealedFormats = new HashSet<string>
    {
        "ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore",
    };

    /// <summary>Password managers and the like, by bundle id: the Mac's list.</summary>
    public static readonly IReadOnlyList<string> DefaultExcludedMacApps = new[]
    {
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "org.keepassxc.keepassxc",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
        "in.sinew.Enpass-Desktop", "com.markmcguill.strongbox.mac",
    };

    /// <summary>The same on Windows, by process name: nothing copied while one of them owns the clipboard is kept.</summary>
    public static readonly IReadOnlyList<string> DefaultExcludedWindowsApps = new[]
    {
        "1Password.exe", "Bitwarden.exe", "KeePass.exe", "KeePassXC.exe", "LastPass.exe", "Dashlane.exe", "Enpass.exe",
    };

    /// <summary>Whether a copy should go into the history: not marked secret or passing by <paramref name="types"/>,
    /// and not copied in an excluded app (compared without case).</summary>
    public static bool ShouldKeep(IEnumerable<string> types, string? app, IEnumerable<string> excluded)
    {
        var list = types.ToList();
        if (list.Any(ConcealedTypes.Contains) || list.Any(WindowsConcealedFormats.Contains)) return false;
        if (app is null) return true;
        return !excluded.Any(e => string.Equals(e.Trim(), app, StringComparison.OrdinalIgnoreCase));
    }

    // MARK: Pictures

    /// <summary>Clipboard formats a picture is kept in, best first: PNG (Snipping Tool, browsers, Office), JPEG and GIF as
    /// some apps write them, and the device-independent bitmap every picture on Windows' clipboard has.</summary>
    public static readonly IReadOnlyList<string> WindowsImageFormats = new[] { "PNG", "JFIF", "GIF", "DeviceIndependentBitmap" };

    /// <summary>Which of the formats found to keep, best first in <paramref name="preference"/>: each while all kept so far
    /// stay within <paramref name="cap"/> bytes, so a huge bitmap is left out while its PNG stays. Empty: none fits.</summary>
    public static List<string> KeptImageTypes(IReadOnlyDictionary<string, int> found, long cap, IEnumerable<string>? preference = null)
    {
        long total = 0;
        var kept = new List<string>();
        foreach (var type in preference ?? WindowsImageFormats)
        {
            if (!found.TryGetValue(type, out var bytes) || total + bytes > cap) continue;
            total += bytes;
            kept.Add(type);
        }
        return kept;
    }

    /// <summary>A short fingerprint of <paramref name="data"/> (FNV-1a, 64 bits), as the Mac writes it.</summary>
    public static string Digest(byte[] data)
    {
        var hash = 0xcbf29ce484222325UL;
        foreach (var b in data) hash = (hash ^ b) * 0x100000001b3UL;
        return $"{hash:x16}-{data.Length}";
    }

    /// <summary>A picture's size in pixels from its header: PNG, a device-independent bitmap, GIF or JPEG; null when unreadable.</summary>
    public static (int Width, int Height)? PixelSize(string format, byte[] b)
    {
        static int Be(byte[] b, int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
        switch (format)
        {
            case "PNG" when b.Length >= 24 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G':
                return (Be(b, 16), Be(b, 20));
            case "DeviceIndependentBitmap" when b.Length >= 12:
                return BitConverter.ToInt32(b, 0) == 12
                    ? (BitConverter.ToUInt16(b, 4), BitConverter.ToUInt16(b, 6))
                    : (BitConverter.ToInt32(b, 4), Math.Abs(BitConverter.ToInt32(b, 8)));
            case "GIF" when b.Length >= 10 && b[0] == 'G' && b[1] == 'I' && b[2] == 'F':
                return (BitConverter.ToUInt16(b, 6), BitConverter.ToUInt16(b, 8));
            case "JFIF" when b.Length >= 4 && b[0] == 0xFF && b[1] == 0xD8:
                // Walk the markers to the first start-of-frame, which holds the height and width.
                for (var i = 2; i + 9 < b.Length;)
                {
                    if (b[i] != 0xFF) return null;
                    var marker = b[i + 1];
                    var length = (b[i + 2] << 8) | b[i + 3];
                    if (marker is >= 0xC0 and <= 0xCF and not 0xC4 and not 0xC8 and not 0xCC)
                        return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
                    i += 2 + length;
                }
                return null;
            default:
                return null;
        }
    }

    /// <summary>A device-independent bitmap as a .bmp file: the 14-byte file header in front, so a decoder reads it.</summary>
    public static byte[] DibAsBmp(byte[] dib)
    {
        var headerSize = BitConverter.ToInt32(dib, 0);
        var bitCount = headerSize == 12 ? BitConverter.ToUInt16(dib, 10) : BitConverter.ToUInt16(dib, 14);
        var compression = headerSize >= 40 ? BitConverter.ToInt32(dib, 16) : 0;
        var used = headerSize >= 40 ? BitConverter.ToInt32(dib, 32) : 0;
        var colours = used > 0 ? used : bitCount <= 8 ? 1 << bitCount : 0;
        var masks = headerSize == 40 && compression is 3 or 6 ? (compression == 3 ? 12 : 16) : 0;
        var offset = 14 + headerSize + masks + colours * (headerSize == 12 ? 3 : 4);
        var bmp = new byte[14 + dib.Length];
        bmp[0] = (byte)'B'; bmp[1] = (byte)'M';
        BitConverter.GetBytes(bmp.Length).CopyTo(bmp, 2);
        BitConverter.GetBytes(offset).CopyTo(bmp, 10);
        dib.CopyTo(bmp, 14);
        return bmp;
    }

    // MARK: Files

    /// <summary><c>clipboard.json</c> and <c>snippets.json</c>, side by side, in the Mac's format, and the pictures in
    /// <c>clipboard-images</c> there, a file per clip and format: <c>&lt;id&gt;.PNG</c>.</summary>
    public sealed class Store
    {
        public string Directory { get; }
        public Store(string directory) { Directory = directory; }
        public string HistoryFile => Path.Combine(Directory, "clipboard.json");
        public string SnippetsFile => Path.Combine(Directory, "snippets.json");
        public string ImagesDirectory => Path.Combine(Directory, "clipboard-images");
        public string ImageFile(Guid id, string type) => Path.Combine(ImagesDirectory, id.ToString("D").ToUpperInvariant() + "." + type);

        /// <summary>A picture's bytes, a file per format.</summary>
        public void SaveImage(Guid id, IEnumerable<(string Type, byte[] Data)> kinds)
        {
            System.IO.Directory.CreateDirectory(ImagesDirectory);
            foreach (var (type, data) in kinds) System.IO.File.WriteAllBytes(ImageFile(id, type), data);
        }

        /// <summary>An image clip's bytes in the formats it was kept as, best first; empty when its files are gone.</summary>
        public List<(string Type, byte[] Data)> LoadImage(Clip clip)
        {
            var read = new List<(string, byte[])>();
            foreach (var type in clip.Picture?.Types ?? new())
            {
                try { read.Add((type, System.IO.File.ReadAllBytes(ImageFile(clip.Id, type)))); }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            }
            return read;
        }

        /// <summary>Deletes every picture file whose clip is no longer in <paramref name="history"/>.</summary>
        public void SweepImages(History history)
        {
            if (!System.IO.Directory.Exists(ImagesDirectory)) return;
            var kept = history.Clips.Where(c => c.Kind == Kind.Image).Select(c => c.Id.ToString("D").ToUpperInvariant()).ToHashSet();
            foreach (var file in System.IO.Directory.GetFiles(ImagesDirectory))
            {
                var name = Path.GetFileName(file);
                if (name.Length < 36 || !kept.Contains(name[..36]))
                    try { System.IO.File.Delete(file); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            }
        }

        private static readonly JsonSerializerOptions options = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = true,
            Converters = { new IsoTimeConverter() },
        };

        public History LoadHistory() => Load<History>(HistoryFile) ?? new History();
        public SnippetBook LoadSnippets() => Load<SnippetBook>(SnippetsFile) ?? new SnippetBook();
        public void Save(History history) => Save(history, HistoryFile);
        public void Save(SnippetBook book) => Save(book, SnippetsFile);

        private static T? Load<T>(string file) where T : class
        {
            try { return System.IO.File.Exists(file) ? JsonSerializer.Deserialize<T>(System.IO.File.ReadAllText(file), options) : null; }
            catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException or FormatException) { return null; }
        }

        private void Save<T>(T value, string file)
        {
            System.IO.Directory.CreateDirectory(Directory);
            var temp = file + ".tmp";
            System.IO.File.WriteAllText(temp, JsonSerializer.Serialize(value, options), new UTF8Encoding(false));
            System.IO.File.Move(temp, file, overwrite: true);
        }
    }

    internal sealed class KindConverter : JsonConverter<Kind>
    {
        public override Kind Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) => reader.GetString() switch
        {
            "rich" => Kind.Rich,
            "files" => Kind.Files,
            "image" => Kind.Image,
            _ => Kind.Text,
        };

        public override void Write(Utf8JsonWriter writer, Kind value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value switch { Kind.Rich => "rich", Kind.Files => "files", Kind.Image => "image", _ => "text" });
    }

    // MARK: Clipy's XML

    /// <summary>Snippets in and out as Clipy's XML: <c>&lt;folders&gt;&lt;folder&gt;&lt;title/&gt;&lt;snippets&gt;&lt;snippet&gt;&lt;title/&gt;&lt;content/&gt;</c>.
    /// A protected snippet is exported with its title and no words.</summary>
    public sealed class NotClipyXmlException : Exception
    {
        public NotClipyXmlException() : base("not Clipy's snippets XML") { }
    }

    public static SnippetBook ImportClipy(string xml)
    {
        var doc = new XmlDocument();
        try { doc.LoadXml(xml); } catch (XmlException) { throw new NotClipyXmlException(); }
        if (doc.DocumentElement is not { Name: "folders" } root) throw new NotClipyXmlException();
        var book = new SnippetBook();
        foreach (var folderNode in root.ChildNodes.OfType<XmlElement>().Where(e => e.Name == "folder"))
        {
            var folder = new Folder { Title = Child(folderNode, "title")?.InnerText.Trim() ?? "" };
            var list = Child(folderNode, "snippets");
            foreach (var s in list?.ChildNodes.OfType<XmlElement>().Where(e => e.Name == "snippet") ?? Enumerable.Empty<XmlElement>())
                folder.Snippets.Add(new Snippet { Title = Child(s, "title")?.InnerText.Trim() ?? "", Text = Child(s, "content")?.InnerText ?? "" });
            book.Folders.Add(folder);
        }
        return book;
    }

    private static XmlElement? Child(XmlNode node, string name) => node.ChildNodes.OfType<XmlElement>().FirstOrDefault(e => e.Name == name);

    public static string ExportClipy(SnippetBook book)
    {
        var sb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<folders>\n");
        foreach (var folder in book.Folders)
        {
            sb.Append("  <folder>\n    <title>").Append(Escape(folder.Title)).Append("</title>\n    <snippets>\n");
            foreach (var s in folder.Snippets)
            {
                sb.Append("      <snippet>\n        <title>").Append(Escape(s.Title)).Append("</title>\n");
                sb.Append("        <content>").Append(s.Protected ? "" : Escape(s.Text)).Append("</content>\n      </snippet>\n");
            }
            sb.Append("    </snippets>\n  </folder>\n");
        }
        return sb.Append("</folders>\n").ToString();
    }

    internal static string Escape(string s) =>
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
}
