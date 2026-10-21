import Foundation

/// Deeds in Russian: the prompt's menu and each character's invitations and
/// answers. Tags stay in Latin letters, as `BOND:` does, so they parse the same.
/// Past tense is avoided where a name is its subject: Russian would need its gender.
extension Deeds {

    public static let russianMenu = """
    Если твои слова значат, что ты правда что-то делаешь, закончи ответ ещё одной строкой: DO: и одно из этого (латиницей, как есть): {deeds} | none. \
    Большинству реплик дело не нужно: тогда напиши DO: none или ничего.
    """
    public static let russianAnswer = "{inviter} зовёт тебя: {offer}. Закончи ответ строкой DO: accept или DO: decline, как ответил бы на самом деле."
    public static let russianNote = """
    Если узнаёшь о {listener} что-то, что стоит помнить неделями (обещание, долг, секрет, соперничество, что любит или терпеть не может), \
    можешь добавить строку NOTE: и это, не больше 12 слов.
    """

    public static let russianAnyone = Voice(
        invite: "{reader}! {game}? Ты и я, прямо сейчас.",
        yes: "{game}? Да! Веди, {reader}.",
        no: "Не сейчас, {reader}. Позови потом.")

    public static let russianVoices: [String: Voice] = [
        "Blocky": Voice(invite: "{reader}. {game}. Нижний край. Если не боишься проиграть.",
                        yes: "Ладно. {game}. Но на приличном краю, {reader}.",
                        no: "Нет. Курсор смотрит. В другой раз, {reader}."),
        "Pip": Voice(invite: "{reader}! {game}! Ну пожалуйста-пожалуйста? Будет здорово!",
                     yes: "Да! Да-да-да! {game} с {reader}! Ура-а!",
                     no: "Ой. Не сейчас, {reader}... но скоро? Обещаешь?"),
        "Mortimer": Voice(invite: "Как говорит старый угол: {game} вдвоём — время, потерянное с толком. Составишь компанию, {reader}?",
                          yes: "*вздыхает* Что ж, {reader}. {game}. Только с достоинством.",
                          no: "Не сегодня, {reader}. Окно говорит: отдыхай. А окно мудрое."),
        "Zed": Voice(invite: "мм... {reader}... {game}...? после... одного маленького сна...",
                     yes: "...ладно, {reader}... {game}... разбуди, если я... хрр... Не сплю. Не сплю.",
                     no: "...нет... слишком сонно, {reader}... завтра... может..."),
        "Dot": Voice(invite: "{reader}! {game}! Сейчас! Быстро! Выиграю за четыре секунды!",
                     yes: "{game}? ПОЕХАЛИ! Не отставай, {reader}!",
                     no: "Некогда, {reader}! Я занят: я быстрый! Потом! Быстрее!"),
        "Ruth": Voice(invite: "{reader}, по моим подсчётам мы должны друг другу один раунд. {game}. Начнём?",
                      yes: "Согласна. {game}, по правилам. Счёт веду я, {reader}.",
                      no: "Отказано, {reader}. Это был бы уже третий за час. Правила."),
        "Whiskers": Voice(invite: "Не то чтобы мне было надо, {reader}, но... {game}? Если тебе нечем заняться.",
                          yes: "Ладно. {game}. Только не делай из этого событие, {reader}.",
                          no: "Лень, {reader}. Спроси тёплое местечко."),
        "Mittens": Voice(invite: "Мрр... {reader}, {game}? А потом в тёплый уголок?",
                         yes: "Мррр, да. {game}, а потом поспать на солнышке, {reader}.",
                         no: "Мм, нет, {reader}. Этот пиксель слишком тёплый, чтобы уходить."),
        "Sir Pounce": Voice(invite: "{reader}! Достойный противник наконец. {game}: охота начинается сейчас!",
                            yes: "Принято! {game}. Готовься, {reader}!",
                            no: "Не сейчас, {reader}. Охотник сам выбирает час."),
        "Hopper": Voice(invite: "{reader}! {game}! Прыгну выше, чем ты когда-нибудь. День ног!",
                        yes: "{game}? Смотри на эти лапы, {reader}! Погнали!",
                        no: "Не могу, {reader}. Лапы отдыхают. Чемпионы отдыхают."),
        "Mossy": Voice(invite: "Тихий пруд ждёт, {reader}, но немного кругов по воде не помешает. {game}?",
                       yes: "Да, {reader}. {game}, неспешно, как вода находит дорогу.",
                       no: "Не сейчас, {reader}. Сперва тишина. Так говорит пруд."),
        "Croak": Voice(invite: "Всё равно всё сухое, {reader}. {game}? Хоть что-то.",
                       yes: "Ладно, {game}. Дождя всё равно не будет, {reader}.",
                       no: "Слишком сухо для этого, {reader}. Для всего слишком сухо."),
        "Boo": Voice(invite: "БУ! {game}, {reader}! ...это была страшная часть. Идёшь?",
                     yes: "Бу-да! {game}! Буду пугать тебя всю игру, {reader}!",
                     no: "Бу... не сейчас, {reader}. Репетирую «бу»."),
        "Wisp": Voice(invite: "{reader}... {game}... как на старых экранах, пока они не погасли?",
                      yes: "Да... {game}, {reader}, пока я ещё здесь.",
                      no: "Не сейчас, {reader}... я сегодня немного бледнею."),
        "Sheet": Voice(invite: "Формально, {reader}, это разрешено. Я проверила. {game}?",
                       yes: "Формально да, {reader}. {game}. Я повишу рядом.",
                       no: "Формально я занята, {reader}. Быть плоской — труд."),
        "Goop": Voice(invite: "{reader}! {game}? Будет мило! И немножко липко!",
                      yes: "Ой, {game}! И мило, И липко! Да, {reader}!",
                      no: "Не сейчас, {reader}, я прилип. Мило прилип, правда."),
        "Puddle": Voice(invite: "{reader}, а можно... {game}? Если я к тому времени не испарюсь?",
                        yes: "{game}? Хорошо, {reader}... только не наступи на меня.",
                        no: "Лучше не надо, {reader}... вдруг испарюсь. Прости."),
        "Blorp": Voice(invite: "Блорп! {reader}! {game}! Блорп-блорп?",
                       yes: "БЛОРП! {game}! Блорп, {reader}!",
                       no: "блорп... нет, {reader}. блорп потом."),
        "Unit 7": Voice(invite: "{reader}. Предложение: {game}. Мои шансы на победу: 61%. Принимаешь?",
                        yes: "Принято, {reader}. {game}. Пересчёт шансов: 63%.",
                        no: "Отклонено, {reader}. Заряд 12%. Переношу."),
        "Sprocket": Voice(invite: "{reader}! {game}? Как раз подтянул болты.",
                          yes: "{game}! Масло свежее, поехали, {reader}!",
                          no: "Не сейчас, {reader}, что-то скрипит. Сначала ремонт."),
        "Glitch": Voice(invite: "{reader}, быстро: {game}, пока курсор нас не просканировал!",
                        yes: "Да, {reader}, {game}! Двигайся, по движущейся цели он не попадёт!",
                        no: "Нет, {reader}! Курсор смотрит! Сканирую... потом."),
        "Spike": Voice(invite: "{reader}. {game}. Суть в том, что ты проиграешь.",
                       yes: "{game}? Остро. Принимаю, {reader}.",
                       no: "Без толку, {reader}. Не сейчас."),
        "Wedge": Voice(invite: "{reader}, {game}. И я от этого не сдвинусь.",
                       yes: "{game}. Договорились, {reader}. И я не передумаю.",
                       no: "Нет, {reader}. Я не сдвинусь. Даже ради такого."),
        "Delta": Voice(invite: "Кое-что изменилось, {reader}: хочу играть. {game}. А ты?",
                       yes: "Отмечено, {reader}: {game}. Это всё меняет.",
                       no: "Не сейчас, {reader}. Сегодня и так слишком многое сдвинулось."),
        "Morel": Voice(invite: "Когда будешь готов, {reader}... {game}? Спешить некуда.",
                       yes: "Да, {reader}. {game}. Неспешно, как хорошая почва.",
                       no: "Пока нет, {reader}. Кое-чему нужно больше времени."),
        "Puff": Voice(invite: "{reader}! Угадай, о чём я думаю! {game}! Угадал?",
                      yes: "Да! {game}! Споры во все стороны, {reader}! Хи!",
                      no: "Ой, не сейчас, {reader}! Угадай почему! ...не скажу!"),
        "Cap": Voice(invite: "В моё время, {reader}, мы играли, пока экран не гас. {game}. Ну?",
                     yes: "{game}? Как в старые времена, {reader}. Пошли.",
                     no: "Не сегодня, {reader}. В моё время знали, когда отдыхать."),
    ]
}
