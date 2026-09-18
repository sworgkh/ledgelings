# Ledgelings

Native macOS app. Tiny creatures crawl around the **edges of your screens** —
along the borders, over the corners, between monitors.

Ambient, click-through, menu-bar only. Not a game, not a widget.

**Status:** v0.2 — a colony on every monitor, with settings and a day/night cycle.
See [BRIEF.md](BRIEF.md) for the plan.

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
| **Shift-click** a creature | It naps on the spot, day or night. Shift-click a sleeper to wake it. A nap also ends at the next dawn |
| **Drag** a sleeper | It comes along, still asleep. Let go and it drops to the nearest edge of whichever monitor it is over |

A sleeper never notices the cursor — that is what lets you grab it. The overlay is
still click-through: it turns clickable only while the cursor is on a creature you
can act on, and it never takes focus from the app you are in.

**They talk.** Once an hour, or when you pick **Make Someone Talk** in the menu, one
creature says a line to its nearest neighbour and the neighbour answers. The lines
come from a small language model running on your Mac in [LM Studio](https://lmstudio.ai),
so nothing leaves the machine. Each creature has a character: a name and a
personality that goes into the prompt. Six come built in; edit them, and the
prompts themselves, in Settings → Talk.

To make it work: install LM Studio, download `google/gemma-3-1b` in it, and keep its
local server running:

```bash
lms get google/gemma-3-1b --mlx
lms server start
```

Settings → Talk → **Check** tells you whether the app can see the server and the
model. If LM Studio is off, the creatures simply stay quiet; the menu shows why.

**Settings** (menu bar icon → Settings…), all saved:

| Setting | Default | Notes |
|---|---|---|
| How many | 3 | 1 to 24 |
| Smallest / Largest | 1.5× / 3× | 1× to 5× in half steps. Every creature gets its own size between the two; set them equal and they all match |
| Colours | 6 | creature 1 wears colour 1, and so on, wrapping round. Eyes stay black |
| Day lasts | 3 min | |
| Night lasts | 5 min | 0 = they never sleep |
| Talk every | 60 min | 0 = only on request |
| Server, model | `http://localhost:1234`, `google/gemma-3-1b` | any model LM Studio has installed |
| Characters | 6 built in | name + personality; creature 1 is character 1, wrapping round |
| Prompts | built in | the system prompt, the opening line and the reply, with `{placeholders}` |

The menu also shows the time left until dusk or dawn, and has **Put Them to Sleep
Now / Wake Them Up Now** and **Make Them Jump**.

Not yet: launch at login, more species.

## Run it

```bash
swift run Ledgelings                                   # from a terminal; Ctrl-C to stop
scripts/make-app.sh && open build/Ledgelings.app       # a real menu-bar app
swift test                                             # geometry, brain, recolouring, prompts
LEDGELINGS_LIVE=1 swift test --filter TalkServiceTests     # a real exchange through LM Studio
```

Everything else is under the menu-bar icon, a filled square.

## Install it

```bash
scripts/make-installer.sh        # VERSION=0.3.0 scripts/make-installer.sh to set the version
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
                            Creature   the brain: walk, idle, blink, jump, sleep
                            DayNight   the colony's clock
                            Banter     characters, prompt templates, cleaning a model's line
Sources/Ledgelings/       the app: Colony (creatures + clock + talk), one ScreenOverlay per monitor
                          with sprites and speech bubbles, TalkService (LM Studio), SpriteAtlas, settings
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
