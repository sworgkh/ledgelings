import Foundation

extension SpriteKit {

    /// The attachments, in the order the prompt numbers them, with the file names Save Images… gives them.
    public static let attachmentNames = ["1-poses.png", "2-template.png"]

    // MARK: The image prompt

    /// What to paste into an image model with the two pictures attached. Built from
    /// the form; asks for a picture, never for text, and shows no letters.
    /// Placeholders: `{kind}` `{colourLine}` `{nameLine}` `{poses}`.
    public static let imagePrompts = Translated(english: """
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
        """, [.russian: russianImagePrompt])

    public static func imagePrompt(_ form: Form, language: Language = .current) -> String {
        let kind = form.trimmedKind.isEmpty ? Language.$override.withValue(language) { SpriteText.describePlaceholder } : form.trimmedKind
        let colourLine: String, nameLine: String
        switch language {
        case .english:
            colourLine = form.tint.map { "Its body colour: \($0.hex)." } ?? "Choose a body colour that suits it (not magenta or pink)."
            nameLine = SpriteKit.speciesName(form.name).map { "\nIts name: \($0)." } ?? ""
        case .russian:
            colourLine = form.tint.map { "Цвет тела: \($0.hex)." } ?? "Цвет тела выбери сам, подходящий к нему (только не пурпурный и не розовый)."
            nameLine = SpriteKit.speciesName(form.name).map { "\nЕго зовут \($0)." } ?? ""
        }
        return fill(imagePrompts(language), ["kind": kind, "colourLine": colourLine, "nameLine": nameLine,
                                              "poses": SpriteText.poses.joined(separator: ", ")])
    }

    // MARK: Refine with AI

    public static let refineSystems = Translated(english: """
        You design creatures for Ledgelings, a desktop toy: tiny pixel creatures that walk along the edges of the screen and talk to each other. Answer with JSON only.
        """, [.russian: russianRefineSystem])

    /// Placeholders: `{idea}` `{name}` `{colour}` `{cast}`.
    public static let refinePrompts = Translated(english: """
        Make a creature from this idea: {idea}
        Already filled in (keep it unless it breaks a rule below): name: {name}; colour: {colour}; characters: {cast}

        Answer with one JSON object and nothing else:
        {"name": "...", "kind": "...", "colour": "#rrggbb", "characters": [{"name": "...", "persona": "..."}, {"name": "...", "persona": "..."}, {"name": "...", "persona": "..."}]}

        - name: the species, one lowercase word of Latin letters and digits.
        - kind: one sentence on how it looks, in the toy's style: a square body in one flat colour, a dark 1-pixel outline, two black square eyes, small square feet, no mouth, no curves (round things become stepped corners). Say its shape, its colour and one or two details made of blocks (ears, a lid, antennae, a tail). For example: "a boxy green frog with two square eye bumps on top and a wide flat body".
        - colour: its body colour as six hex digits. Not magenta or pink, which the toy cuts away.
        - characters: three creatures of this kind, each a short name in Latin letters and a persona of one or two sentences. Say how each one SOUNDS, in plain words a voice can be picked from: old or young, slow or fast, tiny or big, cheerful, grumpy, anxious, sleepy, he or she. Make the three sound different.
        """, [.russian: russianRefinePrompt])

    public static func refinePrompt(_ form: Form, language: Language = .current) -> String {
        let none = language == .russian ? "нет" : "none"
        let idea = form.trimmedKind.isEmpty ? (language == .russian ? "любое маленькое существо на твой вкус" : "any small creature you like") : form.trimmedKind
        let cast = form.namedCast.map { $0.persona.isEmpty ? $0.name : "\($0.name) (\($0.persona))" }.joined(separator: "; ")
        return fill(refinePrompts(language), [
            "idea": idea,
            "name": SpriteKit.speciesName(form.name) ?? none,
            "colour": form.tint?.hex ?? none,
            "cast": cast.isEmpty ? none : cast,
        ])
    }

    /// The model's answer, laid over `form`: what the answer has replaces the form's,
    /// what it lacks stays. Nil when the answer holds no creature at all.
    public static func parseRefine(_ text: String, over form: Form) -> Form? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let object = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any]
        else { return nil }
        func string(_ key: String) -> String? {
            (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        var out = form
        var any = false
        if let kind = string("kind") { out.kind = kind; any = true }
        if let name = string("name").flatMap(SpriteKit.speciesName) { out.name = name; any = true }
        if let colour = string("colour") ?? string("color"), let tint = SpriteText.Tint(hex: colour) { out.colour = tint.hex; any = true }
        let characters = (object["characters"] as? [[String: Any]] ?? []).compactMap { c -> Character? in
            guard let name = (c["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return Character(name: name, persona: (c["persona"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        if !characters.isEmpty { out.cast = Form.three(characters); any = true }
        return any ? out : nil
    }

    static func fill(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
