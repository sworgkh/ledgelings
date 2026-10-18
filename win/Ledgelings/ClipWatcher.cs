using System.Runtime.InteropServices;
using System.Windows;
using Ledgelings.Core;
using Ledgelings.Native;
using WpfClipboard = System.Windows.Clipboard;
using Clipboard = Ledgelings.Core.Clipboard;

namespace Ledgelings;

/// <summary>
/// Watches Windows' clipboard for copies and keeps them in the history (SPEC §7.11). Windows says when the
/// clipboard changes (<c>WM_CLIPBOARDUPDATE</c>), so nothing is polled. A copy marked not for keeping
/// (<c>ExcludeClipboardContentFromMonitorProcessing</c>, <c>Clipboard Viewer Ignore</c>, or
/// <c>CanIncludeInClipboardHistory</c> set to 0, as password managers write), one made by an excluded app, and
/// the app's own writes are left out. Files are kept as their paths; a picture (a copy with no words, only image
/// formats) as files of its own beside the history, as on the Mac.
/// </summary>
public sealed class ClipWatcher : IDisposable
{
    private static readonly Win32.WindowClass windowClass = new("LedgelingsClipboard");
    private readonly AppSettings settings;
    private readonly ClipBook book;
    private readonly IntPtr hwnd;
    private bool listening;
    /// <summary>What the watcher did with each copy, for a trace.</summary>
    public Action<string>? Trace { get; set; }

    public ClipWatcher(AppSettings settings, ClipBook book)
    {
        this.settings = settings;
        this.book = book;
        hwnd = windowClass.Create(0, Win32.WS_POPUP, 0, 0, 0, 0, WndProc);
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.ClipboardEnabled) or nameof(AppSettings.ClipHistoryEnabled)) Follow();
        };
        Follow();
    }

    private void Follow()
    {
        var wanted = settings.ClipboardEnabled && settings.ClipHistoryEnabled;
        if (wanted == listening) return;
        if (wanted) listening = ClipboardNative.AddClipboardFormatListener(hwnd);
        else { ClipboardNative.RemoveClipboardFormatListener(hwnd); listening = false; }
    }

    private IntPtr? WndProc(IntPtr window, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg != ClipboardNative.WM_CLIPBOARDUPDATE) return null;
        Look();
        return IntPtr.Zero;
    }

    /// <summary>Reads the clipboard after a change.</summary>
    public void Look()
    {
        if (!listening) return;
        var data = ClipPaster.Retry(WpfClipboard.GetDataObject);
        if (data is null) return;
        var formats = data.GetFormats(false);
        if (formats.Contains(ClipPaster.OwnFormat)) return;
        var owner = ClipboardNative.GetClipboardOwner();
        var process = ClipboardNative.ProcessName(owner) ?? ClipboardNative.ProcessName(ClipboardNative.GetForegroundWindow());
        if (Refused(data) || !Clipboard.ShouldKeep(formats, process, settings.ClipExcludedApps))
        {
            Trace?.Invoke($"skip {process ?? "?"}: concealed, passing or excluded");
            return;
        }
        var app = ClipboardNative.AppTitle(owner) ?? process;
        if (Read(data, DateTimeOffset.Now, app, settings) is { } clip)
        {
            book.Add(clip, settings.ClipHistoryLimit, settings.ClipKeepDays);
            // A protected snippet's words never reach a log, only their mask.
            Trace?.Invoke($"keep {clip.Kind} \"{book.Snippets.MaskFor(clip) ?? clip.Preview(40)}\" from {clip.App ?? "?"}");
            return;
        }
        switch (ReadImage(data, DateTimeOffset.Now, app, settings))
        {
            case ImageRead.Image(var picture, var kinds):
                book.AddImage(picture, kinds, settings.ClipHistoryLimit, settings.ClipKeepDays);
                Trace?.Invoke($"keep image \"{picture.Text}\" as {string.Join(" + ", kinds.Select(k => k.Type))} from {picture.App ?? "?"}");
                break;
            case ImageRead.TooBig(var bytes):
                Trace?.Invoke($"skip: image of {bytes / 1_048_576.0:F1} MB, over {settings.ClipLargestImageMB} MB");
                break;
            default:
                Trace?.Invoke("skip: no text");
                break;
        }
    }

    public abstract record ImageRead
    {
        public sealed record None : ImageRead;
        /// <summary>A picture, but even its smallest format is over the size kept; its smallest size.</summary>
        public sealed record TooBig(int Bytes) : ImageRead;
        public sealed record Image(Clipboard.Clip Clip, IReadOnlyList<(string Type, byte[] Data)> Kinds) : ImageRead;
    }

    /// <summary>The copy as a picture, in every image format it came in that fits the size kept.</summary>
    public static ImageRead ReadImage(IDataObject data, DateTimeOffset now, string? app, AppSettings settings)
    {
        if (!settings.ClipKeepImages) return new ImageRead.None();
        var found = new Dictionary<string, byte[]>();
        try
        {
            foreach (var format in Clipboard.WindowsImageFormats)
                if (data.GetDataPresent(format, false) && data.GetData(format, false) is MemoryStream stream && stream.Length > 0)
                    found[format] = stream.ToArray();
        }
        catch (Exception e) when (e is COMException or ExternalException or OutOfMemoryException) { }
        if (found.Count == 0) return new ImageRead.None();
        var kept = Clipboard.KeptImageTypes(found.ToDictionary(f => f.Key, f => f.Value.Length), settings.ClipLargestImageMB * 1_048_576L);
        if (kept.Count == 0) return new ImageRead.TooBig(found.Values.Min(v => v.Length));
        if (Clipboard.PixelSize(kept[0], found[kept[0]]) is not var (width, height) || width <= 0 || height <= 0) return new ImageRead.None();
        var kinds = kept.Select(type => (type, found[type])).ToList();
        var picture = new Clipboard.Picture
        {
            Width = width, Height = height, Bytes = kinds.Sum(k => k.Item2.Length), Digest = Clipboard.Digest(found[kept[0]]), Types = kept,
        };
        return new ImageRead.Image(Clipboard.Clip.FromPicture(picture, now, app), kinds);
    }

    /// <summary><c>CanIncludeInClipboardHistory</c> = 0: the app asked to be left out of every history.</summary>
    private static bool Refused(IDataObject data)
    {
        try
        {
            if (data.GetData("CanIncludeInClipboardHistory") is MemoryStream s && s.Length >= 4)
            {
                var bytes = new byte[4];
                s.Position = 0;
                s.ReadExactly(bytes);
                return BitConverter.ToInt32(bytes) == 0;
            }
        }
        catch (Exception e) when (e is COMException or ExternalException or IOException) { }
        return false;
    }

    /// <summary>The copy as a clip: files (as paths), else text with its RTF beside it, else nothing.</summary>
    public static Clipboard.Clip? Read(IDataObject data, DateTimeOffset now, string? app, AppSettings settings)
    {
        try
        {
            if (settings.ClipKeepFiles && data.GetDataPresent(DataFormats.FileDrop) && data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
                return new Clipboard.Clip { Kind = Clipboard.Kind.Files, Text = string.Join("\n", files), CopiedAt = now, App = app };
            if (data.GetData(DataFormats.UnicodeText) is not string text) return null;
            var rtf = settings.ClipKeepFormatting && data.GetData(DataFormats.Rtf) is string r ? System.Text.Encoding.UTF8.GetBytes(r) : null;
            return new Clipboard.Clip { Kind = rtf is null ? Clipboard.Kind.Text : Clipboard.Kind.Rich, Text = text, Rtf = rtf, CopiedAt = now, App = app };
        }
        catch (Exception e) when (e is COMException or ExternalException) { return null; }
    }

    public void Dispose()
    {
        if (listening) ClipboardNative.RemoveClipboardFormatListener(hwnd);
        Win32.WindowClass.Destroy(hwnd);
    }
}

/// <summary>Puts a chosen item on the clipboard and presses Ctrl+V for the app that was in front. No permission is
/// needed for that on Windows, so the copy-only fallback is only for <see cref="AppSettings.ClipAutoPaste"/> off.</summary>
public static class ClipPaster
{
    /// <summary>Marks our own writes, so the watcher (and other clipboard managers) know where they came from.</summary>
    public const string OwnFormat = "Ledgelings.Paste";

    /// <param name="Images">A picture, in each format it was copied as: put back as those formats, with no words.</param>
    public sealed record Item(string Text, byte[]? Rtf = null, IReadOnlyList<string>? Files = null, bool Secret = false,
                              IReadOnlyList<(string Type, byte[] Data)>? Images = null);

    /// <summary>The clipboard is shared and often busy for a moment: a few tries, then nothing.</summary>
    public static T? Retry<T>(Func<T> read) where T : class
    {
        for (var i = 0; i < 5; i++)
        {
            try { return read(); }
            catch (Exception e) when (e is COMException or ExternalException) { Thread.Sleep(15); }
        }
        return null;
    }

    private static void Retry(Action write) => Retry<object>(() => { write(); return new object(); });

    private static MemoryStream Dword(int value) => new(BitConverter.GetBytes(value));

    /// <summary>Writes <paramref name="item"/>; <paramref name="plain"/> leaves its formatting off. A secret is marked
    /// so no clipboard history or cloud clipboard keeps it.</summary>
    public static void Put(Item item, bool plain)
    {
        var data = new DataObject();
        if (item.Files is { Count: > 0 } files) data.SetData(DataFormats.FileDrop, files.ToArray());
        foreach (var (type, bytes) in item.Images ?? Array.Empty<(string, byte[])>()) data.SetData(type, new MemoryStream(bytes), false);
        if (item.Images is not { Count: > 0 }) data.SetData(DataFormats.UnicodeText, item.Text);
        if (!plain && item.Rtf is { } rtf) data.SetData(DataFormats.Rtf, System.Text.Encoding.UTF8.GetString(rtf));
        data.SetData(OwnFormat, "1");
        if (item.Secret)
        {
            data.SetData("ExcludeClipboardContentFromMonitorProcessing", Dword(0));
            data.SetData("CanIncludeInClipboardHistory", Dword(0));
            data.SetData("CanUploadToCloudClipboard", Dword(0));
        }
        Retry(() => WpfClipboard.SetDataObject(data, true));
    }

    /// <summary>The words, formatting and files on the clipboard now, to put back after a secret was pasted.</summary>
    public static Item? Saved()
    {
        var data = Retry(WpfClipboard.GetDataObject);
        if (data is null) return null;
        try
        {
            var files = data.GetData(DataFormats.FileDrop) as string[];
            var text = data.GetData(DataFormats.UnicodeText) as string;
            var rtf = data.GetData(DataFormats.Rtf) is string r ? System.Text.Encoding.UTF8.GetBytes(r) : null;
            return text is null && files is null ? null : new Item(text ?? "", rtf, files);
        }
        catch (Exception e) when (e is COMException or ExternalException) { return null; }
    }

    public static void Restore(Item? before)
    {
        if (before is null) Retry(WpfClipboard.Clear);
        else Put(before, plain: false);
    }
}
