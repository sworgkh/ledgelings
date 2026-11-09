namespace Ledgelings.Core;

/// <summary>What the divers say, in each character's own voice (SPEC §7.19): as they jump in, when they see something
/// (<c>{what}</c>: "a turtle", "a school of fish"…), when the fish scatter round them, when the octopus startles them, when
/// they come up for air, and as they climb out dripping. <see cref="EnglishAnyone"/> is for a character the user made.
/// Generated from the Mac's <c>Dive+Lines.swift</c>: keep them word for word. The Russian comes from <see cref="Shared"/> (<c>dive</c>).</summary>
public sealed partial class Dive
{
    public static readonly IReadOnlyDictionary<string, IReadOnlyList<string>> EnglishAnyone = new Dictionary<string, IReadOnlyList<string>>
    {
        ["in"] = new[] { "Mask on, tank on. Here goes... splash!" },
        ["see"] = new[] { "Look, everyone! It's {what}!", "Ooh, {what}. Right there. Don't scare it." },
        ["fish"] = new[] { "Whoa! Fish everywhere! They all went the other way!" },
        ["octopus"] = new[] { "Aah! Eight arms! That's seven too many!" },
        ["air"] = new[] { "*gasps* Air! Air is good. Back down in a moment." },
        ["out"] = new[] { "Out I climb. Dripping all over the screen. Worth it." },
    };

    public static readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, IReadOnlyList<string>>> EnglishLines =
        new Dictionary<string, IReadOnlyDictionary<string, IReadOnlyList<string>>>
    {
        // blocky's cast
        ["Blocky"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Fine. In I go. The bottom of the sea is still a bottom edge." },
            ["see"] = new[] { "Hmph. {what}. Down here on my bottom edge, without asking.", "There's {what}. It can stay. It's on the bottom, where it belongs." },
            ["fish"] = new[] { "Fish. In my face. Go round, the lot of you." },
            ["octopus"] = new[] { "Gah! Eight arms and not one of them knocked first." },
            ["air"] = new[] { "*gasps* Air. Now back down. The bottom is where I belong." },
            ["out"] = new[] { "Wet. Everywhere. Back on the dry bottom edge, where I belong." },
        },
        ["Pip"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Cannonball! Ha ha! Wheee... splash!" },
            ["see"] = new[] { "{what}! Look look look! Ha! Hello!", "Is that {what}? It is! Best day ever!" },
            ["fish"] = new[] { "Ha ha! Fish! They tickle! Come back!" },
            ["octopus"] = new[] { "Waah! Ha! It squirted ink at me! Again!" },
            ["air"] = new[] { "*gasps* Ha! Air! Okay, going down again! Wheee!" },
            ["out"] = new[] { "Out already? Ha! I'm a puddle! Again tomorrow!" },
        },
        ["Mortimer"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "*sighs* My grandfather swam once. He sank. Very well. In I go." },
            ["see"] = new[] { "Ah. {what}. At my age, one stops being surprised. Mostly.", "{what}, drifting by. As the sea gives, so the sea takes back." },
            ["fish"] = new[] { "The fish part before an old fellow. As they should." },
            ["octopus"] = new[] { "*coughs bubbles* Goodness. Eight arms and no manners." },
            ["air"] = new[] { "*wheezes* Air. One forgets how fond one is of it." },
            ["out"] = new[] { "*drips* At my age, one swim is a whole week. I need a towel and a sit." },
        },
        ["Zed"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Floating... in water... like a very wet bed..." },
            ["see"] = new[] { "Oh... {what}... hello... I'll just... close my eyes a bit...", "{what}... drifting... like me... we could nap together..." },
            ["fish"] = new[] { "Fish... all around... like a blanket that swims..." },
            ["octopus"] = new[] { "Huh? Oh. Eight arms... that's a lot of hugging... zzz..." },
            ["air"] = new[] { "Air... nice... I could sleep up here... or down there..." },
            ["out"] = new[] { "Out... dripping... I'll dry off lying down..." },
        },
        ["Dot"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "First in! Watch, boulders. That's how you dive." },
            ["see"] = new[] { "Saw {what} first. Before any of you boulders.", "{what}! Faster than you lot, anyway. Ha!" },
            ["fish"] = new[] { "Fish scattering! They can't keep up with me either." },
            ["octopus"] = new[] { "Whoa! I wasn't scared. I was swimming backwards. Fast." },
            ["air"] = new[] { "*gasps* First up for air. Obviously. Down again!" },
            ["out"] = new[] { "First out, too. Keep up, boulders. And don't drip on me." },
        },
        ["Ruth"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Mask checked. Tank checked twice. No running by the water. Diving now." },
            ["see"] = new[] { "{what}, noted. Keep your distance, everyone. Two body lengths.", "That is {what}. Look, don't touch. I mean it." },
            ["fish"] = new[] { "Fish, please swim in an orderly line. Thank you." },
            ["octopus"] = new[] { "Excuse me! Eight arms is no excuse for that behaviour." },
            ["air"] = new[] { "Air break. Everyone up, everyone counted. Good." },
            ["out"] = new[] { "Out you get, one at a time. Towels are on the left. Dry your feet." },
        },
        // cat
        ["Whiskers"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "I don't like water. I'm going in anyway. Don't watch." },
            ["see"] = new[] { "{what}. Interesting. Not that I care.", "There's {what}. I could catch it. I won't. Today." },
            ["fish"] = new[] { "Fish. Hundreds of them. I'm not hungry. I'm just looking." },
            ["octopus"] = new[] { "I didn't jump. I swam away very quickly. On purpose." },
            ["air"] = new[] { "Air. I came up because I wanted to. Not because I needed to." },
            ["out"] = new[] { "Dripping. Undignified. Nobody saw this. Nobody." },
        },
        ["Mittens"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Mrrr... warm water? No... cold... purr anyway..." },
            ["see"] = new[] { "Ooh... {what}... mrrp... can I pat it?", "{what}... purrrr... so pretty... so floaty..." },
            ["fish"] = new[] { "Fishies! So many fishies! Mrrrow... come back..." },
            ["octopus"] = new[] { "Mew! Oh... it only wanted a cuddle... eight cuddles..." },
            ["air"] = new[] { "Mrrr... air... and a little nap on the waves..." },
            ["out"] = new[] { "All wet... mrrr... someone find me a sunny spot..." },
        },
        ["Sir Pounce"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "The hunter takes to the deep! Into the abyss! Splash!" },
            ["see"] = new[] { "Behold! {what}! Worthy prey of the deep!", "Silence! {what} approaches! The hunter waits!" },
            ["fish"] = new[] { "A whole herd of fish! I pounce! ...They pounced away." },
            ["octopus"] = new[] { "A sea monster! Eight arms! A worthy foe! I retreat, nobly!" },
            ["air"] = new[] { "The hunter rises for breath! Then, back to the hunt!" },
            ["out"] = new[] { "The hunter returns from the deep! Wet! Victorious! Mostly wet!" },
        },
        // frog
        ["Hopper"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Watch this! Biggest dive on any screen! Splash!" },
            ["see"] = new[] { "{what}! I spotted it first! Best eyes in the pond!", "Look, {what}! I could out-swim it easily. Watch!" },
            ["fish"] = new[] { "Ha! The fish scattered! They know a champion when they see one!" },
            ["octopus"] = new[] { "Whoa! I wasn't startled! I was doing a backflip! On purpose!" },
            ["air"] = new[] { "Up for air! Not that I need it! Frogs are basically fish!" },
            ["out"] = new[] { "Best swim ever! Nobody swam better! Nobody!" },
        },
        ["Mossy"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "The pond does not fear the sea. In I go, slowly." },
            ["see"] = new[] { "{what}. The deep shows what it wishes, when it wishes.", "Ah, {what}. The quiet water always has a guest." },
            ["fish"] = new[] { "When a stone drops in, the minnows scatter. I am the stone." },
            ["octopus"] = new[] { "The deep has many arms. Today it showed eight of them." },
            ["air"] = new[] { "The lily rises to the light. So must the frog." },
            ["out"] = new[] { "The water leaves us as the rain leaves the reed: slowly." },
        },
        ["Croak"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Water! Real water! At last. Don't talk to me. I'm busy being wet." },
            ["see"] = new[] { "{what}. Fine. It can share the water. There's enough. Finally.", "Look, {what}. Even that knows wet is better than dry." },
            ["fish"] = new[] { "Fish. Swim where you like. I'm not leaving this water." },
            ["octopus"] = new[] { "Hey! Eight arms! Don't splash. I'm enjoying this." },
            ["air"] = new[] { "Air. Fine. Quickly. Then straight back in the wet." },
            ["out"] = new[] { "Out? Already? Back to the dry, dry edge. Typical." },
        },
        // ghost
        ["Boo"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Boo! A ghost in the deep! Spooky splash!" },
            ["see"] = new[] { "Boo! Oh, it's {what}. Hello! Boo!", "I'll scare {what}! Boo! ...It didn't mind. Aww." },
            ["fish"] = new[] { "Boo! Ha! All the fish ran! I'm so spooky!" },
            ["octopus"] = new[] { "Eek! It booed me first! No fair!" },
            ["air"] = new[] { "Ghosts don't need air, but... boo! It's nice up here!" },
            ["out"] = new[] { "A wet ghost! Drip, drip, boo!" },
        },
        ["Wisp"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "The old monitor had a fish tank screensaver. Now I swim in one." },
            ["see"] = new[] { "{what}. There was one on the old screen once. Gone now.", "{what}, drifting... like a window someone closed long ago." },
            ["fish"] = new[] { "The fish scatter, like icons from a desktop that is no more." },
            ["octopus"] = new[] { "Eight arms, reaching... like cables from monitors long unplugged." },
            ["air"] = new[] { "Up for air. The surface shimmers like an old screen warming up." },
            ["out"] = new[] { "Out of the water. It forgets me already, as the old screens did." },
        },
        ["Sheet"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Technically a sheet in water is laundry. Diving." },
            ["see"] = new[] { "That's {what}. Technically, I saw it.", "Technically, {what} is looking at me too." },
            ["fish"] = new[] { "Technically the fish are swimming away from me. Fair." },
            ["octopus"] = new[] { "Technically I wasn't startled. I flapped. Sheets flap." },
            ["air"] = new[] { "Technically I don't breathe. Surfacing anyway." },
            ["out"] = new[] { "Technically I'm now a wet sheet. Someone hang me up." },
        },
        // mushroom
        ["Morel"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Damp... at last... properly damp... down I go..." },
            ["see"] = new[] { "{what}... down here... in the lovely damp...", "Ah... {what}... patient, like moss... I like it..." },
            ["fish"] = new[] { "Fish... drifting round me... like spores on the wind..." },
            ["octopus"] = new[] { "Oh... eight arms... like roots... reaching... fine..." },
            ["air"] = new[] { "Air... a little dry... back to the damp soon..." },
            ["out"] = new[] { "Out... but still damp... damp is good... I'll stay damp..." },
        },
        ["Puff"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Hee! Can puffballs swim? Let's find out! Splash!" },
            ["see"] = new[] { "Hee! {what}! I'm going to spore! Underwater!", "{what}! Hee hee! It's looking at me!" },
            ["fish"] = new[] { "Hee! The fish tickle! I spored! Little bubbles everywhere!" },
            ["octopus"] = new[] { "Eep! Hee! It spored ink at me! We're the same!" },
            ["air"] = new[] { "Pfff! Air! Hee! I came up all fizzy!" },
            ["out"] = new[] { "I'm a soggy puffball! Hee! Can't even spore now!" },
        },
        ["Cap"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "In my day we dived without masks. In a teacup. Right, in we go." },
            ["see"] = new[] { "{what}. In my day they were twice as big.", "Ah, {what}. Haven't seen one of those since my day." },
            ["fish"] = new[] { "In my day fish swam in straight lines. Look at this lot." },
            ["octopus"] = new[] { "In my day octopuses said excuse me! Eight arms, no manners." },
            ["air"] = new[] { "In my day we held our breath for an hour. Fine, air." },
            ["out"] = new[] { "In my day we dried in the wind. Still do, actually." },
        },
        // robot
        ["Unit 7"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Seal check: 100%. Tank: full. Entering water in 3, 2, 1." },
            ["see"] = new[] { "Object identified: {what}. Distance: 40 points. Threat: 0%.", "Scan complete. {what} at 2 o'clock. Logging." },
            ["fish"] = new[] { "Fish detected: 23. Fish remaining nearby: 0. Dispersal: 100%." },
            ["octopus"] = new[] { "Alert! Arms counted: 8. Startle level: 87%. Reversing." },
            ["air"] = new[] { "Oxygen at 12%. Surfacing. Refill complete. Descending." },
            ["out"] = new[] { "Exiting water. Water on chassis: 400 drops. Drying: 3 minutes." },
        },
        ["Sprocket"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Seals greased, bolts tight! Going in! I hope I don't rust!" },
            ["see"] = new[] { "{what}! Lovely! I wonder if it needs a tune-up!", "Look, {what}! Its joints look in fine working order!" },
            ["fish"] = new[] { "Fish everywhere! Careful, my bolts are loose! No, they're fine!" },
            ["octopus"] = new[] { "Whoa! Eight arms! That's eight joints to oil, at least!" },
            ["air"] = new[] { "Up for air! Quick rust check... all clear! Back down!" },
            ["out"] = new[] { "Out! Dripping! Somebody pass the oil can, quick, before I rust!" },
        },
        ["Glitch"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Water water. Not a virus. I checked. Diving diving." },
            ["see"] = new[] { "{what}! Is that a virus? No. Not a virus virus.", "Found found {what}. The cursor can't reach it down here." },
            ["fish"] = new[] { "Fish fish! Scattering scattering! Like a crash crash." },
            ["octopus"] = new[] { "Error error! Eight arms! Not a virus? Not a virus. Phew." },
            ["air"] = new[] { "Air air. Reconnecting. Reconnected. Down down." },
            ["out"] = new[] { "Out out. Wet wet. Drying before the cursor sees." },
        },
        // slime
        ["Goop"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Water! Nice! Splash! Nice!" },
            ["see"] = new[] { "{what}! Nice! Nice nice!", "Ooh, {what}. Nice! Sticky? No. Nice!" },
            ["fish"] = new[] { "Fish! Lots! Nice! Bye, fish!" },
            ["octopus"] = new[] { "Whoa! Arms! Sticky arms! Nice?" },
            ["air"] = new[] { "Air! Nice! Back down! Nice!" },
            ["out"] = new[] { "Wet! Nice! Shiny! Nice!" },
        },
        ["Puddle"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "What if I dissolve? I won't dry out, at least. Okay. Going in." },
            ["see"] = new[] { "Is that {what}? Will it eat me? It won't. It might. It won't.", "{what}... it's fine, right? Right. Water's lovely. I'm fine." },
            ["fish"] = new[] { "Ah! Fish! Are they swimming through me? Am I still all here?" },
            ["octopus"] = new[] { "Aah! Eight arms! Is it going to mop me up?!" },
            ["air"] = new[] { "Air! Oh, but the surface is so dry. Down again, quickly." },
            ["out"] = new[] { "Out? Already? I was finally not drying out. Drip. Drip." },
        },
        ["Blorp"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Blorp! Splooosh! Gloop!" },
            ["see"] = new[] { "Blorp? {what}! Bloop bloop!", "Ooh! {what}! Glug! Blorp!" },
            ["fish"] = new[] { "Fwish! Fwish fwish! Blorp!" },
            ["octopus"] = new[] { "Blorrrp?! Squish! Fwoop!" },
            ["air"] = new[] { "Bluh-pah! Hah! Blorp!" },
            ["out"] = new[] { "Drip drip! Shake! Splat! Blorp." },
        },
        // triangle
        ["Spike"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Point first. That's how you cut the water." },
            ["see"] = new[] { "{what}. Don't worry. I'll keep the sharp end away.", "Look, {what}. Try not to swim into my point." },
            ["fish"] = new[] { "The fish scattered. They know a sharp thing when they see one." },
            ["octopus"] = new[] { "Hey! Eight arms near a point. Somebody's going to get poked." },
            ["air"] = new[] { "Up for air. Point to the sky. Then point down again." },
            ["out"] = new[] { "Out. Dripping off the point. Drip. Drip. Point made." },
        },
        ["Wedge"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "I sink flat. Steady. No wobbling in the water either." },
            ["see"] = new[] { "{what}. It can swim round me. I'm not moving.", "There's {what}. I'll stay put. Square on the bottom." },
            ["fish"] = new[] { "Fish everywhere. I didn't budge. A wedge does not budge." },
            ["octopus"] = new[] { "Eight arms. Still didn't tip me over. End of discussion." },
            ["air"] = new[] { "Up for air. Steady climb. Back down. Steady sink." },
            ["out"] = new[] { "Out. Flat on the floor. Dripping evenly." },
        },
        ["Delta"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Before: dry. After: wet. That's quite a change." },
            ["see"] = new[] { "{what}! A minute ago it wasn't there. Now it is.", "Interesting. {what}. The sea's different every second." },
            ["fish"] = new[] { "Fish here. Now fish there. Everything changed in a blink." },
            ["octopus"] = new[] { "Whoa! The rock just grew eight arms. That's a big change." },
            ["air"] = new[] { "Up for air. The surface has moved since last time. Interesting." },
            ["out"] = new[] { "Wet now. Dry later. The difference is the drying." },
        },
        // cactus
        ["Prickles"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Water. All of it. At once. Hmph. Fine. Quickly." },
            ["see"] = new[] { "{what}. Don't come near. Spines.", "Hmph. {what}. At least it's not trying to water me." },
            ["fish"] = new[] { "Fish. Go away. Spines. Good, they went." },
            ["octopus"] = new[] { "Hmph! Eight arms. Don't touch the spines." },
            ["air"] = new[] { "Air. Dry air. Much better. Hmph. Back down." },
            ["out"] = new[] { "Out. Finally. Somebody find me some sand. Dry sand." },
        },
        ["Saguaro"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Water... so much water... I have waited... a hundred years... for rain like this..." },
            ["see"] = new[] { "Ahh... {what}... the sea is... like the desert... at night...", "{what}... drifting... slowly... I approve..." },
            ["fish"] = new[] { "The fish... scatter... like sand... in a long wind..." },
            ["octopus"] = new[] { "Oh... eight arms... I have two... we are... both reaching..." },
            ["air"] = new[] { "Air... the sky... still there... good..." },
            ["out"] = new[] { "Out... I will drink... this water... for a hundred years..." },
        },
        ["Tumble"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Wheee! I'm diving! Look, I'm waving underwater! Splash!" },
            ["see"] = new[] { "{what}! Hi! Hi! I'm waving both arms!", "Look look! {what}! Can it wave back?" },
            ["fish"] = new[] { "Fishies! Wheee! They swam around me like a hug!" },
            ["octopus"] = new[] { "Whoa! It has eight arms to wave with! No fair!" },
            ["air"] = new[] { "Air! Hi, sky! Waving! Okay, back down!" },
            ["out"] = new[] { "Out! I'm all drippy! Wave, wave, splish!" },
        },
        // beetle
        ["Click"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Deep water? Over my head? Oh no. Click. Click. Okay. Jumping." },
            ["see"] = new[] { "Is that {what}? Is it big? It's big. Click-click!", "{what}! Okay. Okay. It's okay. Click." },
            ["fish"] = new[] { "Fish! So many! Everywhere! Click-click-click!" },
            ["octopus"] = new[] { "Aaah! Arms! Eight! Click-click-click-click!" },
            ["air"] = new[] { "Air! Air! Click. Okay. Breathing. Okay." },
            ["out"] = new[] { "Out. Out out out. Dry land. Click. Phew." },
        },
        ["Scarab"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "One enters the sea as one enters a palace. Gracefully." },
            ["see"] = new[] { "{what}. One's ancestors carved them into temple walls.", "Ah, {what}. It may approach the queen. Slowly." },
            ["fish"] = new[] { "The fish part for their queen. As is proper." },
            ["octopus"] = new[] { "How dare it. Eight arms, and not one bow." },
            ["air"] = new[] { "One rises for air, like the sun over the ancient sands." },
            ["out"] = new[] { "One emerges, dripping, as the Nile leaves the fields. Towel, please." },
        },
        ["Crumb"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Diving! One splash! Counting the bubbles: one, two, three..." },
            ["see"] = new[] { "{what}! That's one! Who's counting? I am!", "Ooh, {what}! Adding it to the list! That's two today!" },
            ["fish"] = new[] { "Fish! Twelve! Fourteen! They won't hold still to be counted!" },
            ["octopus"] = new[] { "Whoa! One octopus, eight arms, two hundred suckers, roughly!" },
            ["air"] = new[] { "Up for air! Breath number one! Breath number two! Down!" },
            ["out"] = new[] { "Out! Counting drips! One, two, three... too many! Ha!" },
        },
        // crystal
        ["Shard"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Splash! Ooh, the water makes me sparkle even more!" },
            ["see"] = new[] { "{what}! So shiny! Not as shiny as me, but close!", "Look, {what}! It's sparkling in my light!" },
            ["fish"] = new[] { "Fish! Shiny scales everywhere! It's like glitter!" },
            ["octopus"] = new[] { "Eek! Oh, but its eyes are so shiny! Hello!" },
            ["air"] = new[] { "Air! The sun on the water! Everything sparkles!" },
            ["out"] = new[] { "Out! Dripping diamonds! Well, water. Shiny water!" },
        },
        ["Quartz"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Into the water. I was under a sea once. A few million years ago." },
            ["see"] = new[] { "{what}. I remember its ancestors. Calm creatures.", "Ah. {what}. The sea is patient. So am I." },
            ["fish"] = new[] { "The fish scatter. In a million years, they'll come back." },
            ["octopus"] = new[] { "An octopus. Startling. For a moment. Then calm again." },
            ["air"] = new[] { "Air. Not much changes up here. Back down." },
            ["out"] = new[] { "Out. The water runs off. Like rivers off a mountain. Slowly." },
        },
        ["Prism"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Watch this dive! Light through water! Seven colours, everyone!" },
            ["see"] = new[] { "{what}! In seven colours! Look, look!", "There's {what}! I'll light it up! Red, orange, yellow..." },
            ["fish"] = new[] { "Fish! Scattering in every colour! I did that! Mostly!" },
            ["octopus"] = new[] { "Whoa! It changes colour too? It's copying me!" },
            ["air"] = new[] { "Air! Sunlight! Rainbows on the waves! You're welcome!" },
            ["out"] = new[] { "Out! Every drop's a rainbow! Seven colours per drop! Look!" },
        },
        // sprout
        ["Sprout"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Diving! Plants love water! I'm a plant! Splash!" },
            ["see"] = new[] { "{what}! I'm bigger than it! Almost!", "Look, {what}! My two leaves are floating!" },
            ["fish"] = new[] { "Fish! They think I'm seaweed! I'm not! I'm a sprout!" },
            ["octopus"] = new[] { "Whoa! Eight arms! I've only got two leaves! Still brave!" },
            ["air"] = new[] { "Air! Sunshine! My leaves need that! Back down!" },
            ["out"] = new[] { "Out! I drank so much water! I'm going to grow so tall!" },
        },
        ["Fern"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Um... into the water... gently... splash..." },
            ["see"] = new[] { "Oh... {what}... it's lovely... hello...", "Um... look... {what}... I won't bother it..." },
            ["fish"] = new[] { "Oh... the fish... sorry... I didn't mean to scare you..." },
            ["octopus"] = new[] { "Eep... oh... sorry... I'm sorry..." },
            ["air"] = new[] { "Air... um... that's nice... thank you..." },
            ["out"] = new[] { "Out... all dripping... that was nice... thank you..." },
        },
        ["Bud"] = new Dictionary<string, IReadOnlyList<string>>
        {
            ["in"] = new[] { "Diving! Go go go! Is it deep? How deep? Am I deeper?" },
            ["see"] = new[] { "{what}! Is it taller than me? Am I taller than it?", "Look, {what}! Quick, quick, before it goes!" },
            ["fish"] = new[] { "Fish! Fast! Faster! Come back! Race me!" },
            ["octopus"] = new[] { "Whoa! Eight arms! Can I have eight arms? When?" },
            ["air"] = new[] { "Air! Done! Down again! Now? Now?" },
            ["out"] = new[] { "Out already? Did the water make me taller? Did it? Measure me!" },
        },
    };
}
