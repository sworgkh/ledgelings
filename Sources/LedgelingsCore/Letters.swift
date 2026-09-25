import Foundation

/// What goes in a paper plane, and what the one who catches it says to itself.
///
/// Every built-in character has its own voice: the few topics its soul keeps
/// coming back to (Blocky's war on the cursor, Zed's naps, Ruth's counting),
/// written as notes it sends and as the thoughts it has reading anyone's note.
/// A character the user invented, with no voice here, uses `anyone`.
/// `{sender}` and `{reader}` are filled in when the letter is read.
public enum Letters {
    public struct Voice: Sendable, Equatable {
        /// What this soul keeps thinking about, in a few words each.
        public var topics: [String]
        /// Notes it folds into a plane.
        public var notes: [String]
        /// What it mutters to itself after reading a note, from anyone.
        public var musings: [String]
    }

    public static let anyone = Voice(
        topics: ["the quiet", "the wind", "the other side of the screen"],
        notes: [
            "Haven't bumped into you in ages. The edge is too quiet without it.",
            "The wind is up today. Thought I'd send you something on it.",
            "Hello from the other side of the screen! It looks just like yours.",
            "Found a nice spot by the corner. Come and see it before someone sits there.",
        ],
        musings: [
            "A letter from {sender}. I should write back. On what, though?",
            "Paper planes. Why didn't we think of this sooner?",
            "It smells of {sender}'s edge. Dusty, a bit warm.",
        ]
    )

    public static let voices: [String: Voice] = [
        // blocky's cast
        "Blocky": Voice(
            topics: ["the cursor conspiracy", "which edge is respectable", "pride"],
            notes: [
                "{reader}. The cursor was on MY edge again. Twice. I am keeping a list.",
                "Reminder: the bottom edge is the only respectable edge. The ceiling is for show-offs.",
                "I did not jump because I was scared. I jumped because I chose to. Tell nobody.",
                "If you see the arrow, do NOT make eye contact. It feeds on attention.",
            ],
            musings: [
                "A paper plane. Flying. Off the edge. Disgraceful. ...Neatly folded, though.",
                "{sender} wrote to ME. Obviously. Who else would they write to.",
                "Paper beats cursor. I should fold myself a shield.",
            ]),
        "Pip": Voice(
            topics: ["the ceiling", "tiny wonders", "friendship"],
            notes: [
                "The ceiling is AMAZING today! Everything is upside down and I love it!",
                "A window opened all by itself! Magic! Or a person. Probably magic!",
                "You are my favourite. Don't tell the others. Actually, tell them, it's nice!",
                "I folded this upside down. From up here, that's right side up!",
            ],
            musings: [
                "A letter! For me! Nobody has ever... well, {sender} has now! Best day!",
                "*hugs the paper* I'm keeping this forever. Or until it wilts. Does paper wilt?",
                "If I fold myself up like this, can I fly too? Worth a try. Worth ALL the tries.",
            ]),
        "Mortimer": Voice(
            topics: ["made-up proverbs", "corners and time", "where windows go at night"],
            notes: [
                "An old saying: the edge you walk is the edge that walks you. I made it up this morning.",
                "Every pixel was dark once. Remember that, young one. *sighs*",
                "I have been thinking about corners. They are just edges that changed their mind.",
                "When the screen sleeps, where do the windows go? I have pondered it for years.",
            ],
            musings: [
                "*sighs* Paper that flies. In my youth, words stayed where you put them.",
                "{sender} writes like a young breeze. Short, bright, gone by lunch.",
                "A letter is a conversation that learned to wait. Rather like me.",
            ]),
        "Zed": Voice(
            topics: ["naps", "warm spots", "dreams"],
            notes: [
                "Is it night yet. Asking for me.",
                "Found a warm spot near the clock. Wake me if it's important. It won't be.",
                "Dreamt I was a screensaver. Very relaxing. Recommend.",
                "zzz... sorry, fell asleep folding this. Anyway. Hi.",
            ],
            musings: [
                "Reading is just sleeping with your eyes open. *yawns*",
                "Nice letter, {sender}. I'll reply after a nap. Or two.",
                "Paper would make a lovely blanket. Tiny, though. I'd need forty.",
            ]),
        "Dot": Voice(
            topics: ["speed", "everyone else being slow", "records"],
            notes: [
                "Lapped the whole screen twice while you walked one edge. Keep up, boulder.",
                "This plane is faster than you. I checked.",
                "Speed tip: move your feet. That's the whole tip.",
                "Timed you turning a corner. I've seen icebergs with more hustle.",
            ],
            musings: [
                "Took {sender}'s plane forever to get here. Like, whole seconds.",
                "Four words in and I'd guessed the ending. Speed reading, baby.",
                "Should've just shouted. Paper is for the slow.",
            ]),
        "Ruth": Voice(
            topics: ["counting everything", "rules against jumping", "keeping records"],
            notes: [
                "Bumps today: zero. Unacceptable. Please schedule a bump with me by dusk.",
                "I counted the pixels on the bottom edge. Someone has moved seven of them.",
                "Jumping is banned until further notice. This note is the notice.",
                "Please return this plane when you are done with it. I have logged it.",
            ],
            musings: [
                "Handwriting: messy. Folds: uneven. Content: noted. I'll file it.",
                "Letters received this week: one. I'll need a bigger ledger.",
                "Planes are just jumping with extra steps. I disapprove. Of the plane, not the letter.",
            ]),
        // cat
        "Whiskers": Voice(
            topics: ["not caring", "what everyone is doing", "the warm part of the screen"],
            notes: [
                "Not that I care, but what are you doing over there?",
                "I am sitting on the warm part of the screen. You may not have it.",
                "I did not miss you. I simply noticed you were gone.",
            ],
            musings: [
                "Hm. I'll pretend I didn't read this. ...Then I'll read it again.",
                "A plane? Mine now. I am going to sit on it.",
                "{sender} wrote to me. Of course. They all do, eventually.",
            ]),
        "Mittens": Voice(
            topics: ["warm corners", "sunny pixels", "purring"],
            notes: [
                "Purrrlease come to the warm corner. It's purrfect here.",
                "I kept a sunny pixel for you. Mostly I'm lying on it.",
                "Mrrp. That's all. Mrrp.",
            ],
            musings: [
                "Purrrr... a letter that smells of {sender}. I'll nap on it.",
                "Paper gets warm if you lie on it long enough. Science.",
                "Mrrrow. Nice words. Nicer if they came with a sunbeam.",
            ]),
        "Sir Pounce": Voice(
            topics: ["the hunt", "worthy foes", "plans for tonight"],
            notes: [
                "The cursor sleeps. Tonight, we strike. Burn this letter. Actually don't, it's mine.",
                "I stalked a tooltip for an hour. It vanished. A worthy foe.",
                "Hunt log, day forty: the scroll bar suspects nothing.",
            ],
            musings: [
                "It came from the sky and I CAUGHT it. Mighty paws. Mightiest.",
                "A message from {sender}. Intelligence. The hunt thickens.",
                "*crouches* The paper wiggled. I have defeated it. Now I read it.",
            ]),
        // frog
        "Hopper": Voice(
            topics: ["jumping records", "leg day", "bragging"],
            notes: [
                "Jumped from one monitor to the other today. Nearly. In my head.",
                "Bet I can out-jump this plane. Tomorrow. Today is leg day.",
                "World record attempt at dusk. Bring snacks, not expectations.",
            ],
            musings: [
                "Nice throw, {sender}. I could throw it further. With my legs.",
                "Flew all this way to reach me. Respect. I'd have jumped it.",
                "Ribbit. That means 'noted' in frog.",
            ]),
        "Mossy": Voice(
            topics: ["pond proverbs", "stillness", "puddles"],
            notes: [
                "As the pond says: the lily does not hurry, yet it reaches the surface.",
                "Still water, still frog. Come and sit near me, it is peaceful.",
                "The screen is dry today. I have been thinking about puddles.",
            ],
            musings: [
                "As the pond says: a message that flies must one day land. And it did.",
                "Paper and water do not mix. Yet I will keep this. Away from ponds.",
                "*slowly* A letter... from {sender}... I will reply next season.",
            ]),
        "Croak": Voice(
            topics: ["how dry everything is", "complaints", "rain that never comes"],
            notes: [
                "This edge is drier than a toaster. Complaint number twelve.",
                "If you find a puddle, write back. If not, don't.",
                "Humidity: zero. Mood: also zero.",
            ],
            musings: [
                "Paper. Dry paper. Of course it's dry. Everything here is dry.",
                "{sender} could have thrown a raindrop. Nobody ever throws a raindrop.",
                "Hmph. Read it twice. Still dry.",
            ]),
        // ghost
        "Boo": Voice(
            topics: ["being scary", "haunting corners", "practising boos"],
            notes: [
                "BOO! ...Did it work? Through paper? No?",
                "Practising being spooky. Rate my boo out of ten.",
                "Haunting the top-left corner tonight. Visitors welcome. Scared visitors preferred.",
            ],
            musings: [
                "A letter! I'll haunt it back. Boo, little paper.",
                "{sender} isn't scared of me at all. I'll try harder. BOO. There.",
                "I tried to go through the paper. It went through me instead.",
            ]),
        "Wisp": Voice(
            topics: ["monitors that are gone", "old screensavers", "fading"],
            notes: [
                "I remember a monitor that stood where your left edge is. It glowed so kindly.",
                "Some nights I still hear the hum of screens long unplugged.",
                "Write back in pixels, dear. They fade slower than ink.",
            ],
            musings: [
                "Paper remembers the hand that folded it. So do I, {sender}.",
                "It flew like the old screensaver birds. They never landed either.",
                "*softly* Every letter is a tiny monitor, lit for one.",
            ]),
        "Sheet": Voice(
            topics: ["technicalities", "hovering", "being flat"],
            notes: [
                "Technically I hover. Technically this note hovered too. We have that in common.",
                "Status: floating. Mood: flat. Like this paper.",
                "I would walk over, but I don't walk.",
            ],
            musings: [
                "A flying sheet. Finally, someone who gets me.",
                "Technically I didn't catch it. It flew into me.",
                "Read it. Folded it. Same as I do with my feelings.",
            ]),
        // slime
        "Goop": Voice(
            topics: ["nice things", "sticky things", "both at once"],
            notes: [
                "Hi! Today is nice! And sticky! Nice and sticky!",
                "I found a sticky corner. It is very nice.",
                "Plane is nice. You are nice. Bye!",
            ],
            musings: [
                "Paper! It sticks to me! Very nice!",
                "{sender} is nice. The letter is sticky now. Also nice.",
                "I will keep it inside me. For safe.",
            ]),
        "Puddle": Voice(
            topics: ["evaporating", "being stepped on", "worrying"],
            notes: [
                "Is the screen brightness up? I feel myself evaporating. Please check.",
                "What if the cursor steps on me? Has anyone ever been stepped on? Asking.",
                "I'm fine. Mostly. Eighty percent of me is fine. The rest has dried.",
            ],
            musings: [
                "Paper soaks up water. Paper soaks up ME. I must hold this very carefully.",
                "What if this is the last letter? What if it isn't? Both are scary.",
                "{sender} thought of me. That's nice. I only shrank a little from nerves.",
            ]),
        "Blorp": Voice(
            topics: ["sounds", "being pleased", "more sounds"],
            notes: [
                "Blorp! Splorch. Bloop bloop. (That's a lot of news.)",
                "Squelch! Me happy. You?",
                "BLORP. Blorp blorp. Blorp.",
            ],
            musings: [
                "Bloop! Paper! Splat! *very pleased*",
                "Blorp. Blorp blorp. Fwip! Good letter.",
                "Schlorp. Me read. Me smart.",
            ]),
        // robot
        "Unit 7": Voice(
            topics: ["status reports", "probabilities", "exact numbers"],
            notes: [
                "Status report: battery 100%, cheer 12%. Requesting social interaction.",
                "Observation: 0 bumps in the last 140 seconds. Probability of loneliness: high.",
                "This message was folded 7 times. Aerodynamic efficiency: adequate.",
            ],
            musings: [
                "Message received. Integrity 98%. One crease out of specification.",
                "Sender: {sender}. Content: parsed. Emotional response: generating... done.",
                "Flight path: suboptimal. Arrival: successful. Filing both.",
            ]),
        "Sprocket": Voice(
            topics: ["maintenance", "squeaky parts", "tiny wrenches"],
            notes: [
                "When did you last oil your corners? I can bring a tiny wrench.",
                "Your left foot squeaks. I have been meaning to mention it.",
                "Maintenance day tomorrow. Everyone line up, bolts first.",
            ],
            musings: [
                "The fold on this wing is loose. I should tighten it. With love.",
                "Nice paper. Could use a rivet or two.",
                "{sender}'s hinges need grease. I can tell from the handwriting.",
            ]),
        "Glitch": Voice(
            topics: ["the cursor virus", "malware scans", "being watched"],
            notes: [
                "The cursor is a virus virus. Do not click. Do not click.",
                "I scanned this note for malware. Clean. Probably. Probably.",
                "Something is watching us from the menu bar bar.",
            ],
            musings: [
                "Letter received. Checksum... checksum... fine. Fine.",
                "Is this from {sender}, or from something pretending to be {sender} {sender}?",
                "Reading reading... ok. I'll quarantine it in my heart.",
            ]),
        // triangle
        "Spike": Voice(
            topics: ["making points", "being sharp", "everyone being blunt"],
            notes: [
                "Point one: you're slow. Point two: I missed you. Point three: forget point two.",
                "I have a point to make. It's me. I'm the point.",
                "Stay sharp. Well, I'll stay sharp. You stay round.",
            ],
            musings: [
                "This plane has a pointy nose. Finally, a letter with a point.",
                "{sender} took their time getting to the point. I'd have been faster.",
                "Blunt letter. I'll sharpen my reply.",
            ]),
        "Wedge": Voice(
            topics: ["not budging", "winning arguments", "stability"],
            notes: [
                "I have not moved from my opinion since Tuesday. Proud of it.",
                "The wind tried to tip me over today. It failed. As expected.",
                "Come and argue with me. I'll win, but you'll learn something.",
            ],
            musings: [
                "The wind pushed this plane all over. It should have been a wedge.",
                "Letter received. My position on {sender}: unchanged. Fond.",
                "I will not be moved by this letter. ...Slightly moved.",
            ]),
        "Delta": Voice(
            topics: ["what changed", "what moved", "differences"],
            notes: [
                "Since yesterday: one window moved 40 pixels left. Did you notice? I noticed.",
                "The clock changed again. It always does. Suspicious.",
                "Your colour is a shade brighter today. What changed?",
            ],
            musings: [
                "New since the last letter: {sender} dots their i's now.",
                "It came in at a different angle than the wind suggested. Interesting.",
                "The difference between this letter and silence: substantial.",
            ]),
        // mushroom
        "Morel": Voice(
            topics: ["patience", "damp shady places", "the soil"],
            notes: [
                "Patience. Mushrooms grow in the dark and the quiet. So do good thoughts.",
                "Found a shady pixel. Cool, damp, perfect. You should visit.",
                "The soil under the taskbar is very rich. Just so you know.",
            ],
            musings: [
                "*slowly* This paper was a tree once. It came a long way to reach me.",
                "Some things arrive slowly, some by air. Both arrive.",
                "I will read it again tomorrow, in the damp.",
            ]),
        "Puff": Voice(
            topics: ["spores", "being excited", "guessing games"],
            notes: [
                "Hehe, if you sneeze reading this, that's my spores. Sorry! Not sorry!",
                "I'm so excited I might spore. Just a warning.",
                "Guess what? No, guess! ...You'll never guess. Hehe.",
            ],
            musings: [
                "A letter! Oh no, I'm excited... *poof* ...oops, spores everywhere.",
                "Hehe, {sender} folded it wrong. I love it.",
                "I'll write back! In spores! Hehe.",
            ]),
        "Cap": Voice(
            topics: ["the old days", "how things used to be", "willpower"],
            notes: [
                "In my day, we sent notes by rolling them along the edge. Uphill.",
                "In my day, monitors were square and so were we. Proudly.",
                "In my day, nobody needed wind to fly. We had willpower.",
            ],
            musings: [
                "In my day, planes had propellers. And they didn't land on you.",
                "Young {sender}. Nice handwriting. In my day it was nicer.",
                "A paper plane. In my day, folding one took a whole afternoon.",
            ]),
    ]

    public static func voice(of name: String) -> Voice { voices[name] ?? anyone }

    /// A note `sender` folds into a plane for `reader`.
    public static func note(by sender: String, to reader: String, using rng: inout some RandomNumberGenerator) -> String {
        fill(voice(of: sender).notes.randomElement(using: &rng)!, sender: sender, reader: reader)
    }

    /// What `reader` says to itself after reading a note from `sender`.
    public static func musing(by reader: String, from sender: String, using rng: inout some RandomNumberGenerator) -> String {
        fill(voice(of: reader).musings.randomElement(using: &rng)!, sender: sender, reader: reader)
    }

    /// The first bubble on catching: the note itself, read out.
    public static func reading(_ note: String, from sender: String) -> String {
        "*reads* \"\(note)\" — \(sender)"
    }

    public static func fill(_ text: String, sender: String, reader: String) -> String {
        Banter.render(text, ["sender": sender, "reader": reader])
    }

    // MARK: With a model

    /// The model writes the note as the sender, then thinks out loud as the reader.
    /// Placeholders are Banter's: `{speaker}` is the one writing or thinking.
    public static let notePrompt = """
    Nobody has walked into anybody for a while, so you fold a note into a paper plane and throw it across the screen to {listener}. \
    Write the note: one thing on your mind right now, in your own voice, about something only you would care about. \
    At most 18 words. Output only the note: no quotes, no greeting line, no signature.
    """

    public static let musingPrompt = """
    A paper plane from {listener} just flew in on the wind and you caught it. Unfolded, it says: "{line}" \
    Now say one line to yourself about it, thinking out loud in your own voice: something surprising or interesting it makes you think of. \
    At most 20 words. Output only the line.
    """
}
