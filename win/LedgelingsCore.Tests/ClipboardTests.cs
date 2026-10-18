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
        book.Add(Snippet.Make("Bank PIN", "4321", isProtected: true), work);
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
        Assert.Empty(Clipboard.Search("4321", new(), Book()).Snippets);
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
            Assert.DoesNotContain("4321", json);
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
        Assert.DoesNotContain("4321", xml);
        var back = Clipboard.ImportClipy(xml);
        Assert.Equal(b.Folders.Select(f => f.Title), back.Folders.Select(f => f.Title));
        Assert.Equal(b.All.Select(x => x.Snippet.Title), back.All.Select(x => x.Snippet.Title));
        Assert.Equal("a < b & \"c\"", back.Folders[0].Snippets[0].Text);
        Assert.Equal("", back.Folders[0].Snippets[1].Text);
    }
}
