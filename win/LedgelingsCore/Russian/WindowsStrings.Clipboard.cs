namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>The clipboard manager's Windows wording: Ctrl and Enter where the Mac says ⌘ and ⏎,
    /// Credential Manager for the Keychain, Explorer for Finder, and no fingerprint.</summary>
    private static readonly Dictionary<string, string> RuClipboard = new()
    {
        ["%d more: type to narrow"] = "Ещё %d: набери, чтобы сузить",
        ["Copied. Press Ctrl+V to paste."] = "Скопировано. Нажми Ctrl+V, чтобы вставить.",
        ["ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE"] =
            "ENTER ВСТАВИТЬ  ALT+ENTER %@  CTRL+1–9 ВЫБОР  TAB ГРУППА  CTRL+P ЗАКРЕПИТЬ  DEL ЗАБЫТЬ  CTRL+E ПРАВКА  ESC ЗАКРЫТЬ",
        ["Nothing yet: copy something, or add a snippet (Ctrl+E)."] = "Пока пусто: скопируй что-нибудь или добавь заготовку (Ctrl+E).",
        ["%d snippets"] = "Заготовок: %d",
        ["Programs"] = "Программы",
        ["A protected snippet's words live in Windows Credential Manager, never in a file: shown as dots, kept out of the history and taken off the clipboard a second after pasting."] =
            "Текст защищённой заготовки живёт в диспетчере учётных данных Windows, никогда в файле: показывается точками, не попадает в историю и убирается из буфера через секунду после вставки.",
        ["Enter pastes, Alt+Enter the other way (plain or formatted). A creature brings the sheet and holds its corner; it collapses into the text cursor and the creature leaps back. The paste never waits."] =
            "Enter вставляет, Alt+Enter — наоборот (без оформления или с ним). Существо приносит лист и держит за уголок; лист сворачивается в курсор, существо прыгает обратно. Вставка не ждёт.",
        ["Every copy goes into the history, newest first; copying the same thing again moves it to the top. Pinned copies stay whatever the limits say. Pictures are not kept. Nothing copied ever leaves this PC or reaches a model."] =
            "Каждая копия попадает в историю, новые сверху; повторное копирование поднимает её наверх. Закреплённые копии остаются, что бы ни говорили ограничения. Картинки не сохраняются. Ничто скопированное не покидает этот компьютер и не попадает в модель.",
        ["Keep files copied in Explorer"] = "Сохранять файлы, скопированные в Проводнике",
        ["They work in every app. In the picker: type to search copies and snippets at once, ↑↓ to choose, Ctrl+1–9 for the first nine, Tab between the groups, Ctrl+P to pin, Delete to forget a copy, Esc to close."] =
            "Работают в любой программе. В окне выбора: набирай для поиска сразу по копиям и заготовкам, ↑↓ — выбор, Ctrl+1–9 — первые девять, Tab — между группами, Ctrl+P — закрепить, Delete — забыть копию, Esc — закрыть.",
        ["Paste them from any app with %@: type to search, Enter to paste."] = "Вставляй их из любой программы сочетанием %@: набери для поиска, Enter — вставить.",
        ["Protected: kept in Windows Credential Manager, shown as dots"] = "Защищённая: хранится в диспетчере учётных данных Windows, показывается точками",
    };
}
