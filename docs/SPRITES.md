# Sprites: your own creatures, and the built-in art

## The sprite kit (for users)

A creature is nine 32×32 poses. The app can read them as **letters**, which is
something any chat model can write, so making a new creature is a conversation:

1. Settings › Sprites › **Copy Prompt**.
2. Paste it into any chat model and replace `<describe your creature here>` with
   what you want ("a fat green frog with big eyes", "a grumpy teapot").
3. Save the model's answer as a `.txt` file and Settings › Sprites › **Import Sheet…**.

The new species appears as a card, joins the colony, blinks, walks, turns corners
and takes your colours like the built-in ones. It talks as what it is, with the
characters the model gave it. If the import is refused, the message says which pose
and row is wrong; fix the text and import again, or ask the model to.

### The text format

```
name: pip
kind: a fat green frog with big eyes            (optional)
colour: #6cbf4a                                 (optional; `color:` too; six hex digits)
character: Hopper: Bouncy and loud.             (optional, any number; "Name: persona")
pose: idle
<32 rows of 32 letters>
pose: walk-0 … walk-3, jump, land, sleep-0, sleep-1
```

| Letter | Means |
|---|---|
| `.` | nothing (also `-`, `_` and space) |
| `o` | outline, the dark line around the body |
| `b` | body, the main colour |
| `l` | light, a highlight along the top and left inside the outline |
| `s` | shade, a shadow along the bottom and right inside the outline |
| `k` | an eye pixel, black. Make each eye a vertical block; the app blinks by lowering a lid over it |
| `x` | black that never blinks (a mouth, a spot) |

`#` lines are comments; a short row of nothing is padded. The rules the import checks:

- Every pose is exactly 32 rows of 32 letters, in this order: `idle`, `walk-0`,
  `walk-1`, `walk-2`, `walk-3`, `jump`, `land`, `sleep-0`, `sleep-1`. A missing or
  unknown pose, a row of the wrong length or a strange letter is refused by name.
- The body stays inside columns 6 to 27 and rows 6 to 27 (1-based); ink outside is refused.
- Row 27 is the floor: every pose must have ink on it. The creature stands on it,
  **facing right**; the app mirrors it to walk the other way and rotates it about the
  cell's centre to turn a corner, so keep it roughly centred.
- `name` is one lowercase word (letters, digits, dashes), not a built-in name.

What the header lines do:

- `kind` is how the species is described to the model when it talks.
- `colour` makes the species always wear that colour, whatever colour slot its
  creature lands in (the shipped frog, ghost, slime, robot and mushroom do this).
  Leave it out and the creature wears the colour of its number.
- `character` lines are the species' cast; the prompt asks for three. Without any,
  the species gets one placeholder character you can edit in Settings › Talk.

### Painting instead

**Save PNG Template…** writes a 288×96 sheet on magenta (`#ff00ff`) with every cell
and body box marked: nine pose columns, three eye rows (open, half, closed). Paint
on it, or hand it to an image model, and import the PNG. Magenta becomes
transparent, alpha is hardened to 1 bit, and a sheet painted at 2× or 3× is sampled
down. Use the four palette colours (body `#ff8a3d`, light `#ffb27a`, shade
`#d66220`, outline `#3b1f0f`) for the body if you want recolouring to work; any
other colour is drawn as painted.

### Where they live

An imported creature becomes a normal atlas, `<name>.png` + `<name>.json`, in the
app's sprites folder (`~/Library/Application Support/Ledgelings/sprites/<name>/` on
macOS, `%APPDATA%\Ledgelings\sprites\<name>\` on Windows), with the original `.txt`
beside it. **Open Folder** in Settings › Sprites takes you there. Copy a folder to
another machine, of either platform, and it works there too.

## spritetool (for the built-in art)

The shipped sheets are made by `spritetool`, a small Python tool. A sheet is
described by a **recipe** (`sprites/blocky.yaml`) that declares the layout (columns
= poses, rows = how closed the eyes are), never the pixels.

```bash
pip install -r spritetool/requirements.txt

python -m spritetool template sprites/blocky.yaml   # a labelled layout PNG + a prompt, to paint into
python -m spritetool pack sprites/blocky.yaml --from painted.png   # painted sheet -> atlas for the app
python -m spritetool build sprites/blocky.yaml      # draw in code + pack + previews
python -m spritetool icon sprites/blocky.yaml       # the app icon, from the packed atlas
python -m pytest spritetool -q
```

| Command | Reads | Writes |
|---|---|---|
| `template` | the recipe | `work/<name>/template.png`, `work/<name>/prompt.txt` |
| `draw` | the recipe's `painter` | `work/<name>/painted.png` |
| `pack` | a painted sheet, at any whole-number scale | `<name>.png` + `<name>.json` in `Sources/Ledgelings/Resources/sprites/`, plus `work/<name>/contact.png` and one GIF per animation |
| `build` | the recipe | everything `draw` and `pack` write |
| `icon` | the packed atlas | `build/AppIcon.iconset`, ready for `iconutil -c icns` |

The template is the idea borrowed from `gig-tools/spritekit`: **show the layout,
don't describe it.** Every cell is outlined and named, with a dashed box the
creature must stay inside and a floor line its feet must touch, all on the exact
key colour. `pack` cuts the key colour to real 1-bit transparency itself rather
than trusting anyone to deliver clean alpha.

The recipes:

| Recipe | What | Drawn by |
|---|---|---|
| `sprites/blocky.yaml` | the square creature, 9 poses × 3 eye rows | `spritetool/painters/blocky.py` |
| `sprites/zzz.yaml` | the Z a sleeper floats, one cell | `painters/zzz.py` |
| `sprites/house.yaml` | the house, 68×60 | `painters/house.py` |
| `sprites/flowers.yaml` | ten flowers, one cell each | `painters/flowers.py`, from hand-placed glyphs with the outline added in code |
| `sprites/text/*.txt` | frog, cat, ghost, slime, robot, triangle, mushroom, in the letter format | `sprites/text/make.py` (shapes plus an automatic outline, light and shade) |

The text creatures are turned into sheets by the app's own code:
`LEDGELINGS_BUILD_CREATURES=1 swift test --filter ShippedCreaturesTests` rebuilds
them, and the same test without the variable (and its Windows twin) fails if a
shipped sheet drifts from its text.

A recipe may declare a `palette`. The painter draws with exactly those colours and
they are written into the atlas JSON, which is how the app recolours a creature: it
swaps those pixels for shades of the chosen colour (light = 36 % toward white,
shade = 17 % toward black, outline = 76 % toward black) and touches nothing else.

### The atlas format

Each sheet is a PNG plus a JSON file with `cell`, `contentBox`, `variants`,
`palette`, `frames` (name → rectangle, top-left origin) and `animations`
(name → frames, fps, loop), plus the optional `kind`, `cast` and `colour`. The exact
shape, the frame lookup rule and the sizes of the shipped sheets are in
[SPEC.md §9.1](../SPEC.md). Both apps load the same files.

Two rules for any new creature: draw it **standing on a floor, facing right**, and
keep it **centred in its cell**.
