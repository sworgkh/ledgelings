namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>Dictation's Windows wording: Enter and Esc where the Mac says ⏎ and ⎋, and Windows' microphone switch.</summary>
    private static readonly Dictionary<string, string> RuDictation = new()
    {
        ["Press the shortcut and speak; press it again (or Enter) and the words land on the clipboard and in the clipboard history. Esc lets it go and sends nothing. Holding to talk, it listens while the keys are down. The sound is kept in memory only and never saved."] =
            "Нажмите сочетание и говорите; нажмите его ещё раз (или Enter), и слова окажутся в буфере обмена и в его истории. Esc отпускает и ничего не отправляет. При удержании слушает, пока клавиши нажаты. Звук хранится только в памяти и никогда не сохраняется.",
        ["Windows lets desktop apps use the microphone unless it is switched off in Settings › Privacy › Microphone; Allow… opens that page. Switched off, a recording is silence."] =
            "Windows даёт приложениям микрофон, если он не выключен в Параметры › Конфиденциальность › Микрофон; «Разрешить…» открывает эту страницу. Когда он выключен, запись — тишина.",
    };
}
