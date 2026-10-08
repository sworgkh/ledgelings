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

    /// <summary>Everything the tray menu offers besides the actions is on the sheet too.</summary>
    [Fact]
    public void TheMenusSwitchesSayHowTheyStandAndTheLinksAreThere()
    {
        var s = new ActionsState();
        Assert.True(ActionsSwitches.All.Count == 5 && ActionsLinks.All.Count == 3);
        Assert.True(ActionsSwitch.Talk.Title(s) == "TALK ON" && ActionsSwitch.Talk.IsOn(s));
        Assert.True(ActionsSwitch.Voice.Title(s) == "VOICE OFF" && !ActionsSwitch.Voice.IsOn(s));
        Assert.Equal("CURSOR: A MENACE", ActionsSwitch.Cursor.Title(s));
        Assert.Equal("ENGLISH", ActionsSwitch.Language.Title(s));
        s = s with { TalkOn = false, RevengeOn = false, Mood = CursorMood.Good, Language = Language.Russian };
        Assert.True(ActionsSwitch.Talk.Title(s) == "TALK OFF" && ActionsSwitch.Revenge.Title(s) == "REVENGE OFF");
        Assert.Equal("CURSOR: A PLAYMATE", ActionsSwitch.Cursor.Title(s));
        Assert.Equal("РУССКИЙ", ActionsSwitch.Language.Title(s));
        Assert.Equal("They keep quiet.", ActionsSwitch.Talk.Said(s));
        Assert.Equal(new[] { "SETTINGS", "CHATS", "QUIT" }, ActionsLinks.All.Select(l => l.Title()));
    }

    [Fact]
    public void ASwitchOnTheSheetGoesRoundItsChoices()
    {
        Assert.Equal(CursorMood.Neutral, ActionsSwitches.Next(CursorMoods.All, CursorMood.Good));
        Assert.Equal(CursorMoods.All[0], ActionsSwitches.Next(CursorMoods.All, CursorMoods.All[^1]));
        Assert.Equal(Language.Russian, ActionsSwitches.Next(Languages.All, Language.English));
        Assert.Equal(Language.English, ActionsSwitches.Next(Languages.All, Language.Russian));
    }

    /// <summary>With no sheet on screen there is nothing to put away, and asking is harmless.</summary>
    [Fact]
    public void NoSheetIsUpUntilOneIsShown()
    {
        Assert.False(ActionsSheet.IsUp);
        ActionsSheet.PutAway();
        Assert.False(ActionsSheet.IsUp);
    }
}
