namespace Ledgelings.Core;

public static partial class SpriteKit
{
    /// <summary>The attachments, in the order the prompt numbers them, with the file names Save Images… gives them.</summary>
    public static readonly IReadOnlyList<string> AttachmentNames = new[] { "1-poses.png", "2-template.png" };

    // MARK: The image prompt

    /// <summary>What to paste into an image model with the two pictures attached. Built from
    /// the form; asks for a picture, never for text, and shows no letters.
    /// Placeholders: <c>{kind}</c> <c>{colourLine}</c> <c>{nameLine}</c> <c>{poses}</c>. The Mac's words.</summary>
    public const string EnglishImagePrompt = """
        Attached are two pictures. Paint me a new creature for a pixel-art desktop toy.

        Picture 1 (1-poses.png) shows Blocky, a creature already in the toy, in its nine poses, one per cell, left to right: {poses}. Copy its STYLE, its SIZE and the ORDER and meaning of the poses. Do not copy Blocky itself.
        Picture 2 (2-template.png) is the empty sheet: the same nine cells on magenta, each with a pink frame for the body. Paint on it.

        The creature: {kind}
        {colourLine}{nameLine}

        Send back ONE picture, the same size and layout as picture 2:
        - One creature per cell, in the same order as picture 1, each inside its pink frame, standing on the frame's bottom edge, facing RIGHT.
        - Leave everything else plain magenta #FF00FF. No text, no labels, no frames, no grid lines, no shadow on the ground.
        - Real pixel art: the creature is about 22 by 22 big square pixels, like Blocky. Hard square edges, flat colours, no anti-aliasing, no gradients, no blur, no glow.

        The style, as in picture 1:
        - A square body, or squares added to one; anything round becomes stepped corners.
        - A flat body colour, and a 1-pixel outline all round in a dark shade of it.
        - A light line along the top and left just inside the outline, a shade line along the bottom and right.
        - Two black square eyes, each 3 pixels wide, right of the middle, a quarter of the way down. No mouth.
        - Two small feet, 4 by 2 pixels each, in the outline colour.
        - Only the body colour, its light, its shade, the outline and black. Nothing magenta or pink.

        The poses:
        - idle: stands still.
        - walk-0 to walk-3: one walk cycle; walk-1 squashed a little, walk-3 stretched a little, the feet taking turns.
        - jump: stretched tall, feet tucked in.
        - land: squashed very flat and wide.
        - sleep-0 and sleep-1: slumped low, eyes shut as short flat lines, sleep-1 one pixel lower than sleep-0.
        """;

    public const string EnglishRefineSystem = """
        You design creatures for Ledgelings, a desktop toy: tiny pixel creatures that walk along the edges of the screen and talk to each other. Answer with JSON only.
        """;

    /// <summary>Placeholders: <c>{idea}</c> <c>{name}</c> <c>{colour}</c> <c>{cast}</c>.</summary>
    public const string EnglishRefinePrompt = """
        Make a creature from this idea: {idea}
        Already filled in (keep it unless it breaks a rule below): name: {name}; colour: {colour}; characters: {cast}

        Answer with one JSON object and nothing else:
        {"name": "...", "kind": "...", "colour": "#rrggbb", "characters": [{"name": "...", "persona": "..."}, {"name": "...", "persona": "..."}, {"name": "...", "persona": "..."}]}

        - name: the species, one lowercase word of Latin letters and digits.
        - kind: one sentence on how it looks, in the toy's style: a square body in one flat colour, a dark 1-pixel outline, two black square eyes, small square feet, no mouth, no curves (round things become stepped corners). Say its shape, its colour and one or two details made of blocks (ears, a lid, antennae, a tail). For example: "a boxy green frog with two square eye bumps on top and a wide flat body".
        - colour: its body colour as six hex digits. Not magenta or pink, which the toy cuts away.
        - characters: three creatures of this kind, each a short name in Latin letters and a persona of one or two sentences. Say how each one SOUNDS, in plain words a voice can be picked from: old or young, slow or fast, tiny or big, cheerful, grumpy, anxious, sleepy, he or she. Make the three sound different.
        """;

    public static string ImagePromptTemplate(Language l) => Shared.PromptIn(l, "spriteImage", EnglishImagePrompt);
    public static string RefineSystem => Shared.Prompt("spriteRefineSystem", EnglishRefineSystem);
    public static string RefinePromptTemplate(Language l) => Shared.PromptIn(l, "spriteRefine", EnglishRefinePrompt);

    public static string ImagePrompt(Form form) => ImagePrompt(form, Languages.Current);

    public static string ImagePrompt(Form form, Language language)
    {
        var kind = form.TrimmedKind.Length == 0 ? Languages.With(language, () => SpriteText.DescribePlaceholder) : form.TrimmedKind;
        var name = SpeciesName(form.Name);
        string colourLine, nameLine;
        if (language == Language.Russian)
        {
            colourLine = form.Tint is SpriteText.Tint t ? $"Цвет тела: {t.Hex}." : "Цвет тела выбери сам, подходящий к нему (только не пурпурный и не розовый).";
            nameLine = name is null ? "" : $"\nЕго зовут {name}.";
        }
        else
        {
            colourLine = form.Tint is SpriteText.Tint t ? $"Its body colour: {t.Hex}." : "Choose a body colour that suits it (not magenta or pink).";
            nameLine = name is null ? "" : $"\nIts name: {name}.";
        }
        return Fill(ImagePromptTemplate(language), new Dictionary<string, string>
        {
            ["kind"] = kind, ["colourLine"] = colourLine, ["nameLine"] = nameLine, ["poses"] = string.Join(", ", SpriteText.Poses),
        });
    }

    // MARK: Refine with AI

    public static string RefinePrompt(Form form) => RefinePrompt(form, Languages.Current);

    public static string RefinePrompt(Form form, Language language)
    {
        var ru = language == Language.Russian;
        var none = ru ? "нет" : "none";
        var idea = form.TrimmedKind.Length == 0 ? (ru ? "любое маленькое существо на твой вкус" : "any small creature you like") : form.TrimmedKind;
        var cast = string.Join("; ", form.NamedCast.Select(c => c.Persona.Length == 0 ? c.Name : $"{c.Name} ({c.Persona})"));
        return Fill(RefinePromptTemplate(language), new Dictionary<string, string>
        {
            ["idea"] = idea, ["name"] = SpeciesName(form.Name) ?? none, ["colour"] = form.Tint?.Hex ?? none, ["cast"] = cast.Length == 0 ? none : cast,
        });
    }

    /// <summary>The model's answer, laid over <paramref name="form"/>: what the answer has replaces the form's,
    /// what it lacks stays. Null when the answer holds no creature at all.</summary>
    public static Form? ParseRefine(string text, Form form)
    {
        int open = text.IndexOf('{'), close = text.LastIndexOf('}');
        if (open < 0 || close <= open) return null;
        System.Text.Json.Nodes.JsonObject? obj;
        try { obj = System.Text.Json.Nodes.JsonNode.Parse(text[open..(close + 1)]) as System.Text.Json.Nodes.JsonObject; }
        catch (System.Text.Json.JsonException) { return null; }
        if (obj is null) return null;
        string? Str(string key) =>
            obj[key] is System.Text.Json.Nodes.JsonValue v && v.TryGetValue<string>(out var s) && s.Trim().Length > 0 ? s.Trim() : null;
        var output = form;
        var any = false;
        if (Str("kind") is string kind) { output = output with { Kind = kind }; any = true; }
        if (Str("name") is string typed && SpeciesName(typed) is string name) { output = output with { Name = name }; any = true; }
        if ((Str("colour") ?? Str("color")) is string colour && SpriteText.Tint.FromHex(colour) is SpriteText.Tint tint) { output = output with { Colour = tint.Hex }; any = true; }
        var characters = new List<Character>();
        if (obj["characters"] is System.Text.Json.Nodes.JsonArray list)
            foreach (var item in list)
            {
                if (item is not System.Text.Json.Nodes.JsonObject c) continue;
                var who = c["name"] is System.Text.Json.Nodes.JsonValue nv && nv.TryGetValue<string>(out var ns) ? ns.Trim() : "";
                if (who.Length == 0) continue;
                var persona = c["persona"] is System.Text.Json.Nodes.JsonValue pv && pv.TryGetValue<string>(out var ps) ? ps.Trim() : "";
                characters.Add(new Character(who, persona));
            }
        if (characters.Count > 0) { output = output with { Cast = characters }; any = true; }
        return any ? output : null;
    }

    internal static string Fill(string template, IReadOnlyDictionary<string, string> values) =>
        values.Aggregate(template, (text, kv) => text.Replace("{" + kv.Key + "}", kv.Value));
}
