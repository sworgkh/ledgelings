using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>The Productivity tools tab, where the Reminders tab went. The Mac's ProductivitySettingsTests.</summary>
public class ProductivitySettingsTests
{
    [Fact]
    public void TheTabIsFoundByItsTwoWordHeader()
    {
        Assert.Equal("Productivity tools", SettingsTabs.Header(SettingsTab.Productivity));
        Assert.Equal("Calendar", SettingsTabs.Header(SettingsTab.Calendar));
    }

    [Fact]
    public void RemindersIsTheFirstTool() => Assert.Equal(ProductivityTool.Reminders, Enum.GetValues<ProductivityTool>()[0]);
}
