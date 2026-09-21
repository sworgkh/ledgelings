# Settings, the menu, and your hand

Every setting is saved as you change it and applied live; nothing needs a restart.
On macOS the window is *menu bar icon › Settings…*; on Windows it is *tray icon ›
Settings…*. Four tabs: **Creatures**, **Sprites**, **Talk**, **Chats**.

## The menu

| Item | What it does |
|---|---|
| *Day — they sleep in m:ss* / *Night — they wake in m:ss* | The colony's clock. Reads *Always day — night is set to 0* when the night is off |
| **Put Them to Sleep Now** / **Wake Them Up Now** | Skips to the next dusk or dawn. Hidden when the night is 0 |
| **Make Them Jump** | Every creature startles and jumps to another edge |
| **Hide Them for a While…** | Asks how long (5, 15, 30 minutes; 1, 2, 4 hours; until 08:00 tomorrow) and sends everyone into the house. While they are away the item reads **Bring Them Back Now (m:ss left)** and ends it early |
| **Make Someone Talk** | A random awake creature says something to the nearest one |
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
| **The one with the flower follows the giver while it lasts** | on | | The wearer trails the giver around the edge, stopping about a body behind, until the flower wilts. It still sleeps, flees the cursor and stops to talk like anyone else |

A pair of creatures meets at most once a minute; passing each other in between is
just passing. Every third meeting of the same pair is a gift: one hands the other
one of ten flowers (poppy, tulip, daisy, sunflower, rose, bluebell, dandelion,
lavender, lily, forget-me-not), and the conversation is about it.

### Brain

| Setting | Default | Notes |
|---|---|---|
| **Brain** | LM Studio | or OpenRouter. The status line in the menu says why nothing is said when the brain is not reachable |
| **Server** (LM Studio) | `http://localhost:1234` | Must be a URL with a host. LM Studio's own default |
| **Model** (LM Studio) | `google/gemma-3-1b` | Any model the server has installed. **Check** fetches the list; **Installed** appears next to the field to pick one. The app refuses a model the server does not have, because LM Studio would otherwise silently answer with whatever is loaded |
| **API key** (OpenRouter) | empty | Kept in the keychain (macOS) or Credential Manager (Windows), never in a settings file. Empty means no brain |
| **Model** (OpenRouter) | `anthropic/claude-haiku-4.5` | Any id from openrouter.ai/models. The catalogue below is fetched live: type words from the id or name, cheapest first, free models in green, click a row to pick. 60 rows at a time; add a word to narrow it |
| **Check** | | LM Studio: is the server up, is the model installed. OpenRouter: is the key valid, what it has spent and its limit, does the model exist |

### Spend

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
