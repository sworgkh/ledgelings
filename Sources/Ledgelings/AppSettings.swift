import Combine
import Foundation
import LedgelingsCore

/// Everything the user can change, saved to UserDefaults as it changes.
@MainActor
final class AppSettings: ObservableObject {
    static let countRange = 1...24
    /// Screen points per sprite pixel. Half steps stay crisp on a Retina display.
    static let sizeRange = 1.0...5.0
    static let sizeStep = 0.5
    static let defaultColors = ["#ff8a3d", "#3dc7b5", "#ff6fa3", "#ffd23d", "#9b7bff", "#7bd65a"]

    @Published var creatureCount: Int { didSet { save(creatureCount, "creatureCount") } }
    /// Names of the sprite sheets in use; creature i wears species i, wrapping round.
    @Published var species: [String] { didSet { save(species, "species") } }
    /// Creature number i wears colour i, wrapping round when there are more creatures than colours.
    @Published var colors: [String] { didSet { save(colors, "colors") } }
    /// Each creature gets its own size somewhere from `minSize` to `maxSize`.
    /// Setting one past the other drags the other along, so min <= max always holds.
    @Published var minSize: Double {
        didSet { save(minSize, "minSize"); if maxSize < minSize { maxSize = minSize } }
    }
    @Published var maxSize: Double {
        didSet { save(maxSize, "maxSize"); if minSize > maxSize { minSize = maxSize } }
    }
    @Published var dayMinutes: Double { didSet { save(dayMinutes, "dayMinutes") } }
    /// Zero means they never sleep.
    @Published var nightMinutes: Double { didSet { save(nightMinutes, "nightMinutes") } }

    // MARK: Talk

    /// Where the words come from. The built-in lines need nothing set up.
    enum Brain: String, CaseIterable, Codable, Sendable {
        case script, lmStudio, openRouter

        var title: String {
            switch self {
            case .script: "Built-in lines"
            case .lmStudio: ChatClient.Provider.lmStudio.title
            case .openRouter: ChatClient.Provider.openRouter.title
            }
        }
    }

    static let defaultTalkServer = "http://localhost:1234"
    static let defaultTalkModel = "google/gemma-3-1b"
    static let defaultOpenRouterModel = "anthropic/claude-haiku-4.5"
    /// Seconds a speech bubble stays up, for a line of typical length.
    static let bubbleRange = 4.0...60.0
    /// Minutes a gifted flower stays on a head before it wilts away.
    static let flowerRange = 0.5...30.0
    /// Minutes with no bump before someone throws a paper plane.
    static let planeRange = 0.5...30.0

    @Published var talkEnabled: Bool { didSet { save(talkEnabled, "talkEnabled") } }
    /// The one wearing a flower trails the one who gave it while the flower lasts.
    @Published var followGiver: Bool { didSet { save(followGiver, "followGiver") } }
    /// After a quiet spell, one creature throws another a paper plane with a note in it.
    @Published var planesEnabled: Bool { didSet { save(planesEnabled, "planesEnabled") } }
    @Published var planeMinutes: Double { didSet { save(planeMinutes, "planeMinutes") } }
    /// Who answers, for banter and for anything else that wants words.
    @Published var brain: Brain { didSet { save(brain.rawValue, "brainProvider") } }
    /// The conversations said when the brain is the built-in lines, in `Script`'s text form.
    @Published var script: String { didSet { save(script, "script") } }
    /// LM Studio's local server and the model loaded in it.
    @Published var talkServer: String { didSet { save(talkServer, "talkServer") } }
    @Published var talkModel: String { didSet { save(talkModel, "talkModel") } }
    @Published var openRouterModel: String { didSet { save(openRouterModel, "openRouterModel") } }
    /// Lives in the keychain, never in the preferences file. Empty means no key.
    /// Read the first time something asks, which only happens once OpenRouter
    /// is the chosen brain: touching the keychain at launch put up its
    /// permission dialog for everyone, OpenRouter user or not.
    var openRouterKey: String {
        get {
            if keyCache == nil { keyCache = keychain.get(Self.keychainKeyAccount) ?? "" }
            return keyCache ?? ""
        }
        set {
            // The key field writes its text back whenever it loses focus; an
            // unchanged value must not cost a keychain prompt.
            guard newValue != openRouterKey else { return }
            keyCache = newValue
            keychain.set(newValue, for: Self.keychainKeyAccount)
        }
    }
    @Published private var keyCache: String?
    @Published var bubbleSeconds: Double { didSet { save(bubbleSeconds, "bubbleSeconds") } }
    @Published var flowerMinutes: Double { didSet { save(flowerMinutes, "flowerMinutes") } }
    /// The user's own cast per species; a species not listed uses its sheet's cast.
    @Published var casts: [String: [Character]] { didSet { saveJSON(casts, "casts") } }
    @Published var systemPrompt: String { didSet { save(systemPrompt, "systemPrompt") } }
    @Published var linePrompt: String { didSet { save(linePrompt, "linePrompt") } }
    @Published var replyPrompt: String { didSet { save(replyPrompt, "replyPrompt") } }

    private let defaults: UserDefaults
    private let keychain: any SecretStore
    private static let keychainKeyAccount = "openRouterKey"

    init(defaults: UserDefaults = .standard, keychain: any SecretStore = Keychain()) {
        self.defaults = defaults
        self.keychain = keychain
        let count = defaults.object(forKey: "creatureCount") as? Int ?? 3
        creatureCount = min(max(count, Self.countRange.lowerBound), Self.countRange.upperBound)
        species = defaults.stringArray(forKey: "species") ?? ["blocky"]
        let saved = (defaults.stringArray(forKey: "colors") ?? []).filter { RGB(hex: $0) != nil }
        colors = saved.isEmpty ? Self.defaultColors : saved
        func size(_ key: String, _ fallback: Double) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return min(max(value, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        }
        let low = size("minSize", 1.5), high = size("maxSize", 3)
        minSize = min(low, high)
        maxSize = max(low, high)
        dayMinutes = max(0.5, defaults.object(forKey: "dayMinutes") as? Double ?? 3)
        nightMinutes = max(0, defaults.object(forKey: "nightMinutes") as? Double ?? 5)

        talkEnabled = defaults.object(forKey: "talkEnabled") as? Bool ?? true
        followGiver = defaults.object(forKey: "followGiver") as? Bool ?? true
        planesEnabled = defaults.object(forKey: "planesEnabled") as? Bool ?? true
        let quiet = defaults.object(forKey: "planeMinutes") as? Double ?? 2
        planeMinutes = min(max(quiet, Self.planeRange.lowerBound), Self.planeRange.upperBound)
        // Before the built-in lines existed the brain was LM Studio; someone who
        // set it up keeps it. Everyone else starts with lines that need no server.
        let setUpAModel = ["talkServer", "talkModel", "openRouterModel"].contains { defaults.object(forKey: $0) != nil }
        brain = defaults.string(forKey: "brainProvider").flatMap(Brain.init(rawValue:)) ?? (setUpAModel ? .lmStudio : .script)
        script = defaults.string(forKey: "script") ?? Script.builtInText
        talkServer = defaults.string(forKey: "talkServer") ?? Self.defaultTalkServer
        talkModel = defaults.string(forKey: "talkModel") ?? Self.defaultTalkModel
        openRouterModel = defaults.string(forKey: "openRouterModel") ?? Self.defaultOpenRouterModel
        let bubble = defaults.object(forKey: "bubbleSeconds") as? Double ?? Banter.defaultBubbleSeconds
        bubbleSeconds = min(max(bubble, Self.bubbleRange.lowerBound), Self.bubbleRange.upperBound)
        let flower = defaults.object(forKey: "flowerMinutes") as? Double ?? 2
        flowerMinutes = min(max(flower, Self.flowerRange.lowerBound), Self.flowerRange.upperBound)
        var casts = defaults.data(forKey: "casts").flatMap { try? JSONDecoder().decode([String: [Character]].self, from: $0) } ?? [:]
        // Before species existed, one cast served everyone: it was blocky's.
        if casts.isEmpty, let old = defaults.data(forKey: "characters").flatMap({ try? JSONDecoder().decode([Character].self, from: $0) }), !old.isEmpty {
            casts["blocky"] = old
        }
        self.casts = casts
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? Banter.defaultSystemPrompt
        linePrompt = defaults.string(forKey: "linePrompt") ?? Banter.defaultLinePrompt
        replyPrompt = defaults.string(forKey: "replyPrompt") ?? Banter.defaultReplyPrompt
    }

    func species(forCreature index: Int) -> String {
        species.isEmpty ? "blocky" : species[index % species.count]
    }

    /// Forget species that are no longer in the library (removed, or no longer
    /// built in); blocky steps in when nothing is left.
    func keepSpecies(among names: [String]) {
        let kept = species.filter { names.contains($0) }
        let wanted = kept.isEmpty ? ["blocky"] : kept
        if wanted != species { species = wanted }
    }

    /// The cast of a species: the user's edit if there is one, else `fallback` (the sheet's).
    func cast(of species: String, fallback: [Character]) -> [Character] {
        casts[species].map { $0.isEmpty ? fallback : $0 } ?? fallback
    }

    var talkServerURL: URL? {
        URL(string: talkServer.trimmingCharacters(in: .whitespaces)).flatMap { $0.host == nil ? nil : $0 }
    }

    /// The model any feature should ask, or nil with `brainProblem` saying what
    /// is missing. Nil, too, with the built-in lines: there is no model to ask.
    func chatClient() -> ChatClient? {
        switch brain {
        case .script: return nil
        case .lmStudio:
            guard let url = talkServerURL else { return nil }
            return .lmStudio(server: url, model: talkModel.trimmingCharacters(in: .whitespaces))
        case .openRouter:
            let key = openRouterKey.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return .openRouter(key: key, model: openRouterModel.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Why `chatClient()` came back empty, in words for the menu and the settings window.
    var brainProblem: String {
        switch brain {
        case .script: "the built-in lines need no model"
        case .lmStudio: "LM Studio server address is not a URL"
        case .openRouter: "no OpenRouter API key; add one in Settings › Talk"
        }
    }

    func resetScript() { script = Script.builtInText }

    func resetPrompts() {
        systemPrompt = Banter.defaultSystemPrompt
        linePrompt = Banter.defaultLinePrompt
        replyPrompt = Banter.defaultReplyPrompt
    }

    /// The size for a creature whose place in the range is `share` (0 = smallest,
    /// 1 = largest), snapped to the step.
    func size(forShare share: Double) -> Double {
        let raw = minSize + (maxSize - minSize) * min(max(share, 0), 1)
        return (raw / Self.sizeStep).rounded() * Self.sizeStep
    }

    func color(forCreature index: Int) -> RGB {
        RGB(hex: colors[index % max(colors.count, 1)]) ?? RGB(hex: Self.defaultColors[0])!
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
    private func saveJSON(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
