namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    private static readonly Dictionary<string, string> RuRuntime = new()
    {
        // Why a server did not answer, after "the server is not answering: ".
        ["timed out"] = "время ожидания истекло",
        ["it took too long"] = "слишком долго",
        ["%@, not audio: %@"] = "%@, а не звук: %@",
        // Windows' player.
        ["the clip would not play: %@"] = "запись не проигрывается: %@",
        ["the clip would not open"] = "запись не открывается",
        // Start with Windows (the Run key).
        ["cannot open the Run key"] = "не удаётся открыть раздел автозапуска (Run)",
        ["cannot find the program's own path"] = "не удаётся найти путь к самой программе",
    };
}
