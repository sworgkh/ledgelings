using Microsoft.Win32;

namespace Ledgelings;

/// <summary>Start with Windows, through the per-user Run key: the same list Task
/// Manager shows under Startup apps.</summary>
public static class LaunchAtLogin
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "Ledgelings";

    private static string? ExePath => Environment.ProcessPath;

    public static bool IsOn
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(Name) is string value && ExePath is string exe
                && value.Trim('"').Equals(exe, StringComparison.OrdinalIgnoreCase);
        }
    }

    public static string Status => IsOn ? "on" : "off";

    public static void Set(bool on)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey) ?? throw new InvalidOperationException("cannot open the Run key");
        if (on)
        {
            if (ExePath is not string exe) throw new InvalidOperationException("cannot find the program's own path");
            key.SetValue(Name, "\"" + exe + "\"");
        }
        else key.DeleteValue(Name, throwOnMissingValue: false);
    }
}
