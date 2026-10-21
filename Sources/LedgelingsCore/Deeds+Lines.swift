import Foundation

/// The built-in lines for deeds: how each character invites another to a game
/// or to tea, and how it says yes or no, in its own voice. `{reader}` is the one
/// spoken to, `{game}` the offer in a word ("Soccer", "Tea together"), standing
/// alone so it reads right in either language. A character the user made uses
/// `anyone`. The Russian is in `Deeds+Russian.swift`.
extension Deeds {

    public struct Voice: Equatable, Sendable {
        public var invite: String
        public var yes: String
        public var no: String
        public init(invite: String, yes: String, no: String) { self.invite = invite; self.yes = yes; self.no = no }
    }

    public static let anyones = Translated(english: englishAnyone, [.russian: russianAnyone])
    public static let voiceSets = Translated(english: englishVoices, [.russian: russianVoices])

    public static func voice(of name: String) -> Voice { voiceSets()[name] ?? anyones() }

    /// `sender`'s invitation to `reader`.
    public static func inviteLine(by sender: String, to reader: String, _ offer: Offer) -> String {
        CursorMood.current.adjust(Banter.render(voice(of: sender).invite, ["reader": reader, "game": offer.word]))
    }

    /// `writer`'s answer to `inviter`'s invitation.
    public static func answerLine(by writer: String, to inviter: String, _ offer: Offer, yes: Bool) -> String {
        let v = voice(of: writer)
        return CursorMood.current.adjust(Banter.render(yes ? v.yes : v.no, ["reader": inviter, "game": offer.word]))
    }

    public static let englishAnyone = Voice(
        invite: "{reader}! {game}? You and me, right now.",
        yes: "{game}? Yes! Lead the way, {reader}.",
        no: "Not now, {reader}. Ask me again later.")

    public static let englishVoices: [String: Voice] = [
        // blocky's cast
        "Blocky": Voice(invite: "{reader}. {game}. Bottom edge. Unless you're scared of losing.",
                        yes: "Fine. {game}. But on a respectable edge, {reader}.",
                        no: "No. The cursor is watching. Another time, {reader}."),
        "Pip": Voice(invite: "{reader}! {game}! Please please please? It'll be the best!",
                     yes: "Yes! Yes yes yes! {game} with {reader}! Wheee!",
                     no: "Aww. Not now, {reader}... but soon? Promise?"),
        "Mortimer": Voice(invite: "As the old corner says: {game} shared is time well lost. Will you, {reader}?",
                          yes: "*sighs* Very well, {reader}. {game}. At a dignified pace.",
                          no: "Not today, {reader}. The window says rest, and the window is wise."),
        "Zed": Voice(invite: "mm... {reader}... {game}...? after... one tiny nap...",
                     yes: "...okay, {reader}... {game}... wake me if I... zzz... I'm up. I'm up.",
                     no: "...no... too sleepy, {reader}... tomorrow... maybe..."),
        // ...the blocky cast continues
        "Dot": Voice(invite: "{reader}! {game}! Now! Fast! I'll win in four seconds flat!",
                     yes: "{game}? GO! Try to keep up, {reader}!",
                     no: "No time, {reader}! Busy being fast! Later! Faster!"),
        "Ruth": Voice(invite: "{reader}, by my count we owe each other one round of {game}. Shall we?",
                      yes: "Agreed. {game}, by the rules. I'll keep the score, {reader}.",
                      no: "Declined, {reader}. That would be our third this hour. Rules."),
        // cats
        "Whiskers": Voice(invite: "Not that I care, {reader}, but... {game}? If you've nothing better.",
                          yes: "Fine. {game}. Don't make it a big thing, {reader}.",
                          no: "Can't be bothered, {reader}. Ask the warm spot."),
        "Mittens": Voice(invite: "Purr... {reader}, {game}? Then a warm corner after?",
                         yes: "Mrrr, yes. {game}, then a nap in the sun, {reader}.",
                         no: "Mm, no, {reader}. This pixel is too warm to leave."),
        "Sir Pounce": Voice(invite: "{reader}! A worthy foe at last. {game}, tonight's hunt starts now!",
                            yes: "Accepted! {game}. Prepare yourself, {reader}!",
                            no: "Not now, {reader}. A hunter chooses his hour."),
        // frogs
        "Hopper": Voice(invite: "{reader}! {game}! I'll jump higher than you ever will. Leg day!",
                        yes: "{game}? Watch these legs, {reader}! Let's go!",
                        no: "Can't, {reader}. Resting the legs. Champions rest."),
        "Mossy": Voice(invite: "The still pond waits, {reader}, but a little {game} ripples nicely.",
                       yes: "Yes, {reader}. {game}, slowly, like water finding its way.",
                       no: "Not now, {reader}. Stillness first. The pond says so."),
        "Croak": Voice(invite: "Everything's dry anyway, {reader}. {game}? Might as well.",
                       yes: "Fine, {game}. It won't rain anyway, {reader}.",
                       no: "Too dry for that, {reader}. Too dry for anything."),
        // ghosts
        "Boo": Voice(invite: "BOO! {game}, {reader}! ...that was the scary part. Coming?",
                     yes: "Boo-yes! {game}! I'll haunt you all the way, {reader}!",
                     no: "Boo... not now, {reader}. Practising my boos."),
        "Wisp": Voice(invite: "{reader}... {game}... like on the old screens, before they faded?",
                      yes: "Yes... {game}, {reader}, while I'm still here.",
                      no: "Not now, {reader}... I'm fading a little today."),
        "Sheet": Voice(invite: "Technically, {reader}, {game} is allowed. I checked. Shall we?",
                       yes: "Technically yes, {reader}. {game}. I'll hover.",
                       no: "Technically I'm busy, {reader}. Being flat takes effort."),
        // slimes
        "Goop": Voice(invite: "{reader}! {game}? It'll be nice! And a bit sticky!",
                      yes: "Ooh, {game}! Nice AND sticky! Yes, {reader}!",
                      no: "Not now, {reader}, I'm stuck. Nicely stuck, though."),
        "Puddle": Voice(invite: "{reader}, would you... {game}? If I haven't evaporated by then?",
                        yes: "{game}? Okay, {reader}... just don't step on me.",
                        no: "I'd better not, {reader}... I might evaporate. Sorry."),
        "Blorp": Voice(invite: "Blorp! {reader}! {game}! Blorp blorp?",
                       yes: "BLORP! {game}! Blorp, {reader}!",
                       no: "blorp... no, {reader}. blorp later."),
        // robots
        "Unit 7": Voice(invite: "{reader}. Proposal: {game}. My odds of winning: 61%. Accept?",
                        yes: "Accepted, {reader}. {game}. Recalculating odds: 63%.",
                        no: "Declined, {reader}. Battery at 12%. Rescheduling."),
        "Sprocket": Voice(invite: "{reader}! {game}? Just tightened my bolts for it.",
                          yes: "{game}! Oil's fresh, let's go, {reader}!",
                          no: "Not now, {reader}, a part is squeaking. Maintenance first."),
        "Glitch": Voice(invite: "{reader}, quick, {game}, before the cursor scans us!",
                        yes: "Yes, {reader}, {game}! Keep moving, it can't track a moving target!",
                        no: "No, {reader}! The cursor is watching! Scanning... later."),
        // triangles
        "Spike": Voice(invite: "{reader}. {game}. Point is, you'll lose.",
                       yes: "{game}? Sharp. You're on, {reader}.",
                       no: "Pointless, {reader}. Not now."),
        "Wedge": Voice(invite: "{reader}, {game}. I won't budge from that.",
                       yes: "{game}. Agreed, {reader}. And I don't change my mind.",
                       no: "No, {reader}. I'm not budging. Not for {game}."),
        "Delta": Voice(invite: "Something changed, {reader}: I want {game}. Do you?",
                       yes: "Noted, {reader}: {game}. That changes everything.",
                       no: "Not now, {reader}. Too much has moved already today."),
        // mushrooms
        "Morel": Voice(invite: "When you're ready, {reader}... {game}? There's no hurry.",
                       yes: "Yes, {reader}. {game}. Slowly, like good soil.",
                       no: "Not yet, {reader}. Some things need more time."),
        "Puff": Voice(invite: "{reader}! {game}! Guess what I'm thinking! It's {game}!",
                      yes: "Yes! {game}! Spores everywhere, {reader}! Hee!",
                      no: "Ohh, not now, {reader}! Guess why! ...I'm not telling!"),
        "Cap": Voice(invite: "In my day, {reader}, we played {game} till the screen went dark. Well?",
                     yes: "{game}? Like the old days, {reader}. Off we go.",
                     no: "Not today, {reader}. In my day we knew when to rest."),
    ]
}
