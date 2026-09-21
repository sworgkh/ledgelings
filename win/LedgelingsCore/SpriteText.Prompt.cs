namespace Ledgelings.Core;

public static partial class SpriteText
{
    // MARK: The prompt

    /// <summary>What to paste into a chat model, with the built-in creature's idle pose as the worked example.</summary>
    public static string Prompt(IReadOnlyList<string> example) =>
        "I need a tiny pixel-art creature for a desktop toy, written as text so I can paste it back.\n" +
        $"The creature: {DescribePlaceholder}\n" +
        "\n" +
        "Write it as a sprite sheet in this exact text format and nothing else:\n" +
        "\n" +
        "name: <one lowercase word, letters and digits only>\n" +
        "kind: <what it is, in a few words, e.g. \"a fat green frog with big eyes\">\n" +
        "colour: <its body colour as six hex digits, e.g. #6cbf4a; leave this line out to let the app pick>\n" +
        "character: <a name>: <its personality in one or two sentences>\n" +
        "character: <another name>: <another personality>\n" +
        "character: <a third name>: <a third personality>\n" +
        "pose: idle\n" +
        "<32 rows of exactly 32 characters>\n" +
        "pose: walk-0\n" +
        "<32 rows>\n" +
        $"... and so on for every pose, in this order: {string.Join(", ", Poses)}\n" +
        "\n" +
        "Characters, one per pixel:\n" +
        "  .  nothing (transparent)\n" +
        "  o  outline, a dark line around the body\n" +
        "  b  body, the main colour\n" +
        "  l  light, a highlight along the top and left inside the outline\n" +
        "  s  shade, a shadow along the bottom and right inside the outline\n" +
        "  k  eye pixels (black). Make each eye a vertical block of k; the app blinks by lowering a lid over it\n" +
        "  x  other black detail that must not blink (a mouth, a spot)\n" +
        "\n" +
        "Rules the app checks:\n" +
        "  - Every pose is exactly 32 rows of exactly 32 characters. No other characters, no spaces inside rows.\n" +
        $"  - The creature stays inside columns {Box.X + 1} to {Box.X + Box.W} and rows {Box.Y + 1} to {Box.Y + Box.H} (1-based). Rows outside are empty.\n" +
        $"  - Row {Floor} is the floor: every pose has ink on row {Floor}. The creature stands on it, facing RIGHT.\n" +
        "  - Keep the body roughly centred left-to-right in that box; the app rotates it about the centre at screen corners.\n" +
        "  - The poses: idle stands still. walk-0 to walk-3 are one walk cycle (walk-1 squashed a little, walk-3 stretched, feet alternating).\n" +
        "    jump is stretched tall with feet tucked in. land is squashed very flat and wide. sleep-0 and sleep-1 are slumped low,\n" +
        "    eyes still drawn as k (the app closes them), sleep-1 one row lower than sleep-0.\n" +
        "  - Use only . o b l s k x. Do not add colours, comments or explanations. Output the text block and nothing else.\n" +
        "  - The three characters are who the creatures of this kind will be when they talk to each other: give each a\n" +
        "    distinct voice that fits what the creature is.\n" +
        "\n" +
        "Here is the built-in creature's idle pose, as an example of the size and style (a square body, two eyes, small feet):\n" +
        "\n" +
        "pose: idle\n" +
        string.Join("\n", example);
}
