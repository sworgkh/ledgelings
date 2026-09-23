namespace Ledgelings.Core;

public sealed partial class Script
{
    // MARK: Getting a model to write more

    /// <summary>A prompt to paste into any chat model: the format, the rules, the cast.</summary>
    public static string AgentPrompt(IReadOnlyList<Character> cast, int count = 40)
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
            "- Placeholders: {speaker} is the one saying the line, {listener} is the other one, {flower} is the flower being given.\n" +
            "- Use *asterisks* for an action or emphasis, like *sighs*.\n" +
            "- About a quarter of the blocks start with the tag line [flower]: the one who bumped has just given the other a {flower}, and the lines are about it.\n" +
            "- A few blocks start with [night]: it is dark, and they are supposed to be asleep. A block can have both: [night, flower].\n" +
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
}
