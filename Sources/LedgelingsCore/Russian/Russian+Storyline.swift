extension Strings {
    /// A pair's storyline: the moments they share, the chronicle folded from them,
    /// the built-in stories, and the Storylines section of the Bonds tab.
    /// Past tense is avoided where a name is its subject: Russian would need its gender.
    static let ruStoryline: [String: String] = [
        // The tab
        "Storylines": "Летопись",
        "Each story grows from their whole history": "Каждая история вырастает из всего, что было",
        "Their story so far is kept to": "Их история до сих пор — не длиннее",
        "Latest moments told one by one": "Последних событий по отдельности",
        "Every talk, tea party, flower, paper plane and cursor grab two characters share is kept. A new story is written from their story so far (a short chronicle, rewritten in the same call) and the latest moments, so it can bring back what happened and never contradicts it. About 300 more tokens per story. With the built-in lines, stories are made from these moments without a model.":
            "Каждая беседа, чаепитие, цветок, бумажный самолётик и хватка за курсор, общие для двоих, сохраняются. Новая история пишется из их истории до сих пор (короткой летописи, переписанной в том же запросе) и последних событий, поэтому может вернуться к тому, что было, и никогда ему не противоречит. Примерно на 300 токенов больше на историю. Со встроенными репликами истории складываются из этих событий без модели.",
        "Once two characters have shared the screen this long, they get a small story and a line on how they get on. With the built-in lines there is no model: the story is made from what they lived through, at no cost; choose a model in Settings › Talk for written ones.":
            "Когда двое персонажей проведут вместе на экране столько времени, у них появляется маленькая история и строчка о том, как они ладят. Со встроенными репликами модели нет: история складывается из того, что они пережили, бесплатно; чтобы её писала модель, выберите модель в Настройках › Разговоры.",
        "Reset Story": "Начать заново",
        "Reset All Stories": "Начать все истории заново",
        "So far: %@": "До сих пор: %@",
        "word|words": "слово|слова|слов",

        // For the prompt
        "(not kept)": "(не ведётся)",
        "nothing yet; they have only just met": "пока ничего; они только познакомились",
        "They first met on %@; all told: %@.": "Знакомы с %@; всего вместе: %@.",
        "tea party|tea parties": "чаепитие|чаепития|чаепитий",
        "paper plane|paper planes": "бумажный самолётик|бумажных самолётика|бумажных самолётиков",
        "cursor grab|cursor grabs": "хватка за курсор|хватки за курсор|хваток за курсор",
        "%1$@ and %2$@ talked; %1$@ said: \"%3$@\"": "беседа %1$@ и %2$@; слова %1$@: «%3$@»",
        "%1$@ and %2$@ had a tea party; %1$@ told a story: \"%3$@\"": "чаепитие %1$@ и %2$@; история от %1$@: «%3$@»",
        "%1$@ gave %2$@ a %3$@": "подарок от %1$@ для %2$@: %3$@",
        "%1$@ sent %2$@ a paper plane: \"%3$@\"": "бумажный самолётик от %1$@ для %2$@: «%3$@»",
        "%1$@ grabbed the cursor while %2$@ looked on": "%1$@ хватает курсор на глазах у %2$@",
        "On %@": "%@",
        "Between %@ and %@": "С %@ по %@",
        "%@ in all, the last: %@": "всего %@, последнее: %@",
        "%@, %@": "%@: %@",
        "Then this story played out: %@": "Потом разыгралась история: %@",

        // Built-in stories
        "Since %1$@ gave %2$@ the %3$@ %4$@, %2$@ has been looking for a gift to give back.":
            "После подарка от %1$@ (%3$@, это было %4$@) %2$@ ищет, чем отдарить: %2$@ не любит быть в долгу.",
        "%2$@ has kept the %3$@ %1$@ gave %4$@, and wants to know what it means.":
            "%2$@ бережёт цветок от %1$@ (%3$@, это было %4$@) и гадает, что это значит.",
        "Ever since the tea party %3$@, %2$@ wants to hear how %1$@'s story ends.":
            "После чаепития (это было %3$@) %2$@ хочет узнать, чем кончится история %1$@.",
        "%1$@ is planning another tea party for %2$@, better than the one %3$@.":
            "%1$@ задумывает для %2$@ новое чаепитие, лучше прежнего (то было %3$@).",
        "%2$@ still has the paper plane %1$@ sent %3$@ (\"%4$@\") and is writing an answer.":
            "У %2$@ всё ещё хранится самолётик от %1$@ (это было %3$@: «%4$@»), и ответ уже пишется.",
        "%1$@ waits for %2$@ to answer the paper plane from %3$@.":
            "%1$@ ждёт ответа от %2$@ на самолётик (это было %3$@).",
        "%2$@ cannot decide whether %1$@ grabbing the cursor %3$@ was brave or silly.":
            "%2$@ никак не решит, смело или глупо хватать курсор, как %1$@ (это было %3$@).",
        "%1$@ wants %2$@ to help grab the cursor next time, after %3$@.":
            "После той хватки за курсор (это было %3$@) %1$@ зовёт %2$@ в помощники в следующий раз.",
        "%2$@ keeps coming back to what %1$@ said %3$@: \"%4$@\"":
            "%2$@ всё возвращается к словам %1$@ (это было %3$@): «%4$@»",
        "%1$@ and %2$@ have not settled what they talked about %3$@.":
            "%1$@ и %2$@ так и не договорили о том, о чём шла речь (это было %3$@).",
        "%@ and %@ take turns guarding their favourite corner of the screen.": "%@ и %@ по очереди сторожат любимый угол экрана.",
        "%@ and %@ share a secret about the bottom edge.": "У %@ и %@ общий секрет про нижний край.",
        "After %@, they know each other well.": "Позади %@ — они хорошо знают друг друга.",
        "After %@, they are getting to know each other.": "Позади %@ — они только узнают друг друга.",
        "today": "сегодня",
        "yesterday": "вчера",
        "%@ ago": "%@ назад",
        "week|weeks": "неделю|недели|недель",
    ]
}
