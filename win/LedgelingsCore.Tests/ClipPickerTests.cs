namespace Ledgelings.Core.Tests;

/// <summary>The picker's rows and keys (SPEC §7.11), as the Mac's thePickersKeysMoveJumpAndNumber.</summary>
public class ClipPickerTests
{
    private static (Clipboard.History, Clipboard.SnippetBook) World()
    {
        var h = new Clipboard.History();
        var now = DateTimeOffset.Now;
        for (int i = 0; i < 3; i++) h.Add(new Clipboard.Clip { Text = $"copy {i}", CopiedAt = now.AddSeconds(i), App = "Notepad" });
        var b = new Clipboard.SnippetBook();
        b.Add(Clipboard.Snippet.Make("Sig", "Best regards"));
        return (h, b);
    }

    [Fact]
    public void TheKeysMoveJumpAndNumber()
    {
        var (h, b) = World();
        var p = new ClipPicker(() => (h, b));
        p.Refresh(selectFirst: true);
        Assert.Equal(new[] { "copy 2", "copy 1", "copy 0", "Best regards" }, p.Rows.Select(r => r.Text));
        Assert.Equal("copy 2", p.SelectedRow!.Text);
        p.Step(1);
        Assert.Equal("copy 1", p.SelectedRow!.Text);
        p.JumpGroup();
        Assert.Equal("Sig", p.SelectedRow!.Title);
        p.JumpGroup();
        Assert.Equal("copy 2", p.SelectedRow!.Text);
        Assert.Equal("Sig", p.Numbered(4)!.Title);
        Assert.Null(p.Numbered(5));
        p.Step(-9);
        Assert.Equal("copy 2", p.SelectedRow!.Text);
        p.Search("regards");
        Assert.Equal(new[] { "Sig" }, p.Rows.Select(r => r.Title));
        Assert.Equal("Sig", p.SelectedRow!.Title);
        p.First = ClipPicker.Group.Snippets;
        p.Search("");
        Assert.Equal("Sig", p.Rows[0].Title);
        Assert.Equal((3, 1), p.Counts);
    }

    [Fact]
    public void ForgettingARowChoosesTheOneThatTookItsPlace()
    {
        var (h, b) = World();
        var p = new ClipPicker(() => (h, b));
        p.Refresh(selectFirst: true);
        p.Step(1);
        h.Remove(p.SelectedRow!.Id);
        p.Refresh(keeping: 1);
        Assert.Equal("copy 0", p.SelectedRow!.Text);
    }

    [Fact]
    public void TheDetailSaysWhereAndWhen()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        Languages.With(Language.English, () =>
        {
            Assert.Equal("Notepad · 5 min", ClipPicker.Detail(new Clipboard.Clip { Text = "x", App = "Notepad", CopiedAt = now.AddMinutes(-5) }, now));
            Assert.Equal("FILES · now", ClipPicker.Detail(new Clipboard.Clip { Kind = Clipboard.Kind.Files, Text = "C:\\a", CopiedAt = now }, now));
            Assert.Equal("3 h", ClipPicker.Ago(now.AddHours(-3), now));
            Assert.Equal("2 d", ClipPicker.Ago(now.AddDays(-2), now));
        });
        Languages.With(Language.Russian, () => Assert.Equal("5 мин", ClipPicker.Ago(now.AddMinutes(-5), now)));
    }
}
