namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>The weather's Windows wording: a microphone in use is the only meeting (Windows gives no calendar),
    /// and the hover tags the Mac's page says in its footers.</summary>
    private static readonly Dictionary<string, string> RuWeather = new()
    {
        ["Quiet: no typing and the cursor barely moving for that long, nothing full screen, no game, surf or dive, and no call (an app using the microphone). When you come back it eases off over a few seconds, and the snow left lying melts slowly."] =
            "Тихо — это когда столько времени никто не печатает и курсор почти не двигается, ничего не открыто на весь экран, нет игры, сёрфинга или погружения и нет звонка (приложение пользуется микрофоном). Когда вы вернётесь, погода утихнет за несколько секунд, а лежащий снег медленно растает.",
        ["Snow, rain or wind when the screen is quiet"] = "Снег, дождь или ветер, когда на экране тихо",
        ["Snow mostly in winter, wind in autumn, rain any time"] = "Снег — больше зимой, ветер — осенью, дождь — в любое время",
        ["Half the particles, and the wind pushes nobody"] = "Вдвое меньше частиц, и ветер никого не толкает",
        ["Built-in lines in each character's voice; no model, no cost"] = "Встроенные реплики голосом каждого персонажа; без модели и бесплатно",
        ["No typing and the cursor barely moving for this long"] = "Столько времени никто не печатает и курсор почти не двигается",
        ["About once every 60, 20 or 5 quiet minutes"] = "Примерно раз в 60, 20 или 5 тихих минут",
        ["Then it eases off over a few seconds"] = "Потом за несколько секунд утихает",
        ["A window that moves or closes drops its snow"] = "Окно, которое сдвинули или закрыли, роняет свой снег",
        ["Closer than this, up to three share one umbrella"] = "Если ближе этого, до трёх прячутся под одним зонтом",
        // Weather & Sky: the tray instead of the menu, the top edge instead of the menu bar, a call instead of a meeting.
        ["Snow, rain, wind and storms, the season's leaves, petals and snow, and the fireflies: each with its own switches in the Weather & Sky window, which also opens from the tray's Weather submenu."] =
            "Снег, дождь, ветер и бури, листья, лепестки и снег по сезону, светлячки — у каждого свои переключатели в окне «Погода и небо»; оно открывается и из подменю «Погода» в трее.",
        ["Everything falls from above the top edge, the whole height, a sparse few at a time. Stop activity (Ctrl + Alt + Q), the Stop button and Stop Weather in the tray fade it all out in a second; nothing is switched off."] =
            "Всё падает из-за верхнего края через весь экран, понемногу и редко. «Остановить занятие» (Ctrl + Alt + Q), кнопка «Стоп» и «Остановить погоду» в трее гасят всё за секунду; ничего не выключается.",
        ["On the top edge an umbrella fills and falls"] = "На верхнем краю зонт наполняется и падает",
        ["Quiet: no typing, the cursor barely moving, nothing full screen, no game and no call (an app using the microphone). When you come back it eases off."] =
            "Тихо — это когда никто не печатает, курсор почти не движется, ничего не развёрнуто на весь экран, нет игры и звонка (приложение пользуется микрофоном). Когда вы возвращаетесь, она стихает.",
    };
}
