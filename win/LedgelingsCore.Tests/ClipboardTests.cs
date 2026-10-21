using Clip = Ledgelings.Core.Clipboard.Clip;
using Snippet = Ledgelings.Core.Clipboard.Snippet;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.11: the clipboard history, the snippets, the search across both, what is never kept, and
/// Clipy's XML. The Mac's ClipboardTests, test for test.</summary>
public class ClipboardTests
{
    private static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static Clipboard.History History(params string[] texts)
    {
        var h = new Clipboard.History();
        for (int i = 0; i < texts.Length; i++) h.Add(new Clip { Text = texts[i], CopiedAt = T0.AddSeconds(i) });
        return h;
    }

    [Fact]
    public void NewestComesFirst() => Assert.Equal(new[] { "c", "b", "a" }, History("a", "b", "c").Clips.Select(c => c.Text));

    [Fact]
    public void CopyingTheSameTextAgainMovesItUpAndKeepsItsPin()
    {
        var h = History("a", "b");
        var a = h.Clips[1].Id;
        h.TogglePin(a);
        h.Add(new Clip { Text = "a", CopiedAt = T0.AddSeconds(10) });
        Assert.Equal(new[] { "a", "b" }, h.Clips.Select(c => c.Text));
        Assert.Equal(a, h.Clips[0].Id);
        Assert.True(h.Clips[0].Pinned);
        Assert.Equal(T0.AddSeconds(10), h.Clips[0].CopiedAt);
    }

    [Fact]
    public void BlankCopiesAreNotKept()
    {
        var h = new Clipboard.History();
        Assert.False(h.Add(new Clip { Text = "  \n\t", CopiedAt = T0 }));
        Assert.Empty(h.Clips);
    }

    [Fact]
    public void AHugeCopyIsCutAndHugeFormattingDropped()
    {
        var h = new Clipboard.History();
        h.Add(new Clip { Kind = Clipboard.Kind.Rich, Text = new string('x', Clipboard.LongestClip + 5), Rtf = new byte[Clipboard.LargestRtf + 1], CopiedAt = T0 });
        Assert.Equal(Clipboard.LongestClip, h.Clips[0].Text.Length);
        Assert.Null(h.Clips[0].Rtf);
        Assert.Equal(Clipboard.Kind.Text, h.Clips[0].Kind);
    }

    [Fact]
    public void PruneKeepsTheNewestAndEveryPin()
    {
        var h = History("1", "2", "3", "4", "5");
        h.TogglePin(h.Clips[4].Id);
        h.Prune(2, 0, T0);
        Assert.Equal(new[] { "5", "4", "1" }, h.Clips.Select(c => c.Text));
    }

    [Fact]
    public void PruneForgetsClipsOlderThanTheDaysToKeep()
    {
        var h = new Clipboard.History();
        h.Add(new Clip { Text = "old", CopiedAt = T0 });
        h.Add(new Clip { Text = "new", CopiedAt = T0.AddDays(9) });
        h.Prune(100, 7, T0.AddDays(10));
        Assert.Equal(new[] { "new" }, h.Clips.Select(c => c.Text));
        h.Add(new Clip { Text = "older still", CopiedAt = T0.AddDays(-300) });
        h.Prune(100, 0, T0.AddDays(10));
        Assert.Equal(2, h.Clips.Count);
    }

    [Fact]
    public void ClearAllKeepsPinsUnlessAskedNotTo()
    {
        var h = History("a", "b", "c");
        h.TogglePin(h.Clips[1].Id);
        h.Clear();
        Assert.Equal(new[] { "b" }, h.Clips.Select(c => c.Text));
        h.Clear(pinnedToo: true);
        Assert.Empty(h.Clips);
    }

    [Fact]
    public void RemoveTakesOneClip()
    {
        var h = History("a", "b");
        h.Remove(h.Clips[0].Id);
        Assert.Equal(new[] { "a" }, h.Clips.Select(c => c.Text));
    }

    [Fact]
    public void PreviewFoldsWhitespaceAndCuts()
    {
        Assert.Equal("hello world !", new Clip { Text = "  hello\n\n  world\t!" }.Preview());
        Assert.Equal("abcd…", new Clip { Text = "abcdefghij" }.Preview(5));
        Assert.Equal("a.txt, b.png", new Clip { Kind = Clipboard.Kind.Files, Text = "C:\\Users\\me\\a.txt\nC:\\Users\\me\\b.png" }.Preview());
    }

    [Fact]
    public void AProtectedSnippetNeverHoldsItsWords()
    {
        var s = Snippet.Make("Bank", "hunter2", isProtected: true);
        Assert.Equal("", s.Text);
        Assert.Equal(Clipboard.Mask, s.Preview());
        var book = new Clipboard.SnippetBook();
        var id = book.Add(Snippet.Make("Bank", "x"));
        book.Update(new Snippet { Id = id, Title = "Bank", Text = "hunter2", Protected = true });
        Assert.Equal("", book.Find(id)!.Text);
        Assert.Equal("snippet." + id.ToString("D").ToUpperInvariant(), book.Find(id)!.SecretAccount);
    }

    [Fact]
    public void AddingToAnEmptyBookMakesAFolder()
    {
        var book = new Clipboard.SnippetBook();
        book.Add(Snippet.Make("Hi", "Hello!"));
        Assert.Single(book.Folders);
        Assert.Equal(new[] { "Hi" }, book.All.Select(x => x.Snippet.Title));
    }

    [Fact]
    public void SnippetsMoveWithinAndAcrossFolders()
    {
        var book = new Clipboard.SnippetBook();
        Guid f1 = book.AddFolder("One"), f2 = book.AddFolder("Two");
        var a = book.Add(Snippet.Make("a"), f1);
        book.Add(Snippet.Make("b"), f1);
        book.Add(Snippet.Make("c"), f2);
        book.Move(a, 1);
        Assert.Equal(new[] { "b", "a" }, book.Folders[0].Snippets.Select(s => s.Title));
        book.Move(a, 1);
        Assert.Equal(new[] { "b" }, book.Folders[0].Snippets.Select(s => s.Title));
        Assert.Equal(new[] { "a", "c" }, book.Folders[1].Snippets.Select(s => s.Title));
        book.Move(f2, -1);
        Assert.Equal(new[] { "Two", "One" }, book.Folders.Select(f => f.Title));
        book.RenameFolder(f1, "Uno");
        Assert.Equal("Uno", book.Folders[1].Title);
    }

    [Fact]
    public void RemovingAFolderHandsBackItsSnippets()
    {
        var book = new Clipboard.SnippetBook();
        var f = book.AddFolder("F");
        book.Add(Snippet.Make("a"), f);
        book.Add(Snippet.Make("p", isProtected: true), f);
        Assert.Equal(new[] { "a", "p" }, book.Remove(f).Select(s => s.Title));
        Assert.Empty(book.Folders);
    }

    [Fact]
    public void ASnippetShortcutMustBeUsable()
    {
        var s = Snippet.Make("a");
        Assert.Null(s.Shortcut);
        s = s with { Shortcut = new Shortcut(0x41, ShortcutModifiers.Control | ShortcutModifiers.Option) };
        Assert.Equal(new Shortcut(0x41, ShortcutModifiers.Control | ShortcutModifiers.Option), s.Shortcut);
        s = s with { Modifiers = (int)ShortcutModifiers.Shift };
        Assert.Null(s.Shortcut);
    }

    private static Clipboard.SnippetBook Book()
    {
        var book = new Clipboard.SnippetBook();
        var work = book.AddFolder("Work");
        book.Add(Snippet.Make("Signature", "Best regards, Evgeny"), work);
        book.Add(Snippet.Make("Bank PIN", "wxyz-4321", isProtected: true), work);
        var home = book.AddFolder("Home");
        book.Add(Snippet.Make("Address", "12 Café Street"), home);
        return book;
    }

    [Fact]
    public void SearchFindsAcrossHistoryAndSnippetsAtOnce()
    {
        var h = History("meeting at the café", "invoice 42");
        var found = Clipboard.Search("cafe", h, Book());
        Assert.Equal(new[] { "meeting at the café" }, found.Clips.Select(c => c.Text));
        Assert.Equal(new[] { "Address" }, found.Snippets.Select(s => s.Title));
    }

    [Fact]
    public void EveryWordMustMatchInAnyOrderAndCase()
    {
        var h = History("Quarterly REPORT draft", "report final");
        Assert.Equal(new[] { "Quarterly REPORT draft" }, Clipboard.Search("draft report", h, new()).Clips.Select(c => c.Text));
        Assert.True(Clipboard.Search("mail", h, new()).IsEmpty);
    }

    [Fact]
    public void AClipIsFoundByItsApp()
    {
        var h = History("x");
        h.Clips[0] = h.Clips[0] with { App = "Safari" };
        Assert.Single(Clipboard.Search("safari", h, new()).Clips);
    }

    [Fact]
    public void SnippetsMatchTitleFolderAndWordsButAProtectedOneOnlyItsTitle()
    {
        Assert.Equal(new[] { "Signature" }, Clipboard.Search("regards", new(), Book()).Snippets.Select(s => s.Title));
        Assert.Equal(new[] { "Address" }, Clipboard.Search("home", new(), Book()).Snippets.Select(s => s.Title));
        Assert.Equal(new[] { "Bank PIN" }, Clipboard.Search("pin", new(), Book()).Snippets.Select(s => s.Title));
        Assert.Empty(Clipboard.Search("wxyz-4321", new(), Book()).Snippets);
    }

    [Fact]
    public void AnEmptyQueryFindsEverythingPinnedFirst()
    {
        var h = History("a", "b", "c");
        h.TogglePin(h.Clips[2].Id);
        var found = Clipboard.Search("  ", h, Book());
        Assert.Equal(new[] { "a", "c", "b" }, found.Clips.Select(c => c.Text));
        Assert.Equal(3, found.Snippets.Count);
    }

    [Fact]
    public void ConcealedAndTransientCopiesAreNotKept()
    {
        Assert.False(Clipboard.ShouldKeep(new[] { "public.utf8-plain-text", "org.nspasteboard.ConcealedType" }, null, Array.Empty<string>()));
        Assert.False(Clipboard.ShouldKeep(new[] { "org.nspasteboard.TransientType" }, null, Array.Empty<string>()));
        Assert.False(Clipboard.ShouldKeep(new[] { "ExcludeClipboardContentFromMonitorProcessing" }, null, Array.Empty<string>()));
        Assert.True(Clipboard.ShouldKeep(new[] { "public.utf8-plain-text" }, null, Array.Empty<string>()));
    }

    [Fact]
    public void CopiesInAnExcludedAppAreNotKept()
    {
        Assert.False(Clipboard.ShouldKeep(Array.Empty<string>(), "com.1password.1password", Clipboard.DefaultExcludedMacApps));
        Assert.False(Clipboard.ShouldKeep(Array.Empty<string>(), "KEEPASSXC.EXE", Clipboard.DefaultExcludedWindowsApps));
        Assert.True(Clipboard.ShouldKeep(Array.Empty<string>(), "com.apple.Safari", Clipboard.DefaultExcludedMacApps));
    }

    [Fact]
    public void HistoryAndSnippetsSurviveARelaunch()
    {
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            var store = new Clipboard.Store(dir);
            var h = History("a", "b");
            h.Clips[0] = h.Clips[0] with { Rtf = System.Text.Encoding.UTF8.GetBytes("{\\rtf1 b}"), Kind = Clipboard.Kind.Rich };
            store.Save(h);
            var b = Book();
            store.Save(b);
            var back = store.LoadHistory();
            Assert.Equal(h.Clips.Select(c => (c.Id, c.Text, c.Kind, c.CopiedAt)), back.Clips.Select(c => (c.Id, c.Text, c.Kind, c.CopiedAt)));
            Assert.Equal(h.Clips[0].Rtf, back.Clips[0].Rtf);
            Assert.Equal(b.All.Select(x => (x.Snippet.Id, x.Snippet.Title)), store.LoadSnippets().All.Select(x => (x.Snippet.Id, x.Snippet.Title)));
            var json = File.ReadAllText(store.SnippetsFile);
            Assert.DoesNotContain("wxyz-4321", json);
            Assert.Contains("\"kind\": \"rich\"", File.ReadAllText(store.HistoryFile));
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void TheMacsFilesReadHere()
    {
        const string mac = """
        {
          "clips" : [
            { "app" : "Safari", "copiedAt" : "2026-10-18T09:00:00Z", "id" : "0B7A3C55-1D2E-4F60-8A9B-1C2D3E4F5A6B", "kind" : "rich",
              "pinned" : true, "rtf" : "e1xydGYxIGJ9", "text" : "b" }
          ]
        }
        """;
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(dir);
            var store = new Clipboard.Store(dir);
            File.WriteAllText(store.HistoryFile, mac);
            var clip = Assert.Single(store.LoadHistory().Clips);
            Assert.Equal(("b", Clipboard.Kind.Rich, true, "Safari"), (clip.Text, clip.Kind, clip.Pinned, clip.App));
            Assert.Equal("{\\rtf1 b}", System.Text.Encoding.UTF8.GetString(clip.Rtf!));
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void AMissingOrBrokenFileIsAnEmptyHistory()
    {
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            var store = new Clipboard.Store(dir);
            Assert.Empty(store.LoadHistory().Clips);
            Directory.CreateDirectory(dir);
            File.WriteAllText(store.HistoryFile, "nope");
            Assert.Empty(store.LoadHistory().Clips);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    private const string ClipyXml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <folders>
      <folder>
        <title>Mail</title>
        <snippets>
          <snippet><title>Thanks</title><content>Thank you &amp; best,
    Evgeny</content></snippet>
          <snippet><title>Code</title><content><![CDATA[<b>bold</b>]]></content></snippet>
        </snippets>
      </folder>
      <folder><title>Empty</title><snippets/></folder>
    </folders>
    """;

    [Fact]
    public void ClipyXmlComesIn()
    {
        var book = Clipboard.ImportClipy(ClipyXml);
        Assert.Equal(new[] { "Mail", "Empty" }, book.Folders.Select(f => f.Title));
        Assert.Equal(new[] { "Thanks", "Code" }, book.Folders[0].Snippets.Select(s => s.Title));
        Assert.Equal("Thank you & best,\nEvgeny", book.Folders[0].Snippets[0].Text);
        Assert.Equal("<b>bold</b>", book.Folders[0].Snippets[1].Text);
    }

    [Fact]
    public void SomethingElseIsNotClipyXml()
    {
        Assert.Throws<Clipboard.NotClipyXmlException>(() => Clipboard.ImportClipy("<plist/>"));
        Assert.Throws<Clipboard.NotClipyXmlException>(() => Clipboard.ImportClipy("not xml"));
    }

    [Fact]
    public void AnExportReadsBackAndKeepsNoSecret()
    {
        var b = Book();
        b.Folders[0].Snippets[0] = b.Folders[0].Snippets[0] with { Text = "a < b & \"c\"" };
        var xml = Clipboard.ExportClipy(b);
        Assert.DoesNotContain("wxyz-4321", xml);
        var back = Clipboard.ImportClipy(xml);
        Assert.Equal(b.Folders.Select(f => f.Title), back.Folders.Select(f => f.Title));
        Assert.Equal(b.All.Select(x => x.Snippet.Title), back.All.Select(x => x.Snippet.Title));
        Assert.Equal("a < b & \"c\"", back.Folders[0].Snippets[0].Text);
        Assert.Equal("", back.Folders[0].Snippets[1].Text);
    }

    // MARK: Pictures

    private static Clipboard.Picture Picture(string digest, int w = 1280, int h = 720) =>
        new() { Width = w, Height = h, Bytes = 10, Digest = digest, Types = new() { "PNG" } };

    [Fact]
    public void APictureIsLabelledBySizeAndTheSamePictureMovesUp()
    {
        var h = History("a");
        h.Add(Clip.FromPicture(Picture("one"), T0.AddSeconds(1), "Snipping Tool"));
        h.Add(Clip.FromPicture(Picture("two"), T0.AddSeconds(2)));
        Assert.Equal(3, h.Clips.Count);   // two different pictures of the same size are two clips
        Assert.True(h.Clips[1].Text == "Image 1280×720" && h.Clips[1].Kind == Clipboard.Kind.Image);
        var first = h.Clips[1].Id;
        h.TogglePin(first);
        h.Add(Clip.FromPicture(Picture("one") with { Types = new() { "PNG", "DeviceIndependentBitmap" } }, T0.AddSeconds(3)));
        Assert.Equal(3, h.Clips.Count);
        Assert.True(h.Clips[0].Id == first && h.Clips[0].Pinned);       // the same bytes: the same clip, its pin kept
        Assert.Equal(new[] { "PNG" }, h.Clips[0].Picture!.Types);         // its files are the ones first kept
    }

    [Fact]
    public void APictureIsFoundByImageAndByItsApp()
    {
        var h = History("a picture of a cat");
        h.Add(Clip.FromPicture(Picture("p", 64, 40), T0.AddSeconds(1), "Snipping Tool"));
        Languages.With(Language.English, () =>
        {
            Assert.Equal(new[] { "Image 64×40" }, Clipboard.Search("image", h, new()).Clips.Select(c => c.Text));
            Assert.Single(Clipboard.Search("snipping 64", h, new()).Clips);
            Assert.Equal("Image 64×40", h.Clips[0].Preview());
        });
        Languages.With(Language.Russian, () =>
        {
            Assert.Equal("Картинка 64×40", h.Clips[0].Preview());
            Assert.Single(Clipboard.Search("картинка", h, new()).Clips);
            Assert.Single(Clipboard.Search("image", h, new()).Clips);    // the English word still finds it
        });
    }

    [Fact]
    public void PicturesCountInTheLimit()
    {
        var h = History("a", "b");
        h.Add(Clip.FromPicture(Picture("p"), T0.AddSeconds(5)));
        h.Prune(2, 0, T0);
        Assert.Equal(new[] { "Image 1280×720", "b" }, h.Clips.Select(c => c.Text));
    }

    [Fact]
    public void TheFormatsKeptFitTheCapBestFirst()
    {
        var found = new Dictionary<string, int> { ["PNG"] = 3_000_000, ["DeviceIndependentBitmap"] = 40_000_000, ["GIF"] = 1_000_000 };
        Assert.Equal(new[] { "PNG", "GIF" }, Clipboard.KeptImageTypes(found, 20_000_000));
        Assert.Equal(new[] { "PNG", "GIF", "DeviceIndependentBitmap" }, Clipboard.KeptImageTypes(found, 50_000_000));
        Assert.Equal(new[] { "GIF" }, Clipboard.KeptImageTypes(found, 1_500_000));
        Assert.Empty(Clipboard.KeptImageTypes(found, 500_000));
    }

    [Fact]
    public void TheDigestTellsBytesApartAndMatchesTheMac()
    {
        Assert.Equal(Clipboard.Digest(new byte[] { 1, 2, 3 }), Clipboard.Digest(new byte[] { 1, 2, 3 }));
        Assert.NotEqual(Clipboard.Digest(new byte[] { 1, 2, 3 }), Clipboard.Digest(new byte[] { 1, 2, 4 }));
        Assert.Equal("cbf29ce484222325-0", Clipboard.Digest(Array.Empty<byte>()));
    }

    [Fact]
    public void ThePixelSizeIsReadFromEachFormatsHeader()
    {
        var png = new byte[24];
        new byte[] { 0x89, (byte)'P', (byte)'N', (byte)'G' }.CopyTo(png, 0);
        png[19] = 48; png[23] = 30;
        Assert.Equal((48, 30), Clipboard.PixelSize("PNG", png));
        var dib = new byte[40];
        BitConverter.GetBytes(40).CopyTo(dib, 0); BitConverter.GetBytes(1280).CopyTo(dib, 4); BitConverter.GetBytes(-720).CopyTo(dib, 8);
        Assert.Equal((1280, 720), Clipboard.PixelSize("DeviceIndependentBitmap", dib));   // a top-down bitmap's height is negative
        var gif = new byte[] { (byte)'G', (byte)'I', (byte)'F', (byte)'8', (byte)'9', (byte)'a', 64, 0, 40, 0 };
        Assert.Equal((64, 40), Clipboard.PixelSize("GIF", gif));
        var jpeg = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8, 0, 30, 0, 48, 3, 0, 0, 0 };
        Assert.Equal((48, 30), Clipboard.PixelSize("JFIF", jpeg));
        Assert.Null(Clipboard.PixelSize("PNG", new byte[3]));
    }

    [Fact]
    public void ABitmapGetsAFileHeaderWithItsPixelsOffset()
    {
        var dib = new byte[40 + 4 * 4];
        BitConverter.GetBytes(40).CopyTo(dib, 0); BitConverter.GetBytes(2).CopyTo(dib, 4); BitConverter.GetBytes(2).CopyTo(dib, 8);
        BitConverter.GetBytes((ushort)32).CopyTo(dib, 14);
        var bmp = Clipboard.DibAsBmp(dib);
        Assert.True(bmp[0] == 'B' && bmp[1] == 'M' && BitConverter.ToInt32(bmp, 2) == bmp.Length && BitConverter.ToInt32(bmp, 10) == 54);
        BitConverter.GetBytes((ushort)8).CopyTo(dib, 14);
        Assert.Equal(14 + 40 + 256 * 4, BitConverter.ToInt32(Clipboard.DibAsBmp(dib), 10));   // an 8-bit bitmap's palette comes first
    }

    [Fact]
    public void PicturesAreFilesBesideTheHistoryAndGoWithTheirClip()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clip-images-" + Guid.NewGuid());
        try
        {
            var store = new Clipboard.Store(dir);
            var h = new Clipboard.History();
            var clip = Clip.FromPicture(new Clipboard.Picture { Width = 2, Height = 2, Bytes = 6, Digest = "d", Types = new() { "PNG", "DeviceIndependentBitmap" } }, T0);
            h.Add(clip);
            store.SaveImage(clip.Id, new[] { ("PNG", new byte[] { 1, 2 }), ("DeviceIndependentBitmap", new byte[] { 3, 4, 5, 6 }) });
            store.Save(h);
            var read = store.LoadImage(store.LoadHistory().Clips[0]);
            Assert.Equal(new[] { "PNG", "DeviceIndependentBitmap" }, read.Select(r => r.Type));
            Assert.Equal(new byte[] { 3, 4, 5, 6 }, read[1].Data);
            Assert.Contains("\"kind\": \"image\"", File.ReadAllText(store.HistoryFile));
            store.SweepImages(h);
            Assert.Equal(2, store.LoadImage(clip).Count);   // a kept clip keeps its files
            h.Remove(clip.Id);
            store.SweepImages(h);
            Assert.Empty(store.LoadImage(clip));
            Assert.Empty(Directory.GetFiles(store.ImagesDirectory));
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    // MARK: Masked passwords

    private static Clipboard.SnippetBook BookWithSecret(string words = "pixel-perfect-42")
    {
        var book = new Clipboard.SnippetBook();
        book.Add(Snippet.Make("Wi-Fi", isProtected: true).Sealed(words));
        book.Add(Snippet.Make("Plain", "hello there"));
        return book;
    }

    [Fact]
    public void ACopyOfAProtectedSnippetsWordsIsMaskedByNameAndLength()
    {
        var book = BookWithSecret();
        Assert.Equal("PWD:Wi-Fi: [16] chars", book.MaskFor(new Clip { Text = "pixel-perfect-42", CopiedAt = T0 }));
        Assert.Equal("PWD:Wi-Fi: [16] chars", book.MaskFor(new Clip { Kind = Clipboard.Kind.Rich, Text = "pixel-perfect-42", CopiedAt = T0 }));
        Assert.Null(book.MaskFor(new Clip { Text = "pixel-perfect-43", CopiedAt = T0 }));
        Assert.Null(book.MaskFor(new Clip { Text = "hello there", CopiedAt = T0 }));   // an ordinary snippet's words are not a secret
        var snippet = book.All.First().Snippet;
        Assert.True(snippet.Text == "" && !snippet.SecretHash!.Contains("pixel"));
    }

    [Fact]
    public void TheSameWordsGetADifferentFingerprintEachTime()
    {
        var a = Snippet.Make("A", isProtected: true).Sealed("same");
        var b = Snippet.Make("B", isProtected: true).Sealed("same");
        Assert.True(a.SecretHash != b.SecretHash && a.Holds("same") && b.Holds("same"));
        Assert.False(a.Sealed(null).Holds("same"));
    }

    [Fact]
    public void TheFingerprintIsTheMacs()
    {
        // SHA-256 of the salt's bytes then the words' UTF-8, in lower-case hex.
        var salt = new byte[16];
        var mac = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(salt.Concat("hunter2"u8.ToArray()).ToArray()));
        var snippet = Snippet.Make("X", isProtected: true) with { SecretSalt = Convert.ToBase64String(salt), SecretHash = mac };
        Assert.True(snippet.Holds("hunter2"));
    }

    [Fact]
    public void AMaskedCopyIsFoundByItsMaskNeverByItsWords()
    {
        var h = History("pixel-perfect-42", "pixel art");
        h.Clips[1] = h.Clips[1] with { App = "Notepad" };
        var book = BookWithSecret();
        Assert.Equal(new[] { "pixel art" }, Clipboard.Search("pixel", h, book).Clips.Select(c => c.Text));
        Assert.Equal(new[] { "pixel-perfect-42" }, Clipboard.Search("pwd wi-fi", h, book).Clips.Select(c => c.Text));
        Assert.Equal(new[] { "pixel-perfect-42" }, Clipboard.Search("notepad", h, book).Clips.Select(c => c.Text));
        var picker = new ClipPicker(() => (h, book));
        picker.Refresh(selectFirst: true);
        var masked = picker.Rows.Single(r => r.Masked);
        Assert.Equal("PWD:Wi-Fi: [16] chars", masked.Text);
    }

    [Fact]
    public void UnprotectingASnippetForgetsItsFingerprint()
    {
        var book = BookWithSecret();
        var snippet = book.All.First().Snippet;
        book.Update(snippet with { Protected = false, Text = "pixel-perfect-42" });
        Assert.Null(book.All.First().Snippet.SecretHash);
        Assert.Null(book.MaskFor(new Clip { Text = "pixel-perfect-42", CopiedAt = T0 }));
    }
}
