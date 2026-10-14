extension Bonds {
    /// The shipped plot prompts from before storylines, word for word: a saved copy of one
    /// was never edited, so it becomes the current prompt rather than staying the user's.
    public static let earlierPlotPrompts: [String] = [englishPlotPromptV1, russianPlotPromptV1]

    public static let englishPlotPromptV1 = """
    Do not write their conversations. Write only the two lines described at the end.

    Two small creatures live on the edges of a computer screen and have shared it for {together}.
    {speaker}, {speakerKind}: {speakerPersona}
    {listener}, {listenerKind}: {listenerPersona}
    How they get on so far: {bond}
    Their last story: {lastPlot}
    What they said lately:
    {recent}

    Think up what happens between them over their next {length} conversations: a small plot (a rivalry, a secret, \
    a favour owed, a shared plan, a misunderstanding, a crush), true to both of them and growing from how they get on.

    Answer with exactly these two lines and nothing else:
    BOND: how they get on now, at most 15 words
    PLOT: the story to play out, at most 30 words
    """

    public static let russianPlotPromptV1 = """
    Не пиши их разговоры. Напиши только две строки, описанные в конце.

    Два маленьких существа живут на краях экрана компьютера. Сколько они уже делят его: {together}.
    {speaker}, {speakerKind}: {speakerPersona}
    {listener}, {listenerKind}: {listenerPersona}
    Как они ладят до сих пор: {bond}
    Их прошлая история: {lastPlot}
    Что они говорили недавно:
    {recent}

    Придумай, что произойдёт между ними в ближайших разговорах (их будет столько: {length}): маленький сюжет (соперничество, секрет, \
    должок, общий план, недоразумение, влюблённость), верный им обоим и вырастающий из того, как они ладят.

    Ответь ровно этими двумя строками и ничем больше. Метки BOND: и PLOT: оставь как есть, латиницей; текст после них — по-русски:
    BOND: как они ладят теперь, не больше 15 слов
    PLOT: история, которую им предстоит разыграть, не больше 30 слов
    """
}
