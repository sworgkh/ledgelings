namespace Ledgelings.Core;

public static partial class SpriteText
{
    // MARK: The prompt

    /// <summary>What to paste into a chat model, with the built-in creature's idle pose as the worked example,
    /// in the current language.</summary>
    public static string Prompt(IReadOnlyList<string> example) => Languages.Current switch
    {
        Language.Russian => RussianPrompt(example),
        _ => EnglishPrompt(example),
    };

    public static string EnglishPrompt(IReadOnlyList<string> example) =>
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

    /// <summary><see cref="Prompt"/> in Russian: the Mac's <c>russianPrompt(example:)</c>. The keys
    /// (<c>name:</c>, <c>kind:</c>, <c>colour:</c>, <c>character:</c>, <c>pose:</c>), the pose names and the
    /// letters stay exactly as the parser reads them.</summary>
    public static string RussianPrompt(IReadOnlyList<string> example) =>
        "Мне нужно крошечное пиксельное существо для настольной игрушки, записанное текстом, чтобы его можно было вставить обратно.\n" +
        $"Существо: {DescribePlaceholder}\n" +
        "\n" +
        "Запиши его как лист спрайтов строго в этом текстовом формате и больше ничего не пиши:\n" +
        "\n" +
        "name: <одно слово строчными латинскими буквами, только буквы и цифры>\n" +
        "kind: <что это такое, в нескольких словах, например «толстая зелёная лягушка с большими глазами»>\n" +
        "colour: <цвет тела шестью шестнадцатеричными цифрами, например #6cbf4a; не пиши эту строку, если цвет выберет приложение>\n" +
        "character: <имя>: <характер в одном-двух предложениях>\n" +
        "character: <другое имя>: <другой характер>\n" +
        "character: <третье имя>: <третий характер>\n" +
        "pose: idle\n" +
        "<32 строки ровно по 32 символа>\n" +
        "pose: walk-0\n" +
        "<32 строки>\n" +
        $"... и так для каждой позы, в таком порядке: {string.Join(", ", Poses)}\n" +
        "\n" +
        "Ключи name, kind, colour, character и pose, названия поз и символы ниже пиши ровно так, латиницей.\n" +
        "Описание (kind) и характеры пиши по-русски; имена — латиницей.\n" +
        "\n" +
        "Символы, по одному на пиксель:\n" +
        "  .  ничего (прозрачно)\n" +
        "  o  контур, тёмная линия вокруг тела\n" +
        "  b  тело, основной цвет\n" +
        "  l  свет, блик вдоль верха и левой стороны внутри контура\n" +
        "  s  тень вдоль низа и правой стороны внутри контура\n" +
        "  k  пиксели глаз (чёрные). Каждый глаз — вертикальный блок из k; приложение моргает, опуская на него веко\n" +
        "  x  другие чёрные детали, которые не моргают (рот, пятнышко)\n" +
        "\n" +
        "Правила, которые проверяет приложение:\n" +
        "  - Каждая поза — ровно 32 строки ровно по 32 символа. Никаких других символов, никаких пробелов внутри строк.\n" +
        $"  - Существо не выходит за столбцы с {Box.X + 1} по {Box.X + Box.W} и строки с {Box.Y + 1} по {Box.Y + Box.H} (считая с 1). Строки снаружи пустые.\n" +
        $"  - Строка {Floor} — это пол: в каждой позе на строке {Floor} есть закрашенные пиксели. Существо стоит на ней и смотрит ВПРАВО.\n" +
        "  - Держи тело примерно по центру этой рамки по горизонтали; в углах экрана приложение поворачивает его вокруг центра.\n" +
        "  - Позы: idle — стоит на месте. walk-0 … walk-3 — один цикл ходьбы (walk-1 чуть сплющена, walk-3 вытянута, ноги чередуются).\n" +
        "    jump — вытянуто вверх, ноги поджаты. land — очень сплющено и широко. sleep-0 и sleep-1 — осело вниз,\n" +
        "    глаза всё так же нарисованы k (приложение само их закроет), sleep-1 на одну строку ниже sleep-0.\n" +
        "  - Используй только . o b l s k x. Не добавляй цветов, комментариев и пояснений. Выведи текстовый блок и больше ничего.\n" +
        "  - Три персонажа — это те, кем станут существа этого вида, когда заговорят друг с другом: дай каждому\n" +
        "    свой голос, подходящий к тому, что это за существо.\n" +
        "\n" +
        "Вот поза idle встроенного существа — пример размера и стиля (квадратное тело, два глаза, маленькие ноги):\n" +
        "\n" +
        "pose: idle\n" +
        string.Join("\n", example);
}
