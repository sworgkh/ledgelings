using Ledgelings.Core;
using Ledgelings.Native;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Productivity tools › Clipboard and the book behind it. The Mac's ClipboardSettingsTests, less the
/// fingerprint: Windows asks for none (SPEC §7.11).</summary>
public class ClipboardSettingsTests
{
    [Fact]
    public void TheDefaultsAndAChangeSurviveARelaunch()
    {
        var store = new MemorySettingsStore();
        var secrets = new MemorySecretStore();
        var s = new AppSettings(store, secrets);
        Assert.True(s.ClipboardEnabled && s.ClipHistoryEnabled && s.ClipKeepFormatting && s.ClipKeepFiles && s.ClipAutoPaste && !s.ClipPlainText);
        Assert.True(s.ClipHistoryLimit == 200 && s.ClipKeepDays == 30 && s.ClipAnimationSpeed == 1);
        Assert.True(s.ClipHistoryShortcutEnabled && s.ClipSnippetsShortcutEnabled && s.ClipSnippetShortcutsEnabled);
        Assert.Equal(Shortcut.ClipHistory, s.ClipHistoryShortcut);                                     // Ctrl+Alt+V
        Assert.Equal(Shortcut.ClipSnippets, s.ClipSnippetsShortcut);                                   // Ctrl+Alt+B
        Assert.True(s.ClipAnimate && s.ClipHelperEnabled && s.ClipHelper == "" && s.ClipHelperTalks);
        Assert.Equal(Clipboard.DefaultExcludedWindowsApps, s.ClipExcludedApps);
        Assert.True(s.ClipKeepImages && s.ClipLargestImageMB == 20);

        s.ClipboardEnabled = false; s.ClipHistoryEnabled = false; s.ClipKeepFormatting = false; s.ClipKeepFiles = false;
        s.ClipAutoPaste = false; s.ClipPlainText = true; s.ClipHistoryLimit = 500; s.ClipKeepDays = 0; s.ClipAnimationSpeed = 2;
        s.ClipHistoryShortcutEnabled = false; s.ClipSnippetsShortcutEnabled = false; s.ClipSnippetShortcutsEnabled = false;
        s.ClipHistoryShortcut = new Shortcut(0x48, ShortcutModifiers.Control | ShortcutModifiers.Shift);
        s.ClipAnimate = false; s.ClipHelperEnabled = false; s.ClipHelper = "Blocky"; s.ClipHelperTalks = false;
        s.ClipExcludedApps = new[] { "keepass.exe" };
        s.ClipKeepImages = false; s.ClipLargestImageMB = 5;
        var again = new AppSettings(store, secrets);
        Assert.True(!again.ClipboardEnabled && !again.ClipHistoryEnabled && !again.ClipKeepFormatting && !again.ClipKeepFiles);
        Assert.True(!again.ClipAutoPaste && again.ClipPlainText && again.ClipHistoryLimit == 500 && again.ClipKeepDays == 0 && again.ClipAnimationSpeed == 2);
        Assert.True(!again.ClipHistoryShortcutEnabled && !again.ClipSnippetsShortcutEnabled && !again.ClipSnippetShortcutsEnabled);
        Assert.Equal(new Shortcut(0x48, ShortcutModifiers.Control | ShortcutModifiers.Shift), again.ClipHistoryShortcut);
        Assert.True(!again.ClipAnimate && !again.ClipHelperEnabled && again.ClipHelper == "Blocky" && !again.ClipHelperTalks);
        Assert.Equal(new[] { "keepass.exe" }, again.ClipExcludedApps);
        Assert.True(!again.ClipKeepImages && again.ClipLargestImageMB == 5);

        store.Set("clipHistoryLimit", 5);
        store.Set("clipKeepDays", 9999);
        store.Set("clipAnimationSpeed", 10.0);
        store.Set("clipLargestImageMB", 500);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.ClipHistoryLimit == 10 && clamped.ClipKeepDays == 365 && clamped.ClipAnimationSpeed == 3);   // clamped on load
        Assert.Equal(100, clamped.ClipLargestImageMB);
    }

    [Fact]
    public void ClipboardIsAToolFoundByItsHeader() =>
        Assert.Contains(ProductivityTool.Clipboard, Enum.GetValues<ProductivityTool>());

    [Fact]
    public void AProtectedSnippetsWordsLiveOnlyInTheSecretStore()
    {
        var folder = Path.Combine(Path.GetTempPath(), "ledgelings-clip-" + Guid.NewGuid());
        try
        {
            var secrets = new MemorySecretStore();
            var book = new ClipBook(folder, secrets);
            var work = book.AddFolder("Work");
            var id = book.AddSnippet("Wi-Fi", "pixel-perfect-42", isProtected: true, folder: work);
            var snippet = book.Snippets.Find(id)!;
            Assert.Equal("", snippet.Text);
            Assert.DoesNotContain("pixel-perfect-42", File.ReadAllText(book.Store.SnippetsFile));
            Assert.Equal("pixel-perfect-42", book.Words(snippet));
            Assert.Equal(Clipboard.Mask, snippet.Preview());

            book.SetProtected(id, false);                       // back into the book, out of the store
            Assert.Equal("pixel-perfect-42", book.Snippets.Find(id)!.Text);
            Assert.Null(secrets.Get(snippet.SecretAccount));
            book.SetProtected(id, true);
            Assert.Equal("pixel-perfect-42", secrets.Get(snippet.SecretAccount));
            book.RemoveSnippetOrFolder(work);                   // the folder goes, and its secrets with it
            Assert.Null(secrets.Get(snippet.SecretAccount));
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }

    [Fact]
    public void ProtectedWordsAreFingerprintedNeverWrittenAndOldOnesGetTheirsOnLoad()
    {
        var folder = Path.Combine(Path.GetTempPath(), "ledgelings-clip-" + Guid.NewGuid());
        try
        {
            var secrets = new MemorySecretStore();
            var book = new ClipBook(folder, secrets);
            var id = book.AddSnippet("Wi-Fi", "pixel-perfect-42", isProtected: true);
            Assert.Equal("PWD:Wi-Fi: [16] chars", book.Snippets.MaskFor(new Clipboard.Clip { Text = "pixel-perfect-42" }));
            var plain = book.AddSnippet("Door", "1234");
            book.SetProtected(plain, true);
            Assert.Equal(plain, book.Snippets.SecretMatching("1234")?.Id);
            book.Update(book.Snippets.Find(id)!, "new-password");
            Assert.Null(book.Snippets.SecretMatching("pixel-perfect-42"));
            Assert.Equal(id, book.Snippets.SecretMatching("new-password")?.Id);
            Assert.DoesNotContain("new-password", File.ReadAllText(book.Store.SnippetsFile));

            // A book saved before fingerprints: the first load reads Credential Manager once and fingerprints it.
            foreach (var (_, s) in book.Snippets.All.ToList()) book.Snippets.Update(s with { SecretSalt = null, SecretHash = null });
            book.Store.Save(book.Snippets);
            var again = new ClipBook(folder, secrets);
            Assert.Equal(id, again.Snippets.SecretMatching("new-password")?.Id);
            Assert.Equal(plain, again.Snippets.SecretMatching("1234")?.Id);
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }

    /// <summary>A 48×30 PNG, the same picture as a 32-bit device-independent bitmap.</summary>
    private static (byte[] Png, byte[] Dib) Picture()
    {
        var pixels = new byte[48 * 30 * 4];
        for (var i = 0; i < pixels.Length; i += 4) { pixels[i] = 0x20; pixels[i + 1] = 0x99; pixels[i + 2] = 0xF2; pixels[i + 3] = 0xFF; }
        var source = System.Windows.Media.Imaging.BitmapSource.Create(48, 30, 96, 96, System.Windows.Media.PixelFormats.Bgra32, null, pixels, 48 * 4);
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(source));
        using var png = new MemoryStream();
        encoder.Save(png);
        var dib = new byte[40 + pixels.Length];
        BitConverter.GetBytes(40).CopyTo(dib, 0); BitConverter.GetBytes(48).CopyTo(dib, 4); BitConverter.GetBytes(-30).CopyTo(dib, 8);
        BitConverter.GetBytes((ushort)1).CopyTo(dib, 12); BitConverter.GetBytes((ushort)32).CopyTo(dib, 14);
        pixels.CopyTo(dib, 40);
        return (png.ToArray(), dib);
    }

    [Fact]
    public void ACopiedPictureIsReadKeptAsFilesThumbnailedAndForgotten() => OnSta(() =>
    {
        var folder = Path.Combine(Path.GetTempPath(), "ledgelings-clip-" + Guid.NewGuid());
        try
        {
            var settings = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
            var book = new ClipBook(folder, new MemorySecretStore());
            var (png, dib) = Picture();
            var data = new System.Windows.DataObject();
            data.SetData("PNG", new MemoryStream(png), false);
            data.SetData(System.Windows.DataFormats.Dib, new MemoryStream(dib), false);
            var read = Assert.IsType<ClipWatcher.ImageRead.Image>(ClipWatcher.ReadImage(data, DateTimeOffset.Now, "Snipping Tool", settings));
            Assert.Equal("Image 48×30", read.Clip.Text);
            Assert.Equal(new[] { "PNG", "DeviceIndependentBitmap" }, read.Kinds.Select(k => k.Type));
            book.AddImage(read.Clip, read.Kinds, settings.ClipHistoryLimit, settings.ClipKeepDays);
            book.AddImage(ClipWatcher.ReadImage(data, DateTimeOffset.Now, null, settings) is ClipWatcher.ImageRead.Image again ? again.Clip : read.Clip,
                          read.Kinds, settings.ClipHistoryLimit, settings.ClipKeepDays);
            var clip = Assert.Single(book.History.Clips);                       // the same picture again is the same clip
            Assert.Equal(png, book.ImageData(clip)[0].Data);
            var thumbnail = book.Thumbnail(clip)!;
            Assert.Equal(ClipBook.ThumbnailPixels, Math.Max(thumbnail.PixelWidth, thumbnail.PixelHeight));

            settings.ClipLargestImageMB = 1;
            var big = new System.Windows.DataObject();
            big.SetData(System.Windows.DataFormats.Dib, new MemoryStream(new byte[2 * 1_048_576]), false);
            Assert.IsType<ClipWatcher.ImageRead.TooBig>(ClipWatcher.ReadImage(big, DateTimeOffset.Now, null, settings));
            settings.ClipKeepImages = false;
            Assert.IsType<ClipWatcher.ImageRead.None>(ClipWatcher.ReadImage(data, DateTimeOffset.Now, null, settings));

            book.Remove(clip.Id);
            Assert.Empty(book.ImageData(clip));                                 // a forgotten picture's files go
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    });

    [Fact]
    public void ThePickerDrawsMoreThanOneRow() => OnSta(() =>
    {
        // Each unchosen row once had its panel handed to two parents, which WPF refuses: the app
        // closed the moment the picker opened with two or more copies or snippets.
        var folder = Path.Combine(Path.GetTempPath(), "ledgelings-clip-" + Guid.NewGuid());
        try
        {
            var settings = new AppSettings(new MemorySettingsStore(), new MemorySecretStore());
            var book = new ClipBook(folder, new MemorySecretStore());
            book.AddSnippet("Signature", "Best regards");
            book.AddSnippet("Address", "12 Café Street");
            book.AddSnippet("Phone", "555-0100");
            var controller = new ClipPickerController(settings, book, () => null, () => { });
            var model = new ClipPicker(() => (book.History, book.Snippets)) { First = ClipPicker.Group.Snippets };
            model.Search("");
            model.Refresh(selectFirst: true);
            Assert.Equal(3, model.Rows.Count);
            var window = new ClipPickerWindow(controller, model, settings, Desktop.Primary(Desktop.Monitors())!);
            window.Redraw(scroll: false);
            model.Step(1);
            window.Redraw(scroll: false);                                      // and again with another chosen
            window.Close();
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    });

    private static void OnSta(Action body)
    {
        Exception? failed = null;
        var thread = new Thread(() => { try { body(); } catch (Exception e) { failed = e; } });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failed is not null) throw new Xunit.Sdk.XunitException(failed.ToString());
    }
}
