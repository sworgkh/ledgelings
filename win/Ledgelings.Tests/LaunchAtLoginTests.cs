namespace Ledgelings.Tests;

/// <summary>Reads the Run key only; nothing here changes the user's startup list.</summary>
public class LaunchAtLoginTests
{
    [Fact]
    public void EveryStatusHasWordsTheUserCanActOn()
    {
        Assert.Contains(LaunchAtLogin.Status, new[] { "on", "off" });
        Assert.Equal(LaunchAtLogin.IsOn ? "on" : "off", LaunchAtLogin.Status);
    }

    [Fact]
    public void AskingOutsideAnAppBundleDoesNotCrash()
    {
        // The test host is not Ledgelings.exe; whatever the registry says, it must be a word.
        Assert.NotEmpty(LaunchAtLogin.Status);
        _ = LaunchAtLogin.IsOn;
    }
}
