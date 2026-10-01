using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>Paper planes and reminders on the app side: the plane sheet, the letters' voices,
/// the book on disk, the paper's colours, and the clock field of the Reminders tab.</summary>
public class MailTests : IDisposable
{
    private readonly string dir = Path.Combine(Path.GetTempPath(), "ledgelings-reminders-" + Guid.NewGuid());

    public void Dispose()
    {
        try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch (IOException) { }
    }

    [Fact]
    public void ThePaperPlaneAndItsLetterAreInTheirSheet()
    {
        var plane = SpriteAtlas.Named("plane");
        var frames = plane.MakeFrames();
        Assert.NotNull(frames.Frame("fly", 0));
        Assert.NotNull(frames.Frame("letter", 0));
        foreach (var view in Enum.GetValues<PaperPlane.View>())
            Assert.True(frames.Frame(PaperPlane.Animation(view), 0) is not null, $"the plane rolled: {view}");
        // A reminder's plane turns to face you, then unfolds.
        Assert.NotNull(frames.Frame("front", 0));
        Assert.NotNull(frames.Frame("opening", 0));
        Assert.True(plane.CellSize.Width > plane.CellSize.Height, "a plane is long, nose to tail");
    }

    [Fact]
    public void EveryBuiltInCharacterHasItsOwnVoiceForLetters()
    {
        var library = new SpriteLibrary(Path.Combine(dir, "sprites"));
        foreach (var species in SpriteLibrary.BuiltIn)
            foreach (var character in library.Cast(species))
                Assert.True(Letters.Voices.ContainsKey(character.Name), $"{species}: {character.Name} writes like anyone");
    }

    [Fact]
    public void TheBookIsSavedOnEveryChangeAndReadBack()
    {
        var book = new ReminderBook(dir);
        var changed = 0;
        book.Changed += () => changed += 1;
        book.Add("  Stretch  ", DateTimeOffset.Now.AddMinutes(5), Reminders.Repeat.Daily);
        book.Add("   ", DateTimeOffset.Now, Reminders.Repeat.Once);      // nothing to be reminded of: not added
        Assert.Equal(1, changed);
        var again = new ReminderBook(dir);
        var r = Assert.Single(again.Book.Reminders);
        Assert.True(r.Text == "Stretch" && r.Repeats == Reminders.Repeat.Daily);
        again.MarkSent(r.Id, DateTimeOffset.Now.AddMinutes(6));
        Assert.False(new ReminderBook(dir).Book.Reminders[0].IsFinished);      // a repeat moves on, it does not finish
        again.Remove(r.Id);
        Assert.Empty(new ReminderBook(dir).Book.Reminders);
        Assert.Equal(Path.Combine(dir, "reminders.json"), again.File);
    }

    [Fact]
    public void ThePaperIsInkedInTheLettersColours()
    {
        using var paper = ScreenOverlay.PaperImage(40, 24);
        Assert.True(paper.Width == 40 && paper.Height == 24);
        Assert.Equal(ScreenOverlay.PaperColour(Reminders.Ink.Rim).ToArgb(), paper.GetPixel(0, 0).ToArgb());
        Assert.Equal(0, paper.GetPixel(39, 23).A);      // the folded-down corner is cut away
        Assert.Equal(ScreenOverlay.PaperColour(Reminders.Ink.Light).ToArgb(), paper.GetPixel(5, 1).ToArgb());
    }

    [Fact]
    public void TheClockFieldReadsAnyWayOfWritingATime()
    {
        Assert.Equal(new TimeSpan(14, 30, 0), SettingsWindow.ParseClock("14:30"));
        Assert.Equal(new TimeSpan(9, 5, 0), SettingsWindow.ParseClock("9:05"));
        Assert.Equal(new TimeSpan(9, 30, 0), SettingsWindow.ParseClock("930"));
        Assert.Equal(new TimeSpan(9, 0, 0), SettingsWindow.ParseClock("9"));
        Assert.Equal(new TimeSpan(18, 15, 0), SettingsWindow.ParseClock("18.15"));
        Assert.Null(SettingsWindow.ParseClock("25:00"));
        Assert.Null(SettingsWindow.ParseClock("soon"));
    }

    [Fact]
    public void TheNextGuessForWhenIsTheTopOfAnHour()
    {
        var guess = SettingsWindow.NextRoundHour();
        Assert.True(guess > DateTimeOffset.Now && guess <= DateTimeOffset.Now.AddHours(1));
        Assert.True(guess.Minute == 0 && guess.Second == 0);
    }
}
