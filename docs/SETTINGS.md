# Settings, the menu, and your hand

Every setting is saved as you change it and applied live; nothing needs a restart.
On macOS the window is *menu bar icon › Settings…*; on Windows it is *tray icon ›
Settings…*. Four tabs: **Creatures**, **Sprites**, **Talk**, **Chats**, each in two columns so a tab fits on one screen.

## The menu

| Item | What it does |
|---|---|
| *Day — they sleep in m:ss* / *Night — they wake in m:ss* | The colony's clock. Reads *Always day — night is set to 0* when the night is off |
| **Put Them to Sleep Now** / **Wake Them Up Now** | Skips to the next dusk or dawn. Hidden when the night is 0 |
| **Make Them Jump** | Every creature startles and jumps to another edge |
| **Hide Them for a While…** | Asks how long (5, 15, 30 minutes; 1, 2, 4 hours; until 08:00 tomorrow) and sends everyone into the house. While they are away the item reads **Bring Them Back Now (m:ss left)** and ends it early |
| **Make Someone Talk** | A random awake creature says something to the nearest one |
| **Send a Paper Plane** | One free creature throws a paper plane to another now, whatever the setting below says |
| **Hear Them Talk** (⌘V) | Voice on or off: every bubble read out loud (Talk tab › Voice). Ticked while on |
| *the status line* | The last thing that happened with the model: a line, or why nothing was said |
| **Chat History…** | The Chats tab |
| *Spent: $a today, $b this month* | Shown once there is a record; opens the Talk tab |
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

### Voice

macOS only for now. Every line that appears in a bubble, from a meeting, a poke, a
paper plane or the built-in lines, is also read out loud, one line at a time in the
order they came. When the talk runs far ahead of the voice (four lines waiting),
new lines are skipped rather than read long after their bubble is gone. Emoji and
`*stage directions*` are not read.

| Setting | Default | Range | Notes |
|---|---|---|---|
| **Hear them talk out loud** | off | | Also in the menu as **Hear Them Talk**. Turning it off stops the voice mid-word |
| **Voices** | Built-in voices | | or OpenRouter. Switching stops whatever is being said |
| **Every character gets a voice of their own** | on | | Each name gets its own voice, the same one every launch; two share only once the voices run out. Off: everyone uses the **Voice** below |
| **Voice** (Built-in) | System default | | Every voice the Mac has in your language, novelty voices (Bells, Zarvox…) included. With a voice each, novelty voices are left out and every character also gets a slightly different pitch. More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices |
| **API key** (OpenRouter) | | | The brain's key, shown here only when the brain is not OpenRouter |
| **Model** (OpenRouter) | `hexgrad/kokoro-82m` | | Every OpenRouter speech model, with its price, fetched live. Kokoro costs about $0.00003 a line. The free models have daily limits the creatures would hit |
| **Voice** (OpenRouter) | the model's first | | That model's voices. With a voice each, the English ones are used when the model's voice names say which they are |
| **Speed** | 1× | 0.5 to 2 | Both engines |
| **Pitch** | 1× | 0.5 to 2 | Built-in voices only; OpenRouter has no such knob |
| **Volume** | 0.8 | 0 to 1 | |
| **Test** / **Stop** | | | The first three creatures on screen introduce themselves in their voices, voice on or off |

Each OpenRouter line goes to the spend file under the speech model's id, priced a
few seconds after it is said, when OpenRouter reports the cost (it sends audio,
not a bill, with the line itself).

### Brain

| Setting | Default | Notes |
|---|---|---|
| **Brain** | Built-in lines | or LM Studio, or OpenRouter. The status line in the menu says why nothing is said when a model is not reachable. An install that had set up a model before v0.15 keeps LM Studio |
| **Lines** (Built-in lines) | ~100 conversations | The script itself, editable in place. One conversation per block, a blank line between blocks; the lines alternate between the one who bumped and the one bumped into, two to four per block. A block may start with `[flower]`, `[night]`, `[day]` or `[night, flower]` and is then used only for that moment, in preference to untagged blocks; untagged blocks fit any moment. `{speaker}`, `{listener}` and `{flower}` are filled in; `*asterisks*` show as italics; `#` starts a comment. The status line counts the blocks, or names the line with a problem, and the creatures stay quiet until it is fixed. The same conversation is not repeated until half the fitting ones have been heard |
| **Import… / Export…** | | A plain text file in the same format, whole-script in and out |
| **Copy Agent Prompt** | | Puts a request on the clipboard: the format, the rules and the cast in use, asking for 40 more blocks. Paste it into any chat model and paste the answer into the editor |
| **Reset Lines** | | Brings the built-in script back |
| **Server** (LM Studio) | `http://localhost:1234` | Must be a URL with a host. LM Studio's own default |
| **Model** (LM Studio) | `google/gemma-3-1b` | Any model the server has installed. **Check** fetches the list; **Installed** appears next to the field to pick one. The app refuses a model the server does not have, because LM Studio would otherwise silently answer with whatever is loaded |
| **API key** (OpenRouter) | empty | Kept in the keychain on macOS and the Credential Manager on Windows, never in the settings file. Empty means no brain. On macOS the app only reads it once OpenRouter is the chosen brain and something needs it, so picking another brain never touches the keychain; macOS asks once per new build whether Ledgelings may read it, and **Always Allow** stops it asking for that build. Writing the key never asks. The Credential Manager never prompts, so Windows reads it at launch |
| **Model** (OpenRouter) | `anthropic/claude-haiku-4.5` | Any id from openrouter.ai/models. The catalogue below is fetched live: type words from the id or name, cheapest first, free models in green, click a row to pick. 60 rows at a time; add a word to narrow it |
| **Check** | | LM Studio: is the server up, is the model installed. OpenRouter: is the key valid, what it has spent and its limit, does the model exist |

### Spend

Shown for LM Studio and OpenRouter; the built-in lines cost nothing and record nothing.
Every call to the model, whether or not its line was usable, is appended to
`spend.jsonl` with its tokens and, for OpenRouter, the price OpenRouter itself
reports for that call. LM Studio calls are recorded at $0. The section shows today,
this month and all time (calls, tokens, cost), the five dearest models, and the
file's path with a button to reveal it. A `+` after a total means some of its calls
came back without a price. Money reads `$0.00`, `<$0.001`, three decimals under ten
cents, else two.

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

## Chats tab

Every conversation that produced at least one line is written when it ends, to one
JSON-lines file per local calendar day. The tab lists the days on the left (today
and yesterday by name) and each exchange on the right: time, model, cost and tokens
when known, the situation, then each line. Buttons open the folder in Finder or
Explorer and in a terminal. The files are plain text on purpose; one line looks like:

```json
{"time": "2026-09-18T14:03:11Z",
 "situation": "It is day. Dot is on the bottom edge. Blocky is on the bottom edge. They just walked into each other.",
 "provider": "LM Studio", "model": "google/gemma-3-1b",
 "lines": [{"speaker": "Dot", "text": "Move, boulder."}, {"speaker": "Blocky", "text": "Says the pebble."}],
 "cost": 0.00084, "tokens": 660}
```

Where the files live on each platform is in [INSTALL.md](INSTALL.md).
