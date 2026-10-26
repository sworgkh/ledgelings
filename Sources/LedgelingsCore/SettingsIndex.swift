import Foundation

/// One page of the settings window. The sidebar lists them by `group`, in the
/// order of `allCases`; `named` is what `--settings <name>` opens.
public enum SettingsPage: String, CaseIterable, Hashable, Sendable {
    case creatures, actions, sprites, beds, flowers, calendar
    case chases, play, ballGames
    case talk, voice, bonds, relationships
    case reminders, clipboard, screenshots, dictation, translate
    case costs, chats

    public var title: String {
        switch self {
        case .creatures: tr("Creatures")
        case .actions: tr("Actions")
        case .sprites: tr("Sprites")
        case .beds: tr("Beds")
        case .flowers: tr("Flowers")
        case .calendar: tr("Calendar")
        case .chases: tr("Chases")
        case .play: tr("Play")
        case .ballGames: tr("Ball games")
        case .talk: tr("Talk")
        case .voice: tr("Voice")
        case .bonds: tr("Bonds")
        case .relationships: tr("Relationships")
        case .reminders: tr("Reminders")
        case .clipboard: tr("Clipboard")
        case .screenshots: tr("Screenshots")
        case .dictation: tr("Dictation")
        case .translate: tr("Translate")
        case .costs: tr("Costs")
        case .chats: tr("Chats")
        }
    }

    public var group: SettingsGroup {
        switch self {
        case .creatures, .actions, .sprites, .beds, .flowers, .calendar: .creaturesAndWorld
        case .chases, .play, .ballGames: .games
        case .talk, .voice, .bonds, .relationships: .talkAndFriends
        case .reminders, .clipboard, .screenshots, .dictation, .translate: .tools
        case .costs, .chats: .moneyAndHistory
        }
    }

    /// The page a script names after `--settings`: its own name in lower case
    /// (`ballgames`), or an old tab's. `productivity` and `reminders`, the old
    /// names of the tools tab, open its first tool.
    public static func named(_ name: String) -> SettingsPage? {
        let lower = name.lowercased()
        if lower == "productivity" { return .reminders }
        return allCases.first { $0.rawValue.lowercased() == lower }
    }
}

/// A heading in the settings sidebar, over its pages.
public enum SettingsGroup: CaseIterable, Hashable, Sendable {
    case creaturesAndWorld, games, talkAndFriends, tools, moneyAndHistory

    public var title: String {
        switch self {
        case .creaturesAndWorld: tr("Creatures & world")
        case .games: tr("Games")
        case .talkAndFriends: tr("Talk & friends")
        case .tools: tr("Tools")
        case .moneyAndHistory: tr("Money & history")
        }
    }

    public var pages: [SettingsPage] { SettingsPage.allCases.filter { $0.group == self } }
}

/// What the settings search looks through: every section of every page, with
/// its heading, the labels of its controls, its footer and the saved keys it
/// sets. Written in English, the way the views write them; looked up through
/// `tr` when searched, so a search in Russian finds the Russian words.
///
/// A new setting goes into the section that shows it. A test fails for a key
/// `AppSettings` saves that is in no section and not in `unshown`.
public enum SettingsIndex {
    public struct Section: Sendable, Hashable {
        public let page: SettingsPage
        /// The section's heading as the view writes it; "" for one without.
        public let title: String
        public let labels: [String]
        public let footer: String
        public let keys: [String]

        public init(_ page: SettingsPage, _ title: String, labels: [String] = [], footer: String = "", keys: [String] = []) {
            self.page = page; self.title = title; self.labels = labels; self.footer = footer; self.keys = keys
        }
    }

    /// One place a search found: the words that matched (a control's label, or
    /// the heading), on which page, in which section.
    public struct Hit: Sendable, Hashable {
        public let page: SettingsPage
        public let section: String
        public let text: String

        public init(page: SettingsPage, section: String, text: String) {
            self.page = page; self.section = section; self.text = text
        }
    }

    /// Saved keys no control sets directly, and why.
    public static let unshown: [String: String] = [
        "memoryTokensMoved": "a one-time move of the memory budget, done at launch",
        "shotLastRect": "the last rectangle taken, remembered for ⇧⌘\\",
    ]

    /// The sections whose words hold every word of `query`, best first: a
    /// label or heading holding the whole query before a footer that only
    /// mentions it. Case and accents do not matter.
    public static func search(_ query: String, in sections: [Section] = sections) -> [Hit] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let whole = words.joined(separator: " ")
        var ranked: [(score: Int, order: Int, hit: Hit)] = []
        for (order, section) in sections.enumerated() {
            let title = section.title.isEmpty ? "" : tr(section.title)
            let labels = section.labels.map { tr($0) }
            let footer = section.footer.isEmpty ? "" : tr(section.footer)
            let everything = fold(([section.page.title, title, footer, section.title, section.footer] + labels + section.labels).joined(separator: " "))
            guard words.allSatisfy(everything.contains) else { continue }
            let label = zip(labels, section.labels).first { fold($0.0).contains(whole) || fold($0.1).contains(whole) }?.0
            let score = label != nil ? 0 : fold(title).contains(whole) ? 1 : fold(section.page.title).contains(whole) ? 2 : 3
            let text = label ?? (title.isEmpty ? section.page.title : title)
            ranked.append((score, order, Hit(page: section.page, section: section.title, text: text)))
        }
        return ranked.sorted { ($0.score, $0.order) < ($1.score, $1.order) }.map(\.hit)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static let sections: [Section] = [
        // creatures
        Section(.creatures, "Creatures", labels: ["How many", "Smallest", "Largest", "Live on", "All screens"], footer: "Every creature gets its own size between the two. Set them equal and they all match. Live on: keep them all on one monitor; choose another and they parachute over. While it is unplugged they use every screen, and go back when it returns.", keys: ["creatureCount", "homeScreen", "homeScreenName", "maxSize", "minSize"]),
        Section(.creatures, "Colours", labels: ["Add Colour", "Remove Last", "Reset"], footer: "Creature 1 wears the first colour, creature 2 the second, and so on, starting over when the colours run out.", keys: ["colors"]),
        Section(.creatures, "Tea parties", labels: ["Sit down to tea now and then", "Share of bumps", "Lasts", "Sip between stories"], footer: "Now and then two creatures who bump into each other put a little table out between them and sit down to tea, taking turns to tell each other stories from their lives. One party at a time. With talk off they just sip.", keys: ["teaPartiesEnabled", "teaPartyChance", "teaPartyMinutes", "teaSipSeconds"]),
        Section(.creatures, "Day and night", labels: ["Day lasts", "Night lasts", "never"], footer: "They walk by day and sleep by night. Set the night to 0 and they never sleep. A cursor still startles a sleeper awake.", keys: ["dayMinutes", "nightMinutes"]),
        Section(.creatures, "The cursor", labels: ["The cursor is", "Complain when pushed around", "Puts up with", "Calms down after"], footer: "A playmate: a chase is a game of tag. Just there: they hop aside. A menace: a grudge. Chase one too often in a row and it says so in its own voice.", keys: ["complainAfter", "complainCalmSeconds", "complainEnabled", "cursorMood"]),
        Section(.creatures, "Language and startup", labels: ["Language", "Start Ledgelings when you log in", "Status"], footer: "Menus, settings and what the creatures say. Prompts you edited stay as written. Login uses the system's Login Items.", keys: ["language"]),

        // actions
        Section(.actions, "Creature Actions", labels: ["Keep the sheet up after an action"], footer: "On, the Creature Actions sheet stays up until you press Done; off, it folds away after one action.", keys: ["actionsStayOpen"]),
        Section(.actions, "When the icon is hidden", labels: ["Shortcut from any app", "Shortcut", "Opening Ledgelings again shows the sheet"], footer: "macOS hides menu bar icons it has no room for. The shortcut brings the Creature Actions sheet up whichever app is in front, and pressed again puts it away; the sheet has the menu's switches, Settings and Quit. Click the shortcut to record another: a key with Command, Control or Option held. Esc keeps the old one. Or open Ledgelings again from Spotlight or Finder.", keys: ["reopenShowsActions", "shortcutEnabled", "shortcutKeyCode", "shortcutModifiers"]),

        // sprites
        Section(.sprites, "Creatures", labels: ["Open Folder"]),
        Section(.sprites, "Sprite kit: the new creature", labels: ["What it is", "What it is: a fat green frog with big eyes", "Name", "Name (the model chooses)", "Own colour", "Body colour", "Personality", "who they are, how they sound", "Refine with AI", "Clear"], footer: "Anything empty is the model's to choose. On import the name, colour and characters come from here; the picture gives only the looks.", keys: ["spriteKitForm"]),
        Section(.sprites, "Ask an image model", labels: ["Copied", "Copy Prompt", "Show", "Import…", "Save Images…", "Copy Images"], footer: "Give an image model (ChatGPT, Gemini…) the prompt and both pictures, in order: 1 the poses to copy, 2 the sheet to paint on. Import… what it paints, at any size; a text sheet (.txt) imports too.", keys: ["spriteKitForm"]),

        // beds
        Section(.beds, "Beds", labels: ["Each one sleeps in its own bed"], footer: "Every character has a bed of its own, picked for who it is: a crate for Blocky, a basket for Mittens, a lily pad for Hopper. Falling asleep, it puts the bed down and sleeps on it; waking, it folds it away. Off, they sleep on the bare edge as before.", keys: ["bedsEnabled"]),
        Section(.beds, "The favourite place", labels: ["Pull of the favourite place", "Walks to it at most"], footer: "At nightfall a creature gets up and walks to its favourite place, if it is on the same screen outline and no further along the edge than this. The first night it picks a place its character likes (Blocky the bottom edge, Pip the ceiling). Each night there makes it likelier to go back, up to this pull; a night slept elsewhere wears the habit down, and enough of them move it. A nap you ask for is slept where it is.", keys: ["bedPull", "bedWalkDistance"]),
        Section(.beds, "Talking about it", labels: ["Say something about it now and then"], footer: "Some nights a creature says a line as it lies down, in its own voice, and it mumbles something when you move its bed. Built-in lines: no model calls.", keys: ["bedTalk"]),
        Section(.beds, "Who sleeps where", footer: "Drag a sleeper's bed, by its edge or the part under its feet, to anywhere on an edge: it lands there, still asleep, and that is its favourite place from now on. Dragging a bed is not a chase. Kept by name: rename a character and it looks for a place afresh."),
        Section(.beds, "The file", labels: ["Forget All Places…"]),

        // flowers
        Section(.flowers, "Wearing", labels: ["Flower lasts", "The one with the flower follows the giver while it lasts"], footer: "Every third meeting of a pair, one gives the other a flower, worn on the head until it wilts or is planted. With the box ticked, the wearer trails the giver around the edge meanwhile. A creature wearing a flower walks past everyone without bumping.", keys: ["flowerMinutes", "followGiver"]),
        Section(.flowers, "Planting", labels: ["They plant their flowers where they like", "A planted flower lasts", "Flowers in the ground at most", "Clear Planted Flowers", "Nothing was planted."], footer: "After wearing it a while, each one stops following its giver, goes looking for the kind of spot its character likes and plants the flower in the edge there. What it likes comes from who it is: Blocky wants the bottom edge, Pip the ceiling, Ruth a neat row beside the others, Dot plants at once, Zed waits for dark. If nowhere suits before the flower would wilt, it plants it where it stands. Planting one more than the most wilts the oldest. Clear Planted Flowers, here or in the menu, pulls them all up at once. Planted flowers are not kept when the app quits.", keys: ["gardenMinutes", "gardenSize", "plantFlowers"]),
        Section(.flowers, "Who plants where", footer: "Read from each character's description and its species on the Talk tab, the same way voices are cast: words like bottom, ceiling, corner, quiet, cheerful, counts, sleepy or fast. Edit a description and this changes with it.", keys: ["creatureCount", "species"]),

        // calendar
        Section(.calendar, "The day", labels: ["They know the time of day", "They know the day of the week and the date"], footer: "Your Mac's clock and calendar, told to the model before every line and paper plane: \"late evening (22:40)\", \"Saturday, 26 September 2026\". This is apart from the colony's own day and night, which only says when they sleep.", keys: ["knowsDate", "knowsTimeOfDay"]),
        Section(.calendar, "Holidays", labels: ["Jewish holidays", "Christian holidays", "Muslim holidays", "Mention a holiday", "only on the day"], footer: "On a holiday they know it, and which day of it (\"day 3 of Sukkot\"); before one, how far off it is. Jewish dates come from the Hebrew calendar and Muslim ones from the Islamic (Umm al-Qura) calendar, both built into macOS, so nothing is looked up online; a holiday that starts at sundown \"begins this evening\" the evening before. Where the new moon is sighted locally, a Muslim date can fall a day apart. With the built-in lines, one conversation in three on a holiday is about it; they only know a holiday on the day, so how far ahead to mention one needs a model.", keys: ["christianHolidays", "holidayLookAhead", "jewishHolidays", "muslimHolidays"]),
        Section(.calendar, "What they know right now", labels: ["Nothing: every box is off."]),
        Section(.calendar, "Coming up in the next 60 days", labels: ["No holidays ticked.", "Nothing in the next 60 days."]),

        // chases
        Section(.chases, "Counting", labels: ["Count chases and pick-ups"], footer: "Every time the cursor chases a creature off its edge or picks it up, it counts, by character: today, this week and in all. Days and weeks follow your calendar. Off, nothing is counted and the numbers stay as they are.", keys: ["huntCountEnabled"]),
        Section(.chases, "Talking about it", labels: ["They know their count", "How often it comes up"], footer: "This share of conversations, tea stories and paper planes carries the numbers: with a model they go into its prompt, compared with yesterday and the week, with any record; with the built-in lines a creature says its count in its own voice. A complaint always knows them, and a round number or a record day is said out loud. How they take it follows the cursor mood: a score, a fact, or a grudge. No extra model calls.", keys: ["huntTalkChance", "huntTalkEnabled"]),
        Section(.chases, "Wariness", labels: ["Much-chased creatures keep their distance", "After"], footer: "When the cursor is a menace, a creature chased this often today jumps away from further off, until tomorrow.", keys: ["huntWary", "huntWaryAfter"]),
        Section(.chases, "Shaking it off", labels: ["Shakes to break free", "Each shake at least", "Shakes within"], footer: "Move the mouse back and forth: this many turns, each after a stroke this long, within this time. Fewer, shorter, slower is gentler.", keys: ["revengeShakeStroke", "revengeShakeWindowSeconds", "revengeShakes"]),
        Section(.chases, "Revenge", labels: ["Grab the cursor in revenge", "After", "Within", "Holds on for at most", "no limit", "Tells you off again every", "never", "Holds the pointer still", "Then peace for"], footer: "Chased or picked up this often in that time, a creature jumps on the cursor and rides along on it, telling you off now and then in its own words and the cursor mood, until you shake it off or the limit runs out. Holding the pointer still, you cannot move it until it lets go, after 10 s at the latest. Escape lets go too; outside Ledgelings only with Accessibility allowed.", keys: ["revengeAfter", "revengeCooldownMinutes", "revengeEnabled", "revengeHoldSeconds", "revengePinsCursor", "revengeTauntSeconds", "revengeWindowSeconds"]),
        Section(.chases, "The count"),
        Section(.chases, "The file", labels: ["Reset All…"]),

        // play
        Section(.play, "Playing", labels: ["They play now and then"], footer: "Now and then a creature stops walking and plays, the way the worms in Worms fool about between turns, with nobody hurt. One game at a time, never in the middle of a talk, a tea party, a flower, a plane, a grab or sleep; the players are left alone until it is over.", keys: ["playEnabled"]),
        Section(.play, "Which games", labels: ["Catch me if you can (two)", "Ninja rope swing", "Parachute jump", "Basketball (alone, or two taking turns)", "Soccer (anyone free, in teams)", "Baseball (anyone free, round every edge)"], footer: "Tag is for two: they chase each other round the edges, and a touch makes the other one \"it\". The rope is fired at the ceiling to swing across the floor; the parachute jump starts from the ceiling; the hoop goes on a wall at the end of a floor. Soccer and baseball are for whoever is free, and have a tab of their own: Ball games. Off, a game is never played, and its row on the Activities page is greyed.", keys: ["playBaseballEnabled", "playBasketballEnabled", "playParachuteEnabled", "playRopeEnabled", "playSoccerEnabled", "playTagEnabled"]),
        Section(.play, "How often", labels: ["A game about every", "Friends play more often by"], keys: ["playBondBoost", "playEveryMinutes"]),
        Section(.play, "How the games go", labels: ["Tag lasts", "Parachute comes down at", "Ball keeps on each bounce", "Throws at the hoop each"], keys: ["ballBounce", "basketballThrows", "parachuteFallSpeed", "tagSeconds"]),
        Section(.play, "Talking about it", labels: ["Say something as a game starts and ends"], footer: "Whoever starts a game says so in its own voice, and someone has the last word when it is over. With a model set up on the Talk tab, the first line is written by the model (counted under Plays, or Soccer and baseball, on the Costs tab), and a goal's or a home run's cheer too; otherwise, and for the last word, built-in lines. Needs Talk on.", keys: ["playTalk"]),
        Section(.play, "The props", footer: "Drawn like the creatures, and the same for every species, your own imported ones too."),

        // ballGames
        Section(.ballGames, "Soccer", labels: ["Soccer (anyone free, in teams)", "Soccer at most every", "A match lasts up to", "Goals to win", "Soccer players at most"], footer: "On the widest floor there is, a little net at each end. One plays keepy-uppy and shoots at an empty goal; two have a goal each; three share one goal and take turns in it; four or more split into teams of friends, a keeper each from six. First to the goals, or the best score when time is up.", keys: ["playSoccerEnabled", "soccerEveryMinutes", "soccerGoals", "soccerMinutes", "soccerPlayers"]),
        Section(.ballGames, "The props", footer: "Drawn like the creatures, and the same for every species, your own imported ones too."),
        Section(.ballGames, "Baseball", labels: ["Baseball (anyone free, round every edge)", "Baseball at most every", "Innings", "Baseball players at most"], footer: "Home where the batter stands, the bases on the three edges furthest apart, the pitcher on the batter's floor. One practises; two to five bat in turn, a runner who must bat again leaving a pennant on its base; six or more play as two teams. Out over the top of the screen is a home run.", keys: ["baseballEveryMinutes", "baseballInnings", "baseballPlayers", "playBaseballEnabled"]),
        Section(.ballGames, "Who plays"),

        // talk
        Section(.talk, "Talk", labels: ["Creatures talk when they bump into each other", "Bubble stays", "Not repeating their last", "off", "Paper planes", "A paper plane every"], footer: "Two creatures meeting on the same edge trade a line and a reply. Every third meeting of a pair, one gives the other a flower (the Flowers tab). Every so often one folds a note into a paper plane and throws it to another; its own wind swirls it across the screen, the catcher reads it out, thinks aloud about it and throws one answer back. \"Make Someone Talk\" and \"Send a Paper Plane\" in the menu work at any time. Longer lines stay up a little longer; a click on a bubble closes it. Each creature remembers its last lines and says something else until it has run through the rest; a model is shown them and asked for something new.", keys: ["bubbleSeconds", "lineMemory", "planeMinutes", "planesEnabled", "talkEnabled"]),
        Section(.talk, "Brain", labels: ["Brain", "Room for each line"], keys: ["brainProvider", "lineTokens", "openRouterModel", "script", "talkModel", "talkServer"]),
        Section(.talk, "Characters", labels: ["Species", "Name", "Take them out of the cast", "Who they are", "Add Character", "Reset Cast"], footer: "Every species has its own cast. The first creature wearing a species is its first character, the second its second, and so on, starting over when the cast runs out. The species itself is described to the model, so a frog talks like a frog.", keys: ["casts"]),
        Section(.talk, "Prompts", labels: ["Who is speaking (system prompt)", "Opening line", "Reply", "Reset Prompts"], keys: ["linePrompt", "replyPrompt", "systemPrompt"]),

        // voice
        Section(.voice, "Characters", labels: ["Nobody on screen right now.", "Casting…", "Cast Everyone with Model"], footer: "The characters on screen now. Each starts automatic: with \"Voices fit each character's personality\" on, their description and species choose the voice, pitch and speed (old and slow, tiny and quick, a robot, a ghost…); off, voices are only handed out to differ. \"Cast with Model\" asks the brain model instead, which understands any description, and keeps its choice as the character's own; it costs one call. A voice picked here is theirs alone; the automatic ones go round it. Speed and Pitch here multiply the overall sliders on the left; Speed follows pitch can be set for one character alone. \"Auto\" puts a character back to automatic. Settings follow the name, on every engine; an OpenRouter voice the chosen model does not have is ignored. With the Local server, \"Custom blend…\" mixes Kokoro voices, af_bella(2)+am_puck(1) being two parts Bella to one of Puck: endless voices from the 72, free. OpenRouter's Kokoro refuses blends.", keys: ["characterVoices"]),
        Section(.voice, "Voice", labels: ["Hear them talk out loud", "Voices", "Every character gets a voice of their own", "Cartoon voices: squeakier, sillier", "Voices fit each character's personality", "Speed", "Pitch", "Speed follows pitch: no echo, higher talks a little faster", "Pause before the answer", "Volume", "Test", "Stop", "Status"], keys: ["cartoonVoices", "castByPersonality", "keepVoices", "localVoice", "localVoiceModel", "localVoiceServer", "openRouterVoice", "reuseLineVoices", "speedFollowsPitch", "systemVoice", "voiceEnabled", "voiceEngine", "voiceModel", "voicePerCharacter", "voicePitch", "voiceSpeed", "voiceTurnPause", "voiceVolume"]),

        // bonds
        Section(.bonds, "Stories", labels: ["Pairs who live together get a story", "First story after", "A story lasts"], keys: ["plotAfterHours", "plotLength", "plotsEnabled"]),
        Section(.bonds, "Storylines", labels: ["Each story grows from their whole history", "Their story so far is kept to", "Latest moments told one by one"], footer: "Every talk, tea party, flower, paper plane, game and cursor grab two characters share is kept. A new story is written from their story so far (a short chronicle, rewritten in the same call) and the latest moments, so it can bring back what happened and never contradicts it. About 300 more tokens per story. With the built-in lines, stories are made from these moments without a model.", keys: ["plotsEnabled", "storyMoments", "storyWords", "storylinesEnabled"]),
        Section(.bonds, "The prompt that writes a story", labels: ["Reset Prompt"], keys: ["plotPrompt"]),
        Section(.bonds, "Who lives with whom", labels: ["Nobody has shared the screen yet."], footer: "Time counts while both are on screen, and is kept by name: rename a character and it starts again as a stranger."),
        Section(.bonds, "The file", labels: ["Reveal in Finder", "Reset All Stories", "Forget All"]),

        // relationships
        Section(.relationships, "Deeds from talk", labels: ["What they say can turn into what they do", "Invite to a game", "Invite to tea", "Give a flower", "Send a letter", "Walk over to someone", "Follow someone", "Go to sleep"], footer: "A line or a letter may end in a deed: \"soccer?\" answered \"yes\" starts the match. Each prompt offers only what is possible right now, and anything else is ignored. About 40 more tokens a line.", keys: ["deedFlower", "deedFollow", "deedGames", "deedLetter", "deedSleep", "deedTea", "deedVisit", "deedsEnabled"]),
        Section(.relationships, "How often", labels: ["After a deed, the next waits", "no wait", "Most deeds an hour", "no limit", "Same pair, same deed again after", "An invitation stays open", "A yes waits for both to be free", "Following lasts", "Built-in letters and talks that invite", "Built-in answers that say yes"], footer: "Zero turns a limit off; the same two never do two things within 15 seconds. Without a model each character invites and answers in its own words, close friends saying yes more often.", keys: ["builtInAcceptChance", "builtInInviteShare", "deedGapMinutes", "deedPairGapMinutes", "deedWaitMinutes", "deedsPerHour", "followSeconds", "inviteOpenMinutes"]),
        Section(.relationships, "Long-term memory", labels: ["Pairs remember each other", "Memory sent with each line", "none", "Facts kept per pair", "Days of timeline kept", "The model may note facts as it speaks", "Each knows what it did today", "Things from today it mentions"], footer: "Every conversation, letter and tea party carries what the two remember, cut to the tokens set here. The timeline is for you; only today and yesterday are sent.", keys: ["dayContextEnabled", "dayContextItems", "memoryDays", "memoryEnabled", "memoryFacts", "memoryNotes", "memoryTokens"]),
        Section(.relationships, "The diary", labels: ["At nightfall the model writes their memory down", "A pair's memory at most every", "Pairs a night"], footer: "One call a pair (Costs › Long-term memory): their story, the facts that still matter, the day in a line. Without a model days are counted and facts come from deeds and games.", keys: ["diaryEnabled", "diaryEveryHours", "diaryPairsPerNight"]),
        Section(.relationships, "Their past", labels: ["Days read back", "Lines shown per pair", "Check First", "Read the Past In", "Open Relationships"], footer: "Builds each pair's memory from what they said on this Mac, one call a pair (Costs › Memory: reading the past); only their own lines are sent. Check First sends nothing. bonds.json is copied first.", keys: ["seedDays", "seedLines"]),

        // reminders
        Section(.reminders, "New reminder", labels: ["Remind me to", "Stretch, call mom, stand-up…", "When", "Repeat", "In 5 min", "In 30 min", "In 1 hour", "Add Reminder"], footer: "When the time comes, one of the creatures folds it into a paper plane and throws it at you. A time already past is delivered straight away. Repeating reminders keep their time of day; weekdays skip Saturday and Sunday."),
        Section(.reminders, "Delivery", labels: ["Reminders arrive by paper plane", "Letter stays open", "The thrower reads its note out loud", "Add a Reminder… opens a paper note", "Send a Test Letter", "This is what a reminder looks like"], keys: ["reminderLetterSeconds", "reminderPaperNote", "reminderReadAloud", "remindersEnabled"]),
        Section(.reminders, "Your reminders", labels: ["No reminders yet."], footer: "Sent one-off reminders stay here, greyed, until you clear them."),
        Section(.reminders, "The file", labels: ["Clear Sent"]),

        // clipboard
        Section(.clipboard, "History", labels: ["Clipboard manager", "Keep a history of what is copied", "Copies kept", "Kept for", "always", "Keep formatting (rich text)", "Keep files copied in Finder", "Keep images", "Largest image kept"], footer: "Every copy goes into the history, newest first; copying the same thing again moves it to the top. Pinned copies stay whatever the limits say. Pictures count as copies; one bigger than the largest size is left out. Nothing copied ever leaves this Mac or reaches a model.", keys: ["clipHistoryEnabled", "clipHistoryLimit", "clipKeepDays", "clipKeepFiles", "clipKeepFormatting", "clipKeepImages", "clipLargestImageMB", "clipboardEnabled"]),
        Section(.clipboard, "Shortcuts", labels: ["History picker", "Snippets picker", "A snippet's own shortcut pastes it at once"], footer: "They work in every app. In the picker: type to search copies and snippets at once, ↑↓ to choose, ⌘1–9 for the first nine, ⇥ between the groups, ⌘P to pin, ⌫ to forget a copy, ⎋ to close.", keys: ["clipHistoryShortcutEnabled", "clipHistoryShortcutKeyCode", "clipHistoryShortcutModifiers", "clipSnippetShortcutsEnabled", "clipSnippetsShortcutEnabled", "clipSnippetsShortcutKeyCode", "clipSnippetsShortcutModifiers"]),
        Section(.clipboard, "Pasting", labels: ["Paste into the app I was in", "Needs Accessibility, to press ⌘V for you. Until then it only copies.", "Allow…", "Paste as plain text", "Unfold and collapse the picker", "Animation speed", "Who brings it", "Whoever is nearest the middle", "Nobody: it unfolds by itself", "It says a line as the sheet unfolds"], footer: "⏎ pastes, ⌥⏎ the other way (plain or formatted). A creature brings the sheet and holds its corner; it collapses into the text cursor and the creature leaps back. The paste never waits.", keys: ["clipAnimate", "clipAnimationSpeed", "clipAutoPaste", "clipHelper", "clipHelperEnabled", "clipHelperTalks", "clipPlainText"]),
        Section(.clipboard, "Snippets", labels: ["Edit Snippets…"], footer: "A protected snippet's words live in the Keychain, never in a file: shown as dots, pasted or shown only after your fingerprint (Touch ID, no password instead), kept out of the history and taken off the clipboard a second after pasting."),
        Section(.clipboard, "Never kept", labels: ["No app.", "Add App…", "Remove"], footer: "Nothing copied in these apps is kept, nor anything a password manager marks as secret. Clear History keeps pinned copies.", keys: ["clipExcludedApps"]),

        // screenshots
        Section(.screenshots, "Screenshots", labels: ["Screenshot tool", "Needs Screen Recording, to see the screen. Until then a shot only says so.", "Allow…"], footer: "Every screen freezes and dims; drag an area (R), draw a loop (L), or take the screen (W) or all of them (A). Then box (B), arrow (→), highlight (H), blur (X) or blur by hand (F), in six colours (1–6); ⌘Z undoes. ⏎ takes it, ⌘C copies, ⌘S saves, ⎋ lets go. Pictures only, never video; nothing leaves this Mac.", keys: ["shotEnabled"]),
        Section(.screenshots, "Shortcuts", labels: ["Capture with the toolbar", "Full screen at once", "Full screen takes", "All screens, in one picture", "The screen under the cursor", "The last rectangle again"], footer: "They work in every app. Full screen and the last rectangle go straight to the clipboard or the folder, with no toolbar; with no rectangle taken yet, the last-rectangle keys open the toolbar. All monitors are stitched at each one's own sharpness.", keys: ["shotCaptureShortcutEnabled", "shotCaptureShortcutKeyCode", "shotCaptureShortcutModifiers", "shotFullScope", "shotFullShortcutEnabled", "shotFullShortcutKeyCode", "shotFullShortcutModifiers", "shotLastShortcutEnabled", "shotLastShortcutKeyCode", "shotLastShortcutModifiers"]),
        Section(.screenshots, "Where a shot goes", labels: ["Copy to the clipboard", "Save to a folder", "Folder", "Choose…", "Show"], footer: "As a PNG named for its time (Screenshot 2026-10-18 14.03.22.png); the folder is made on the first save. ⌘C on the toolbar only copies, ⌘S always saves. A copy also lands in the clipboard history.", keys: ["shotCopy", "shotFolder", "shotSave"]),
        Section(.screenshots, "Marks", labels: ["Line thickness", "Colour"], footer: "Boxes and arrows are this thick; blurring by hand is four times as wide. A blur is big square blocks, baked into the picture, so the words under it cannot be read back. The toolbar starts on the last colour picked.", keys: ["shotColour", "shotThickness"]),
        Section(.screenshots, "Creatures", labels: ["Hide the creatures while capturing", "A creature brings the shot home"], footer: "Hidden, they are out of the picture too. Once it is taken, one hops up to where the toolbar was and carries a tiny picture of it back to its edge.", keys: ["shotCreatureBrings", "shotHideCreatures"]),

        // dictation
        Section(.dictation, "Dictation", labels: ["Dictation", "The microphone is not allowed. Allow… opens System Settings on its switch.", "Needs the microphone. macOS asks once; until then nothing is heard.", "Allow…", "Microphone", "none found"], footer: "Press the shortcut and speak; press it again (or ⏎) and the words land on the clipboard and in the clipboard history. ⎋ lets it go and sends nothing. The sound is kept in memory only and never saved.", keys: ["dictationEnabled"]),
        Section(.dictation, "Shortcut", labels: ["Start and stop", "Hold to talk", "Longest recording"], footer: "It works in every app. Holding to talk, it listens while the keys are down and writes it down when you let go. At the longest length it stops by itself and sends what it heard.", keys: ["dictationHoldToTalk", "dictationMaxSeconds", "dictationShortcutEnabled", "dictationShortcutKeyCode", "dictationShortcutModifiers"]),
        Section(.dictation, "Writing it down", labels: ["Model", "Spoken in", "Tidy it up"], footer: "OpenRouter's models that listen to sound, cheapest first; each recording is priced in Settings › Costs as Dictation. Tidying leaves out um and uh, stutters and false starts, and adds punctuation, in the same call.", keys: ["dictationCleanUp", "dictationLanguage", "dictationModel"]),
        Section(.dictation, "The words and the creature", labels: ["Paste into the app I was in", "Needs Accessibility, to press ⌘V for you. Until then it only copies.", "Allow…", "Who holds the microphone", "Anyone free, by chance", "Nobody: a note says how it went"], footer: "A creature leaps to the middle of the screen holding a microphone whose bars follow your voice, the clock over its head; it thinks while the words are written, says the first of them and hops home.", keys: ["dictationCreature", "dictationHelper", "dictationPaste"]),

        // translate
        Section(.translate, "Translate", labels: ["Translator", "Type to translate", "Translate the last copy", "The last copy", "Opens the sheet, already translated", "Puts it on the clipboard quietly"], footer: "Both work in every app. Type to translate opens the sheet: your words on the left, the translation on the right as you type. The last copy opens in the sheet already translated, or quietly replaces the clipboard with its translation and says so by the text cursor. ⏎ copies the translation, ⌘⏎ pastes it into the app you were in.", keys: ["translateClipMode", "translateClipShortcutEnabled", "translateClipShortcutKeyCode", "translateClipShortcutModifiers", "translateEnabled", "translateShortcutEnabled", "translateShortcutKeyCode", "translateShortcutModifiers"]),
        Section(.translate, "Languages", labels: ["English", "Russian", "Hebrew"], footer: "Told apart by their letters, Latin, Cyrillic or Hebrew, on this Mac and for free, before anything is sent. A text already in its target goes into the target's own language instead. At least two stay on.", keys: ["translateLanguages", "translateTargets"]),
        Section(.translate, "Model", labels: ["Model", "Guess the rest of the phrase", "Guess model", "Wait after typing"], footer: "An OpenRouter model, with the key from Settings › Talk; with LM Studio as the brain and no key, its model, free. Cheap and fast is best: about a cent a day. Every call shows on Costs as Translation, every guess as Autocomplete. ⇥ takes the grey words.", keys: ["translateAutocomplete", "translateAutocompleteModel", "translateDelayMs", "translateModel"]),
        Section(.translate, "Clipboard and safety", labels: ["Translate button in the clipboard picker", "Keep translations in the clipboard history", "Ask before sending more than", "Who brings the sheet", "Whoever is nearest the middle", "Nobody: it unfolds by itself"], footer: "Text goes to the model only when you translate it. Protected snippets and copies of their words never do, and get no button. Links, e-mails, code and numbers are kept as they are. Longer texts wait for ⏎ and say their parts and price first; never more than 50 000 characters.", keys: ["translateHelper", "translateHelperEnabled", "translateKeepInHistory", "translateLiveLimit", "translatePickerButton"]),

        // costs
        Section(.costs, "Spent", labels: ["Cost", "Calls", "Tokens", "Today", "This month", "All time"]),
        Section(.costs, "By feature", labels: ["Nothing yet."], footer: "Talk is the meetings and pokes (two calls a conversation); paper planes the notes and the catcher's thought; voice every line said by a paid speech model; voice casting each Cast with Model; relationship plots one call per story a pair gets (Bonds tab). Calls from before features were labelled are counted apart."),
        Section(.costs, "By model"),
        Section(.costs, "Latest calls", labels: ["No calls yet."]),
        Section(.costs, "The file", labels: ["Reveal in Finder"], footer: "spend.jsonl, one JSON line per call: time, provider, model, feature, tokens and cost. Plain text on purpose."),

        // chats
        Section(.chats, "Chats", labels: ["Open in Finder"]),
    ]
}
