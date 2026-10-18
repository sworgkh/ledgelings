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

        s.ClipboardEnabled = false; s.ClipHistoryEnabled = false; s.ClipKeepFormatting = false; s.ClipKeepFiles = false;
        s.ClipAutoPaste = false; s.ClipPlainText = true; s.ClipHistoryLimit = 500; s.ClipKeepDays = 0; s.ClipAnimationSpeed = 2;
        s.ClipHistoryShortcutEnabled = false; s.ClipSnippetsShortcutEnabled = false; s.ClipSnippetShortcutsEnabled = false;
        s.ClipHistoryShortcut = new Shortcut(0x48, ShortcutModifiers.Control | ShortcutModifiers.Shift);
        s.ClipAnimate = false; s.ClipHelperEnabled = false; s.ClipHelper = "Blocky"; s.ClipHelperTalks = false;
        s.ClipExcludedApps = new[] { "keepass.exe" };
        var again = new AppSettings(store, secrets);
        Assert.True(!again.ClipboardEnabled && !again.ClipHistoryEnabled && !again.ClipKeepFormatting && !again.ClipKeepFiles);
        Assert.True(!again.ClipAutoPaste && again.ClipPlainText && again.ClipHistoryLimit == 500 && again.ClipKeepDays == 0 && again.ClipAnimationSpeed == 2);
        Assert.True(!again.ClipHistoryShortcutEnabled && !again.ClipSnippetsShortcutEnabled && !again.ClipSnippetShortcutsEnabled);
        Assert.Equal(new Shortcut(0x48, ShortcutModifiers.Control | ShortcutModifiers.Shift), again.ClipHistoryShortcut);
        Assert.True(!again.ClipAnimate && !again.ClipHelperEnabled && again.ClipHelper == "Blocky" && !again.ClipHelperTalks);
        Assert.Equal(new[] { "keepass.exe" }, again.ClipExcludedApps);

        store.Set("clipHistoryLimit", 5);
        store.Set("clipKeepDays", 9999);
        store.Set("clipAnimationSpeed", 10.0);
        var clamped = new AppSettings(store, secrets);
        Assert.True(clamped.ClipHistoryLimit == 10 && clamped.ClipKeepDays == 365 && clamped.ClipAnimationSpeed == 3);   // clamped on load
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
}
