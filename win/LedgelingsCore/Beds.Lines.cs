namespace Ledgelings.Core;

/// <summary>Each built-in character on its bed, in its own voice (SPEC §7.9), generated from the Mac's
/// <c>Beds+Lines.swift</c>: keep them word for word. The Russian comes from <see cref="Shared"/>.</summary>
public static partial class Beds
{
    public static readonly IReadOnlyList<string> EnglishSettleAnyone = new[]
    {
        "Bed. Finally. {bed}, my favourite.",
        "Right here, in {bed}. Goodnight, everyone.",
    };

    public static readonly IReadOnlyList<string> EnglishMovedAnyone = new[]
    {
        "Mm? New spot? ...fine. Here, then.",
        "Someone moved my bed... it's nice here too...",
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishSettleLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "My crate. On the bottom edge. Where a bed belongs.", "Straw, solid wood, no cursor. Goodnight." },
        ["Pip"] = new[] { "Hammock time! Ha! It swings! Everything swings!", "Up here in my hammock, nearly touching the ceiling! Night night!" },
        ["Mortimer"] = new[] { "*sighs* The old quilt. Every patch a year, and every year a nap.", "A wise creature once said: lie down before you fall down. I said it. Just now." },
        ["Zed"] = new[] { "Pillow... at last... I've been thinking about it all day...", "The pillow and I have an understanding. Goodnight..." },
        ["Dot"] = new[] { "Matchbox. Fits me perfectly. Fits a boulder never.", "Fastest one to bed, as always. Night, slowpokes." },
        ["Ruth"] = new[] { "Sheet straight, blanket folded, lights out at exactly now.", "My bed is made. I made it. I always make it." },
        ["Whiskers"] = new[] { "This box is mine. I don't care about it. It's mine.", "I am not sleeping in the box. I am resting near the inside of it." },
        ["Mittens"] = new[] { "Mrrr... my basket... the warm side... purrrr...", "Basket. Curl. Purr. Goodnight..." },
        ["Sir Pounce"] = new[] { "The royal cushion awaits its hunter. I shall rest. Briefly. Majestically.", "Behold: the night's lair! It is a cushion. It is perfect." },
        ["Hopper"] = new[] { "Watch me jump straight onto my lily pad! ...I walked. Same thing.", "Best lily pad on any screen! Goodnight, everybody!" },
        ["Mossy"] = new[] { "Soft moss is a slow pond's pillow.", "The moss is damp. The night is long. All is well." },
        ["Croak"] = new[] { "A puddle. An actual puddle. Wake me when it dries. Don't.", "Finally, something wet on this dry edge." },
        ["Boo"] = new[] { "Boo! ...I'm going to sleep on my cloud now. Boo.", "Even scary ghosts need a fluffy cloud. Don't tell anyone." },
        ["Wisp"] = new[] { "A leaf that fell from a tree that is gone. I'll sleep on it anyway.", "The leaf remembers autumn. I remember the old monitor. Goodnight." },
        ["Sheet"] = new[] { "A blanket for a sheet. Technically I'm the bedding.", "Lying down. Technically hovering down." },
        ["Morel"] = new[] { "The old log... is patient... like me...", "Good damp wood... a good long night..." },
        ["Puff"] = new[] { "Grass! Tickly! Hee! Don't make me spore!", "Snuggling into the grass! Hee hee! Night!" },
        ["Cap"] = new[] { "In my day we slept in a proper pot of soil. We still do.", "Good dark soil. They don't make it like this any more." },
        ["Unit 7"] = new[] { "Docked. Charge 12%. Expected full: 0600. Sleep mode: on.", "Charging dock reached at 1 of 1 attempts. Powering down." },
        ["Sprocket"] = new[] { "My toolbox! Every bolt tight, every hinge oiled. Perfect pillow.", "Sleeping on the toolbox, in case anything needs tightening at night." },
        ["Glitch"] = new[] { "Spacebar. Space. Bar. Sleeping on the the biggest key.", "If the cursor comes, I'm a keyboard. Keyboard. Goodnight." },
        ["Goop"] = new[] { "Sponge! Nice! Squishy! Nice!", "Nice sponge. Sticky me. Goodnight." },
        ["Puddle"] = new[] { "A teacup can't dry out. Can it? It can't. I'm sure it can't.", "Safe in my teacup. Nobody steps in a teacup. Right?" },
        ["Blorp"] = new[] { "Pop! Pop! Blorp. Zzz.", "Bubble wrap! Pop. Night. Pop." },
        ["Spike"] = new[] { "Pincushion. Soft on top, sharp around. Like me.", "Goodnight. Mind the pins. That's the point." },
        ["Wedge"] = new[] { "Three good books underneath. Nothing tips me over at night.", "Solid stack. Solid sleep. End of discussion." },
        ["Delta"] = new[] { "My sock is where I left it. Unlike its pair.", "Something moved since last night. Not my sock. Good." },
    };

    public static readonly IReadOnlyDictionary<string, string[]> EnglishMovedLines = new Dictionary<string, string[]>
    {
        ["Blocky"] = new[] { "Who moved my crate? ...fine. It's still a good crate." },
        ["Pip"] = new[] { "Whee! My hammock flew! Ha! Can it fly again?" },
        ["Mortimer"] = new[] { "*sighs* A new place for an old quilt. So it goes." },
        ["Zed"] = new[] { "...moved?... don't care... still asleep..." },
        ["Dot"] = new[] { "Moved me? Fast. Didn't think you had it in you." },
        ["Ruth"] = new[] { "Unannounced bed relocation. Noted. I'll allow it." },
        ["Whiskers"] = new[] { "I meant to sleep here all along." },
        ["Mittens"] = new[] { "Mrrr... warm here too... purr..." },
        ["Sir Pounce"] = new[] { "The lair has been moved! A new hunting ground! ...tomorrow." },
        ["Hopper"] = new[] { "My lily pad jumped! Further than me!" },
        ["Mossy"] = new[] { "Moss grows wherever it is put down." },
        ["Croak"] = new[] { "You moved my puddle. Did you at least make it wetter?" },
        ["Boo"] = new[] { "Boo? Oh. My cloud drifted. Clouds do that." },
        ["Wisp"] = new[] { "Carried somewhere new, like a leaf in the wind." },
        ["Sheet"] = new[] { "Moved. Technically I was the one being carried." },
        ["Morel"] = new[] { "...a new... place... it will do..." },
        ["Puff"] = new[] { "Hee! The grass moved! I nearly spored!" },
        ["Cap"] = new[] { "In my day a pot stayed where it was put. Oh well." },
        ["Unit 7"] = new[] { "Dock relocated. New coordinates saved. Resuming sleep mode." },
        ["Sprocket"] = new[] { "New spot! I'll tighten the floor here in the morning." },
        ["Glitch"] = new[] { "Spacebar moved. Moved. Error ignored. Sleeping." },
        ["Goop"] = new[] { "Moved! Nice. Still sticky." },
        ["Puddle"] = new[] { "Where are we? Is it dry here? Is it safe? ...okay." },
        ["Blorp"] = new[] { "Whoosh! Blorp. Zzz." },
        ["Spike"] = new[] { "You moved my pincushion. Bold. Pointless, but bold." },
        ["Wedge"] = new[] { "You moved the books. I did not tip. Noted." },
        ["Delta"] = new[] { "My sock moved. I noticed. I always notice." },
    };
}
