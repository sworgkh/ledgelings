extension Strings {
    /// Plot twists: the news when someone joins, leaves or comes back to the gang,
    /// the first meeting it leaves in a storyline, and the Plot twists page.
    /// Past tense is avoided where a name is its subject: Russian would need its gender.
    static let ruGang: [String: String] = [
        // The page
        "Plot twists": "Повороты сюжета",
        "A newcomer or a departure is news for days": "Новичок или уход — новость на несколько дней",
        "Someone leaving is news too": "Уход — тоже новость",
        "The news stays a topic for": "Новость обсуждают",
        "Conversations that bring it up at first": "Разговоров о ней поначалу",
        "When a character new to the gang turns up (a species switched on, more creatures, an imported sprite, a new one in an update), or one leaves, the others talk about it: welcome, suspicion, gossip, missing someone. The chance fades to nothing as the news gets old. Sleeping or moving to another monitor is not leaving.":
            "Когда в компании появляется новый персонаж (включён вид, существ стало больше, импортирован спрайт, новый вид пришёл с обновлением) или кто-то уходит, остальные это обсуждают: встречают, подозревают, сплетничают, скучают. Чем старее новость, тем реже о ней вспоминают, пока не перестанут совсем. Сон или переход на другой монитор — не уход.",
        "What it does": "Что это даёт",
        "The news rides in the prompts already sent (talk, tea, letters, stories, the diary), so it costs a few tokens and no call of its own. Without a model each character has a line of its own about someone new, someone gone and someone back. A newcomer's first meeting with each of the others is kept in their storyline, and a departure in the closest friends' memory.":
            "Новость едет в уже отправляемых запросах (разговоры, чай, письма, истории, дневник): несколько токенов и ни одного отдельного запроса. Без модели у каждого персонажа своя реплика о новичке, об ушедшем и о вернувшемся. Первая встреча новичка с каждым из остальных попадает в их летопись, а уход — в память ближайших друзей.",
        "News in the gang": "Новости компании",
        "No news: the gang is as it was.": "Новостей нет: компания всё та же.",
        "Forget the News": "Забыть новости",
        "A change counts once it has held for two minutes. Forget the News ends every topic now; the gang is still remembered.":
            "Перемена засчитывается, если держится две минуты. «Забыть новости» сразу закрывает все темы; состав компании помнится.",
        "The gang": "Компания",
        "Nobody yet: the gang is counted half a minute after launch.": "Пока никого: компанию считают через полминуты после запуска.",
        "On screen": "На экране",
        "Gone": "Ушли",
        "Everyone who has ever been on screen, kept by name in bonds.json: a rename is a newcomer.":
            "Все, кто когда-либо был на экране, по именам, в bonds.json: переименованный — новичок.",
        "%@ joined the gang %@": "%@ появляется в компании — %@",
        "%@ left the gang %@": "%@ уходит из компании — %@",
        "%@ came back %@": "%@ возвращается — %@",

        // For the prompt
        "News in the gang: %@": "Новости компании: %@",
        "You are new here: you joined the gang %@, and everyone is still new to you; be shy, curious or show off, as you would.":
            "Ты тут новичок: появление в компании — %@, и все тебе пока незнакомы; стесняйся, любопытствуй или красуйся — как тебе свойственно.",
        "%@, %@, is new to the gang: arrived %@.": "%@ (%@) — новичок в компании; появление — %@.",
        "%@ is new to the gang: arrived %@.": "%@ — новичок в компании; появление — %@.",
        "%1$@ has left the gang (%2$@); nobody has seen %1$@ since, or knows where to.":
            "%1$@ уходит из компании (%2$@), и с тех пор %1$@ не видно; куда — никто не знает.",
        "a while": "давних пор",
        "You are back in the gang %@, after being away since %@; the others remember you.":
            "Ты снова в компании (%@) после отсутствия с %@; остальные тебя помнят.",
        "%@ came back to the gang %@, after being away since %@.": "%@ снова в компании (%@) после отсутствия с %@.",
        "You and %@: %@": "Вы с %@: %@",
        "It may touch their story.": "Это может отразиться на их истории.",
        "If it suits you, bring it up in your own way (a welcome, suspicion, gossip, missing someone, a rumour), in a word or two; never explain it.":
            "Если к месту — упомяни это по-своему (приветствие, подозрение, сплетня, тоска по ушедшему, слух), парой слов; никогда не объясняй.",

        // The storyline and memory
        "first meeting|first meetings": "первая встреча|первые встречи|первых встреч",
        "%1$@, new to the gang, met %2$@ for the first time": "первая встреча новичка %1$@ с %2$@",
        "%2$@ has been sizing up the newcomer %1$@ ever since they met %3$@.": "%2$@ присматривается к новичку %1$@ с первой встречи (%3$@).",
        "%1$@ is new to the gang and hopes %2$@ will show them around, after meeting %3$@.":
            "%1$@ — новичок в компании и надеется, что %2$@ всё тут покажет; знакомство — %3$@.",
        "met %@ for the first time at %@": "первая встреча с %@ в %@",
        "met the newcomer %@ at %@": "знакомство с новичком %@ в %@",
        "%@ left the gang": "%@ уходит из компании",
        "%@ came back to the gang": "%@ возвращается в компанию",
        "%1$@ and %2$@ first met when %1$@ was new to the gang": "%1$@ и %2$@ знакомятся, когда %1$@ — новичок в компании",
    ]
}
