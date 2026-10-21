extension Strings {
    /// Deeds from talk and long-term memory: the Relationships tab and window,
    /// what a prompt carries, the facts deeds leave behind.
    /// Past tense is avoided where a name is its subject: Russian would need its gender.
    static let ruRelationships: [String: String] = [
        // The menu
        "Deeds from Talk": "Дела из разговоров",
        "Relationships…": "Отношения…",
        "Relationships": "Отношения",
        "The creatures are not on screen.": "Существ нет на экране.",
        "%@ to read, about %@ tokens to send. Nothing was sent.": "Прочитать: %@, отправить примерно %@ токенов. Ничего не отправлено.",
        "%@ read in. See them in Relationships….": "Прочитано: %@. Смотрите в «Отношениях…».",
        "pair|pairs": "пара|пары|пар",

        // The tab: deeds
        "What they say can turn into what they do": "Сказанное может стать делом",
        "Invite to a game": "Звать играть",
        "Invite to tea": "Звать на чай",
        "Give a flower": "Дарить цветок",
        "Send a letter": "Писать письмо",
        "Walk over to someone": "Ходить в гости",
        "Follow someone": "Ходить следом",
        "Go to sleep": "Ложиться спать",
        "Deeds from talk": "Дела из разговоров",
        "A line or a letter may end in a deed: \"soccer?\" answered \"yes\" starts the match. Each prompt offers only what is possible right now, and anything else is ignored. About 40 more tokens a line.":
            "Реплика или письмо может закончиться делом: на «футбол?» ответили «да» — и матч начинается. Каждый запрос предлагает только то, что возможно сейчас, остальное не выполняется. Примерно на 40 токенов больше на реплику.",
        "After a deed, the next waits": "После дела следующее ждёт",
        "Most deeds an hour": "Дел в час, не больше",
        "Same pair, same deed again after": "Та же пара, то же дело снова через",
        "An invitation stays open": "Приглашение ждёт ответа",
        "A yes waits for both to be free": "Согласие ждёт, пока оба освободятся",
        "Following lasts": "Ходить следом",
        "Built-in answers that say yes": "Встроенные ответы «да»",
        "none": "ничего",
        " tokens": " ток.",

        // The tab: memory
        "Pairs remember each other": "Пары помнят друг друга",
        "Memory sent with each line": "Памяти с каждой репликой",
        "Facts kept per pair": "Фактов на пару",
        "Days of timeline kept": "Дней в летописи по дням",
        "The model may note facts as it speaks": "Модель может записывать факты по ходу",
        "Each knows what it did today": "Каждый знает, что делал сегодня",
        "Things from today it mentions": "Событий дня в запросе",
        "Long-term memory": "Долгая память",
        "A pair's memory at most every": "Память пары не чаще, чем раз в",
        "Pairs a night": "Пар за ночь",
        "The diary": "Дневник",
        "Lines shown per pair": "Реплик на пару",
        "Check First": "Сначала проверить",
        "Read the Past In": "Прочитать прошлое",
        "Open Relationships": "Открыть «Отношения»",
        "Reading…": "Читаю…",
        "Their past": "Их прошлое",
        "Met on %@ · %@ together on screen": "Знакомы с %@ · вместе на экране: %@",
        "Their story so far": "Их история до сих пор",
        "What they remember": "Что они помнят",
        "Their games": "Их игры",
        "Day by day": "День за днём",
        "What they carry into a conversation": "Что они несут в разговор",
        "%@ (%@):": "%@ (%@):",
        "(nothing)": "(ничего)",
        "Their memory has cost %@ so far.": "Их память пока стоила %@.",

        "Built-in letters and talks that invite": "Встроенные письма и разговоры с приглашением",
        "no wait": "сразу",
        "At nightfall the model writes their memory down": "С наступлением ночи модель записывает их память",
        "Read the chat log back": "Читать журнал разговоров за",
        "only just met": "только познакомились",
        "Zero turns a limit off; the same two never do two things within 15 seconds. Without a model each character invites and answers in its own words, close friends saying yes more often.":
            "Ноль отключает ограничение; одни и те же двое не делают двух дел за 15 секунд. Без модели каждый персонаж зовёт и отвечает своими словами, близкие друзья соглашаются чаще.",
        "Every conversation, letter and tea party carries what the two remember, cut to the tokens set here. The timeline is for you; only today and yesterday are sent.":
            "Каждый разговор, письмо и чаепитие несёт то, что двое помнят, в пределах указанных токенов. Летопись по дням — для вас; в запрос идут только сегодня и вчера.",
        "One call a pair (Costs › Long-term memory): their story, the facts that still matter, the day in a line. Without a model days are counted and facts come from deeds and games.":
            "Один запрос на пару (Расходы › Долгая память): их история, важные факты, день одной строкой. Без модели дни считаются, а факты берутся из дел и игр.",
        "Builds each pair's memory from what they said on this Mac, one call a pair (Costs › Memory: reading the past); only their own lines are sent. Check First sends nothing. bonds.json is copied first.":
            "Собирает память каждой пары из того, что они говорили на этом Mac, один запрос на пару (Расходы › Память: чтение прошлого); отправляются только их реплики. «Сначала проверить» ничего не отправляет. bonds.json сначала копируется.",

        // Costs
        "Memory: reading the past": "Память: чтение прошлого",

        // What a prompt carries
        "You and %@ first met on %@; all told: %@.": "Вы с %@ знакомы с %@; всего вместе: %@.",
        "Today together: %@.": "Сегодня вместе: %@.",
        "You remember: %@.": "Ты помнишь: %@.",
        "Games between you: %@.": "Ваши игры: %@.",
        "Yesterday: %@.": "Вчера: %@.",
        "Your story so far: %@": "Ваша история до сих пор: %@",
        "Your day so far: %@.": "Твой день до сих пор: %@.",
        "played %@ with %@ at %@": "%@ с %@ в %@",
        "had tea with %@ at %@": "чай с %@ в %@",
        "gave %@ a %@ at %@": "подарок для %1$@: %2$@, в %3$@",
        "got a %@ from %@ at %@": "подарок от %2$@: %1$@, в %3$@",
        "sent %@ a paper plane at %@": "бумажный самолётик для %@ в %@",
        "got a paper plane from %@ at %@": "бумажный самолётик от %@ в %@",
        "grabbed the cursor at %@": "хватка за курсор в %@",

        // Games
        "%@ asked for it": "по приглашению от %@",
        "a draw": "ничья",
        "a draw, %@": "ничья, %@",
        "draw|draws": "ничья|ничьи|ничьих",
        "won by %@": "победа: %@",
        "won by %@, %@": "победа: %@, %@",
        "touch|touches": "касание|касания|касаний",
        "Basketball": "Баскетбол",
        "Catch-me-if-you-can": "Догонялки",
        "Tea together": "Чай вдвоём",
        "tea together": "чаепитие вдвоём",

        // Facts deeds leave behind
        "%1$@ said no to %2$@'s invitation: %3$@": "%1$@: отказ на приглашение от %2$@ (%3$@)",
        "%1$@'s invitation (%2$@) got no answer from %3$@": "приглашение от %1$@ (%2$@) осталось без ответа от %3$@",
        "%1$@ and %2$@ agreed on %3$@, but never got to it": "%1$@ и %2$@ договорились (%3$@), но так и не собрались",
    ]
}
