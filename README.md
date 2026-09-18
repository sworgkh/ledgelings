# Ledgelings

Native macOS app. Tiny creatures crawl around the **edges of your screens** —
along the borders, over the corners, between monitors.

Ambient, click-through, menu-bar only. Not a game, not a widget.

**Status:** v0.7 — a colony on every monitor that talks when it meets, gives flowers,
thinks locally or through OpenRouter, keeps every chat, and goes home when asked.
See [BRIEF.md](BRIEF.md) for the original plan and [SPEC.md](SPEC.md) for the full,
platform-neutral specification of everything the app does.

## What it does

**Blocky** is a square sprite with two black rectangle eyes. Each one crawls the
edges of your monitors, turns the corners, stops now and then, and blinks. Move the
cursor within ~90 points and it jumps to a random spot on a different edge, on any
monitor. The overlay never takes a click: a creature asks where the cursor is, it
does not receive mouse events.

**All monitors, one outline.** Monitors that touch are fused, and the creatures walk
the outline of the whole desktop. They cross from one monitor to the next along a
shared floor, climb the wall where a taller monitor begins, and never walk the
invisible seam between two screens. Unplug a monitor and everyone on it moves to
the nearest edge that still exists.

**Day and night.** The colony shares one clock: 3 minutes of day, then 5 of night,
forever. At dusk each creature wanders a few more seconds, then slumps, shuts its
eyes and floats Zs. At dawn they wake a few seconds apart.

**Your hand.** Three rules:

| You do | What happens |
|---|---|
| Hold **Shift** | Nobody flees, so you can get the cursor onto one |
| **Shift-click** a creature | A poke: it says something to whoever is nearest, and they stop to talk |
| **Shift-drag** a creature | It comes along, awake or asleep, and lands the same way on the nearest edge of whichever monitor it is over |
| **Drag** a sleeper | Same, no Shift needed: a sleeper never notices the cursor |
| **Shift-right-click** a creature | It naps on the spot, day or night. Same again to wake it. A nap also ends at the next dawn |

A sleeper never notices the cursor — that is what lets you grab it. The overlay is
still click-through: it turns clickable only while the cursor is on a creature you
can act on, and it never takes focus from the app you are in.

**They talk.** When two creatures walk into each other on the same edge, a few pixel
stars fly up, both stop and turn to face each other, one says a line, the other
answers, and then each goes on its way, like two people who meet in the street. A
pair only meets once a minute, so passing each other in between is just passing.
**Make Someone Talk** in the menu does the same at any time. Click a speech bubble
to close it. The lines come from a language model,
and Settings → Talk → **Brain** picks which one:

- **LM Studio** (default): a small model running on your Mac in
  [LM Studio](https://lmstudio.ai), so nothing leaves the machine.
- **OpenRouter**: any model on [openrouter.ai](https://openrouter.ai), for better
  lines at a few cents a day. Paste an API key (it goes in your keychain, not in a
  preferences file) and a model id; the default is `anthropic/claude-haiku-4.5`.
  Give the key a spending limit when you make it. **Check** confirms the key and
  shows what it has spent. Below it, the whole OpenRouter catalogue is fetched
  live: search by any words in the id or name ("flash lite", "gemma", "free"),
  cheapest first with prices per million tokens, click to pick. For one-line
  banter, `google/gemini-2.5-flash-lite` or `google/gemma-3-12b-it` cost about a
  tenth of Haiku and are quicker.

Each creature has a character: a name and a personality that goes into the prompt.
Six come built in; edit them, and the prompts themselves, in Settings → Talk.

**They can go home for a while.** **Hide Them for a While…** in the menu asks how
long (5 minutes to "until tomorrow morning"). A little house appears on the bottom
edge of the main screen, everyone runs or jumps home, the house shrinks to
nothing, and when the time is up it grows back and they walk out one by one. The
same menu item, now **Bring Them Back Now**, ends it early.

**Every chat is kept.** Each conversation goes to
`~/Library/Application Support/Ledgelings/chats/YYYY-MM-DD.jsonl`, one line per
exchange with the time, the situation, the model and what each of them said.
**Chat History…** in the menu (or Settings → Chats) shows each day's chats, with
buttons to open the folder in Finder or Terminal.

**They give flowers.** Every third time the same two creatures bump into each other,
one hands the other a flower, which it then wears on its head for a couple of
minutes before it wilts away. Ten flowers, drawn
by `sprites/flowers.yaml`: poppy, tulip, daisy, sunflower, rose, bluebell,
dandelion, lavender, lily and forget-me-not.

For LM Studio: install it, download `google/gemma-3-1b` in it, and keep its local
server running:

```bash
lms get google/gemma-3-1b --mlx
lms server start
```

Settings → Talk → **Check** tells you whether the app can see the server and the
model. If the brain is off or the key is missing, the creatures simply stay quiet;
the menu shows why.

**Settings** (menu bar icon → Settings…), all saved:

| Setting | Default | Notes |
|---|---|---|
| How many | 3 | 1 to 24 |
| Smallest / Largest | 1.5× / 3× | 1× to 5× in half steps. Every creature gets its own size between the two; set them equal and they all match |
| Colours | 6 | creature 1 wears colour 1, and so on, wrapping round. Eyes stay black |
| Day lasts | 3 min | |
| Night lasts | 5 min | 0 = they never sleep |
| Bubble stays | 14 s | 4 to 60 s; longer lines stay a little longer, never past twice this |
| Flower lasts | 2 min | 0.5 to 30 min on the head, then it wilts |
| Brain | LM Studio | or OpenRouter |
| LM Studio server, model | `http://localhost:1234`, `google/gemma-3-1b` | any model LM Studio has installed |
| OpenRouter key, model | none, `anthropic/claude-haiku-4.5` | key in the keychain; any id from openrouter.ai/models |
| Characters | 6 built in | name + personality; creature 1 is character 1, wrapping round |
| Prompts | built in | the system prompt, the opening line and the reply, with `{placeholders}` |

The menu also shows the time left until dusk or dawn, and has **Put Them to Sleep
Now / Wake Them Up Now**, **Make Them Jump**, **Hide Them for a While…**, **Make Someone
Talk** and **Chat History…**.

Not yet: launch at login, more species.

## Run it

```bash
swift run Ledgelings                                   # from a terminal; Ctrl-C to stop
scripts/make-app.sh && open build/Ledgelings.app       # a real menu-bar app
swift test                                             # geometry, brain, recolouring, prompts
LEDGELINGS_LIVE=1 swift test --filter ChatClientLiveTests            # a real line through LM Studio
OPENROUTER_API_KEY=sk-or-… swift test --filter ChatClientLiveTests   # and through OpenRouter
```

Everything else is under the menu-bar icon, a filled square.

## Install it

```bash
scripts/make-installer.sh        # VERSION=0.8.0 scripts/make-installer.sh to set the version
```

| File | What it is |
|---|---|
| `build/Ledgelings-<version>.pkg` | Double-click installer. Puts `Ledgelings.app` in `/Applications` |
| `build/Ledgelings-<version>.dmg` | Disk image. Open it and drag the app onto Applications |

Both files, and the app, wear the creature as their icon. The icon is drawn from
the same sprite atlas the app animates: `python -m spritetool icon sprites/blocky.yaml`.

The app is ad-hoc signed, not notarised. On this Mac it just opens. On another Mac,
Gatekeeper objects the first time: right-click the app or the `.pkg` and choose **Open**.

## Sprites

Art is a sprite sheet, and a sheet is described by a **recipe** — `sprites/blocky.yaml`.
A recipe declares the layout (columns = poses, rows = how closed the eyes are),
never the pixels. `spritetool` does the rest:

```bash
pip install -r spritetool/requirements.txt

python -m spritetool template sprites/blocky.yaml   # a labelled layout PNG + a prompt, to paint into
python -m spritetool pack sprites/blocky.yaml --from painted.png   # painted sheet -> atlas for the app
python -m spritetool build sprites/blocky.yaml      # draw in code + pack + previews
python -m pytest spritetool -q
```

| Command | Reads | Writes |
|---|---|---|
| `template` | the recipe | `work/<name>/template.png`, `work/<name>/prompt.txt` |
| `draw` | the recipe's `painter` | `work/<name>/painted.png` |
| `pack` | a painted sheet, at any whole-number scale | `<name>.png` + `<name>.json` in the app's resources, plus `work/<name>/contact.png` and one GIF per animation |
| `build` | the recipe | everything `draw` and `pack` write |
| `icon` | the packed atlas | `build/AppIcon.iconset`, ready for `iconutil -c icns` |

The template is the idea borrowed from `gig-tools/spritekit`: **show the layout,
don't describe it.** Every cell is outlined and named, with a dashed box the
creature must stay inside and a floor line its feet must touch, all on the exact
key colour (`#ff00ff`). Hand that image plus `prompt.txt` to an image model or an
artist. `pack` then cuts the key colour to real 1-bit transparency itself rather
than trusting anyone to deliver clean alpha.

`sprites/zzz.yaml` is a second, one-cell recipe: the Z a sleeper floats.
`sprites/house.yaml` is the house, drawn from shapes by `spritetool/painters/house.py`.
`sprites/flowers.yaml` is the ten flowers, one cell each, drawn by
`spritetool/painters/flowers.py` from hand-placed pixel glyphs with the outline added in code.

A recipe may declare a `palette`. The painter draws with exactly those colours and
they are written into the atlas, which is how the app recolours a creature: it
swaps those pixels for shades of the colour you picked and touches nothing else.

Two rules for any new creature: draw it **standing on a floor, facing right**, and
keep it **centred in its cell**. The app mirrors it to walk the other way and
rotates it about the cell centre to turn a corner.

## Layout

```
Sources/LedgelingsCore/   pure logic, no AppKit:
                            EdgeWorld  fuses the monitors into walkable loops
                            EdgeLoop   one closed loop; a position is a single number
                            Creature   the brain: walk, idle, blink, jump, sleep, stop to chat
                            DayNight   the colony's clock
                            Meetings   who bumped into whom, once per touch, with a cooldown
                            Gifts      flowers in flight and on heads
                            Sparks     the pixel stars of a bump
                            Hideout    the house: appear, gather, shrink, hide, grow, release
                            Banter     characters, prompt templates, cleaning a model's line
                            ChatLog    conversations on disk, one JSON-lines file per day
Sources/Ledgelings/       the app:
                            Colony            creatures + clock + monitors + the frame loop
                            Colony+Meetings   the stop, the stars, the flower, letting go
                            Colony+Talk       who says what to whom, the bubbles
                            Colony+Hand       clicks, pokes, drags
                            Colony+Hideout    sending everyone home and letting them out
                            ScreenOverlay     one per monitor: sprites, bubbles, stars, flowers
                            ChatClient        LM Studio or OpenRouter, for banter and anything else
                            ModelCatalog      OpenRouter's model list, searched and priced
                            ChatHistory       the log folder, and the Chats tab (ChatHistoryView)
                            Keychain, SpriteAtlas, AppSettings, SettingsView, TalkSettingsView
Tests/                    unit tests for both
spritetool/               the sprite sheet tool (Python: Pillow + PyYAML)
sprites/                  recipes
scripts/make-app.sh       wrap the release binary as Ledgelings.app, with its icon
scripts/make-installer.sh the .pkg and .dmg
```

## Stack

- macOS 26+, Swift 6, Swift Package Manager (no Xcode project)
- One AppKit overlay window per monitor, plain `CALayer`s, one 30 fps display link (12 fps while all sleep)
- SwiftUI for the settings window only
- Apple Silicon
