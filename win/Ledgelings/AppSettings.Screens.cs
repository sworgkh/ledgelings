using Ledgelings.Core;

namespace Ledgelings;

/// <summary>Which monitor the creatures live on (SPEC §2.4): the same keys and default as the Mac.</summary>
public sealed partial class AppSettings
{
    private string homeScreen = HomeScreen.All;
    private string homeScreenName = "";

    private void LoadScreens()
    {
        homeScreen = store.Get<string>("homeScreen") ?? HomeScreen.All;
        homeScreenName = store.Get<string>("homeScreenName") ?? "";
    }

    /// <summary>The monitor they live on, by its id (<see cref="Monitor.Id"/>); empty: every monitor.
    /// Kept while that monitor is unplugged (they live on all meanwhile) and applied again when it is back.</summary>
    public string HomeScreenId { get => homeScreen; set => Put(ref homeScreen, value ?? HomeScreen.All, "homeScreen"); }
    /// <summary>That monitor's name when it was chosen, to show while it is away.</summary>
    public string HomeScreenName { get => homeScreenName; set => Put(ref homeScreenName, value ?? "", "homeScreenName"); }

    /// <summary>Live on <paramref name="monitor"/> only, or on every monitor (null).</summary>
    public void LiveOn(HomeScreen.Monitor? monitor)
    {
        HomeScreenName = monitor?.Name ?? "";
        HomeScreenId = monitor?.Id ?? HomeScreen.All;
    }
}
