namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>The translator's, the Tools screen's and the settings sidebar's Windows wording: Ctrl, Alt, Enter, Tab and
    /// Esc where the Mac draws ⌘, ⌥, ⏎, ⇥ and ⎋, and Move up and Move down where the Mac drags. Each as its Mac twin says it.</summary>
    private static readonly Dictionary<string, string> RuTranslate = new()
    {
        ["In %@ on the clipboard: Ctrl+V pastes it"] = "В буфере на языке «%@»: Ctrl+V вставит",
        ["ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+T TRANSLATE  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE"] =
            "ENTER ВСТАВИТЬ  ALT+ENTER %@  CTRL+1–9 ВЫБОР  TAB ГРУППА  CTRL+T ПЕРЕВОД  CTRL+P ЗАКРЕПИТЬ  DEL ЗАБЫТЬ  CTRL+E ПРАВКА  ESC ЗАКРЫТЬ",
        ["INTO %@ · CTRL+TAB NEXT · ENTER PASTES IT"] = "НА %@ · CTRL+TAB ДАЛЬШЕ · ENTER ВСТАВЛЯЕТ",
        ["Clear the search (Esc)"] = "Очистить поиск (Esc)",
        ["Search every setting (Ctrl+F); Enter opens the first place"] = "Поиск по всем настройкам (Ctrl+F); Enter открывает первое место",
        ["Move down"] = "Ниже",
        ["Move up"] = "Выше",
        ["From OpenRouter"] = "Из OpenRouter",
        ["An OpenRouter model, with the key from Settings › Talk; with LM Studio as the brain and no key, its model, free. Cheap and fast is best: about a cent a day. Every call shows on Costs as Translation, every guess as Autocomplete. Tab takes the grey words. An empty guess model guesses with the translating one."] =
            "Модель OpenRouter с ключом из Настройки › Разговоры; если ключа нет, а мозг — LM Studio, то его модель, бесплатно. Лучше всего дешёвая и быстрая: около цента в день. Каждый вызов виден в «Расходах» как «Перевод», каждая подсказка — как «Автодополнение». Tab принимает серые слова. Без своей модели подсказок подсказывает модель перевода.",
        ["Both work in every app. Type to translate opens the sheet: your words on the left, the translation on the right as you type. The last copy opens in the sheet already translated, or quietly replaces the clipboard with its translation and says so by the text cursor. Enter copies the translation, Ctrl+Enter pastes it into the app you were in."] =
            "Оба работают в любой программе. «Набрать и перевести» открывает лист: ваш текст слева, перевод справа, прямо по мере набора. Последняя копия открывается в листе уже с переводом или тихо заменяется в буфере своим переводом, о чём говорит записка у курсора. Enter копирует перевод, Ctrl+Enter вставляет его в программу, где вы были.",
        ["Every tool on one sheet, a big picture each: click one, press its number, or choose with the arrows and Enter; Esc closes. The Creature Actions sheet opens it too (K). A tool switched off is greyed, and a click opens the page that switches it on."] =
            "Все инструменты на одном листе, у каждого большая картинка: нажмите на неё, на её цифру или выберите стрелками и Enter; Esc закрывает. Лист «Действия существ» тоже его открывает (K). Выключенный инструмент серый, и нажатие открывает страницу, где он включается.",
        ["Move a tool up or down to change the order: the first is 1, the next 2. Switched off here, a tool is not on the screen. Windows has no screenshot tool yet, so no screenshot tiles."] =
            "Двигайте инструмент выше или ниже, чтобы поменять порядок: первый — 1, следующий — 2. Выключенного здесь инструмента на экране нет. Снимков экрана в Windows пока нет, поэтому и их плиток нет.",
        ["Text goes to the model only when you translate it. Protected snippets and copies of their words never do, and get no button. Links, e-mails, code and numbers are kept as they are. Longer texts wait for Enter and say their parts and price first; never more than 50 000 characters."] =
            "Текст уходит в модель, только когда вы его переводите. Защищённые заготовки и копии их слов — никогда, у них нет кнопки. Ссылки, адреса, код и числа остаются как есть. Длинный текст ждёт Enter и сначала показывает число частей и цену; не больше 50 000 символов.",
        ["Told apart by their letters, Latin, Cyrillic or Hebrew, on this computer and for free, before anything is sent. A text already in its target goes into the target's own language instead. At least two stay on."] =
            "Языки различаются по буквам — латиница, кириллица или иврит — прямо на этом компьютере и бесплатно, ещё до отправки. Текст, уже написанный на целевом языке, переводится на язык, указанный для того. Включёнными остаются хотя бы два.",
        ["Uses the OpenRouter key from Settings › Talk, and none is saved there yet. Without one, and without LM Studio as the brain, the sheet says so."] =
            "Берёт ключ OpenRouter из Настройки › Разговоры, а там он пока не сохранён. Без него и без LM Studio в роли мозга лист только скажет об этом.",
        ["1–%d START  ←→↑↓ CHOOSE  ENTER START  ESC CLOSE"] = "1–%d ЗАПУСК  ←→↑↓ ВЫБОР  ENTER ЗАПУСК  ESC ЗАКРЫТЬ",
        ["%@ · about %@ · Enter translates"] = "%@ · около %@ · Enter переводит",
        ["%@ · Enter translates"] = "%@ · Enter переводит",
        ["ENTER COPY  CTRL+ENTER PASTE  SHIFT+ENTER NEW LINE  TAB GUESS  CTRL+S SWAP  CTRL+1–4 FROM  ALT+1–3 INTO  ESC CLOSE"] =
            "ENTER КОПИЯ  CTRL+ENTER ВСТАВИТЬ  SHIFT+ENTER СТРОКА  TAB ПОДСКАЗКА  CTRL+S ПОМЕНЯТЬ  CTRL+1–4 С  ALT+1–3 НА  ESC ЗАКРЫТЬ",
        ["From %@ (%@)"] = "С языка: %@ (%@)",
        ["Into %@ (%@)"] = "На язык: %@ (%@)",
        ["Tell the language by its letters (%@)"] = "Определить язык по буквам (%@)",
        ["No answer in %d s: offline? Enter to try again"] = "Нет ответа за %d с: нет сети? Enter — ещё раз",
        ["The model sent nothing back. Enter to try again"] = "Модель ничего не прислала. Enter — ещё раз",
    };
}
