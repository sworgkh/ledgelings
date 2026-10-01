using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>The Creature Actions tiles, as the Mac's ActionsSheetTests has them.</summary>
public class ActionsSheetTests
{
    [Fact]
    public void EveryTileHasItsOwnLetterAndAPicture()
    {
        Assert.Equal(ActionsTiles.All.Count, ActionsTiles.All.Select(t => t.Key()).Distinct().Count());
        foreach (var tile in ActionsTiles.All) Assert.NotNull(ActionIcons.Picture(tile));
    }

    [Fact]
    public void TilesGreyOutWhenThereIsNothingToDo()
    {
        var s = new ActionsState();
        Assert.Equal(new[] { ActionsTile.Flowers }, ActionsTiles.All.Where(t => !t.IsEnabled(s)));
        Assert.Equal("none planted", ActionsTile.Flowers.Detail(s));
        s = s with { Planted = 3 };
        Assert.True(ActionsTile.Flowers.Title(s) == "CLEAR 3 FLOWERS" && ActionsTile.Flowers.IsEnabled(s));
        s = s with { NightOff = true };
        Assert.True(!ActionsTile.Sleep.IsEnabled(s) && ActionsTile.Sleep.Detail(s) == "night is set to 0");
        s = s with { TeaEnabled = false };
        Assert.True(!ActionsTile.Tea.IsEnabled(s) && ActionsTile.Tea.Detail(s) == "off in settings");
    }

    [Fact]
    public void WhileTheyHideOnlyTheHouseAndTheNotesAndTheClockWork()
    {
        var s = new ActionsState(Hiding: true, HideLeft: 299);
        Assert.Equal(new[] { ActionsTile.Reminder, ActionsTile.Hide, ActionsTile.Sleep }, ActionsTiles.All.Where(t => t.IsEnabled(s)));
        Assert.True(ActionsTile.Hide.Title(s) == "BRING THEM BACK" && ActionsTile.Hide.Detail(s) == "4:59 left");
    }

    [Fact]
    public void TheSleepTileSaysWhichWayTheClockGoes()
    {
        var s = new ActionsState(PhaseLeft: 75);
        Assert.True(ActionsTile.Sleep.Title(s) == "PUT THEM TO SLEEP" && ActionsTile.Sleep.Detail(s) == "dusk in 1:15");
        s = s with { IsNight = true };
        Assert.True(ActionsTile.Sleep.Title(s) == "WAKE THEM UP" && ActionsTile.Sleep.Detail(s) == "dawn in 1:15");
    }
}
