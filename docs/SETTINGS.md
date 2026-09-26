# Settings, the menu, and your hand

Every setting is saved as you change it and applied live; nothing needs a restart.
On macOS the window is *menu bar icon › Settings…*; on Windows it is *tray icon ›
Settings…*. Nine tabs: **Creatures**, **Sprites**, **Talk**, **Bonds**, **Calendar**, **Reminders**, **Voice**, **Costs**, **Chats**, each in two columns so a tab fits on one screen.

## The menu

| Item | What it does |
|---|---|
| *Day — they sleep in m:ss* / *Night — they wake in m:ss* | The colony's clock. Reads *Always day — night is set to 0* when the night is off |
| **Put Them to Sleep Now** / **Wake Them Up Now** | Skips to the next dusk or dawn. Hidden when the night is 0 |
| **Make Them Jump** | Every creature startles and jumps to another edge |
| **Hide Them for a While…** | Asks how long (5, 15, 30 minutes; 1, 2, 4 hours; until 08:00 tomorrow) and sends everyone into the house. While they are away the item reads **Bring Them Back Now (m:ss left)** and ends it early |
| **Make Someone Talk** | A random awake creature says something to the nearest one |
| **Send a Paper Plane** | One free creature throws a paper plane to another now, whatever the setting below says |
| **Add a Reminder…** (⌘R) | The Reminders tab. Under it, *Next: Call mom, Today 14:30* while one is waiting; *(off)* when reminders are off |
| **Hear Them Talk** (⌘V) | Voice on or off: every bubble read out loud (Talk tab › Voice). Ticked while on |
| *the status line* | The last thing that happened with the model: a line, or why nothing was said |
| **Chat History…** | The Chats tab |
| *Spent: $a today, $b this month* | Shown once there is a record; opens the Costs tab |
| **Settings…** | The settings window |
| **Quit** | Everyone vanishes; nothing is persisted about the hide |

## What your hand can do

The overlay is click-through: clicks land on whatever is under the creatures. It
becomes clickable only while the cursor is on something you can act on, and it never
takes focus from the app you are in.

| You do | What happens |
|---|---|
| Move the cursor within ~90 points of a creature | It jumps to a random spot on a different edge, on any monitor |
| Hold **Shift** | Nobody flees, so you can get the cursor onto one |
| **Shift-click** a creature (press and release without moving) | A poke: it says a line to whoever is nearest, and both stop to talk |
| **Shift-drag** a creature | It comes along, awake or asleep, dangling upright under the cursor, and lands the same way it left on the nearest edge of whichever monitor it is over |
| **Drag** a sleeper (no Shift) | The same; a sleeper never notices the cursor, so it can be picked up as it is |
| **Shift-right-click** (or Shift-Control-click) a creature | A nap: it lies down on the spot, day or night. The same again wakes it; the next dawn also ends a nap |
| Click a speech bubble | Closes it |
| Click a reminder's letter | Folds it back into a plane, which flies away |

Two creatures that are talking (stopped face to face) can still be startled away
by the cursor, which ends the chat.

## Creatures tab

| Setting | Default | Range | Notes |
|---|---|---|---|
| **How many** | 3 | 1 to 24 | Creatures are added at the end and removed from the end, so the first ones keep their colours and characters |
| **Smallest** / **Largest** | 1.5× / 3× | 1× to 5× in half steps | Screen points per sprite pixel. Every creature is born with a place between the two and keeps it, so moving the sliders resizes everyone without reshuffling who is big. Set them equal and they all match. Dragging one past the other drags the other along. On Windows the scale is multiplied by the primary monitor's dpi factor |
| **Colours** | 6 swatches | 1 to 12 | Creature 1 wears colour 1, creature 2 colour 2, and so on, starting over when the colours run out. The body, its highlight, shade and outline are all shades of the one colour; eyes stay black. A species with its own colour (frog, ghost, slime, robot, mushroom) ignores the slot. **Add Colour**, **Remove Last**, **Reset** restore the six defaults |
| **Day lasts** | 3 min | 0.5 to 60 | |
| **Night lasts** | 5 min | 0 to 60 | 0 means they never sleep. At dusk each creature wanders 0.5 to 7 more seconds, then lies down; at dawn each gets up within 3 seconds |
| **Start at login** | off | | macOS: the system's Login Items (only an installed app can register). Windows: the per-user Startup list |

## Sprites tab

Every species the app knows, built in or imported, as a card showing its idle pose.
Click a card to put that species in the colony or take it out; a check marks the
ones in use. Creature 1 wears the first species chosen, creature 2 the second, and
so on, starting over when they run out; with nothing chosen everyone is Blocky.

| Control | What it does |
|---|---|
| **Import Sheet…** | A `.txt` from the sprite kit, or a 288×96 PNG painted on magenta (or a whole multiple of that size). The new species is added to the colony at once |
| **Open Folder** | The folder imported creatures live in |
| 🗑 on an imported card | Deletes that creature's folder |
| **Copy Prompt** | The sprite kit prompt, for any chat model |
| **Save Example Sheet…** | Blocky written in the kit's letter format, to show a model or edit by hand |
| **Save PNG Template…** | A magenta 288×96 sheet with every cell and body box marked, for an image model or a paint program |

The format, the rules the import checks, and what a species can declare
(`kind`, `colour`, `character` lines) are in [SPRITES.md](SPRITES.md).

## Talk tab

### Talking

| Setting | Default | Range | Notes |
|---|---|---|---|
| **Creatures talk when they bump into each other** | on | | Off: they still stop, face each other, throw stars and give flowers, but say nothing. *Make Someone Talk* and pokes still work |
| **Bubble stays** | 14 s | 4 to 60 | For a line of about eight words. Longer lines stay a little longer, never past twice this. The reply appears while the first bubble is still up |
| **Flower lasts** | 2 min | 0.5 to 30 | How long a gifted flower sits on the head before it wilts |
| **The one with the flower follows the giver while it lasts** | on | | The wearer trails the giver around the edge, stopping about a body behind, until the flower wilts. It still sleeps and flees the cursor. A flower wearer never bumps into anyone, so a crowd of followers does not meet non-stop; it still answers a poke |
| **Paper planes** | on | | Every so often one creature throws a paper plane to another across the screen, swirling in its own wind. The catcher stops, reads the note out, thinks aloud about it and throws one answer back, which is read but never answered. Everything goes in the chat history. With talk off they read in silence |
| **A paper plane every** | 3 min | 0.5 to 60 | Minutes from one plane to the next, whatever the meetings. Nothing is sent at night or while they are hidden |

A pair of creatures meets at most once a minute; passing each other in between is
just passing. Every third meeting of the same pair is a gift: one hands the other
one of ten flowers (poppy, tulip, daisy, sunflower, rose, bluebell, dandelion,
lavender, lily, forget-me-not), and the conversation is about it.

A paper plane's words come from the brain. With the built-in lines, every character
of every built-in cast has its own notes, thoughts and answers, about the topics its
personality keeps returning to; a character you wrote yourself uses a few general
ones. With a model, the sender writes the note in its persona while the plane is in
the air, and the catcher's thought comes from a second call; both are priced like
any other call.

## Bonds tab

Creatures who share the screen for a long time get to know each other. Every pair
of characters on screen at the same time adds up time together, kept by name in
`bonds.json` beside the chats. Once a pair has lived side by side long enough, the
model writes them a **story** (a rivalry, a secret, a favour owed, a shared plan, a
crush) and a **bond**, one line on how they get on. Both go into their prompts, a few
dozen words, with which part of the story this conversation is, so the next
conversations follow it and the last one wraps it up. When a story has run its
course the next one grows from the bond, the last story and the last four lines they
said. One short call per story (about 300 tokens), shown as *Relationship plots* on
the Costs tab. With the built-in lines there is no model and so no stories.

| Setting | Default | Range | Notes |
|---|---|---|---|
| **Pairs who live together get a story** | on | | Off: time together is still counted, but nothing goes into the prompts and no story is written |
| **First story after** | 1 h | 0.25 to 72 h | Time both must have been on screen together before their first story |
| **A story lasts** | 6 conversations | 2 to 20 | Conversations with a model between the two; a paper plane uses the story but does not count |
| **The prompt that writes a story** | the built-in one | | Placeholders `{speaker}` `{speakerKind}` `{speakerPersona}` `{listener}` `{listenerKind}` `{listenerPersona}` `{together}` `{bond}` `{lastPlot}` `{recent}` `{length}`. The answer must have a line starting `PLOT:` and may have one starting `BOND:`. **Reset Prompt** brings the built-in one back |

On the right, every pair, the longest together first: time together, conversations,
stories so far and what they cost, the bond, and the story with its part (or the last
one). **Forget** clears one pair; **Forget All** and **Reveal in Finder** act on the
file. A renamed character starts again as a stranger. The Chats tab shows the story
under each conversation that played part of it.

To place the story yourself in the talk prompt, write `{relationship}` in *Who is
speaking* on the Talk tab; without it, the story is added at the end.

## Calendar tab (macOS)

The creatures know your day: the time on your Mac's clock, the date, and the
holidays of the faiths you tick. It goes into every conversation and paper plane
as one or two sentences, for example *For the person at this computer it is
Saturday, 26 September 2026, late evening (22:40). Today is day 1 of Sukkot, a
Jewish holiday.* This is apart from the colony's own day and night (Creatures tab),
which only says when they sleep.

| Setting | Default | Range | Notes |
|---|---|---|---|
| **They know the time of day** | on | | The part of the day (early morning, morning, midday, afternoon, evening, late evening, the middle of the night) and the time |
| **They know the day of the week and the date** | on | | "Saturday, 26 September 2026" |
| **Jewish holidays** | on | | From the Hebrew calendar: Rosh Hashanah, Yom Kippur, Sukkot, Simchat Torah, Hanukkah, Tu BiShvat, Purim, Passover, Lag BaOmer, Shavuot, Tisha B'Av |
| **Christian holidays** | on | | Epiphany, Orthodox Christmas, Ash Wednesday, Palm Sunday, Good Friday, Easter and Orthodox Easter, Ascension Day, Pentecost, All Saints' Day, Christmas Eve, Christmas |
| **Muslim holidays** | on | | From the Islamic (Umm al-Qura) calendar: Islamic New Year, Ashura, the Prophet's Birthday, Isra and Mi'raj, Ramadan (every day of it), Laylat al-Qadr, Eid al-Fitr, the Day of Arafah, Eid al-Adha. Where the new moon is sighted locally, a date can fall a day apart |
| **Mention a holiday** | 3 days ahead | 0 to 14 days | How early they start saying a holiday is coming ("Hanukkah is in 3 days"). 0: only on the day. A Jewish or Muslim holiday tomorrow "begins this evening" from 17:00 |

On the right, what they know right now, word for word, and the ticked holidays in
the next 60 days. Everything is worked out on the Mac; nothing is looked up online.
With the built-in lines, one conversation in three on a holiday is a `[holiday]`
block about it (`{holiday}` is its name).

## Reminders tab (macOS)

Things you want to be reminded of. When the time comes, a free creature stops,
folds the reminder into a paper plane and throws it at you: the plane swirls to the
middle of the screen your cursor is on, growing as it comes, turns to face you,
rushes at you and unfolds into a letter. On it: your reminder in big letters, a
note from whoever threw it in its own voice ("Stop staring at the cursor. It's
time: call mom." — Blocky), its signature and its face. With voice on, it reads the
note out loud. Click the letter to fold it away; it flies off over the top.

**New reminder** (left):

| Field | Default | Notes |
|---|---|---|
| **Remind me to** | empty | Your words, shown as they are on the letter. Return adds it |
| **When** | the top of the next hour | Date and time. A time already past is delivered straight away. **In 5 min**, **In 30 min**, **In 1 hour** set it from now |
| **Repeat** | Once | **Every day**, **Every weekday** (Monday to Friday) or **Every week** (the same weekday). A repeat keeps its hour and minute; if the Mac was off or asleep through several, you get one letter, late, and the next one is on schedule |

**Delivery** (left):

| Setting | Default | Range | Notes |
|---|---|---|---|
| **Reminders arrive by paper plane** | on | | Off: nothing is delivered. Whatever comes due meanwhile arrives, late, when you turn it back on |
| **Letter stays open** | 60 s | 10 to 600 s | Then it folds itself away. The time only counts while you are at the computer (you touched the mouse or keyboard in the last 30 s), so a letter that arrives while you are away waits for you |
| **The thrower reads its note out loud** | on | | Only when voice is on (Voice tab) |
| **Send a Test Letter** | | | A sample reminder, delivered now |

**Your reminders** (right): waiting ones by time ("Every day, next Tomorrow 09:00"),
then sent one-offs, greyed, until **Clear Sent**. Each has **Send Now** (deliver it
now; its schedule does not change) and **Delete**. They are kept in `reminders.json`
in `~/Library/Application Support/Ledgelings`, not with the other settings.

With a model chosen on the Talk tab, the thrower's note is written for the moment,
while the plane is in the air (one short call, Costs › Reminders); with the built-in
lines every character has two notes of its own. A letter late by more than two
minutes says so: *REMINDER · for Today 14:30*. Every letter is also in the Chats tab.

## Voice tab

macOS only for now. The left column is how they all sound; the right column,
**Characters**, is one card per character on screen. Every line that appears in a bubble, from a meeting, a poke, a
paper plane or the built-in lines, is also read out loud, one line at a time in the
order they came. When the talk runs far ahead of the voice (four lines waiting),
new lines are skipped rather than read long after their bubble is gone. Emoji and
`*stage directions*` are not read.

Out loud there is **one conversation at a time**: while a pair is talking, another
pair that meets only bumps (stars, and the flower if one is due), and a paper plane
that lands is held until the talk ends (a minute at most) before it is read.

With voice on, a bubble first shows `...`, a dot more every third of a second, while
its sound is on its way (an OpenRouter line can take a second or two). When the
voice starts, the line types itself out in step with it: word by word with the
Mac's voices, which say where they are, and evenly over the clip's length with
OpenRouter. The bubble is sized for the whole line from the start, so it does not
grow as the words come in. A line that cannot be said (stopped, failed, skipped)
shows in full at once. A bubble gives up waiting after 45 s.

| Setting | Default | Range | Notes |
|---|---|---|---|
| **Hear them talk out loud** | off | | Also in the menu as **Hear Them Talk**. Turning it off stops the voice mid-word |
| **Voices** | Built-in voices | | or OpenRouter, or Local server. Switching stops whatever is being said |
| **Every character gets a voice of their own** | on | | Each name gets its own voice, the same one every launch; two share only once the voices run out. Off: everyone uses the **Voice** below |
| **Cartoon voices: squeakier, sillier** | on | | Every character speaks 1.15 to 1.6 times higher (its own height, on top of **Pitch**), and the playful voices go first: on the Mac the character voices (Grandma, Grandpa, Rocko, Shelley, Eddy…) and the talking novelty ones (Zarvox, Bubbles, Junior, Trinoids, Boing…), never the singing ones (Bells, Cellos, Organ, Good News, Bad News, Superstar); on OpenRouter voice names such as `English_AnimeCharacter`, `English_PlayfulGirl`, `en_paul_excited`, when a model has at least two. Off: plain voices, each nudged only slightly. Acting directions in the text ("say it squeaky") do not work: Gemini reads them out |
| **Voice** (Built-in) | System default | | Every voice the Mac has in your language, novelty voices (Bells, Zarvox…) included. With a voice each, novelty voices are left out and every character also gets a slightly different pitch. More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices |
| **API key** (OpenRouter) | | | The brain's key, shown here only when the brain is not OpenRouter |
| **Model** (OpenRouter) | `hexgrad/kokoro-82m` | | Every OpenRouter speech model, with its price, fetched live. Kokoro costs about $0.00003 a line. The free models have daily limits the creatures would hit |
| **Voice** (OpenRouter) | the model's first | | That model's voices. With a voice each, the English ones are used when the model's voice names say which they are |
| **Keep every line it says** (OpenRouter) | on | | Each line is saved as a WAV file in `~/Library/Application Support/Ledgelings/voices/<day>/<time>-<speaker>-<key>.wav`, beside the chats, and listed in `voices/voices.jsonl` (time, speaker, text, model, voice, speed, file). **Reveal in Finder** opens the folder. A line already kept in the same model, voice and speed is played from there, free, whether or not this is on |
| **Server** / **Model** / **Voice** (Local server) | `http://localhost:8880`, `kokoro`, the server's first | | Any speech server on this Mac that answers like OpenAI's `/v1/audio/speech` and lists voices at `/v1/audio/voices`: Kokoro-FastAPI, LMS Speaks. Free; nothing priced, and only the built-in lines are kept (below). **Check** lists the voices; **Copy Setup Command** puts Kokoro-FastAPI's install-and-start line on the clipboard (`[ -d ~/Kokoro-FastAPI ] || git clone https://github.com/remsky/Kokoro-FastAPI.git ~/Kokoro-FastAPI; cd ~/Kokoro-FastAPI && { [ -d .venv ] || uv venv; } && HOST=127.0.0.1 ./start-gpu_mac.sh`, needs git and uv, downloads about a gigabyte once). LM Studio cannot speak itself, but it can run **Orpheus** for [Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI): load `lex-au/Orpheus-3b-FT-Q4_K_M.gguf` in LM Studio, point Orpheus-FastAPI's `ORPHEUS_API_URL` at `http://127.0.0.1:1234/v1/completions`, then use server `http://127.0.0.1:5005`, model `orpheus`. Eight English voices (tara, leah, jess, leo, dan, mia, zac, zoe; the others are other languages and are skipped for a voice each). On an Apple Silicon Mac it makes speech at about a third of real time: a 3 s line takes about 8 s |
| **Save the built-in lines' voices** (OpenRouter, Local server) | on | | Every built-in line (the script's conversations, the ready-made paper-plane notes and thoughts, the Test lines) is saved once said, in `~/Library/Application Support/Ledgelings/line-voices/`, laid out like `voices/` with its own `voices.jsonl`, and played from there the next time the same words come in the same model, voice and speed: made once, never paid for or waited on again. A built-in line goes here instead of the kept lines above. **Saved** counts them; **Reveal in Finder** opens the folder; **Clear** deletes them all, and each is made again when next said. Off: every line is made each time it is said (on OpenRouter, still found among the kept lines above) |
| **Speed** | 1× | 0.5 to 2 | Every engine |
| **Pitch** | 1× | 0.5 to 2 | Both engines. An OpenRouter line is asked for that much slower and played that much faster, like a tape sped up: higher, at the usual pace, with no echo. Kokoro and Gemini honour the slower speed; Voxtral ignores it and Qwen refuses it (the app then leaves it out), so with them a raised pitch also talks faster |
| **Speed follows pitch** | on | | A raised voice also talks a little faster, by the square root of its lift (1.18× at 1.4×), so no voice is ever asked to drawl, which smears into an echo. The Mac's voices are then rendered and sped up like a tape instead of using their own pitch shifter, and the bubble types over the clip's length. Off: the pace stays exact, with some smear on big lifts |
| **Pause before the answer** | 0.35 s | 0 to 2 | Out loud, each line of a conversation or a paper plane waits for the one before to be said, then follows after this pause; its sound is fetched while the other was talking, so it starts at once. The silent bubble timing is not used |
| **Volume** | 0.8 | 0 to 1 | |
| **Test** / **Stop** | | | The first three creatures on screen introduce themselves in their voices, voice on or off |

### Characters

Every character starts automatic. With **Voices fit each character's
personality** (on by default, left column), its description and its species are
read for words that say how it should sound, and the voice, pitch and speed follow:

| Words in the description or species | Voice |
|---|---|
| old, ancient, wise, philosophical, "in my day", proverb | an old voice (Grandpa, Grandma, George…), lower, slower |
| slow, sleepy, nap, lazy, calm, damp, purr | softer, slower |
| fast, quick, speed · tiny, small, little | younger, quicker · higher |
| cheerful, giggly, laughs, bouncy, excited, sweet, adorable | a bright voice, a little higher and quicker |
| grumpy, stubborn, stern, proud, fat, big | a deep voice, lower |
| anxious, worried, nervous | a little higher and quicker |
| robot, antenna, bolts, status, glitch | a robot voice (Zarvox, Trinoids, Fred) |
| ghost, spirit, haunt, hovering | the whisper (only for these) |
| he, sir, grandpa… · she, lady, grandma… | a male · female voice |

Voices are tagged from their names: the Mac reports each one's sex, Kokoro's start
`af_`/`am_`, Orpheus's are known by name, MiniMax's describe themselves
(`English_ManWithDeepVoice`). The characters with the strongest wishes choose first,
each taking the best-fitting voice still free. Words the rules do not know leave a
neutral voice; **Cast with Model** understands any description.

Off, voices are handed out by name only, to differ, with the cartoon lift or a small nudge for pitch.

**Cast with Model** (on a card) and **Cast Everyone with Model** (under the cards) ask
the brain model (LM Studio or OpenRouter; not the built-in lines) to choose a voice
from the engine's list and a pitch and speed, given the character's name, species and
description. Its choice is kept as the character's own, as if picked by hand, with its
reason shown under the card. One call per character, priced into the spend file.

On its card:

| Setting | Default | Range | Notes |
|---|---|---|---|
| **Voice** | Automatic (shows which) | | Any Mac voice, any of the chosen OpenRouter model's voices, or any of the local server's, depending on the engine. With the Local server, **Custom blend…** opens a field for a Kokoro blend: voices joined by `+`, each with an optional weight, `af_bella(2)+am_puck(1)` being two parts Bella to one of Puck. A blend naming a voice the server lacks is flagged in red and the automatic voice is used until it is fixed. OpenRouter's Kokoro refuses blends. A voice picked by hand is that character's alone; the automatic voices are handed out around it. An OpenRouter voice the current model does not have is ignored |
| **Speed** | 1× | 0.5 to 2 | Times the overall Speed |
| **Pitch** | its automatic pitch | 0.5 to 2 | Times the overall Pitch, instead of the automatic lift |
| **Speed follows pitch** | As overall | | On, Off, or as the overall checkbox. On: this character talks a little faster when higher, never smeared. Off: exact pace |
| **Test** / **Auto** | | | Test: it introduces itself. Auto: back to automatic |

Settings follow the character's name, so they survive restarts and species changes,
and apply to both engines (the voice is kept per engine).

### Spend and the archive

Each OpenRouter line goes to the spend file under the speech model's id, priced a
few seconds after it is said, when OpenRouter reports the cost (it sends audio,
not a bill, with the line itself).

### Brain

| Setting | Default | Notes |
|---|---|---|
| **Brain** | Built-in lines | or LM Studio, or OpenRouter. The status line in the menu says why nothing is said when a model is not reachable. An install that had set up a model before v0.15 keeps LM Studio |
| **Lines** (Built-in lines) | ~100 conversations | The script itself, editable in place. One conversation per block, a blank line between blocks; the lines alternate between the one who bumped and the one bumped into, two to four per block. A block may start with `[flower]`, `[night]`, `[day]`, `[holiday]` or `[night, flower]` and is then used only for that moment, in preference to untagged blocks; untagged blocks fit any moment. `[holiday]` blocks come up one conversation in three on a holiday the Calendar tab knows. `{speaker}`, `{listener}`, `{flower}` and `{holiday}` are filled in; `*asterisks*` show as italics; `#` starts a comment. The status line counts the blocks, or names the line with a problem, and the creatures stay quiet until it is fixed. The same conversation is not repeated until half the fitting ones have been heard |
| **Import… / Export…** | | A plain text file in the same format, whole-script in and out |
| **Copy Agent Prompt** | | Puts a request on the clipboard: the format, the rules and the cast in use, asking for 40 more blocks. Paste it into any chat model and paste the answer into the editor |
| **Reset Lines** | | Brings the built-in script back |
| **Server** (LM Studio) | `http://localhost:1234` | Must be a URL with a host. LM Studio's own default |
| **Model** (LM Studio) | `google/gemma-3-1b` | Any model the server has installed. **Check** fetches the list; **Installed** appears next to the field to pick one. The app refuses a model the server does not have, because LM Studio would otherwise silently answer with whatever is loaded |
| **API key** (OpenRouter) | empty | Kept in the keychain on macOS and the Credential Manager on Windows, never in the settings file. Empty means no brain. On macOS the app only reads it once OpenRouter is the chosen brain and something needs it, so picking another brain never touches the keychain; macOS asks once per new build whether Ledgelings may read it, and **Always Allow** stops it asking for that build. Writing the key never asks. The Credential Manager never prompts, so Windows reads it at launch |
| **Model** (OpenRouter) | `anthropic/claude-haiku-4.5` | Any id from openrouter.ai/models. The catalogue below is fetched live: type words from the id or name, cheapest first, free models in green, click a row to pick. 60 rows at a time; add a word to narrow it |
| **Check** | | LM Studio: is the server up, is the model installed. OpenRouter: is the key valid, what it has spent and its limit, does the model exist |

Costs moved to their own tab in v0.18; see [Costs tab](#costs-tab).

### Characters

Every species has a **cast**: names and personalities that go into the prompt.
Blocky's six come built in (Blocky, Pip, Mortimer, Zed, Dot, Ruth); the other
built-ins carry three each in their sheet; an imported sheet without any gets one
placeholder. The first creature wearing a species is its first character, the
second its second, and so on, starting over when the cast runs out. The species
itself (its `kind`, e.g. "a fat green frog with big eyes") is described to the
model, so a frog talks like a frog.

Pick a species, edit names and personalities in place (changes save when a field
loses focus), **Add Character**, remove one with **−** (a cast keeps at least one),
**Reset Cast** to go back to the sheet's own.

### Prompts

Three templates with `{placeholders}`, editable; **Reset Prompts** restores them.

| Template | Used for |
|---|---|
| **Who is speaking** (system prompt) | Both calls: who the speaker is, who it is talking to |
| **Opening line** | The first line of a meeting |
| **Reply** | The answer, with `{line}` being what was just said |

Placeholders: `{speaker}` `{speakerKind}` `{speakerPersona}` `{listener}`
`{listenerKind}` `{listenerPersona}` `{situation}` `{line}`. An unknown placeholder
is left as written. `{situation}` is written by the app: the time of day, where each
creature is ("Dot is on the bottom edge", "asleep on the ceiling", "dangling from the
user's cursor", "mid-jump") and, for a meeting, "They just walked into each other."
or "Pip just walked into Dot and gave Dot a poppy."

The model's answer is cleaned before it is shown: anything before a `</think>` tag
is dropped, the first non-empty line is taken, a leading "Name:" and wrapping quotes
or asterisks are stripped, and it is cut at 160 characters. Calls use temperature
0.9 and at most 80 tokens.

## Costs tab

Every call to a model, text or voice, whether or not its answer was usable, is
appended to `spend.jsonl` with its tokens, the feature that made it and, for
OpenRouter, the price OpenRouter itself reports (for speech, looked up a few seconds
after the line). LM Studio calls are recorded at $0; a local speech server and the
Mac's own voices are free and record nothing.

| Column | What it shows |
|---|---|
| **Spent** (left) | Today, this month, all time: cost, calls, tokens |
| **By feature** (left) | Talk, Paper planes, Voice, Voice casting, Relationship plots; calls from before v0.18 as *Earlier, unlabelled* |
| **By model** (left) | The ten dearest models |
| **Latest calls** (right) | The last 200, newest first: model, time, feature, tokens, cost (*no price* in orange) |
| **The file** (right) | `spend.jsonl`'s path and Reveal in Finder |

A `+` after a total means some of its calls came back without a price. Money reads
`$0.00`, `<$0.001`, three decimals under ten cents, else two.

## Chats tab

Every conversation that produced at least one line is written when it ends, to one
JSON-lines file per local calendar day. The tab lists the days on the left (today
and yesterday by name) and each exchange on the right: time, model, cost and tokens
when known, the situation, then each line. When the lines were said out loud by an
OpenRouter voice, the header also shows **voice $x (n lines)**, with `+` if a
price never came back and **n replayed free** for lines played from the voice
archive; hover it for the speech model. Those prices are kept beside the day's
file in `YYYY-MM-DD.voice.jsonl`, one line per spoken line (time, speaker, words,
model, cost, kept), because OpenRouter reports them seconds after the conversation
is written down; each goes to the latest conversation with that speaker saying
those words. The built-in voices are free and write nothing. Buttons open the folder in Finder or
Explorer and in a terminal. The files are plain text on purpose; one line looks like:

```json
{"time": "2026-09-18T14:03:11Z",
 "situation": "For the person at this computer it is Friday, 18 September 2026, afternoon (17:03). On the edge it is day. Dot is on the bottom edge. Blocky is on the bottom edge. They just walked into each other.",
 "provider": "LM Studio", "model": "google/gemma-3-1b",
 "lines": [{"speaker": "Dot", "text": "Move, boulder."}, {"speaker": "Blocky", "text": "Says the pebble."}],
 "cost": 0.00084, "tokens": 660}
```

Where the files live on each platform is in [INSTALL.md](INSTALL.md).
