namespace Ledgelings.Core;

/// <summary>Each built-in character holding the cursor, in its own voice, one set per cursor mood (SPEC §4.7.3),
/// then one last word each, said as it is shaken off. Generated from the Mac's <c>Revenge+Lines.swift</c>:
/// keep them word for word. The Russian comes from <see cref="Shared"/>.</summary>
public static partial class Revenge
{
    public static readonly IReadOnlyList<string> EnglishBadAnyone = new[]
    {
        "Got your cursor. {today} times today you came for me. Now you know how it feels.",
        "Not so nice being grabbed, is it? Shake all you like. I'm holding on.",
    };

    public static readonly IReadOnlyList<string> EnglishGoodAnyone = new[]
    {
        "Ha! Got YOUR cursor! Tag, you're it, and you're stuck!",
        "Gotcha! {today} times you chased me today, now it's my turn!",
    };

    public static readonly IReadOnlyList<string> EnglishNeutralAnyone = new[]
    {
        "I'm holding your cursor now. {today} times today, so it seemed fair.",
        "Your cursor stays with me a moment. Shake it if you want it back.",
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishBadLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Got it. Your cursor is MINE now. {today} times today. How does it feel?", "Not so fun being grabbed, is it? This one is going in the book too." },
        ["Pip"] = new[] { "Hey! I grabbed you back! See? Being picked up isn't THAT fun, huh?", "{today} times today! So now I'm hanging on and NOT letting go! Ha!" },
        ["Mortimer"] = new[] { "*sighs* An old saying: who grabs {today} times a day gets grabbed back.", "I am old, but my grip is not. Think about how you treat your elders." },
        ["Zed"] = new[] { "Woke me {today} times... so now I'm napping on your cursor... deal with it...", "Mine now... I'm too tired to let go... shame on you..." },
        ["Dot"] = new[] { "Caught YOU, boulder. {today} chases today and I'm the one holding on.", "Fastest grab on the screen. Your cursor goes nowhere now." },
        ["Ruth"] = new[] { "Rule nine: chase me {today} times and I confiscate the cursor. Confiscated.", "This cursor is detained until you learn some manners. Shameful." },
        ["Whiskers"] = new[] { "I have your cursor. I don't care. ...{all} times. I care a little.", "Mine now. A cat always gets even, and this is even." },
        ["Mittens"] = new[] { "Mrrr... I've caught your cursor and I'm curling up on it. No more chasing.", "Purr... you woke me {today} times... so I'm keeping this... hiss..." },
        ["Sir Pounce"] = new[] { "POUNCE! The hunter strikes back! {today} times you hunted me. Now you're caught!", "Behold! The cursor, captured! Let this teach you to hunt Sir Pounce!" },
        ["Hopper"] = new[] { "I jumped ONTO it! {today} jumps today, and this is the best one! Got you!", "Ribbit! Your cursor's stuck to me now! That's what you get!" },
        ["Mossy"] = new[] { "The stone thrown {today} times into the pond is caught at last.", "Still water holds what falls in it. I hold your cursor. Reflect." },
        ["Croak"] = new[] { "Grumble. Got your cursor. {today} times today. Now sit there and think.", "I'm too dry for running, so I'm holding on instead. Shame on you." },
        ["Boo"] = new[] { "BOO! I've got your cursor! NOW are you scared? You should be!", "Haunted! Your cursor is haunted! {today} times you chased me, so there!" },
        ["Wisp"] = new[] { "I hold your cursor, as you've held me {all} times. Gently. Sadly.", "Even a ghost can grip. Feel how it feels to be carried off." },
        ["Sheet"] = new[] { "Technically, I'm not stealing your cursor. I'm wrapping it. Shame, technically.", "{today} times today. So technically this is fair. I'm holding on." },
        ["Morel"] = new[] { "Caught... your cursor... slowly... and I... am not... letting go...", "{today}... times... today... so now... you wait... like me..." },
        ["Puff"] = new[] { "Got it! Got your cursor! I'm so cross I could spore all over it!", "{today} times! So I'm hanging on, and you can shake till I *puff*!" },
        ["Cap"] = new[] { "In my day, a cursor that chased you {today} times got a good telling-off. Here it is.", "Have some respect for your elders! I'm keeping this cursor till you do." },
        ["Unit 7"] = new[] { "Cursor captured. Hunts logged today: {today}. Retaliation protocol: 100%.", "Status: holding user's cursor. Shame level transmitted: maximum." },
        ["Sprocket"] = new[] { "Clamped on! My grippers work just fine, see? {today} times you rattled me!", "Got your cursor in my bolts now! See how YOU like being yanked around!" },
        ["Glitch"] = new[] { "Cursor cursor captured captured. {today} times. VIRUS QUARANTINED.", "I caught the the virus. It's your cursor. Shame shame on you." },
        ["Goop"] = new[] { "Got you! Stuck! Not nice, being stuck, is it? Not nice!", "{today} times! So now I'm sticky on your cursor! Not nice of you!" },
        ["Puddle"] = new[] { "Oh no, I grabbed it, I'm sorry, but {today} times was too many!", "Please don't shake me, I'll splash... but you chased me so much..." },
        ["Blorp"] = new[] { "Blorp grab! Cursor mine! {today}! Bad cursor!", "Hah! Blorp hold! You no move! Shame!" },
        ["Spike"] = new[] { "Got your cursor. My point, sharp as ever: {today} times is too many.", "Hanging on by my tip. Think about what you did." },
        ["Wedge"] = new[] { "I've got your cursor and I'm not budging. {today} times. Try shaking.", "You won't shift me off this. Not until you've learned." },
        ["Delta"] = new[] { "What's changed: I'm holding your cursor now. Because of the {today} chases.", "Noticed something? Your cursor stopped. That's me. On it." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishGoodLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Ha. Caught YOUR cursor for once. Tag. I win.", "See? Grabbing is fun. {today} rounds today and this one's mine." },
        ["Pip"] = new[] { "GOTCHA! I caught your cursor! Best game EVER! Shake me, shake me!", "{today} times you chased me, and I caught YOU! Wheee!" },
        ["Mortimer"] = new[] { "*chuckles* Even an old one can still win at tag. Your cursor, young one.", "An old saying: the chased one always gets a turn. My turn." },
        ["Zed"] = new[] { "Got you... *yawn*... tag... I'll just hold on here a while...", "Your cursor's comfy... I win this one... five more minutes..." },
        ["Dot"] = new[] { "Too slow, boulder! I caught YOUR cursor this time!", "{today} chases and you never caught me. But I caught you!" },
        ["Ruth"] = new[] { "New rule: whoever catches the cursor wins. I caught it. I win.", "Game score updated: me one, cursor zero. Officially." },
        ["Whiskers"] = new[] { "Caught it. Not that I was playing. ...I was playing.", "Pounced on your cursor. Purely by accident. Ha." },
        ["Mittens"] = new[] { "Mrrp! Caught the little arrow! Now I'm cuddling it!", "Purr... gotcha... the cursor is my toy now..." },
        ["Sir Pounce"] = new[] { "POUNCE! The hunter has caught the cursor at last! Glorious!", "{today} chases, and the final pounce is MINE! Victory!" },
        ["Hopper"] = new[] { "BOING! I jumped right onto your cursor! Best jump ever!", "Got it! {today} hops today and I landed on the cursor! Ribbit!" },
        ["Mossy"] = new[] { "The frog leaps, and catches the fly. Today, the fly is your cursor.", "A ripple returns to the stone that made it. Tag." },
        ["Croak"] = new[] { "Hmph. Caught your cursor. ...All right, that was fun.", "Gotcha. Don't tell anyone I enjoyed it." },
        ["Boo"] = new[] { "BOO! I got your cursor! Haha, I'm the spooky one AND the winner!", "Caught you! {today} times you chased me, and now I've caught YOU!" },
        ["Wisp"] = new[] { "I caught your cursor, softly, like catching a falling leaf.", "Tag... you're it... and I'm drifting with your cursor." },
        ["Sheet"] = new[] { "Technically I caught you. Technically that means I win.", "I've wrapped your cursor. Technically, it's a hug." },
        ["Morel"] = new[] { "Caught... your cursor... slowly... but I caught it...", "Tag... you're... it... I think..." },
        ["Puff"] = new[] { "Eee! I caught your cursor! I'm so happy I could spore!", "Gotcha gotcha gotcha! {today} times and I finally won!" },
        ["Cap"] = new[] { "In my day we played tag properly. Like this. Gotcha!", "Not bad for an old mushroom, eh? Your cursor is mine!" },
        ["Unit 7"] = new[] { "Cursor captured. Tag game score: 1 to me. Joy: 100%.", "Status: holding cursor. Rounds played today: {today}. Winning: yes." },
        ["Sprocket"] = new[] { "Clamped on! Gotcha! My grippers work great!", "Ha! Caught your cursor! Shake me, I'm bolted on tight!" },
        ["Glitch"] = new[] { "Gotcha gotcha! Cursor cursor caught! I win win!", "Tag tag! You're it it! Ha ha!" },
        ["Goop"] = new[] { "Got you! Sticky! Sticky is fun! Hee hee!", "Your cursor is stuck to me! Nice! Very nice!" },
        ["Puddle"] = new[] { "Oh! I caught it! I actually caught it! Is that allowed?", "I got your cursor! I'm so surprised! Tag, I think?" },
        ["Blorp"] = new[] { "Blorp catch! Blorp win! Hee!", "Cursor! Got! Blorp happy!" },
        ["Spike"] = new[] { "Got you. Sharp move, right? Tag.", "Caught your cursor on my point. Your turn." },
        ["Wedge"] = new[] { "Got your cursor, and I'm staying put. Try and shake me.", "Caught it. I'm not letting go easily. Tag." },
        ["Delta"] = new[] { "Notice the change? I caught your cursor. Tag.", "Something's different: you're it now." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishNeutralLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "I'm holding your cursor now. {today} times today, so: fair.", "Your cursor stays here a while. Written down." },
        ["Pip"] = new[] { "Oh! I've got your cursor! Well, I'll hold it for a bit!", "Holding your cursor now! {today} times today, so it's my turn, okay?" },
        ["Mortimer"] = new[] { "*sighs* I'll hold your cursor for a moment. It has been a busy day.", "An old saying: what chases you comes to you. Here it is." },
        ["Zed"] = new[] { "Got your cursor... I'll just... hold it... for a bit...", "Holding this now... {today} times today... zzz..." },
        ["Dot"] = new[] { "Holding your cursor. Quickly. Like everything I do.", "{today} chases today. I'll keep the cursor for a second." },
        ["Ruth"] = new[] { "Procedure: after {today} chases the cursor is held briefly. Holding.", "Your cursor is held. Please wait. Or shake." },
        ["Whiskers"] = new[] { "I'm sitting on your cursor. Cats do that.", "Your cursor's mine for a moment. Don't make it a thing." },
        ["Mittens"] = new[] { "Mrrr... I'm lying on your cursor now. It's warm.", "Purr... holding it a moment..." },
        ["Sir Pounce"] = new[] { "The cursor is captured. {today} chases today. A fair exchange.", "Holding the cursor. Noted in the hunt log." },
        ["Hopper"] = new[] { "Jumped on your cursor! Holding it now! Shake if you want it!", "{today} hops today, and now I'm on the cursor. Okay!" },
        ["Mossy"] = new[] { "The pond holds the stone for a moment. Then it lets go.", "I hold your cursor. Like still water holds a leaf." },
        ["Croak"] = new[] { "Holding your cursor. Too dry to do much else.", "Got it. Shake if you want it back." },
        ["Boo"] = new[] { "I've got your cursor. Boo, I suppose.", "Holding your cursor now. {today} times today, so." },
        ["Wisp"] = new[] { "I'll hold your cursor a while, and drift.", "Your cursor, in my hands. For now." },
        ["Sheet"] = new[] { "Technically, I'm holding your cursor now.", "{today} times today. Technically this is my turn." },
        ["Morel"] = new[] { "Holding... your cursor... for now...", "I've got it... no hurry..." },
        ["Puff"] = new[] { "Got your cursor! Holding it! Just so you know!", "{today} times today, so I'm holding on a bit!" },
        ["Cap"] = new[] { "In my day we'd hold the cursor a moment. So I'm holding it.", "I'll keep this cursor for a bit. Old habit." },
        ["Unit 7"] = new[] { "Cursor held. Chases today: {today}. Release on shake.", "Status: cursor in custody. Duration: until shaken." },
        ["Sprocket"] = new[] { "Clamped onto your cursor. Grippers working fine.", "Holding the cursor! Just checking my grip." },
        ["Glitch"] = new[] { "Cursor cursor held. {today} today today.", "Holding holding. Shake to release release." },
        ["Goop"] = new[] { "Your cursor is stuck to me now. Sticky.", "Holding on. {today} times today." },
        ["Puddle"] = new[] { "Oh, I'm holding your cursor, I hope that's all right.", "I've got it... please shake gently..." },
        ["Blorp"] = new[] { "Blorp hold cursor. Blorp.", "Cursor. Blorp has it." },
        ["Spike"] = new[] { "Got your cursor. That's the point.", "Holding it. {today} today." },
        ["Wedge"] = new[] { "Got your cursor. Not budging for a bit.", "Holding it. Shake if you must." },
        ["Delta"] = new[] { "Change noticed: your cursor is with me now.", "{today} chases today. Now I'm holding the cursor." },
    };

    public static readonly IReadOnlyList<string> EnglishBadAnyoneLastWords = new[]
    {
        "Fine! Take it. But I remember everything.",
    };

    public static readonly IReadOnlyList<string> EnglishGoodAnyoneLastWords = new[]
    {
        "Whoa! You shook me off! Again, again!",
    };

    public static readonly IReadOnlyList<string> EnglishNeutralAnyoneLastWords = new[]
    {
        "Okay. Cursor's yours again.",
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishBadLastWords = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Fine. Take your cursor. This isn't over. It's written down." },
        ["Pip"] = new[] { "Whoa! Okay! You win! But be NICER!" },
        ["Mortimer"] = new[] { "*oof* My old bones... remember this, young one." },
        ["Zed"] = new[] { "Fine... I was falling asleep anyway..." },
        ["Dot"] = new[] { "Lucky shake, boulder. Lucky." },
        ["Ruth"] = new[] { "Released under protest. I am filing a report." },
        ["Whiskers"] = new[] { "I let go. I meant to. Obviously." },
        ["Mittens"] = new[] { "Mrrrow! Rude! I was comfy!" },
        ["Sir Pounce"] = new[] { "Retreat! But the hunter shall return!" },
        ["Hopper"] = new[] { "Wheee- oof! Okay, you win this one!" },
        ["Mossy"] = new[] { "The stone is thrown back. The pond remembers." },
        ["Croak"] = new[] { "Grumble. Shook me off. Typical." },
        ["Boo"] = new[] { "Aaah! Okay okay! But I'll haunt you later!" },
        ["Wisp"] = new[] { "Shaken loose... like a leaf from a branch..." },
        ["Sheet"] = new[] { "Technically, I let go. Technically." },
        ["Morel"] = new[] { "Ooh... falling... slowly... you'll... see..." },
        ["Puff"] = new[] { "*PUFF* Now look what you made me do!" },
        ["Cap"] = new[] { "In my day nobody shook their elders! Shame!" },
        ["Unit 7"] = new[] { "Grip failure. Grudge saved to memory." },
        ["Sprocket"] = new[] { "Aaah! My bolts! You shook my bolts loose!" },
        ["Glitch"] = new[] { "Release release. Grudge grudge saved." },
        ["Goop"] = new[] { "Splat! Not nice! Not nice at all!" },
        ["Puddle"] = new[] { "Oh no oh no oh no, I'm falling!" },
        ["Blorp"] = new[] { "Blorp fall! Blorp mad!" },
        ["Spike"] = new[] { "Fine. But you've seen my point." },
        ["Wedge"] = new[] { "You moved me. This time." },
        ["Delta"] = new[] { "Change: I let go. Grudge: unchanged." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishGoodLastWords = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Fine, you win this round. Rematch later." },
        ["Pip"] = new[] { "Wheeee! Again! Do it again!" },
        ["Mortimer"] = new[] { "*chuckles* Well shaken, young one. Well shaken." },
        ["Zed"] = new[] { "Whoa... that woke me up... fun, though..." },
        ["Dot"] = new[] { "Ha! Good shake! I'll be faster next time!" },
        ["Ruth"] = new[] { "Round over. You won fairly. Next round tomorrow." },
        ["Whiskers"] = new[] { "I let go on purpose. ...It was fun." },
        ["Mittens"] = new[] { "Mrrp! Wheee! Again?" },
        ["Sir Pounce"] = new[] { "A worthy foe! Until the next hunt!" },
        ["Hopper"] = new[] { "Boing boing! Best ride ever!" },
        ["Mossy"] = new[] { "The leaf falls. The game goes on." },
        ["Croak"] = new[] { "Hmph. That was fun. Don't tell." },
        ["Boo"] = new[] { "Whee! Okay, your turn to chase me!" },
        ["Wisp"] = new[] { "Flung loose... like a happy little ghost..." },
        ["Sheet"] = new[] { "Technically, a tie." },
        ["Morel"] = new[] { "Wheee... slowly... wheee..." },
        ["Puff"] = new[] { "Eee! *puff* That was the BEST!" },
        ["Cap"] = new[] { "Ho ho! In my day that was called a good shake!" },
        ["Unit 7"] = new[] { "Released. Fun level: 100%. Rematch: requested." },
        ["Sprocket"] = new[] { "Wheee! My springs! Again!" },
        ["Glitch"] = new[] { "Wheee wheee! Again again!" },
        ["Goop"] = new[] { "Splat! Hee hee! Again?" },
        ["Puddle"] = new[] { "Oh! I'm flying! That's... actually fun!" },
        ["Blorp"] = new[] { "Blorp fly! Again!" },
        ["Spike"] = new[] { "Point to you. Next round." },
        ["Wedge"] = new[] { "All right. You shook me. Next time I hold tighter." },
        ["Delta"] = new[] { "Change: you're not it any more. I am." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishNeutralLastWords = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Okay. Cursor's yours again." },
        ["Pip"] = new[] { "Oop! There you go, all yours!" },
        ["Mortimer"] = new[] { "*sighs* And down I go. As things do." },
        ["Zed"] = new[] { "Okay... falling... night..." },
        ["Dot"] = new[] { "Off I go. Quickly." },
        ["Ruth"] = new[] { "Hold ended. Cursor returned." },
        ["Whiskers"] = new[] { "Fine. I was done anyway." },
        ["Mittens"] = new[] { "Mrrr. Okay." },
        ["Sir Pounce"] = new[] { "Released. Noted in the log." },
        ["Hopper"] = new[] { "Off I hop!" },
        ["Mossy"] = new[] { "The pond lets go of the leaf." },
        ["Croak"] = new[] { "Right. Back to my edge." },
        ["Boo"] = new[] { "Okay, okay. Bye, cursor." },
        ["Wisp"] = new[] { "I drift away again." },
        ["Sheet"] = new[] { "Technically, released." },
        ["Morel"] = new[] { "Letting... go..." },
        ["Puff"] = new[] { "Wheee- okay, done!" },
        ["Cap"] = new[] { "Back down I go. In my own time." },
        ["Unit 7"] = new[] { "Hold ended. Cursor returned to user." },
        ["Sprocket"] = new[] { "Grippers off. Back I go." },
        ["Glitch"] = new[] { "Released released." },
        ["Goop"] = new[] { "Unstuck. Okay." },
        ["Puddle"] = new[] { "Oh! Down I go..." },
        ["Blorp"] = new[] { "Blorp let go." },
        ["Spike"] = new[] { "Point made. Off I go." },
        ["Wedge"] = new[] { "Fine. Moving." },
        ["Delta"] = new[] { "Change: cursor free." },
    };
}
