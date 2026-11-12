namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>The chat's Windows wording: Ctrl, Shift, Enter and Esc where the Mac draws ⌘, ⇧, ⏎ and ⎋, and the tray
    /// where the Mac has its menu. Each as its Mac twin says it.</summary>
    private static readonly Dictionary<string, string> RuChat = new()
    {
        ["ENTER SEND  SHIFT+ENTER NEW LINE  CTRL+1–9 TO ONE  CTRL+0 EVERYONE  CTRL+, SETTINGS  ESC CLOSE"] =
            "ENTER ОТПРАВИТЬ  SHIFT+ENTER НОВАЯ СТРОКА  CTRL+1–9 ОДНОМУ  CTRL+0 ВСЕМ  CTRL+, НАСТРОЙКИ  ESC ЗАКРЫТЬ",
        ["Write to %@ and press Enter."] = "Напишите: %@ — и нажмите Enter.",
        ["Write to all of them and press Enter: a few will answer, one after another."] = "Напишите всем и нажмите Enter: ответят несколько, по очереди.",
        ["The shortcut opens a paper window from any app, and so do the tray, the Tools screen and Creature Actions. Write to one creature, or to Everyone; Enter sends, Shift+Enter makes a new line, Esc closes."] =
            "Сочетание открывает бумажное окно из любого приложения, как и значок в трее, экран «Инструменты» и «Действия существ». Пишите одному существу или всем; Enter отправляет, Shift+Enter — новая строка, Esc закрывает.",
    };
}
