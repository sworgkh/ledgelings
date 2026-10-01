extension Strings {
    /// Sentences that go to a model, not to a person: the almanac, the bonds, the line memory.
    static let ruLinesPrompts: [String: String] = [
        // Bonds
        "they have not really made their minds up about each other yet": "они ещё толком не решили, как друг к другу относиться",
        "none yet; this is their first": "пока не было; эта — первая",
        "(nothing yet)": "(пока ничего)",
        "You and %@ have shared this screen for %@.": "Сколько вы с %@ уже делите этот экран: %@.",
        "How you get on: %@": "Как вы ладите: %@",
        "What is going on between you (part %d of %d): %@": "Что происходит между вами (часть %d из %d): %@",
        "This is the last part: let your line bring it to an end.": "Это последняя часть: пусть твоя реплика её завершит.",
        "Let it colour your line and move the story on a little; never explain it.":
            "Пусть это окрасит твою реплику и чуть продвинет историю; никогда её не объясняй.",

        // The almanac
        "For the person at this computer it is %@, %@.": "У человека за этим компьютером сейчас %@, %@.",
        "For the person at this computer it is %@.": "У человека за этим компьютером сейчас %@.",
        "Today is day %d of %@, %@.": "Сегодня идёт %2$@ (%3$@), %1$d-й день.",
        "Today is %@, %@.": "Сегодня %@ (%@).",
        "%@, %@, begins this evening.": "Сегодня вечером начинается %@ (%@).",
        "Tomorrow is %@, %@.": "Завтра %@ (%@).",
        "%@, %@, is in %@.": "%@ (%@) — через %@.",
        "a Jewish holiday": "иудейский праздник",
        "a Christian holiday": "христианский праздник",
        "a Muslim holiday": "мусульманский праздник",
        "early morning": "раннее утро",
        "morning": "утро",
        "midday": "полдень",
        "afternoon": "день",
        "evening": "вечер",
        "late evening": "поздний вечер",
        "the middle of the night": "глубокая ночь",

        // Line memory
        "You said these lately. Say something new: do not repeat them, their jokes, or the way they start.":
            "Это ты говоришь в последнее время. Скажи что-то новое: не повторяй эти реплики, их шутки и то, как они начинаются.",
    ]
}
