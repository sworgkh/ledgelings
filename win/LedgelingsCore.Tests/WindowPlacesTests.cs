namespace Ledgelings.Core.Tests;

/// <summary>Every window the app opens can be dragged, and a dragged one reopens where it was let go.</summary>
public class WindowPlacesTests
{
    static readonly Rect Laptop = new(0, 0, 1920, 1040), Monitor = new(1920, 0, 2560, 1400);

    [Fact]
    public void EveryWindowMovesButTheOverlaysOverTheScreen()
    {
        var fix = new[] { WindowPlaces.Window.Overlay, WindowPlaces.Window.ShotScreens, WindowPlaces.Window.ShotToolbar,
                          WindowPlaces.Window.ClipToast, WindowPlaces.Window.ClipGhost };
        foreach (var w in WindowPlaces.All) Assert.Equal(!fix.Contains(w), w.Movable());
        Assert.Equal(new[] { "settings", "relationships", "snippets", "actions", "reminder", "tools", "translate", "readAloud", "clipPicker", "chat", "weather" },
                     WindowPlaces.All.Where(w => w.Movable()).Select(w => w.Key()));
    }

    [Fact]
    public void ASavedPlaceOnAScreenIsWhereItReopens() =>
        Assert.Equal(new Rect(2100, 300, 600, 400), WindowPlaces.Frame(2100, 300, 600, 400, new[] { Laptop, Monitor }));

    [Fact]
    public void APlaceOnAMonitorThatIsGoneIsForgotten()
    {
        Assert.Null(WindowPlaces.Frame(2100, 300, 600, 400, new[] { Laptop }));
        Assert.Null(WindowPlaces.Frame(-900, 300, 600, 400, new[] { Laptop, Monitor }));
    }

    [Fact]
    public void AWindowHangingOffItsScreenIsPulledBackIn() =>
        Assert.Equal(new Rect(1320, 640, 600, 400), WindowPlaces.Frame(1800, 900, 600, 400, new[] { Laptop }));

    [Fact]
    public void APaperStaysInsideItsWindow()
    {
        Assert.Equal(new Rect(0, 640, 560, 400), WindowPlaces.Paper(new Rect(-40, 700, 560, 400), 1920, 1040));
        Assert.Equal(new Rect(100, 61, 560, 400), WindowPlaces.Paper(new Rect(100.4, 60.6, 560, 400), 1920, 1040));
    }
}
