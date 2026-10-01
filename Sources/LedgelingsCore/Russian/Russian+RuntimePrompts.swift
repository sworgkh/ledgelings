extension Strings {
    /// The situation handed to a model with every prompt (and kept in the chat
    /// log beside the conversation): where each creature is, what just happened.
    static let ruRuntimePrompts: [String: String] = [
        "on the right edge": "на правом краю",
        "on the ceiling": "на потолке",
        "on the left edge": "на левом краю",
        "On the edge it is night.": "На краю сейчас ночь.",
        "On the edge it is day.": "На краю сейчас день.",
        "%@ is dangling from the user's cursor": "%@ болтается на курсоре пользователя",
        "%@ is mid-jump": "%@ в прыжке",
        "%@ is asleep %@": "%@ спит %@",
        "%@ is %@": "%@ сидит %@",
        "They just walked into each other.": "Они только что наткнулись друг на друга.",
        "%1$@ just walked into %2$@ and gave %2$@ a %3$@.": "%1$@ натыкается на %2$@ и дарит %2$@ цветок: %3$@.",
        "%@ has been chased or picked up by the user's cursor %d times in a row.":
            "Курсор пользователя гоняет или хватает %@ — уже столько раз подряд: %d."
,
        "you": "хозяин экрана",
        "the person at the computer": "человек за компьютером",
        "The person whose screen you all live on.": "Человек, на чьём экране вы все живёте.",
        "%@ and %@ have put a little table out %@ and are sitting down to tea together.":
            "%@ и %@ поставили столик %@ и садятся вместе пить чай.",
    ]
}
