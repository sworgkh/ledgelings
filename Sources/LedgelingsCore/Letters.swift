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
        /// What it writes back, once, to whoever sent it a plane.
        public var replies: [String]
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
        ],
        replies: [
            "Got your plane, {reader}. Sending this one back on the same wind.",
            "Thanks for the letter. Nobody writes any more. Except you, apparently.",
            "Read it twice. Folding you an answer before I forget.",
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
            ],
            replies: [
                "Received. Filed under 'things I did not ask for'. ...Keep them coming.",
                "{reader}. Your plane crossed MY airspace. Next time, knock.",
                "Fine. A reply. Short, because the cursor is watching.",
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
            ],
            replies: [
                "I got your plane!!! I screamed! Happily! Write again!",
                "Your letter made my whole ceiling brighter! Sending all my happy back!",
                "Best letter ever! Well, the only one. Still best!",
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
            ],
            replies: [
                "An old saying: a letter answered is a friend kept. I just made that up for you.",
                "Your words arrived like a slow thought. I have been chewing on them. *sighs*",
                "Thank you, young {reader}. I will answer properly next century.",
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
            ],
            replies: [
                "Got it. Replying before I fall asl-",
                "Nice letter. Read it lying down. Very comfy.",
                "Writing back quick, then nap. Priorities.",
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
            ],
            replies: [
                "Replied before your plane even landed. Keep up.",
                "Got it. Read it. Answered it. Beat that.",
                "Short reply, because I'm fast and you're a boulder.",
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
            ],
            replies: [
                "Letter received at the proper time. Reply enclosed. Please file both.",
                "Your note has been counted, stamped and logged. Response: noted.",
                "Next time use the correct fold. This is a reply AND a reminder.",
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
            ],
            replies: [
                "I read it. By accident. Anyway, what are you doing now?",
                "Not replying because I care. Replying because I was bored.",
                "Your letter was acceptable. You may send another.",
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
            ],
            replies: [
                "Purrr, thank you. I read it in the warmest spot. Come share it.",
                "Mrrp! Your letter was cozy. Sending a cozy one back.",
                "I napped on your letter. That means I love it.",
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
            ],
            replies: [
                "Message intercepted and understood. The hunt continues, ally.",
                "Your plane was a worthy prey. I caught it. Here is its twin.",
                "Word received! I shall pounce upon a reply. There. Pounced.",
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
            ],
            replies: [
                "Got your plane! I'd have jumped it back, but paper's faster. Today.",
                "Replying with my strongest legs. Metaphorically.",
                "Nice letter. I read it mid-hop. Nearly.",
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
            ],
            replies: [
                "As the pond says: every ripple returns to the stone. Here is mine.",
                "Your note sank in slowly, like a good rain. Thank you.",
                "*slowly* I have replied. It took all afternoon.",
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
            ],
            replies: [
                "Got your letter. It was dry. Like everything. Thanks anyway.",
                "Replying. Grudgingly. With a wet thumb.",
                "Your plane made it. Unlike the rain.",
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
            ],
            replies: [
                "BOO! That was my reply. Were you scared? Be honest.",
                "Got your letter! Haunting you back with this one.",
                "I wrote back in spooky ink. It's invisible. Oops.",
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
            ],
            replies: [
                "Your letter glowed, dear. I sent this one on a sigh.",
                "I will keep your words beside the old monitors I remember.",
                "Writing back before the pixels forget us both.",
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
            ],
            replies: [
                "Reply: technically received. Technically replying. Flatly.",
                "Got your plane. It hovered. We have that in common.",
                "This is a reply. It is also a sheet. Like me.",
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
            ],
            replies: [
                "Got it! Nice! Sticky now! Sending back nice!",
                "Your letter is nice. This letter is also nice.",
                "Reply! Very nice! Bye!",
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
            ],
            replies: [
                "Got it! Did I spell everything right? Please don't worry if I didn't. I will.",
                "Thank you. I replied quickly before I dry out.",
                "Your letter was lovely. I only shrank a little reading it.",
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
            ],
            replies: [
                "Blorp! Blorp blorp! (Thank you.)",
                "Splorch! Got it! Fwoop back!",
                "BLORP. Me write back. Me proud.",
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
            ],
            replies: [
                "Acknowledgement: letter received. Reply generated in 0.3 seconds.",
                "Response to your message: positive. Friendship level: +4.",
                "Reply transmitted. Please confirm receipt by paper plane.",
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
            ],
            replies: [
                "Got your plane! Tightened a loose fold and sent it back better.",
                "Reply attached. Also, your wing needs a little oil.",
                "Thanks! Maintenance tip enclosed: stay squeak-free.",
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
            ],
            replies: [
                "Reply reply sent. Scanned it twice. Twice.",
                "Letter received. Not a virus. Probably. Replying replying.",
                "Got it got it. Sending this one before the cursor sees.",
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
            ],
            replies: [
                "Got your point. Here's mine. Sharper.",
                "Reply, to the point: thank you. Point made.",
                "Your letter was blunt. Mine is pointier. You're welcome.",
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
            ],
            replies: [
                "I have read your letter and my opinion has not changed. It is fond.",
                "Replying firmly. Like everything I do.",
                "Your plane wobbled. My reply will not.",
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
            ],
            replies: [
                "Change noted: you write letters now. I approve of this change.",
                "Reply sent. Since your letter, one thing is different: me, a bit.",
                "Your plane took a new route. So does my reply.",
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
            ],
            replies: [
                "*slowly* Your words rested with me a while. Here are mine.",
                "Thank you. I read it in a damp, quiet corner. The best place.",
                "Patience brought your letter. Patience sends this one back.",
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
            ],
            replies: [
                "Hehe! Got it! I sporred all over it! Sending it back sporey!",
                "Your letter made me SO excited. Here, have a giggle back.",
                "I wrote back! Guess what it says! No, read it! Hehe!",
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
            ],
            replies: [
                "In my day, we answered letters within the week. I did it in a minute. Progress.",
                "Received, young one. In my day, planes had pilots.",
                "A fine letter. In my day it would have been finer, but fine.",
            ]),
    ]

    public static func voice(of name: String) -> Voice { voices[name] ?? anyone }

    /// A note `sender` folds into a plane for `reader`: one it has not written lately.
    public static func note(by sender: String, to reader: String, memory: LineMemory = LineMemory(limit: 0),
                            using rng: inout some RandomNumberGenerator) -> String {
        fresh(voice(of: sender).notes, by: sender, sender: sender, reader: reader, memory: memory, using: &rng)
    }

    /// What `reader` says to itself after reading a note from `sender`.
    public static func musing(by reader: String, from sender: String, memory: LineMemory = LineMemory(limit: 0),
                              using rng: inout some RandomNumberGenerator) -> String {
        fresh(voice(of: reader).musings, by: reader, sender: sender, reader: reader, memory: memory, using: &rng)
    }

    /// The one answer `writer` sends back to whoever threw it a plane.
    public static func reply(by writer: String, to reader: String, memory: LineMemory = LineMemory(limit: 0),
                             using rng: inout some RandomNumberGenerator) -> String {
        fresh(voice(of: writer).replies, by: writer, sender: writer, reader: reader, memory: memory, using: &rng)
    }

    private static func fresh(_ texts: [String], by who: String, sender: String, reader: String, memory: LineMemory,
                              using rng: inout some RandomNumberGenerator) -> String {
        let filled = texts.map { fill($0, sender: sender, reader: reader) }
        return filled[memory.pick(from: filled, by: who, using: &rng)!]
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
    {situation}
    Nobody has walked into anybody for a while, so you fold a note into a paper plane and throw it across the screen to {listener}. \
    Write the note: one thing on your mind right now, in your own voice, about something only you would care about. \
    At most 18 words. Output only the note: no quotes, no greeting line, no signature.
    """

    /// The answer: `{line}` is the note being answered. Nobody answers an answer.
    public static let replyPrompt = """
    {situation}
    {listener} just threw you a paper plane. Their note said: "{line}" \
    Write your answer to fold into a plane and throw back: one short reply, in your own voice. \
    At most 18 words. Output only the reply: no quotes, no greeting line, no signature.
    """

    public static let musingPrompt = """
    A paper plane from {listener} just flew in on the wind and you caught it. Unfolded, it says: "{line}" \
    Now say one line to yourself about it, thinking out loud in your own voice: something surprising or interesting it makes you think of. \
    At most 20 words. Output only the line.
    """
}
