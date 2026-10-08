namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    private static readonly Dictionary<string, string> RuApp = new()
    {
        ["Ledgelings is already running. Look for the square in the notification area."] = "Ledgelings уже запущен. Ищите квадратик в области уведомлений.",
        ["Ledgelings could not start: %@"] = "Ledgelings не удалось запустить: %@",
        ["Windows would not take %@: another app holds it. Record another."] = "Windows не приняла %@: сочетание занято другой программой. Запишите другое.",
        ["Windows tucks tray icons away when there are many. The shortcut brings the Creature Actions sheet up whichever app is in front, and pressed again puts it away; the sheet has the menu's switches, Settings and Quit. Click the shortcut to record another: a key with Ctrl, Alt or the Windows key held. Esc keeps the old one. Or start Ledgelings again from the Start menu."] = "Windows прячет значки в области уведомлений, когда их много. Сочетание клавиш открывает лист «Действия существ», какая бы программа ни была впереди, а повторное нажатие его убирает; на листе есть переключатели из меню, настройки и выход. Нажмите на сочетание, чтобы записать другое: клавишу вместе с Ctrl, Alt или клавишей Windows. Esc оставит прежнее. Или запустите Ledgelings ещё раз из меню «Пуск».",
    };
}
