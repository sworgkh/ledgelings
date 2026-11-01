namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>Read aloud's Windows wording: Ctrl, Shift, Enter and Esc where the Mac draws ⌘, ⇧, ⏎ and ⎋; Windows' own
    /// voices where the Mac has its own; the WAV-only file and the pace from the next part. Each as its Mac twin says it,
    /// and a preset is always «пресет» (a «заготовка» is a snippet).</summary>
    private static readonly Dictionary<string, string> RuReadAloud = new()
    {
        ["Windows' own voices"] = "Голоса самой Windows",
        ["%@ has no %@ voice: Windows' reads it"] = "У %@ нет голоса для языка «%@»: читает голос Windows",
        ["%@ takes no pace: read at its own"] = "%@ не принимает темп: читает в своём",
        ["a part in MP3 (or a WAV of another kind) plays but is left out of the saved file"] = "часть в MP3 (или в WAV другого вида) звучит, но в сохранённый файл не попадает",
        ["No OpenRouter key: Windows' own voice reads it, free. Add one in Settings › Talk."] =
            "Нет ключа OpenRouter: читает голос Windows, бесплатно. Добавьте ключ в Настройки › Разговоры.",
        ["The local server's address is not a URL: Windows' own voice reads it, free"] = "Адрес локального сервера — не URL: читает голос Windows, бесплатно",
        ["Windows has no %@ voice: those parts are skipped"] = "В Windows нет голоса для языка «%@»: эти части пропущены",
        ["Windows' voice said nothing"] = "голос Windows ничего не сказал",
        ["%@ · %@ · about %@ · Enter reads"] = "%@ · %@ · около %@ · Enter читает",
        ["%@ · %@ · Enter reads"] = "%@ · %@ · Enter читает",
        ["%@ from the next part"] = "%@ со следующей части",
        ["ENTER READ · PAUSE  SHIFT+ENTER NEW LINE  CTRL+. STOP  CTRL+- CTRL+= PACE  CTRL+1–9 PRESET  CTRL+R READER  CTRL+S SAVE  CTRL+SHIFT+C COPY  ESC CLOSE"] =
            "ENTER ЧИТАТЬ · ПАУЗА  SHIFT+ENTER СТРОКА  CTRL+. СТОП  CTRL+- CTRL+= ТЕМП  CTRL+1–9 ПРЕСЕТ  CTRL+R ЧТЕЦ  CTRL+S СОХРАНИТЬ  CTRL+SHIFT+C КОПИЯ  ESC ЗАКРЫТЬ",
        ["Nothing read yet: Enter reads it first"] = "Ещё ничего не прочитано: сначала Enter",
        ["Paste or type, choose a preset, and Enter reads it."] = "Вставьте или наберите текст, выберите пресет — Enter прочитает.",
        ["The sound file is on the clipboard: Ctrl+V drops it into a chat or a mail"] = "Звуковой файл в буфере: Ctrl+V бросит его в чат или письмо",
        ["ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+T TRANSLATE  CTRL+R READ  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE"] =
            "ENTER ВСТАВИТЬ  ALT+ENTER %@  CTRL+1–9 ВЫБОР  TAB ГРУППА  CTRL+T ПЕРЕВОД  CTRL+R ВСЛУХ  CTRL+P ЗАКРЕПИТЬ  DEL ЗАБЫТЬ  CTRL+E ПРАВКА  ESC ЗАКРЫТЬ",
        ["ENTER PASTE  ALT+ENTER %@  CTRL+1–9 PICK  TAB GROUP  CTRL+R READ  CTRL+P PIN  DEL FORGET  CTRL+E EDIT  ESC CLOSE"] =
            "ENTER ВСТАВИТЬ  ALT+ENTER %@  CTRL+1–9 ВЫБОР  TAB ГРУППА  CTRL+R ВСЛУХ  CTRL+P ЗАКРЕПИТЬ  DEL ЗАБЫТЬ  CTRL+E ПРАВКА  ESC ЗАКРЫТЬ",
        ["The shortcut works in every app: a creature brings a sheet with the clipboard's text in it and reads it out, the parts playing as they come. Enter reads and pauses, Ctrl+. stops, Ctrl+S saves the sound, Ctrl+Shift+C copies it as a file. With Keep reading on, closing the sheet lets it read on; the tray's Stop Reading ends it."] =
            "Сочетание работает в любой программе: существо приносит лист с текстом из буфера и читает его, части звучат по мере готовности. Enter читает и ставит на паузу, Ctrl+. останавливает, Ctrl+S сохраняет звук, Ctrl+Shift+C копирует его файлом. С «Читать дальше» закрытый лист не прерывает чтение; его останавливает «Остановить чтение» в меню в трее.",
        ["A preset is who reads and how: the voice, a character or a narrator, the pace and the rest after each paragraph. Ctrl+1–9 picks one on the sheet. A character reads in a voice cast from its persona and species, the one it has on the Voice page when that is the same model. Each part's language is told by its letters, and a voice that speaks it is found; if the model has none, Windows' own voice for that language reads that part, free, and a part no voice on this PC speaks is skipped. A new pace on the sheet starts with the next part."] =
            "Пресет — это кто читает и как: голос, персонаж или рассказчик, темп и пауза после каждого абзаца. На листе его выбирают Ctrl+1–9. Персонаж читает голосом, подобранным по его характеру и виду, — тем, что у него на странице «Голос», если модель та же. Язык каждой части определяется по буквам, и находится голос, который на нём говорит; если у модели такого нет, эту часть бесплатно читает голос Windows для этого языка, а часть, для которой на этом компьютере голоса нет, пропускается. Новый темп на листе действует со следующей части.",
        ["Save writes the whole reading as one WAV file in this folder, named by the time and its first words: Windows has no M4A encoder to hand, so M4A is saved as WAV too. A part an MP3-only model sent plays but is not in the file. Copy puts the file on the clipboard, to drop into a chat or a mail. Every call to a speech model shows on Costs as Read aloud, a stopped one too. Longer texts wait for Enter and say their parts and price first; never more than 50 000 characters. Protected snippets are never read."] =
            "Сохранение пишет всё чтение одним файлом WAV в эту папку, с временем и первыми словами в названии: кодировщика M4A в Windows под рукой нет, поэтому и M4A сохраняется как WAV. Часть, которую модель прислала только в MP3, звучит, но в файл не попадает. Копирование кладёт файл в буфер, чтобы бросить его в чат или письмо. Каждый вызов речевой модели виден в «Расходах» как «Чтение вслух», даже остановленный. Длинный текст ждёт Enter и сначала показывает части и цену; не больше 50 000 знаков. Защищённые заготовки не читаются никогда.",
    };
}
