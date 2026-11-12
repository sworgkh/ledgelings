namespace Ledgelings.Core;

public static partial class WindowsStrings
{
    /// <summary>The effects' Windows wording: Windows' Show animations where the Mac has Reduce motion in Accessibility,
    /// keys only counted, and no calendar for Clock ticking. Each as its Mac twin says it.</summary>
    private static readonly Dictionary<string, string> RuEffects = new()
    {
        ["Pixel effects on the creatures, drawn in their own square pixels: styles they wear for a while, and moments in the features they mark. They are only drawn: clicks go through them. Reduce motion follows Windows' Show animations setting unless you choose, and turns the busy ones off (sparks, flames, confetti, the falling particles)."] =
            "Пиксельные эффекты на существах, нарисованные их же квадратными пикселями: стили, которые они носят какое-то время, и моменты, которыми они отмечают события. Эффекты только нарисованы: щелчки проходят сквозь них. «Меньше движения» следует настройке Windows «Показывать анимацию», если не выбрать иначе, и выключает самые суетливые (искры, пламя, конфетти, падающие частицы).",
        ["Frost: now and then from December to February, or on a creature nobody has met for that long. Smitten: two friends meet, or a letter's invitation is accepted. Charged: grabbing the cursor, or a whole hour with at least that many keys pressed (only counted, nothing is recorded). Fired up: grumpy at the cursor, or losing a game. Haunted: now and then from 25 October to 1 November, or Boo spooking a friend."] =
            "Иней: время от времени с декабря по февраль или на существе, которого никто так долго не встречал. Влюблённость: встретились двое друзей или принято приглашение из письма. Заряд: схватил курсор или целый час, когда нажато не меньше стольких клавиш (только счёт, ничего не записывается). Ярость: злится на курсор или проиграл игру. Призрачность: время от времени с 25 октября по 1 ноября или когда Бу пугает друга.",
        ["Clock ticking needs a calendar to read meetings from, and Windows gives the creatures none yet: Play shows it. Money spent drops the coins once a day, when the day's spend on Settings › Costs passes the budget."] =
            "Для «Часы тикают» нужен календарь, из которого видны встречи, а Windows пока такого существам не даёт: «Показать» покажет их. «Деньги потрачены» роняет монетки раз в день, когда траты за день в Настройках › Расходы превышают бюджет.",
    };
}
