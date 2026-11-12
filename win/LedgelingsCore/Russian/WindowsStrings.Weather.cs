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
    };
}
