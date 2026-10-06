namespace Ledgelings.Core;

/// <summary>The good and neutral cursor moods' complaints (SPEC §4.7.1), generated from the Mac's
/// <c>Complaints+Moods.swift</c>: keep them word for word.</summary>
public static partial class Complaints
{
    public static readonly IReadOnlyList<string> EnglishGoodAnyone = new[]
    {
        "Ha! That's {times} times, and you still haven't caught me!",
        "Tag! You're it! Again, again!",
    };

    public static readonly IReadOnlyList<string> EnglishNeutralAnyone = new[]
    {
        "{times} hops in a row. Oh well.",
        "Moved again. That's how it goes.",
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishGoodLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "{times} times and you still haven't caught me. Not that I'm counting. I am.", "Fine. That was almost fun. Tell anyone and I'll deny it." },
        ["Pip"] = new[] { "Again! Again! That's {times}! Tag, you're it!", "Wheee! Best game ever! Chase me to the ceiling!" },
        ["Mortimer"] = new[] { "*chuckles* {times} times. In my youth I'd have led you a merrier dance.", "Ah, a game of tag. My knees object, but my heart is young." },
        ["Zed"] = new[] { "{times} times... fine, *yawn*, you win this round. Nap first, rematch later.", "Tag is fun... sleepy fun... can we play lying down..." },
        ["Dot"] = new[] { "{times} tries and still not even close. Again, slowpoke!", "Too fast for you! Come on, one more lap!" },
        ["Ruth"] = new[] { "Score: me {times}, you nought. Best of fifty?", "Rule two of tag: I win. You may try again." },
        ["Whiskers"] = new[] { "{times} times. I let you chase me. That's how a cat says it likes you.", "Fine, it's a game. I'm only playing because I want to." },
        ["Mittens"] = new[] { "Mrrrow! {times} times! Again, then a nap, then again!", "Purr... a chase and then a cuddle? Yes please." },
        ["Sir Pounce"] = new[] { "{times} pounces dodged! The hunter salutes a worthy foe!", "Ha! None catch Sir Pounce! Try again, brave hunter!" },
        ["Hopper"] = new[] { "{times} jumps! New record! Again, again, again!", "RIBBIT! Chase me higher! I can jump all the way across!" },
        ["Mossy"] = new[] { "{times} ripples on the pond. A pleasant game, friend.", "The frog who plays tag never grows old. Again, if you like." },
        ["Croak"] = new[] { "{times}. Fine. It was fun. Don't let it go to your head.", "Grumble. That was... not terrible. Once more, then water." },
        ["Boo"] = new[] { "Boo! {times} times and you never caught me! Spooky AND fast!", "Hee hee! My turn to chase you next!" },
        ["Wisp"] = new[] { "{times} times we drifted round each other. Almost a dance.", "How lovely, to be chased by someone who only wants to play." },
        ["Sheet"] = new[] { "{times} times. Technically I won every one of them.", "Technically, this is the best game on the screen." },
        ["Morel"] = new[] { "{times}... chases... slow fun... the best kind...", "Again... but slower... mushrooms like... slow games..." },
        ["Puff"] = new[] { "Eee! {times} times! I'm so happy I could spore!", "Hee hee! Again! *puff* *puff*" },
        ["Cap"] = new[] { "In my day we played tag too. {times} rounds! You'd have done well.", "Young people and their games. ...All right, one more." },
        ["Unit 7"] = new[] { "Game log: {times} successful evasions. Enjoyment: 97%.", "Tag protocol active. Score: Unit 7 leading. Continue?" },
        ["Sprocket"] = new[] { "{times} jumps! My gears are spinning with joy!", "Whee! Fully oiled and ready for another round!" },
        ["Glitch"] = new[] { "{times} times! The cursor cursor is fun fun. Again again.", "Scan complete: this is a game. Playing playing." },
        ["Goop"] = new[] { "Wheee! {times} times! Sticky fun!", "Again! I'll bounce extra high!" },
        ["Puddle"] = new[] { "{times} times and I didn't even splash! Was I good? Can we go again?", "Oh! Oh! That was fun! Only a little scary!" },
        ["Blorp"] = new[] { "Blorp! {times}! Fun! Again!", "Zoom zoom! Blorp win!" },
        ["Spike"] = new[] { "{times} times, and I'm still the sharpest at tag. Point made.", "You'll need a sharper aim than that. Again." },
        ["Wedge"] = new[] { "{times} tries and I'm still on my spot. Good game. Try again.", "You won't tag me. But I like that you keep trying." },
        ["Delta"] = new[] { "Change logged: {times} chases. Mood: improved. Again.", "Interesting: being chased is fun now. Noted." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishNeutralLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "{times} times. Noted. Back to my edge.", "There it goes again. Moving on." },
        ["Pip"] = new[] { "Ooh, {times} hops in a row! Okay! Back to the ceiling!", "Hop! That's just how it goes sometimes!" },
        ["Mortimer"] = new[] { "{times} times. The world moves, and so do I. Slowly.", "*sighs* Hop, hop. Such is life on an edge." },
        ["Zed"] = new[] { "{times} hops... okay... *yawn*... where was I...", "Moved again... fine... still sleepy..." },
        ["Dot"] = new[] { "{times} hops. Barely noticed. Too fast to care.", "Hop. Done. Next." },
        ["Ruth"] = new[] { "That is {times} hops in a row. Recorded. No further comment.", "Counted: {times}. Carrying on." },
        ["Whiskers"] = new[] { "{times} times. Whatever. I wasn't sitting there anyway.", "Hmph. Moved. Doesn't matter." },
        ["Mittens"] = new[] { "Mrrp. {times} times. I'll find another warm spot.", "Mrrow... moved again. Fine. More sun over here." },
        ["Sir Pounce"] = new[] { "{times} retreats. Strategic ones, naturally.", "A small hop for a cat. Nothing more." },
        ["Hopper"] = new[] { "{times} hops! Hops are hops!", "Ribbit. Hopped. Nice." },
        ["Mossy"] = new[] { "{times} ripples. The pond does not mind.", "Water moves. Frogs move. It is so." },
        ["Croak"] = new[] { "{times}. Hmph. Whatever.", "Moved again. Still dry. Same as ever." },
        ["Boo"] = new[] { "{times} times! Huh. Ghosts drift, I guess!", "Whoosh! Moved. Anyway!" },
        ["Wisp"] = new[] { "{times} times I drifted. Drifting is what I do.", "Here, then there. It's all the same to me." },
        ["Sheet"] = new[] { "{times} times. Technically, I just floated somewhere else.", "Technically, this is fine." },
        ["Morel"] = new[] { "{times}... moved... it's all... soil...", "Somewhere else... is also... damp enough..." },
        ["Puff"] = new[] { "{times} hops! Okay! *puff*", "Hee, moved again. Whatever!" },
        ["Cap"] = new[] { "{times} times. In my day we moved too. It's what edges are for.", "Hm. Moved again. Such is the way of things." },
        ["Unit 7"] = new[] { "Relocations logged: {times}. Status: normal.", "Position changed. No action required." },
        ["Sprocket"] = new[] { "{times} jumps! Gears still fine!", "Moved. Everything still tight. Carry on!" },
        ["Glitch"] = new[] { "Relocated relocated: {times} times. No virus found.", "Moved moved. Nothing to report report." },
        ["Goop"] = new[] { "{times} bounces! Okay!", "Boing. Moved. Still sticky." },
        ["Puddle"] = new[] { "{times} times... oh. Well. I'm still here.", "Moved again. Didn't spill. That's good." },
        ["Blorp"] = new[] { "Blorp. {times}. Okay.", "Zoom. Blorp fine." },
        ["Spike"] = new[] { "{times} times. Doesn't change my angle.", "Moved. Still sharp." },
        ["Wedge"] = new[] { "{times} times. I'll settle back where I was.", "Moved a bit. I'll be back on my spot." },
        ["Delta"] = new[] { "Change since last time: {times} hops. Nothing else.", "Noticed: I moved. That's all." },
    };

    public const string EnglishGoodPrompt = "{situation}\nThe person whose screen you live on keeps chasing you with the mouse cursor and picking you up: {times} times in a row now. To you it is a game of tag, and you love it. Say ONE line to them, playful and teasing, in your own voice. At most 20 words. Output only the line: no quotes, no name.";

    public const string EnglishNeutralPrompt = "{situation}\nThe person whose screen you live on has moved you about with the mouse cursor and picked you up: {times} times in a row now. It means nothing to you: it just happens. Say ONE line to them about it, a passing remark in your own voice, neither pleased nor annoyed. At most 20 words. Output only the line: no quotes, no name.";

}
