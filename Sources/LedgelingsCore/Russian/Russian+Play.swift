extension Strings {
    /// The games: the Play tab, the Actions sheet's tiles and switch, the menu item,
    /// what the games are called in a prompt and a storyline, and the colony's status.
    static let ruPlay: [String: String] = [
        // The games, in a prompt and a storyline
        "a game of catch me if you can": "игра в салки",
        "a swing on a ninja rope": "качание на ниндзя-верёвке",
        "a parachute jump from the ceiling": "прыжок с парашютом с потолка",
        "a game of basketball": "игра в баскетбол",
        " with %@": " с %@",
        "game|games": "игра|игры|игр",
        "%1$@ and %2$@ played: %3$@": "%1$@ и %2$@ играли вместе: %3$@",
        "%2$@ wants a rematch of %3$@ with %1$@, after %4$@.": "%2$@ хочет реванша после того, что было %4$@: снова %3$@ с %1$@.",
        "%1$@ has been practising since %3$@ with %2$@ %4$@, and means to win next time.":
            "%1$@ всё тренируется (%4$@ — %3$@ с %2$@), и в следующий раз — только победа.",
        "Plays": "Игры",

        // The colony's status line
        "%@: %@": "%@: %@",
        "nobody is free to play": "играть некому: все заняты",
        "tag needs two free creatures on one screen outline": "для салок нужны двое свободных на одном контуре экранов",
        "no room to play that here": "тут для этой игры нет места",

        // The menu and the Actions sheet
        "Activities…": "Занятия…",
        "ACTIVITIES…": "ЗАНЯТИЯ…",
        "ACTIVITIES · WHAT SHOULD THEY PLAY?": "ЗАНЯТИЯ · ВО ЧТО ИМ ПОИГРАТЬ?",
        "CATCH ME IF YOU CAN": "САЛКИ",
        "NINJA ROPE": "НИНДЗЯ-ВЕРЁВКА",
        "PARACHUTE": "ПАРАШЮТ",
        "BASKETBALL": "БАСКЕТБОЛ",
        "Two friends chase each other round the edges. A touch, and the other one is it.": "Двое друзей гоняются друг за другом по краям. Коснулся — и водит другой.",
        "A hook into the ceiling, a big swing over the floor, a somersault down.": "Крюк в потолок, большой мах над полом, сальто вниз.",
        "Up to the ceiling, then down slowly under a little parachute.": "Наверх, к потолку, и медленно вниз под маленьким парашютом.",
        "A hoop on the wall and a few throws; two friends take turns.": "Кольцо на стене и несколько бросков; двое друзей бросают по очереди.",
        "PLAY NOW": "ИГРАТЬ",
        "BACK": "НАЗАД",
        "PLAY ON": "ИГРЫ ВКЛ",
        "PLAY OFF": "ИГРЫ ВЫКЛ",
        "They play now and then.": "Иногда они играют.",
        "No more games.": "Больше никаких игр.",
        "Off they go: %@.": "Поехали: %@.",
        "No game: %@.": "Игры не будет: %@.",

        // The tab
        "Play": "Игры",
        "They play now and then": "Иногда они играют",
        "Now and then a creature stops walking and plays, the way the worms in Worms fool about between turns, with nobody hurt. One game at a time, never in the middle of a talk, a tea party, a flower, a plane, a grab or sleep; the players are left alone until it is over.":
            "Иногда существо перестаёт бродить и играет — как червяки в Worms дурачатся между ходами, только никто не страдает. Одна игра за раз, и никогда посреди разговора, чаепития, цветка, самолётика, захвата курсора или сна; игроков не трогают, пока игра не кончится.",
        "Playing": "Игра",
        "Which games": "Какие игры",
        "Catch me if you can (two)": "Салки (вдвоём)",
        "Ninja rope swing": "Ниндзя-верёвка",
        "Parachute jump": "Прыжок с парашютом",
        "Basketball (alone, or two taking turns)": "Баскетбол (один или вдвоём по очереди)",
        "Tag is for two: they chase each other round the edges, and a touch makes the other one \"it\". The rope is fired at the ceiling to swing across the floor; the parachute jump starts from the ceiling; the hoop goes on a wall at the end of a floor. Off, a game is never played, and its row on the Activities page is greyed.":
            "Салки — на двоих: они гоняются друг за другом по краям, и касание делает водящим другого. Верёвку цепляют за потолок, чтобы пролететь над полом; прыжок с парашютом начинается с потолка; кольцо вешают на стену в конце пола. Выключенная игра не случается никогда, а её строка на странице «Занятия» серая.",
        "A game about every": "Игра примерно раз в",
        "Friends play more often by": "Друзья играют чаще на",
        "How often": "Как часто",
        "The wait between games is this many minutes, give or take, shortened by how close the closest pair on screen is: at 100 % the best of friends play twice as often. Close pairs (who have shared a few talks, tea parties, flowers) play tag and take turns at the hoop; strangers play alone.":
            "Между играми проходит примерно столько минут, и тем меньше, чем ближе самая дружная пара на экране: при 100 % лучшие друзья играют вдвое чаще. Близкие пары (у которых за плечами несколько разговоров, чаепитий, цветов) играют в салки и бросают в кольцо по очереди; незнакомцы играют поодиночке.",
        "Tag lasts": "Салки длятся",
        "Parachute comes down at": "Парашют спускается со скоростью",
        " pt/s": " тчк/с",
        "Ball keeps on each bounce": "Мяч сохраняет при отскоке",
        "Throws at the hoop each": "Бросков в кольцо у каждого",
        "How the games go": "Как идут игры",
        "After tag both stand puffing for a few seconds. The parachute sways as it comes down; slower is longer to watch. The ball bounces off the floor, the board and the rim; at 0 % it drops dead. About half the throws are aimed true; the rest fall short or bang off the board.":
            "После салок оба несколько секунд стоят, отдуваясь. Парашют покачивается на спуске; чем медленнее, тем дольше смотреть. Мяч отскакивает от пола, щита и дужки; при 0 % падает замертво. Примерно половина бросков точные, остальные не долетают или бьются о щит.",
        "Say something as a game starts and ends": "Говорить что-нибудь в начале и в конце игры",
        "Whoever starts a game says so in its own voice, and someone has the last word when it is over. With a model set up on the Talk tab, the first line is written by the model (counted under Plays on the Costs tab); otherwise, and for the last word, built-in lines. Needs Talk on.":
            "Кто начинает игру, объявляет об этом своим голосом, а когда она кончается, за кем-то последнее слово. Если на вкладке «Разговоры» настроена модель, первую реплику пишет она (учитывается как «Игры» на вкладке «Расходы»); иначе, и для последнего слова, — встроенные реплики. Нужны включённые разговоры.",
        "The props": "Реквизит",
        "Drawn like the creatures, and the same for every species, your own imported ones too.":
            "Нарисован как сами существа и одинаков для всех видов, в том числе ваших импортированных.",
    ]
}
