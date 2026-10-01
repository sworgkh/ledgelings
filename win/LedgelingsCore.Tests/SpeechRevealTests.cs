namespace Ledgelings.Core.Tests;

public class SpeechRevealTests
{
    private const string Line = "Nice edge you've got there.";

    [Fact]
    public void WhileTheSoundIsOnItsWayTheBubbleCountsDots()
    {
        var waiting = new SpeechReveal.Waiting(10);
        Assert.Equal("...", waiting.Shown(Line, 10).Text);
        Assert.Equal(1.0 / 3, waiting.Shown(Line, 10).Share);
        Assert.Equal(2.0 / 3, waiting.Shown(Line, 10.4).Share);
        Assert.Equal(1, waiting.Shown(Line, 10.7).Share);
        Assert.Equal(1.0 / 3, waiting.Shown(Line, 11.05).Share);      // and round again
    }

    [Fact]
    public void AClipTypesTheLineEvenlyOverItsLength()
    {
        var timed = new SpeechReveal.Timed(5, 2);
        Assert.Equal(0, timed.Shown(Line, 4).Share);
        Assert.Equal(0.5, timed.Shown(Line, 6).Share);
        Assert.Equal((Line, 1.0), timed.Shown(Line, 9));
        Assert.Equal(1, new SpeechReveal.Timed(5, 0).Shown(Line, 5).Share);
    }

    [Fact]
    public void AReportingVoiceShowsWhatItHasSaid()
    {
        Assert.Equal((Line, 0.25), new SpeechReveal.Spoken(0.25).Shown(Line, 0));
        Assert.Equal(1, new SpeechReveal.Spoken(3).Shown(Line, 0).Share);
        Assert.Equal((Line, 1.0), SpeechReveal.All.Shown(Line, 0));
    }

    [Fact]
    public void LettersAppearWholeAndTheLastOnlyAtTheEnd()
    {
        Assert.Equal(0, SpeechReveal.Visible(0, 10));
        Assert.Equal(5, SpeechReveal.Visible(0.55, 10));
        Assert.Equal(9, SpeechReveal.Visible(0.999, 10));
        Assert.Equal(10, SpeechReveal.Visible(1, 10));
    }
}
