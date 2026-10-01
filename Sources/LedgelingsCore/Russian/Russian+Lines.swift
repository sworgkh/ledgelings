extension Strings {
    static let ruLines: [String: String] = [
        // The built-in script, as the Talk tab reports it
        "line %d: %@": "строка %d: %@",
        "a conversation needs at least one line after its tags": "после тегов у разговора должна быть хотя бы одна реплика",
        "tags go on the first line of a conversation": "теги пишутся в первой строке разговора",
        "unknown tag \"%@\"; the tags are %@": "неизвестный тег «%@»; теги такие: %@",
        "no conversations": "ни одного разговора",
        "flower": "цветок",
        "the holiday": "праздник",

        // How long a pair has been together
        "a moment": "совсем недолго",
        "hour|hours": "час|часа|часов",

        // Reminders
        "Once": "Один раз",
        "Every day": "Каждый день",
        "Every weekday": "По будням",
        "Every week": "Каждую неделю",
        "%@, next %@": "%@, следующее: %@",
        "Tomorrow": "Завтра",

        // The holidays' faiths
        "Jewish": "Иудейский",
        "Christian": "Христианский",
        "Muslim": "Мусульманский",

        // A creature drawn by a model, and what is wrong with it
        "<describe your creature here>": "<опишите здесь своё существо>",
        "colour must be six hex digits like #f0a0b0, not \"%@\"": "цвет — это шесть шестнадцатеричных цифр, например #f0a0b0, а не «%@»",
        "the first line should be `name: something`": "первая строка должна быть `name: что-нибудь`",
        "pose %@ is missing": "нет позы %@",
        "pose %@ is not one of %@": "поза %@ — не из списка: %@",
        "pose %@ has %d rows, not %d": "в позе %@ строк: %d, а нужно %d",
        "pose %@, row %d has %d letters, not %d": "поза %@, строка %d: символов %d, а нужно %d",
        "pose %@, row %d: `%@` is not one of . o b l s k x": "поза %@, строка %d: `%@` — не из . o b l s k x",
        "pose %@ has ink at row %d, column %d, outside columns %d–%d and rows %d–%d":
            "в позе %@ закрашен пиксель в строке %d, столбце %d — за пределами столбцов %d–%d и строк %d–%d",
        "pose %@ does not stand on the floor: row %d is empty": "поза %@ не стоит на полу: строка %d пустая",
        "pose %@ is empty": "поза %@ пустая",
    ]
}
