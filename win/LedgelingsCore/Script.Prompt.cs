namespace Ledgelings.Core;

public sealed partial class Script
{
    // MARK: Getting a model to write more

    /// <summary>A prompt to paste into any chat model: the format, the rules, the cast,
    /// asking for lines in the current language. Tags and placeholders stay as they are.</summary>
    public static string AgentPrompt(IReadOnlyList<Character> cast, int count = 40) => Languages.Current switch
    {
        Language.Russian => RussianAgentPrompt(cast, count),
        _ => EnglishAgentPrompt(cast, count),
    };

    public static string EnglishAgentPrompt(IReadOnlyList<Character> cast, int count = 40)
    {
        var who = cast.Count == 0 ? "" : "\nThe creatures who might be talking (a line must work for any of them, so never use a name; write {speaker} and {listener} instead):\n"
            + string.Join("\n", cast.Select(c => $"- {c.Name}: {c.Persona}")) + "\n";
        return
            $"Write {count} short conversations between two small pixel creatures who live on the edges of a computer screen. " +
            "They crawl along the bottom, the sides and the ceiling, flee the mouse cursor, sleep at night, and sometimes walk into each other. " +
            "Each conversation happens when one creature walks into another. Make them funny, teasing, a little odd; never mean-spirited.\n" +
            "\n" +
            "Format, exactly:\n" +
            "- One conversation per block, with a blank line between blocks.\n" +
            "- The lines of a block alternate: the first line is the one who bumped, the second is the one who was bumped into, and so on. Two to four lines per block, mostly two.\n" +
            "- Each line is at most 20 words. No name prefixes, no quotes, no numbering.\n" +
            "- Placeholders: {speaker} is the one saying the line, {listener} is the other one, {flower} is the flower being given, {holiday} is the holiday it is today.\n" +
            "- Use *asterisks* for an action or emphasis, like *sighs*.\n" +
            "- About a quarter of the blocks start with the tag line [flower]: the one who bumped has just given the other a {flower}, and the lines are about it.\n" +
            "- A few blocks start with [night]: it is dark, and they are supposed to be asleep. A block can have both: [night, flower].\n" +
            "- A few blocks start with [holiday]: today is a holiday, named by {holiday} (it could be Christmas, Hanukkah, Eid al-Fitr or any other), so the lines must fit any of them.\n" +
            "- Blocks without a tag line happen at any time.\n" +
            who + "\n" +
            "Example:\n" +
            "\n" +
            "Nice edge you've got there, {listener}.\n" +
            "It was nicer before you turned up.\n" +
            "\n" +
            "[flower]\n" +
            "Here. I found a {flower} under the cursor.\n" +
            "Is it... ticking?\n" +
            "\n" +
            "[night]\n" +
            "*whispers* Are you awake?\n" +
            "No.\n" +
            "\n" +
            "Output only the blocks, nothing before or after.";
    }

    /// <summary><see cref="AgentPrompt"/> in Russian: the same format and rules, asking for Russian lines.
    /// Tags and placeholders stay English, the parser reads them. The Mac's <c>russianAgentPrompt</c>,
    /// which the shared export does not carry: it is built around the cast and the count.</summary>
    public static string RussianAgentPrompt(IReadOnlyList<Character> cast, int count = 40)
    {
        var who = cast.Count == 0 ? "" : "\nСущества, которые могут разговаривать (реплика должна подходить любому из них, поэтому никогда не пиши имён; пиши {speaker} и {listener}):\n"
            + string.Join("\n", cast.Select(c => $"- {c.Name}: {Banter.Spoken(c.Persona)}")) + "\n";
        return
            $"Напиши {count} коротких разговоров (столько блоков) между двумя маленькими пиксельными существами, которые живут на краях экрана компьютера. " +
            "Они ползают по нижнему краю, по бокам и по потолку, убегают от курсора мыши, ночью спят, а иногда врезаются друг в друга. " +
            "Каждый разговор случается, когда одно существо врезается в другое. Пусть будет смешно, с подколками и немного странно, но никогда не зло.\n" +
            "\n" +
            "Пиши по-русски. Существа говорят друг другу «ты». Мы не знаем их пола, поэтому избегай прошедшего времени " +
            "и прилагательных с родом для говорящего и собеседника («я видел», «ты устала»): пиши в настоящем времени.\n" +
            "\n" +
            "Формат, строго:\n" +
            "- Один разговор на блок, между блоками пустая строка.\n" +
            "- Реплики в блоке чередуются: первая — того, кто врезался, вторая — того, в кого врезались, и так далее. От двух до четырёх реплик в блоке, чаще две.\n" +
            "- В каждой реплике не больше 20 слов. Без имён в начале, без кавычек, без нумерации.\n" +
            "- Подстановки (пиши их ровно так, латиницей): {speaker} — тот, кто говорит реплику, {listener} — другой, {flower} — цветок, который дарят, {holiday} — праздник, который сегодня.\n" +
            "- {flower} и {holiday} подставляются в именительном падеже, так что ставь их туда, где он подходит: «Держи: {flower}.», «Сегодня {holiday}!».\n" +
            "- *Звёздочками* выделяй действие или ударение, например *вздыхает*.\n" +
            "- Примерно четверть блоков начинается со строки-тега [flower]: тот, кто врезался, только что подарил другому {flower}, и реплики об этом.\n" +
            "- Несколько блоков начинаются с [night]: темно, и им полагается спать. У блока могут быть оба тега: [night, flower].\n" +
            "- Несколько блоков начинаются с [holiday]: сегодня праздник, его название — {holiday} (это может быть Рождество, Ханука, Ураза-байрам или любой другой), поэтому реплики должны подходить к любому из них.\n" +
            "- Блоки без строки-тега случаются в любое время.\n" +
            "- Теги пиши ровно так, по-английски, в квадратных скобках.\n" +
            who + "\n" +
            "Пример:\n" +
            "\n" +
            "Уютный у тебя край, {listener}.\n" +
            "Был уютный. До тебя.\n" +
            "\n" +
            "[flower]\n" +
            "Держи. Нашлось под курсором: {flower}.\n" +
            "Это... тикает?\n" +
            "\n" +
            "[night]\n" +
            "*шёпотом* Ты не спишь?\n" +
            "Сплю.\n" +
            "\n" +
            "Выведи только блоки, ничего до и после.";
    }
}
