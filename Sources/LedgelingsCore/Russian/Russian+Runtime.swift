extension Strings {
    /// What the app says while it runs: the status line in the menu, the
    /// situations handed to a prompt and kept in the chat log, errors from the
    /// servers, the voices' names for "nobody chosen".
    static let ruRuntime: [String: String] = [
        // The brain and the voice engines
        "Built-in lines": "Встроенные реплики",
        "Built-in voices": "Встроенные голоса",
        "Local server": "Локальный сервер",
        "Needs a model: the built-in lines have none. Choose LM Studio or OpenRouter as the Brain in Settings › Talk.":
            "Нужна модель: у встроенных реплик её нет. Выберите LM Studio или OpenRouter как «Мозг» в Настройках › Разговоры.",
        "LM Studio server address is not a URL": "Адрес сервера LM Studio — не URL",
        "no OpenRouter API key; add one in Settings › Talk": "нет ключа API OpenRouter; добавьте его в Настройках › Разговоры",
        "no OpenRouter API key; add one in Settings › %@": "нет ключа API OpenRouter; добавьте его в Настройках › %@",

        // What happened, for the chat log
        "%@ wrote back to %@ by paper plane.": "%@ отвечает %@ бумажным самолётиком.",
        "%@ sent %@ a paper plane.": "%@ отправляет %@ бумажный самолётик.",
        "%@ brought you a reminder by paper plane: \"%@\".": "%@ приносит вам напоминание бумажным самолётиком: «%@».",
        "part %d of %d: %@": "часть %d из %d: %@",

        // The status line in the menu
        "not tried yet": "ещё не пробовали",
        "needs at least two creatures": "нужно хотя бы два существа",
        "everyone is mid-conversation": "все заняты разговором",
        "nobody free to listen": "никто не свободен, чтобы слушать",
        "someone else is talking; out loud it is one conversation at a time":
            "говорит кто-то другой; вслух — только один разговор за раз",
        "asking %@ via %@…": "спрашиваю %@ через %@…",
        "the model sent an empty line": "модель прислала пустую реплику",
        "the built-in lines: %@": "встроенные реплики: %@",
        "no built-in line fits right now": "сейчас не подходит ни одна встроенная реплика",
        "%@ and %@ are having tea": "%@ и %@ пьют чай",
        "needs two creatures who are awake and free": "нужны два существа, которые не спят и свободны",
        "%@ is telling %@ a story via %@…": "%@ рассказывает %@ историю через %@…",
        "%@ is telling %@ a story": "%@ рассказывает %@ историю",
        "%@ and %@: %@": "%@ и %@: %@",
        "%@ is complaining via %@…": "%@ жалуется через %@…",
        "%@ complained: %@": "%@ жалуется: %@",
        "a paper plane is already in the air": "бумажный самолётик уже в воздухе",
        "nobody free to throw or catch a plane": "никто не свободен, чтобы бросить или поймать самолётик",
        "%@ is writing a letter via %@…": "%@ пишет письмо через %@…",
        "%@ is writing back via %@…": "%@ пишет ответ через %@…",
        "%@ got an answer from %@": "%@ получает ответ от %@",
        "%@ got a paper plane from %@": "%@ получает бумажный самолётик от %@",
        "%@ is writing a reminder via %@…": "%@ пишет напоминание через %@…",
        "%@ delivered a reminder: %@": "%@ приносит напоминание: %@",

        // The reminder letter
        "The Ledgelings": "Ledgelings",
        "REMINDER · for %@": "НАПОМИНАНИЕ · на %@",
        "REMINDER · %@": "НАПОМИНАНИЕ · %@",
        "click to fold it away": "щёлкните, чтобы сложить",

        // Voices
        "nobody on screen to test with": "на экране нет никого, чтобы проверить",
        "Hi, I'm %@. This is how I sound.": "Привет, я %@. Вот так я звучу.",
        "And I'm %@.": "А я %@.",
        "skipped a line: still saying the ones before it": "реплика пропущена: ещё звучат предыдущие",
        "system voice": "системный голос",
        "system default": "системный по умолчанию",
        "default voice": "голос по умолчанию",
        "the model's own": "на выбор модели",
        "the server's own": "на выбор сервера",
        "the local server's address is not a URL": "адрес локального сервера — не URL",
        "the address is not a URL": "адрес — не URL",
        "%@: %@ on %@": "%@: %@, модель %@"
,
        "%@: %@ on local %@": "%@: %@, локальная модель %@",
        ", kept copy, free": ", сохранённая копия, бесплатно",
        "no voices to choose from": "не из каких голосов выбирать",
        "no audio": "нет звука",

        // Servers and prices
        "the server is not answering: %@": "сервер не отвечает: %@",
        "model %@ is not available": "модель %@ недоступна",
        " (have: %@)": " (есть: %@)",
        "the server refused: %@": "сервер отказал: %@",
        "unexpected reply: %@": "неожиданный ответ: %@",
        "price unknown": "цена неизвестна",
        "free": "бесплатно",
        "$%.2f in · $%.2f out per M": "$%.2f вход · $%.2f выход за млн",
        "$%.2f per M chars": "$%.2f за млн символов",

        // What each feature cost, Settings › Costs
        "Voice casting": "Подбор голосов",
        "Relationship plots": "Сюжеты отношений",
        "Complaints": "Жалобы",
        "Earlier, unlabelled": "Раньше, без пометки",

        // Launch at login

        "waiting for your approval in System Settings › General › Login Items":
            "ждёт вашего разрешения в Системных настройках › Основные › Объекты входа",
        "not available here; use the installed Ledgelings.app": "здесь недоступно; используйте установленный Ledgelings.app",
        "unknown": "неизвестно",

        // Importing a sprite sheet
        "cannot read %@": "не удаётся прочитать %@",
        "%@ is neither a sprite text file (.txt, .md) nor a PNG": "%@ — не текстовый файл спрайтов (.txt, .md) и не PNG",
        "the PNG is %d×%d; a sheet is 288×96, or a whole multiple of that":
            "PNG размером %d×%d; лист — 288×96 или кратный этому размер",
        "\"%@\" cannot be used: lowercase letters, digits and dashes only, and not a built-in name":
            "«%@» не подходит: только строчные буквы, цифры и дефисы, и не встроенное имя",
    ]
}
