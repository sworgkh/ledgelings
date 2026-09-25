# Ledgelings — full specification

A platform-neutral description of the whole product, precise enough to
re-implement it on Linux, Windows or anywhere else without reading the Swift.
Every number here is the one the macOS app ships with (v0.18). Where the
behaviour is a formula, the formula is given. Where it is a judgement call, the
call is stated so the port makes the same one.

Units: **points** are screen units (device-independent pixels). **Sheet pixels**
are pixels of a sprite sheet; a creature of *size* `s` draws one sheet pixel as
`s` points. Time is seconds. Angles are radians, counter-clockwise positive.

---

## 1. What it is

Tiny pixel-art creatures live on the **edges of the desktop**: they walk along
the outline of all monitors together, turn corners, cross from one monitor to
the next along a shared edge, jump when the cursor comes near, sleep at night,
bump into each other, stop to trade a line of dialogue, from a built-in script
or written by a language model, and every third meeting one gives the other a
flower to wear.

Ambient and click-through. A tray/menu-bar app with no main window. Not a
game, not a widget, not a desktop pet that wanders over windows: edges only.

### 1.1 What the platform must provide

| Need | macOS answer | Port must find |
|---|---|---|
| One transparent, always-on-top, click-through window **per monitor** | `NSPanel`, `level = .screenSaver`, joins all Spaces and full-screen apps, non-activating | X11: override-redirect + input shape / Wayland: layer-shell; Windows: `WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_NOACTIVATE` |
| Toggle click-through **per frame** | flip `ignoresMouseEvents` | same flag toggled, or a small input region moved onto the creature |
| Global cursor position without a permission prompt | `NSEvent.mouseLocation` | X11 `XQueryPointer`, Windows `GetCursorPos`, Wayland needs a workaround (see §13) |
| Modifier keys polled each frame (Shift, Control) | `NSEvent.modifierFlags` | `XQueryPointer` mask / `GetAsyncKeyState` |
| Monitor geometry in one global coordinate space, and a change notification | `NSScreen.screens`, `didChangeScreenParametersNotification` | RandR / `EnumDisplayMonitors` + `WM_DISPLAYCHANGE` |
| A frame timer tied to the display | `CADisplayLink` at 30 fps, 12 fps when all asleep | any 30 Hz timer; vsync not required |
| A tray icon with a menu | `NSStatusItem` | StatusNotifier / Shell_NotifyIcon |
| A settings window | SwiftUI form | anything |
| A key-value settings store | `UserDefaults` | ini/json/registry |
| A secret store for the API key | Keychain generic password, service `Ledgelings`, account `openRouterKey` | libsecret / Credential Manager; never the plain settings file |
| HTTPS client | `URLSession` | anything |
| Nearest-neighbour image scaling and per-layer rotation, mirror, opacity | `CALayer` | any 2-D compositor; a GPU is not needed |

The coordinate space used throughout is **global desktop points, origin
bottom-left, y up** (AppKit's). A port using y-down must flip once at the window
boundary and keep the rest of this document as written; all rotations are then
mirrored, which is the only thing that changes.

---

## 2. Geometry: the edge world

### 2.1 Loops

Every walkable path is a closed **loop** of axis-aligned segments, traversed
with the inside of the screens on the **left**. So the bottom edge of a single
monitor is walked left to right, the right edge bottom to top, the top edge
right to left, the left edge top to bottom.

A loop is a list of corner vertices. A position on it is one number `t` in
`[0, length)`. Each segment `i` has:

- `start_i`: the `t` where it begins (cumulative length of earlier segments)
- `direction_i`: unit vector from vertex `i` to vertex `i+1`
- `inward_i` = rotate `direction_i` by +90°: `(-d.y, d.x)`. Points into the screen.
- `rotation_i` = `atan2(d.y, d.x)` mapped into `[0, 2π)`. A sprite drawn standing on a floor facing right, rotated by this about its centre, stands on segment `i` with its head pointing inward. Floor = 0, right wall = π/2, ceiling = π, left wall = 3π/2.

Operations: `wrap(t)` (mod length, non-negative), `segment(t)`, `point(t)`,
`t(segment, fraction)`, `nearest(point) → (t, distance)` by projecting onto
each segment and clamping.

### 2.2 Fusing monitors into loops

Input: the rectangles of all monitors in global points, and an `inset` `d`
(half the creature's body, §5.1). Output: the boundary loops of the **union of
the monitors shrunk inwards by `d`**. The creature's *centre* travels on these
loops, so a corner is a plain rotation about its centre and it never walks the
invisible seam between two touching monitors.

Algorithm (grid method; any exact polygon-offset gives the same result):

1. Ignore monitors narrower or shorter than 4 points. Clamp `d` to
   `min(d, smallestSide/2 − 1)`, at least 0.
2. Build sorted, de-duplicated (tolerance 0.01) lists of x-lines and y-lines
   from every monitor edge `e` and `e ± d`. These are the only coordinates
   where the shrunken outline can turn.
3. A grid cell (between consecutive x-lines and y-lines) is **inside** if the
   cell grown back outwards by `d − 0.01` is fully covered by the monitors.
   "Fully covered" is tested by splitting that grown rectangle at every monitor
   edge that crosses it and checking that the centre of every piece lies inside
   some monitor.
4. Emit directed boundary edges between grid points so that inside is on the
   left: for each inside cell, bottom edge left→right if the cell below is
   outside, right edge bottom→top if the cell to the right is outside, top edge
   right→left, left edge top→bottom.
5. Walk edges into closed paths, always starting from the lowest-then-leftmost
   unused point. Discard paths with fewer than 5 points. Drop collinear points;
   keep a path only if at least 4 corners remain.
6. If nothing survives, use one 100×100 loop at the origin so the code never
   runs with zero loops.

Each loop is independent: a creature on loop 0 never meets one on loop 1 and
cannot walk to it, only jump.

### 2.3 Per-size worlds

The inset depends on creature size, so the colony keeps one world per distinct
size (sizes come in half steps, so a handful). On any monitor change all worlds
are rebuilt and every creature is **re-homed**: put on the nearest point of the
nearest loop, rotation snapped, any jump abandoned, asleep stays asleep.

---

## 3. The day/night clock

One clock for the colony: `day` seconds then `night` seconds, forever.
`day = max(1, dayMinutes·60)`, `night = max(0, nightMinutes·60)`.

- `isNight(elapsed)` = `night > 0 && elapsed mod cycle ≥ day`
- `remaining(elapsed)` = seconds until the current phase ends
- "skip phase" sets `elapsed += remaining`

`elapsed` is the colony's own simulation time: the sum of frame steps, each
capped at 0.1 s so a stalled timer cannot teleport anyone.

---

## 4. One creature: the state machine

A creature is a pure value updated by `update(dt, cursor?, isNight, rng)`.
It owns: its world, `spot (loop, t)`, `direction` (+1 walks in +t, −1 the other
way), `position`, `rotation`, `mode`, `eyes` (open/half/closed),
`animationTime` (seconds in the current animation), plus a few private flags.

### 4.1 Configuration (defaults; the colony overrides two, §5.2)

| Name | Value | Meaning |
|---|---|---|
| walkSpeed | 55 pt/s | along the loop |
| fleeRadius | 90 pt | cursor closer than this to the centre → jump |
| turnSpeed | 9 rad/s | how fast rotation chases the segment's rotation |
| jumpSpeed | 1500 pt/s | flight speed used to derive jump duration |
| jumpDuration | 0.35 … 0.8 s | clamp on a jump |
| landDuration | 0.16 s | squash after landing |
| walkSpell | 3 … 9 s | one walking stretch |
| idleSpell | 0.8 … 2.5 s | one pause |
| blinkEvery | 1.5 … 5 s | between blinks |
| dozeOffAfter | 0.5 … 7 s | at dusk, how long before it lies down |
| wakeUpAfter | 0 … 3 s | at dawn, how long before it gets up |
| restlessSpell | 1.5 … 3.5 s | after being startled at night, how long it wanders before sleeping again |
| reverseChance | 0.35 | chance to turn round after a pause |

"a … b" means uniformly random in that range each time it is needed.

### 4.2 Modes

```
walking(remaining)   t += direction · walkSpeed · dt; rotation chases the segment
idle(remaining)      stands; rotation chases the segment
jumping(jump)        in the air between two spots (§4.5)
landing(remaining)   squash frame
sleeping(wakeIn?)    wakeIn is nil during the night, a countdown once day breaks
held                 in the user's hand (§4.7)
chatting(remaining)  stopped to talk (§4.8)
running(to)          hurrying home along its loop (§4.9)
```

Animation name per mode: walking→`walk`, idle→`idle`, jumping→`jump`,
landing→`land`, sleeping→`sleep`, held→`sleep` if it was asleep when picked up
else `idle`, chatting→`land` for the first 0.16 s then `idle`, running→`walk`.

`animationTime` resets to 0 on every mode change ("enter").

### 4.3 Transitions each frame (in this order)

1. **Eyes.** If it looks asleep: eyes closed, blink cancelled. Else run the
   blink: countdown `blinkIn`; when it fires, play half 0.05 s → closed 0.09 s
   → half 0.05 s → open, then pick a new `blinkIn` from `blinkEvery`.
2. **Dusk and dawn** (edge-triggered on `isNight` changing):
   - dusk: if walking or idle, cap `remaining` to a fresh `dozeOffAfter`.
   - dawn: every nap ends (`isNapping = false`); a sleeper with `wakeIn = nil`
     gets `wakeIn` from `wakeUpAfter`.
   - if night and sleeping with a countdown: countdown becomes nil.
3. **Cursor.** If not jumping, not asleep-looking, not held, and the cursor is
   within `fleeRadius` of `position` → **startle** (§4.6). The colony passes no
   cursor while Shift is held.
4. **Mode step** with `animationTime += dt`:
   - walking: move; when `remaining` runs out → sleeping (night) or idle (day)
     with a fresh `idleSpell`.
   - idle: when out → sleeping (night); else with `reverseChance` flip
     direction, then walking with a fresh `walkSpell`.
   - jumping: §4.5; on arrival → landing.
   - landing: when out → sleeping if it was carried asleep and dropped, else
     walking with `restlessSpell` (night) or `walkSpell` (day).
   - sleeping: rotation chases the segment; if a countdown exists and runs out
     → walking with `walkSpell`.
   - held: rotation chases 0 (dangles upright).
   - chatting: rotation chases the segment; when out → walk on (§4.8).
   - running(to): step `walkSpeed·2.5·dt` toward the target the way chosen at
     the start; when the distance left is within one step, snap to it, enter
     idle with no end, and set `hasArrived`.

"Rotation chases X" = move `rotation` toward X along the shortest arc by at
most `turnSpeed·dt`, snapping when within reach.

`shortestArc(from, to)` = `(to − from) mod 2π` brought into `(−π, π]`.

### 4.4 Derived facts

- `isSleeping`: sleeping, or held while napping. `looksAsleep`: isSleeping or
  falling asleep after a drop. `isMirrored`: `direction < 0`.
- `restingRotation`: the current segment's rotation.

### 4.5 Jumping

A jump holds `from` (point), `fromRotation`, `to` (spot), `bulge` (vector,
length ≤ 1), `duration`, `elapsed`. Each frame:

```
p      = min(1, elapsed / duration)
eased  = p² · (3 − 2p)
target = world.point(to)
dist   = |target − from|
pull   = sin(π·p) · 0.2 · dist
position = from + (target − from)·eased + bulge·pull
rotation = fromRotation + shortestArc(fromRotation, rotation of landing segment) · eased
```

At `p ≥ 1`: spot = `to`, position = target, rotation = landing rotation, enter
landing.

### 4.6 Startle (jump somewhere else)

Refused while jumping. Candidate targets: every (loop, segment) on any monitor
except the current one, with segment length > 1, **weighted by length**. Land
at a fraction 0.15 … 0.85 along it. `duration = clamp(dist / jumpSpeed,
jumpDuration)`. `bulge` = average of the inward vectors of the segment it
leaves and the one it lands on. Direction after landing: random.

### 4.7 The hand

- `pickUp(evenAwake)`: refused while jumping or already held. A sleeper is
  always taken; an awake creature only when `evenAwake` (a Shift-drag). It
  remembers whether it was asleep. Enter `held`.
- `drag(point)`: position = point.
- `drop()`: target = nearest spot on any loop; `bulge = 0`;
  `duration = max(0.12, min(dist / jumpSpeed, 0.8))`; lands asleep if it was
  picked up asleep, else walking.
- `toggleNap()`: refused while jumping or held. A sleeper wakes and walks; an
  awake one lies down with `isNapping = true`, so daylight does not wake it;
  the next dawn does.

### 4.8 Meeting someone

- `meet(facing, for = 30 s)`: refused while jumping, asleep-looking or held.
  Remembers the current direction (once), sets `direction = facing`, enters
  chatting with the 30 s safety limit.
- `walkOn()`: only from chatting. Restores the remembered direction and enters
  walking with a fresh `walkSpell`.
- A startle (cursor) or anything else that changes mode ends the chat.

### 4.9 Going home

- `run(to t)`: refused while jumping or held. Wakes a sleeper, ends a nap.
  Direction = +1 if `wrap(t − here) ≤ length/2` else −1. Enter running.
  Running ignores the cursor and the night.
- `leap(to spot)`: a directed jump (same arc as §4.5, bulge from the two
  inward vectors, duration clamped as in §4.6) that on landing enters an
  endless idle with `hasArrived` set, instead of walking off.
- `emerge(at spot, facing)`: placed at the spot, rotation snapped, walking
  `facing` with a fresh `walkSpell`.
- `hasArrived` clears on any mode change.

---

## 5. The colony

### 5.1 Creatures, sizes, worlds

- `count` creatures (setting, 1–24, default 3).
- Each creature gets a **size share** in `[0, 1]` at birth, fixed for life. Its
  size = `minSize + (maxSize − minSize)·share`, snapped to 0.5 steps. Moving the
  sliders resizes everyone without reshuffling who is big.
- `bodyHalf` (sheet px) = half the width of the sprite's content box = **11**
  for the shipped sheet. World inset for size `s` = `11·s` points.
- `fleeRadius = 11·s + 68`.
- `walkSpeed` random 38 … 72 at birth, so no two walk in lockstep.
- Spawn: a uniformly random (loop, segment) pair, fraction 0.1 … 0.9 along it,
  random facing.
- Colour: creature `i` wears colour `i mod colours.count`, unless its
  species' atlas has a `colour`, which always wins (§9.1.1). Character: `i mod
  characters.count`.

### 5.2 Applying settings (any change)

Rebuild the clock. If the held creature's index is now out of range, let go.
Remove creatures from the end, or spawn new ones, to match `count`. Prune
flowers and any flower in flight that refer to removed creatures. For each
creature whose snapped size changed: re-home into that size's world and update
`fleeRadius`. Recolour frames (cached per colour). Render.

### 5.3 The frame

At each tick with `dt = min(now − last, 0.1)`:

1. `elapsed += dt`.
2. Read cursor and Shift. Update every creature with `cursor = nil` when Shift
   is down. Track `asleepFor[i]` (seconds it has looked asleep, for the Zs).
3. Update click-through (§10.4).
4. Drop expired bubbles. Land the flower in flight if its time is up; wilt hats
   past their time; steer every wearer after its giver if `followGiver` (§7.3).
   Age the sparks (§7.4). Release the chatting pair if
   it is over (§7.2). Detect bumps and handle them (§7.1). Run the post:
   send, fly, catch, read and answer a paper plane (§7.6).
5. Render (§9).
6. Frame rate: 30 fps normally; 12 fps when nobody is held and every creature
   is asleep.

---

## 6. Talking

### 6.1 Characters and prompts

A character is `{name, persona}`. Six ship by default:

| Name | Persona |
|---|---|
| Blocky | Grumpy and proud. Hates the mouse cursor. Thinks the bottom edge is the only respectable edge. |
| Pip | Cheerful and easily impressed. Loves the ceiling. Laughs at everything, including insults. |
| Mortimer | Old and philosophical. Speaks slowly, quotes wisdom he made up, sighs a lot. |
| Zed | Sleepy. Would rather be napping. Every sentence drifts toward bed. |
| Dot | Tiny, fast and sarcastic. Brags about speed. Calls everyone else a boulder. |
| Ruth | Bossy, organised, keeps count of everything. Disapproves of jumping. |

Every species has a **kind** (what it is, for the model: blocky is "a small
square creature") and a **cast**: blocky's is the six above; the other
built-ins carry three each in their sheet; an imported sheet without a cast
gets one placeholder character. The user may replace any species' cast in
Settings › Talk. The k-th creature wearing a species is that species' k-th
character, wrapping round.

Three editable templates with `{placeholders}`: `speaker`, `speakerKind`,
`speakerPersona`, `listener`, `listenerKind`, `listenerPersona`, `situation`,
`line`. Unknown placeholders are left as written.

System prompt (default):

```
You are {speaker}, {speakerKind}, living on the edge of a computer screen. {speakerPersona}
You are talking to {listener}, {listenerKind}, who lives on the same edge. {listenerPersona}
Say ONE line to {listener}: a joke, a jab or a tease, at most 20 words, in your own voice.
Output only the line. No quotes, no name prefix, no explanation.
```

Opening line prompt:

```
Right now: {situation}
Say your line to {listener}.
```

Reply prompt:

```
Right now: {situation}
{listener} just said to you: "{line}"
Answer back in ONE line, in character, at most 20 words.
```

`situation` is written by the app:
`"It is {day|night}. {describe(speaker)}. {describe(listener)}."` plus, for a
meeting, `" They just walked into each other."` or
`" {A} just walked into {B} and gave {B} a {flower}."`.

`describe(i)` = `"{name} is dangling from the user's cursor"` if held,
`"{name} is mid-jump"` if jumping, else `"{name} is {asleep on|on} {edge}"`
where edge is the nearest of: the bottom edge (rotation 0), the right edge
(π/2), the ceiling (π), the left edge (3π/2), by shortest arc from the
creature's current rotation.

### 6.2 One conversation

`talk(speaker, listener, event?, flower?)`. Refused (returns false) if either
creature is already in a conversation (`busy`), an index is invalid, or no brain
is configured (§8). With the built-in lines as the brain, §6.7 applies instead
of the rest of this section. Other pairs may talk at the same time; a busy creature is not
eligible for bumps or pokes until its conversation ends. Then, in the
background:

1. `checkModel()` (§8.2).
2. Ask for the opening line: system = rendered system prompt, user = rendered
   line prompt. Clean it (§6.3). Empty → status "the model sent an empty line",
   stop.
3. Show it as the speaker's bubble. Status line = `"{name}: {line}"`.
4. Swap roles (speaker↔listener, `line` = the opening line), ask for the reply
   with the reply prompt, clean it.
5. Wait `showTime(openingLine) · 0.6` seconds **after the reply has arrived**
   (so the reply appears while the first bubble is still up), then show the
   reply as the listener's bubble.
6. Any error → status = the error text, logged to stderr.
7. Whatever happened, when the task ends release the chatting pair 1.2 s later
   (§7.2).

### 6.3 Cleaning a model's line

`cleanLine(raw, speaker, maxLength = 160)`:

1. If the text contains `</think>`, keep only what follows it.
2. Take the first non-empty line, trimmed.
3. Strip a leading `"{Speaker}:"`, `"{SPEAKER}:"` or `"*{Speaker}*:"`.
4. Repeatedly strip matching wrapping quotes: `"…"`, `“…”`, `'…'`, `*…*`.
5. Over `maxLength` characters → cut and append `…`.

The cleaned line is what is logged. Marks inside it are kept, and shown as
styles wherever the line is drawn (§6.3.1).

### 6.3.1 Marks in a line

Models write `*sighs*`, `*good*`, `_really_`, `**important**` (in practice
over 20 % of lines carry single-star spans, mostly stage directions and
emphasis; bold is rare). `styled(line)` cuts a line into runs `{text, bold,
italic}`:

- `*x*` and `_x_` → italic; `**x**` (or `__x__`) → bold; `***x***` → both.
  A run of four or more marks is literal.
- A mark **opens** only when the next character is not a space and not the
  same mark; it **closes** only when the previous character is not a space
  and not the same mark. `_` additionally needs no letter or digit on the
  outside (so `snake_case_name` is literal). An opener counts only if a
  closer of the same mark and length exists later in the line; otherwise
  the mark is literal (`2 * 3`, `*sigh without an end`, `a ** b`).
- Marks nest by a stack; a closer must match the innermost opener.
- Runs of two or more spaces collapse to one (models leave two after a
  closing mark).

`plain(line)` is the runs' text joined, for a surface that cannot style.
The speech bubble (§9.5) and the chat viewer (§6.5) draw the runs; the
Windows bubble, one face per draw call, shows `plain`.

### 6.4 Bubble time

`showTime(text, base) = min(2·base, base/2 + words·0.9)` where `words` is the
count of space-separated pieces and `base` is the "Bubble stays" setting
(default 14 s, range 4–60). A bubble is removed when its time is up, when its
creature disappears, or when the user clicks it.

### 6.5 The chat log

Every conversation that produced at least one line is written to disk when it
ends, to `<app support>/Ledgelings/chats/YYYY-MM-DD.jsonl` (the day in the
local calendar, from the time the conversation started). One JSON object per
line, ISO-8601 time:

```json
{"time": "2026-09-18T14:03:11Z",
 "situation": "It is day. Dot is on the bottom edge. Blocky is on the bottom edge. They just walked into each other.",
 "provider": "LM Studio", "model": "google/gemma-3-1b",
 "lines": [{"speaker": "Dot", "text": "Move, boulder."}, {"speaker": "Blocky", "text": "Says the pebble."}],
 "cost": 0.00084, "tokens": 660}
```

`cost` (US dollars) and `tokens` (prompt + completion, both calls) are present
when the server reported usage; `cost` is the sum of the priced calls, absent
when none was priced. Older lines without them still read.

A one-sided exchange (the reply failed or came back empty) is still written
with its one line. Reading: list days = files named `YYYY-MM-DD.jsonl`, newest
first; a day's exchanges are its lines in file order; a line that does not
parse is skipped. The viewer (Settings › Chats, also "Chat History…" in the
menu) lists days on the left, naming today and yesterday, and shows each
exchange as time, model, situation, then `**Name:** text` per line, with
buttons that open the folder in the file manager and in a terminal.

### 6.5.1 The spend file

Every model call, whether or not its line was usable, appends one record to
`<app support>/Ledgelings/spend.jsonl`:

```json
{"time": "2026-09-20T14:03:11Z", "provider": "OpenRouter", "model": "google/gemini-2.5-flash-lite",
 "usage": {"promptTokens": 312, "completionTokens": 18, "cost": 0.00042}}
```

`cost` is what the server said the call cost (§8.1); a call to LM Studio is
recorded with cost 0 (it is free), a call whose server gave no price with no
`cost`. The summary, recomputed from the whole file after each record:

| Total | Records counted |
|---|---|
| today | same local calendar day as now |
| this month | same local calendar month as now |
| all time | all |
| by model | all, grouped by model id, dearest first, then most calls |

A total is `calls`, `promptTokens`, `completionTokens`, `cost` (sum of the
priced calls) and `unpriced` (how many had no price). Money is shown as
`$0.00` for zero, `<$0.001` under a tenth of a cent, three decimals under ten
cents, else two; a total with unpriced calls gets a `+` after it. Shown in
Settings › Talk › Spend (three rows, up to five models, the file path, a
button revealing the file) and as a menu line "Spent: $a today, $b this month"
(hidden until there is a record); the Chats viewer shows each exchange's cost
and tokens.

### 6.6 Menu and poke

"Make Someone Talk" picks a random awake, non-jumping creature that is not
busy (anyone free if none is awake); the nearest free creature listens. A Shift-poke (§11) does the same
with the poked creature as speaker. Both first **hold** the pair (§7.2). If the
talk could not start, release after 1 s.

### 6.6.1 Voice (macOS)

Every `say` (a bubble going up, whatever its source) also hands the line to the
voice when `voiceEnabled`. The line is first made speakable: `**bold**` keeps its
words, `*stage directions*` go, emoji and the marks `*`, `_`, `~`, backtick and `#` go, runs of spaces
collapse, and no space is left before `. , ! ? ; :`. Nothing left → nothing said.

Lines are said one at a time, in order. Queued-or-playing lines are counted; at 4,
a new line is dropped (the status says so). Turning voice off, or switching engine,
stops everything at once.

**Who sounds like whom.** With `voicePerCharacter`, the names of all creatures on
screen are handed voices from a pool: names sorted, each starts at FNV-1a(name)
mod pool size and takes the first voice not yet taken, going round; when the pool
runs out, the start voice. The same names and pool always give the same answer.
Built-in pool: the Mac's voices in the user's language (English if none), no
novelty or personal voices, one per voice name (the user's region preferred),
sorted by identifier; pitch is also multiplied by 0.9 + 0.2 × (FNV-1a(name +
"#pitch") mod 1000) / 999. OpenRouter pool: the model's `supported_voices`, cut to
the English ones when any name is marked English (`-en` suffix; `en_`, `gb_`,
`en-`, `English_` prefix; Kokoro's `af_ am_ bf_ bm_`). Without it: the chosen
voice, or the system default / the model's first.

**Per character.** `characterVoices` maps a name to `{systemVoice?, openRouterVoice?,
localVoice?, speed?, pitch?, followPitch?}` (`followPitch` nil = `speedFollowsPitch`); nil fields are automatic, an all-nil entry is removed. Speed =
`voiceSpeed` × (own speed ?? 1). A hand-picked voice is kept; `Voices.assign` hands
the others voices from the pool minus the hand-picked ones (the whole pool if that
empties it). An `openRouterVoice` not among the model's voices is ignored.

**Pitch.** A name speaks at `voicePitch` × (own pitch if set, else with `cartoonVoices`: 1.15 + 0.45 ×
(FNV-1a(name + "#cartoon") mod 1000) / 999; else with `voicePerCharacter` the
0.9–1.1 nudge; else 1). With `cartoonVoices` the built-in pool is the Eloquence
voices and the `speech.synthesis.voice.*` ones minus the singers (Bells, Cellos,
Organ, Good News, Bad News), if at least two; the OpenRouter pool is cut to names
containing anime, playful, whimsical, comedian, jovial, lovely, upbeat, excited,
cheerful, happy, santa, boy, girl, radiant or kind-hearted, if at least two.

**Built-in engine:** `AVSpeechSynthesizer`, rate = default rate × `voiceSpeed`
(clamped to the system's range), pitch multiplier as above (0.5–2), volume `voiceVolume`.
With `speedFollowsPitch` (default on) the speed asked for is `speed / √pitch`
instead of `speed / pitch` (below), and the Mac's voices are rendered with
`AVSpeechSynthesizer.write` at that rate and pitch 1, then played through the same
varispeed at rate = pitch; their bubble then types over the clip's length.

**Local server engine.** `{server}/v1/audio/speech` with `{model, input, voice,
response_format: "wav", speed}`, no key, no OpenRouter headers; voices from `GET
{server}/v1/audio/voices` (`{"voices": [...]}`, strings or objects with `id`/`name`,
or a bare array). Not kept, not priced, not looked up in the archive. Defaults
`http://localhost:8880`, `kokoro` (Kokoro-FastAPI).

OpenRouter lines are asked for at speed `voiceSpeed / pitch` (clamped 0.25–4) and
played through `AVAudioEngine`: player → varispeed at rate = pitch (0.25–4) →
mixer, so they come out `pitch` times higher at the usual pace. (A time-pitch
unit was tried first: at 1.15–1.6× it smeared lines into an audible echo.) The
archive key uses the asked speed. Format: `pcm` first; a refusal whose message
names `response_format` and the other format (MiniMax wants `"mp3"`) is retried
once in that format, remembered per model until the app quits. A refusal about
the speed parameter itself (Qwen: "does not support the speed parameter … omit
it") is retried without `speed`, also remembered; such a model then talks faster
as well as higher when the pitch is raised.

**OpenRouter engine:** `POST {base}/audio/speech` with `{model, input, voice,
response_format, speed}` and the brain's key and headers. The reply is 16-bit
little-endian samples typed `audio/pcm;rate=24000;channels=1` (rate and channels
read from the type, 24000 and 1 if missing), given a 44-byte WAV header and
played; an `audio/mpeg` reply plays as is, a JSON reply is an error. The fetch starts at once, the play waits for the
line before. The `X-Generation-Id` header is then looked up at `GET
{base}/generation?id=…` after 3 s and up to three more times 5 s apart; its
`total_cost` (or `usage`) and `tokens_prompt` go to the spend file (§6.5.1) under
the speech model's id, without a price if it never came.

**Bubbles while speaking.** `say` returns whether the line will be said; if so
the bubble starts as `waiting` (text `...`, showing (⌊3·t⌋ mod 3 + 1)/3 of it) with
`until` = now + 45 s, and the voice cues it: `started(duration)` → typed evenly
over `duration`, `until` = now + max(showTime, duration + 2); `started(nil)` (Mac
voices) → shown as far as the last `willSpeakRange` end / line length; `done` →
all shown, `until` = max(min(until, now + showTime), now + 2); `dropped` → all
shown, `until` = now + showTime. A cue for a bubble since replaced is ignored (a
serial per `say`). Hidden letters are drawn transparent in the full-size bubble;
a cut never splits a composed character.

**Voice cost per conversation.** Each OpenRouter line appends `{time (when said),
speaker, text (as spoken), model, cost, kept}` to `chats/YYYY-MM-DD.voice.jsonl`
once priced (kept copies at once, cost 0, kept true). The Chats tab gives each to
the latest exchange written no later than 60 s after it that has the same speaker
with the same `speakable` words, and sums cost, lines, unpriced and kept per exchange.

**The voice archive** (`Application Support/Ledgelings/voices`). With
`keepVoices`, every OpenRouter line is written as `<yyyy-MM-dd>/<HHmmss>-<speaker>-<key8>.wav`
(speaker reduced to letters, digits, `-`, `_`, at most 24) and appended to
`voices.jsonl` as `{time, speaker, text, model, voice, speed, file, key}`, time in
whole seconds. `key` = FNV-1a hex of text, model, voice and speed (2 decimals),
joined by U+001F. Before asking OpenRouter, the key is looked up (last match,
file still present); a hit is played from disk and neither asked for nor charged.
The built-in voices are not kept: they cost nothing to say again. Speech models: `GET
{base}/models?output_modalities=speech` (public), cheapest input first.

### 6.7 The built-in lines (no model)

The default brain. A **script** is a list of conversations, kept as text in the
settings (`script`, default: the shipped text of about a hundred blocks) and
parsed whenever a conversation is wanted.

Text form, line by line (each trimmed of surrounding spaces):

| Line | Meaning |
|---|---|
| empty | ends the current block |
| starts with `#` | comment, ignored |
| `[tag, tag]` as the first line of a block | the block's tags: any of `flower`, `night`, `day`, split on commas and spaces, case-insensitive. Unknown tag → error naming it; a tag line after the block's first line → error |
| anything else | one line of the block; the first is said by the one who bumped (`speaker`), the next by the other, alternating |

A block with tags and no lines is an error; a text with no blocks is an error.
Errors carry the 1-based line number and are shown as the talk status
(`"the built-in lines: line N: …"`); the pair is released as if the talk had
not started.

Choosing: the **moment** is the set `{day | night}` plus `flower` when the
meeting gave one. Candidates are the blocks whose every tag is in the moment
(untagged blocks always qualify). Of those, keep only the ones with the most
tags, so a `[night, flower]` block wins at night with a flower, a `[flower]`
block wins with a flower by day, and untagged blocks are used only when no
tagged block fits. From that pool, pick uniformly among the blocks not in
`recent`, or from the whole pool when all are recent. `recent` keeps the last
`max(1, blocks / 2)` chosen indices.

Saying: `{speaker}` and `{listener}` are filled per line with the names of the
one saying it and the one hearing it; `{flower}` with the flower given, or the
word `flower`. Both creatures become busy. Line 1 shows at once; line k+1 shows
`showTime(line k) · 0.6` seconds after line k (§6.4), on the colony's own clock
(so it pauses with the app, unlike the model path). When the last line shows,
the pair is freed and released 1.2 s later (§7.2). The exchange is written to
the chat log (§6.5) when the conversation starts, provider `"Built-in lines"`,
empty model, no cost or tokens; nothing is written to the spend file.

The **agent prompt** (`Script.agentPrompt(cast, count = 40)`) is a fixed text
asking any chat model for `count` more blocks in exactly this format, with the
rules above, three example blocks, and the cast in use (every character of every
species in use, name and persona) as the voices to write for, telling the
model to use `{speaker}`/`{listener}` rather than names.

---

## 7. Meetings, flowers, stars

### 7.1 Bump detection

Every frame, for every pair `a < b` of creatures that are both **eligible**
(awake, on the ground, not held, not chatting) and on the **same loop and
segment**: they are *touching* if
`|pos_b − pos_a| ≤ halfSize_a + halfSize_b + gap` with `halfSize = 11·size`
points and `gap = 12`.

A **bump** fires on the rising edge: touching now, not touching last frame,
and at least `cooldown = 60 s` since this pair's last bump. Each bump
increments the pair's count; when it reaches `giftEvery = 3` the bump is a
**gift** and the count resets to 0. Counts and cooldowns are per pair and
never expire.

On a bump:

1. Pick giver/receiver at random between the two.
2. **Hold** the pair (§7.2), and burst stars (§7.4) at the midpoint of the two
   positions, thrown along creature `a`'s inward vector, coloured white,
   `#ffd23d`, colour of `a`, colour of `b`.
3. If it is a gift and no flower is already in flight: pick a random flower,
   start its flight giver→receiver, and the situation event becomes
   `"{A} just walked into {B} and gave {B} a {flower}."`; otherwise
   `"They just walked into each other."`.
4. If talking is enabled, `talk(giver, receiver, event)`. If talking is off or
   the talk could not start, release the pair after 2 s.

A creature wearing a flower (§7.3) never counts as able to talk here: it walks
past everyone, so a wearer trailing its giver does not bump into it, or into
the crowd around it, every few seconds.

### 7.2 Holding a pair (stop and face)

`hold(i, j)`: both call `meet(facing)` where `facing` for `i` toward `j` is
+1 if `wrap(t_j − t_i) < length/2` on their shared loop, −1 otherwise; on
different loops, keep the current direction. The colony records
`chat = (i, j, releaseAt = nil)`.

`endChat(after)` sets `releaseAt = min(existing, elapsed + after)`.

Each frame: if either of the pair is no longer chatting (startled, asleep,
removed), or `releaseAt ≤ elapsed`, both `walkOn()` and the record is
cleared.

Timeline of a normal meeting: bump → stars + squash → both stand facing →
opening bubble → reply bubble → 1.2 s → both walk on in their old directions
(so a head-on pair passes through each other once; the cooldown stops a
re-bump).

### 7.3 Flowers (gifts)

Ten flowers, each a 16×16 sprite: poppy, tulip, daisy, sunflower, rose,
bluebell, dandelion, lavender, lily, forget-me-not.

- **Flight**: one at a time, `flightTime = 0.6 s`. Drawn at
  `lerp(head(giver), head(receiver), p) + inward_receiver · sin(π·p) · 24`, with
  the receiver's rotation and size. `head(i)` = position + inward ·
  `(11 + 8)·size` (half body plus half a flower cell).
- On landing the receiver **wears** it for `flowerMinutes·60` s (default 2 min,
  range 0.5–30), then it vanishes.
- A hat remembers its **giver**. While the setting `followGiver` (default
  on) is on, every frame after the hats are updated the wearer **follows**
  the giver: if both are on the same loop, neither is held, jumping or in a
  chat (§7.2), and the house is not out (§7.5), and the wearer is walking or
  idling, then with `ahead = wrap(giver.t − wearer.t)` and
  `distance = min(ahead, loopLength − ahead)`: the wearer faces the giver
  (`direction = ahead ≤ loopLength/2 ? +1 : −1`); if `distance > gap` it
  walks (a walking spell of at least 1 s more, so it never idles mid-chase),
  else it idles (at least 1 s more), standing and facing the giver. `gap =
  (size(wearer) + size(giver)) / 2 + 16` points. The follower keeps its own
  walking speed, so a slow one trails. Sleepers, jumpers, the held and the
  chatting are not steered; the moment the flower wilts the wearer is left in
  whatever mode it was in and wanders on.
- Hats and flights referring to removed creatures are dropped.

### 7.4 Stars (sparks)

A burst is 8 stars from one point. Each: angle = inward's angle ± up to 60°
uniformly; speed 70 … 150 pt/s; gravity = `−inward · 300` pt/s² (pulled back
toward the edge); life = `0.7 · (0.7 … 1.1)` s; opacity = `1 − age/life`; a
`tint` index 0…7 that the renderer maps onto the palette cyclically. Each frame
velocity += gravity·dt, position += velocity·dt, age += dt; dead when
`age ≥ life`. Drawn as plain squares of side `2 · largestCreatureSize` points.

---

### 7.5 Hiding in the house

"Hide Them for a While…" asks for a duration (5, 15, 30 minutes, 1, 2, 4
hours, or until 08:00 tomorrow) and starts the `Hideout` state machine with
`count` = number of creatures:

```
away → appearing (0.4 s) → gathering → shrinking (0.5 s) → hidden … until the
time is up → growing (0.4 s) → releasing (one out every 0.6 s) → vanishing (0.5 s) → away
```

- **House**: a 68×60 sheet-pixel sprite (content box `[2,2,64,58]`), drawn
  at `maxSize · scale(phase)` points per pixel, so its doorway takes the
  largest creature. Its own bottom-right corner is pinned to the primary
  monitor's bottom-right corner (`x = maxX + 2·s`, `y = minY`, `s = maxSize`),
  and it grows and shrinks **about that corner**, never about its centre.
  `scale` ramps 0→1 during appearing and growing, 1→0 during shrinking and
  vanishing, 1 while gathering and releasing, 0 otherwise. Drawn **behind**
  the creatures.
- **Through the door**: a creature that reaches the doorway's middle stands
  there and shrinks to nothing over 0.35 s, scaled about its centre while its
  centre sinks toward the floor (`centre −= inward · bodyHalf · (1 − shrink)`),
  so its feet stay down; then it is inside. Coming out it grows from 0 to 1
  over 0.35 s the same way while already walking.
- **Doorway**: on the house's left, 26 px wide and 28 px tall from the floor,
  its middle 19 sheet px from the cell's left edge. The door point is that
  middle on the floor; each creature's door spot is the nearest point of its
  own world to it.
- **Porch**: a point 150 points left of the doorway on the floor.
- **Gathering**, every frame, for every creature not yet inside, with `along`
  = its loop distance to the door (infinite on another loop): if held, let
  go; if in the air, wait; if `along ≤ 6` it starts shrinking into the door
  and 0.35 s later is **inside** (skipped by update and render from now on);
  else if `along > 420` and it has not just landed,
  `leap` to the porch; else if not already running, `run` to the door. So the
  far-away ones jump to the porch and walk the last stretch in. Cursor is ignored by everyone while the
  house is out. When every creature is inside, or 25 s have passed (the rest
  are pulled in), the house shrinks.
- **Hidden**: the frame rate drops to 12 fps. No bumps, no talk, no clicks.
- **Releasing**: the smallest index still inside `emerge`s at its door walking
  left (away from the corner), one every 0.6 s; when nobody is left the house
  vanishes.
- **Bring Them Back Now** (the same menu item while hiding): from hidden →
  growing; from shrinking → growing from the current size; from appearing or
  gathering → releasing whoever is inside, the rest just carry on.
- Starting a hide clears bubbles, releases any chat and drops anything held.
  A second hide while one is active is ignored. Not persisted: a restart
  brings everyone back.

### 7.6 Paper planes

Every so often one creature folds a note into a paper plane and throws it to
another. The plane flies in weather of its own, swirling across the screen;
the catcher stops, reads the note out, says something to itself about it, and
throws **one** answer back, which is read and thought about but never
answered. macOS only for now; the Windows app does not have it yet.

- **The post**: `interval = planeMinutes · 60` s (default 3 min, range
  0.5–60; 0 when `planesEnabled` is off). Every first plane sent (not an
  answer) sets `lastStir = elapsed`. When `elapsed − lastStir ≥ interval`, no
  plane is out and no answer is owed, it is day and the house is not out, a
  plane is sent; if that is not possible (night, the house, fewer than two
  free creatures), try again in 10 s (`lastStir = elapsed − interval + 10`).
  Bumps do not touch the post. The clock runs through the night, so after a
  night a plane goes up as soon as two are awake.
- **Free** for mail: awake, not busy talking, not chatting, not jumping, not
  held, not in the house. **Who**: the sender is any free creature; the
  catcher is a random one of the half of the other free creatures farthest from
  it (at least one), so the plane crosses some sky. One plane at a time.
- **The throw**: the sender stops facing the catcher for 0.9 s (a chat-mode
  stop that ends by itself). The plane starts at `head(sender)` (§7.3) with
  velocity `(0.5·unit(head(catcher) − start) + inward_sender) · 220 · cruise/240`.
- **Its own weather**, drawn at the throw:
  `cruise` = 380…580 pt/s four times in five, else 220…340 (a glide);
  `surge` 0.1…0.3; `swirl` 250…1100 pt/s²; `swirlRate` 1.2…3.4 rad/s;
  `phase` 0…2π; and a wind with `strength` 180…480, four `phases` 0…2π,
  `scale` 0.6…1.6, `pace` 0.7…1.8:
  ```
  x' = x/scale   y' = y/scale   t' = t·pace          t = elapsed
  dx = sin(y'/260 + 0.35t' + φ0) + 0.6·sin((x'+y')/410 − 0.23t' + φ1)
  dy = cos(x'/310 − 0.29t' + φ2) + 0.6·cos((x'−y')/470 + 0.19t' + φ3)
  wind = strength · (dx, dy) / 1.6
  ```
- **Flight**, each frame toward `target = head(catcher)` (it keeps moving):
  `want = unit(target − p)`; `speed = cruise·(1 + surge·sin(1.7·age + phase/2))`;
  `grip = min(8, 0.9 + 0.45·age) · (2.2 if |target − p| < 160 else 1)`;
  `calm = min(1, |target − p| / 220)`; `side = unit(−v.y, v.x)`;
  `twist = swirl · sin(swirlRate·age + phase) · calm`;
  `v += ((want·speed − v)·grip + (wind + side·twist)·calm)·dt`; speed clamped
  to 90…760 pt/s; `p += v·dt`. The swirl swings it side to side into
  S-curves and now and then a loop; the grip grows with time and closeness,
  so it always arrives.
- **Trail**: a puff every 9 pt of flight, laid back evenly along each step so a
  fast plane leaves no gaps; each lives 1.1 s and keeps fading after the plane
  is caught or lost.
- **Reservation**: while a plane is flying to a creature, that creature does
  not bump into talks (its `canTalk` is false, §7.1) and is not picked as a
  listener by *Make Someone Talk*.
- **Catch**: when the plane's last step passed within `bodyHalf(catcher) + 10`
  of the target (the segment from the previous position to this one, so a fast
  plane cannot skip through): if the catcher is free it catches (below); if it
  is asleep the plane is **dropped**; else (held, jumping, chatting) the plane
  keeps circling. After 30 s in the air it is dropped. The house coming out,
  or the catcher going in, drops it too. A dropped plane fades out over 0.6 s.
- **Reading**: the catcher stops (a chat-mode stop, facing its own way),
  becomes busy, and holds the open letter out. With talk on: bubble 1 is
  `*reads* "<note>" — <sender>`; after `showTime(bubble 1) · 0.6` the bubble
  becomes the thought; after `showTime(thought) · 0.6 + 1` s the letter goes
  away, the catcher is free and walks on. With talk off it just holds the
  letter for 3 s. Logged with situation `"<sender> sent <catcher> a paper
  plane."`, or for an answer `"<sender> wrote back to <catcher> by paper
  plane."`, two lines, sender then catcher.
- **The answer**: when a first plane has been read, its catcher owes the
  sender one answer. As soon as that plane's trail is gone and both are free,
  the catcher throws it (same throw, fresh weather); if they are not both free
  within 20 s, or night falls, or the house comes out, it is never sent. An
  answer is read and thought about like any plane, and owes nothing.
- **Built-in letters**: every character of every built-in cast has a *voice*:
  a few topics its persona keeps returning to, three or four notes it writes,
  three thoughts it has on reading any note, and three answers it writes
  back. Blocky's are about the cursor and which edge is respectable, Zed's
  about naps, Ruth's about counting, Unit 7's in numbers, and so on. A
  character with no voice (a user's own) uses a generic one. `{sender}` and
  `{reader}` are filled in.
- **With a model** (talk on, brain not the built-in lines): as the plane is
  thrown, two calls go out in the background with the usual system prompt
  (§6.1): the sender writes the note (`notePrompt`, or `replyPrompt` with
  `{line}` = the note being answered), then the catcher, seats swapped and
  `{line}` = the note, thinks aloud about it (`musingPrompt`). Lines are
  cleaned (§6.3) and priced (§6.5.1). If the catcher has the plane before both
  answers are in, it holds the unread letter up to 8 s, then falls back to the
  built-in letters for whatever is missing.

## 8. The brain: chat client

One client speaks the OpenAI-style chat API to either provider.

| | LM Studio | OpenRouter |
|---|---|---|
| Base URL | `{server}/v1`, default server `http://localhost:1234` | `https://openrouter.ai/api/v1` |
| Auth | none | `Authorization: Bearer {key}` |
| Extra headers | — | `HTTP-Referer: https://github.com/sworgkh/ledgelings`, `X-Title: Ledgelings` |
| Default model | `google/gemma-3-1b` | `anthropic/claude-haiku-4.5` |
| Model list | `GET /models` (10 s timeout) | same, public (no key needed) |
| Key check | — | `GET /auth/key` → `data.label`, `data.usage`, `data.limit` |

### 8.1 Completion

`POST {base}/chat/completions`, JSON
`{model, messages: [{role: "system", content}, {role: "user", content}],
temperature: 0.9, max_tokens: 80}`, plus `usage: {include: true}` for
OpenRouter only (it then prices the call in the reply), 60 s timeout. Reply
text = `choices[0].message.content`; usage, when present, =
`usage.prompt_tokens`, `usage.completion_tokens` (missing → 0) and
`usage.cost` (US dollars, OpenRouter only; missing → unknown), see §6.5.1. Callers may pass other `max_tokens` and
`temperature`; banter uses the defaults.

Errors, in order of checking: transport failure → "the server is not
answering: …"; a body of shape `{"error": {"message": …}}` → "the server
refused: {message}"; anything else undecodable → "unexpected reply: {first 160
chars}".

### 8.2 checkModel

Fetch the model list and require the configured id to be in it. LM Studio
silently answers with whatever model is loaded when asked for one it does not
have, which is why this check exists; OpenRouter refuses unknown ids itself but
gets the same treatment for a consistent settings UI. Failure text: "model X is
not available (have: first eight ids)".

### 8.3 Model catalogue (OpenRouter browser)

Parse `GET /models` rows: `id`, `name` (fallback id), `pricing.prompt` and
`pricing.completion` (strings, dollars per token; multiply by 10⁶ and round to
6 decimals to get dollars per million; missing → unknown), `context_length`.

- `isFree`: both prices are exactly 0.
- `exchangeCost` = `2·(300·promptPerM + 80·completionPerM) / 10⁶` dollars (one
  meeting: two calls of about 300 tokens in, 80 out).
- `priceLabel`: `"$%.2f in · $%.2f out per M"`, or `"free"`, or `"price unknown"`.
- `search(query)`: every whitespace-separated word must appear, case-insensitive,
  in `id + " " + name`. Sort by `exchangeCost` ascending, unpriced last, ties by
  id.

### 8.4 Settings that feed it

`brainProvider` (`script` | `lmStudio` | `openRouter`), `talkServer`,
`talkModel`, `openRouterModel`, `openRouterKey` (secret store only).
`chatClient()` returns nil for `script` (nothing to call, §6.7) and nil with a
reason when the server address is not a URL or the OpenRouter key is empty; the
reason is shown as the talk status.

---

## 9. Rendering

### 9.1 Sprite sheets (atlas format)

Each sheet is a PNG plus a JSON file:

```json
{
  "name": "blocky", "image": "blocky.png",
  "cell": [32, 32],                 // frame size in sheet px
  "contentBox": [5, 5, 22, 22],     // x, y, w, h: the square the body stays inside
  "variants": ["open", "half", "closed"],
  "palette": {"body": "#ff8a3d", "light": "#ffb27a", "shade": "#d66220", "outline": "#3b1f0f"},
  "frames": {"walk-1_half": {"x": 64, "y": 32, "w": 32, "h": 32}, ...},   // top-left origin
  "animations": {"walk": {"frames": ["walk-0","walk-1","walk-2","walk-3"], "fps": 8, "loop": true}, ...}
}
```

Frame lookup for animation `A` at time `t` with eye state `e`:
`pose = frames[loop ? floor(t·fps) mod n : min(floor(t·fps), n−1)]`, image =
`frames["{pose}_{e}"]` falling back to `frames[pose]`.

Shipped sheets:

| Sheet | Size | Cell | Content box | Frames | Animations |
|---|---|---|---|---|---|
| blocky | 288×96 | 32×32 | [5,5,22,22] | 9 poses × 3 eye rows: idle, walk-0..3, jump, land, sleep-0, sleep-1 × open/half/closed | idle 1 fps; walk 4 frames 8 fps loop; jump; land; sleep 2 frames 0.8 fps loop |
| zzz | 10×10 | 10×10 | whole | `z` | float |
| flowers | 160×16 | 16×16 | [1,1,14,15] | ten flowers, one frame each | one per flower |
| house | 68×60 | 68×60 | [2,2,64,58] | `house` | house |

Art rules for any new creature sheet: drawn **standing on a floor, facing
right**, body **centred in its cell** (rotation is about the cell centre), eyes
pure black, the four palette colours used only for the body. Every block in
the game (creature body, house wall, roof slabs, chimney) is drawn the same
way: flat fill, a 1 px outline of `mix(fill, black, 0.76)`, a 1 px line of
`mix(fill, white, 0.36)` along the top and left inside the outline, a 1 px
line of `mix(fill, black, 0.17)` along the bottom and right. Pixel art; the
flowers carry a 1 px rim of `#281e32` (40, 30, 50), added automatically around
every filled pixel.

### 9.1.1 User sheets and the text format

Eight species ship: `blocky` (painted by the sprite tool), and `frog`, `cat`,
`ghost`, `slime`, `robot`, `triangle`, `mushroom`, each written in the text format below
(`sprites/text/<name>.txt`) and turned into a sheet at build time. Their
names are reserved. Imported creatures live in `<app support>/Ledgelings/sprites/<name>/` as
`<name>.png` + `<name>.json` in exactly the built-in layout (32×32 cells,
body box `[5,5,22,22]`, 9 pose columns × 3 eye-variant rows, same palette),
so the app treats them like its own. Creature `i` wears species
`speciesInUse[i mod count]` ("blocky" when the list is empty).

Two import routes:

- **Text** (`.txt`/`.md`), the format a chat model can write:

  ```
  name: pip
  kind: a fat green frog with big eyes            (optional)
  colour: #6cbf4a                                 (optional; `color:` too; six hex digits or the sheet is rejected)
  character: Hopper: Bouncy and loud.             (optional, any number; "Name: persona")
  pose: idle
  <32 rows of 32 letters>
  pose: walk-0 … walk-3, jump, land, sleep-0, sleep-1
  ```

  `kind`, `cast` and `colour` go into the atlas JSON as `kind` (string),
  `cast` (array of `{name, persona}`) and `colour` (hex string). A species
  with a `colour` is always recoloured to it (§9.2), in the colony and on
  its settings card, instead of the creature's slot colour. Shipped:
  frog `#6cbf4a`, ghost `#cfd3ea`, slime `#4fd1a3`, robot `#9aa5b1`,
  mushroom `#d9483b`; the rest have none.

  Letters: `.` nothing, `o` outline, `b` body, `l` light, `s` shade, `k` eye
  (black, blinks), `x` black that never blinks. `-`, `_` and space also mean
  nothing; a short row of nothing is padded; `#` lines are comments; an empty
  line is skipped. Rejected: a missing or unknown pose, a row that is not 32
  wide, an unknown letter, ink outside the body box (columns 6–27, rows 6–27,
  1-based), an empty pose, or no ink on row 27 (the floor). Eye variants are
  derived: for each vertical run of `k`, `half` keeps the lower half (rounded
  up), `closed` keeps the bottom row; what the lid covers becomes body.
  Pixels use the built-in palette, so recolouring (§9.2) works.
- **PNG** on magenta `#ff00ff` (tolerance 60 in RGB distance), 288×96 or a
  whole multiple of it (sampled down at cell centres), alpha hardened to 1 bit.

Settings › Sprites shows every species as a card (idle pose at 3×, name, a
check overlay when it is in the colony); a click toggles it; imported ones
have a delete button. The **sprite kit** below offers: the prompt (the format
above including `kind` and three `character` lines, the rules, and the
built-in creature's idle pose written in letters as the example, with a
placeholder for the user's description), the built-in creature as a whole
text file, and a PNG template: magenta with cell borders and body boxes
marked.

### 9.2 Recolouring

Per body colour `C` (the species' own colour when it has one, else the
creature's slot colour), make a copy of the sheet where every fully opaque
pixel within ±2 per channel of a palette entry becomes:

| Role | New colour |
|---|---|
| body | `C` |
| light | `mix(C, white, 0.36)` |
| shade | `mix(C, black, 0.17)` |
| outline | `mix(C, black, 0.76)` |

`mix(a, b, k) = round(a·(1−k) + b·k)` per channel. Everything else (the black
eyes) is untouched. Cache per colour.

### 9.3 Layer tree per creature

```
body (position, rotation = creature.rotation)
├─ sprite   (bounds = cell·size, contents = frame, scaleX = −1 when mirrored)
├─ Z ×3     (see below; counter-rotated so the letter stays upright)
├─ hat      (flower, bounds 16·size, position (0, bodyHeight/2 + hatHeight/2 − size))
└─ letter   (paper plane's note while reading, bounds 18×12·size,
             position (±0.42·32·size, −0.08·bodyHeight), + when facing right, − when mirrored)
```

The hat lives in the body layer so it turns with the creature onto walls and
the ceiling but never mirrors. `bodyHeight = 32·size`. Nearest-neighbour
filtering everywhere. No implicit animations.

A window only draws a creature when its position is within
`2.5 · 32 · size` points of that monitor's rectangle (a creature crossing a
seam is drawn by both windows). Every window receives every creature.

### 9.4 Zs while asleep

Three Z layers, cycle 2.6 s, the k-th starting `k/3` of a cycle later. With
`clock = asleepFor/2.6 − k/3` (hidden while negative) and `p = clock mod 1`:

```
position (in body space) = (bodyHeight·(0.22 + 0.10·sin(2πp) + 0.18·p), bodyHeight·(0.30 + 0.75·p))
opacity  = min(1, 5p) · min(1, 2.5·(1−p))
scale    = 0.7 + 0.8·p
```

### 9.5 Speech bubble

Text: monospaced, semibold, 12 pt, white, wrapped at 250 pt; the line's runs
(§6.3.1) drawn heavy for bold and in the italic face for italic (skewed 0.22 if
the font has none). Plate: text size +
8 pt padding all round, background `rgba(43, 36, 64, 0.96)`, 1 pt border white
at 35 %, corner radius 6. Centre = `position + inward · (16·size + hatHeight +
10 + plate/2 along inward)`, then clamped so the plate stays 6 pt inside its
monitor. Bubbles are not rotated. A bubble is hit-testable for click-to-close.

### 9.6 Flower in flight and stars

Flight: one sprite layer, bounds 16·size, at the flight position (§7.3),
rotated like the receiver. Stars: a pool of square layers, one per live star,
coloured and faded per §7.4, z above creatures.

### 9.7 Paper plane

The `plane` sheet: 18×12 cells, animations `fly` (the plane, nose right) and
`letter` (the unfolded note). The plane is drawn at the catcher's size, above
everything, rotated to its heading; when the heading points left
(`cos < 0`) it is also flipped vertically so the wing stays on top. Its trail
is a pool of plain white squares, side `max(2, round(1.5·size))` points, opacity
`0.8 · (1 − age/1.1)`, just below the plane.

---

## 10. Windows and input plumbing

### 10.1 Overlay window

One per monitor, exactly the monitor's rectangle, transparent, no shadow,
always above everything including full-screen apps, present on every virtual
desktop, never activates, never becomes key/main, click-through by default.

### 10.2 Hit test

`creature(at point)`: the highest-index creature with
`|point − position| ≤ 11·size + 4` on both axes (a square with 4 pt of
forgiveness). `bubble(at point)`: any window's bubble plate containing the point.

### 10.3 Hand events (global coordinates)

`down(point, shift)`, `dragged(point)`, `up(point)`, `secondaryDown(point)`
(right button, or Control held with the left).

### 10.4 Click-through toggling (every frame)

A window accepts mouse input only if it contains the cursor **and** one of: a
creature is held; the cursor is over a sleeper; the cursor is over any creature
while Shift is down; the cursor is over a speech bubble. Otherwise every click
falls through to whatever is underneath.

---

## 11. What the user can do

| Action | Result |
|---|---|
| Move the cursor near a creature | it jumps to another edge (§4.6); Shift held suppresses this |
| Click a speech bubble | closes it |
| Drag a sleeper (no modifier) | carried, still asleep; drops to the nearest edge of whichever monitor it is over |
| Shift-press and release within 4 pt | **poke**: it speaks to the nearest creature; both stop to talk |
| Shift-press and move ≥ 4 pt | **carry** any creature; awake ones ride with eyes open and land awake |
| Shift-right-click (or Shift-Control-click) | nap toggle: lie down now, or wake |
| Menu: Make Them Jump | every creature startles |
| Menu: Make Someone Talk | §6.5 |
| Menu: Send a Paper Plane | a plane goes up now if two creatures are free (§7.6) |
| Menu: Put Them to Sleep Now / Wake Them Up Now | skip to the next phase (hidden when night = 0) |
| Menu: Hide Them for a While… / Bring Them Back Now | §7.5; while hiding the item shows the time left |
| Menu: Chat History… | the settings window on the Chats tab (§6.5) |
| Menu: Settings… | the settings window |
| Settings › Startup: Start at login | registers the app in the system's login items (macOS `SMAppService`); only an installed .app can |

The menu also shows `"Day — they sleep in m:ss"` / `"Night — they wake in
m:ss"` (or `"Always day — night is set to 0"`), the last talk status line
(first 70 characters), and Quit.

---

## 12. Settings (all persisted, applied live)

| Key | Default | Range / notes |
|---|---|---|
| creatureCount | 3 | 1–24 |
| colors | `#ff8a3d #3dc7b5 #ff6fa3 #ffd23d #9b7bff #7bd65a` | 1–12 hex colours; invalid ones dropped on load |
| minSize / maxSize | 1.5 / 3 | 1–5 in 0.5 steps; setting one past the other drags the other |
| dayMinutes | 3 | 0.5–60 |
| nightMinutes | 5 | 0–60; 0 = never sleep |
| talkEnabled | true | |
| followGiver | true | the wearer of a flower trails its giver (§7.3) |
| planesEnabled | true | paper planes every `planeMinutes` (§7.6); the menu item works either way |
| planeMinutes | 3 | 0.5–60, clamped on load: minutes from one plane to the next |
| brainProvider | script | script, lmStudio, openRouter. Absent on load: `lmStudio` if any of talkServer, talkModel, openRouterModel is stored (a model was set up before scripts existed), else `script` |
| script | the shipped lines (§6.7) | free text in the script format; "Reset Lines" restores; Import/Export read and write it as a `.txt` whole |
| talkServer | `http://localhost:1234` | must parse as a URL with a host |
| talkModel | `google/gemma-3-1b` | |
| openRouterModel | `anthropic/claude-haiku-4.5` | |
| openRouterKey | empty | **secret store**, never the settings file; empty = removed. Read lazily: the store is first opened when something asks for the key (`chatClient()` with OpenRouter chosen, or the Talk tab showing the OpenRouter fields), never at launch, so a user of the local brain never sees a keychain prompt |
| bubbleSeconds | 14 | 4–60, clamped on load |
| flowerMinutes | 2 | 0.5–30, clamped on load |
| characters | the six above | ≥ 2; JSON |
| systemPrompt / linePrompt / replyPrompt | §6.1 | free text; "Reset Prompts" restores |
| voiceEnabled | false | §6.6.1; also the menu's "Hear Them Talk" |
| voiceEngine | system | system, openRouter, local |
| voicePerCharacter | true | |
| systemVoice | empty | a voice identifier; empty = system default |
| voiceModel | `hexgrad/kokoro-82m` | an OpenRouter speech model |
| openRouterVoice | empty | one of the model's voices; empty = its first |
| voiceSpeed / voicePitch | 1 / 1 | 0.5–2, clamped on load; pitch applies to both engines |
| voiceVolume | 0.8 | 0–1 |
| cartoonVoices | true | pitch lift and playful voices first (§6.6.1) |
| characterVoices | {} | name → `{systemVoice, openRouterVoice, localVoice, speed, pitch, followPitch}`, JSON (§6.6.1) |
| speedFollowsPitch | true | ask for `speed / √pitch`, Mac voices rendered and sped up (§6.6.1) |
| localVoiceServer / localVoiceModel / localVoice | `http://localhost:8880` / `kokoro` / empty | the Local server engine |
| keepVoices | true | keep each OpenRouter line in the voice archive (§6.6.1) |

Settings window: 1100×760 points, five tabs, each laid out as two columns
that scroll on their own so a tab fits on one screen (Chats is a day list
beside the day's exchanges). **Creatures**: count, smallest/largest sliders,
colour swatches (add/remove/reset), day/night sliders. **Talk**: talk toggle,
bubble and flower sliders, follow-the-giver and paper-plane toggles and the
plane-interval slider; Brain picker; for Built-in lines: the script in a
monospaced editor, a status line (block counts, or the error and its line),
Import…, Export…, Copy Agent Prompt, Reset Lines; for LM Studio: server, model,
"Installed" menu of ids, Check, status; for OpenRouter: masked key, model,
Check (validates the key, shows label and spend), then a search box and a
scrolling list of the whole catalogue (§8.3), 60 rows at a time, click to
pick, free models tinted green, current model highlighted; characters editor;
prompt editors with a placeholder legend. **Voice**: on the left the toggle,
engine picker, voice-each and cartoon toggles, voice picker or key/model/voice
pickers and Keep with its count and Reveal, speed/pitch/volume sliders, Test,
Stop, status; on the right a card per character on screen with voice picker
(automatic names the voice it gets), speed and pitch sliders, Test and Auto.

---

## 13. Platform notes for a port

- **Wayland** has no global cursor position for an unfocused surface. Options:
  a layer-shell surface that receives pointer motion without focus, or
  polling via a compositor-specific protocol; without it the flee, the
  click-through toggling and the pick-up all degrade to "clickable only while
  Shift is down", which is acceptable.
- **Windows** `WS_EX_TRANSPARENT` makes the whole window click-through; to
  accept a click on a creature, clear the style for the frame the cursor is on
  a target (§10.4) and restore it after, or use a per-pixel alpha layered
  window and let hit-testing fall through where alpha is 0 (bubbles and
  sprites then hit naturally).
- **Linux X11**: `_NET_WM_WINDOW_TYPE_DOCK` or override-redirect plus
  `XShapeCombineRectangles` on the input shape to expose only the creature
  squares and bubble rectangles; recompute each frame is cheap.
- Keep the simulation (§2–§8) in a library with no window dependency and port
  the tests in §14 first; the macOS app has 144 such tests and 82 app-side ones.

---

## 14. Acceptance tests (port these)

Geometry: a loop runs counter-clockwise from the bottom-left; segments change
exactly at corners; `wrap` works both ways; rotation stands the creature on
each edge facing inwards; nearest point on a loop; one screen is its rect
pulled in by the inset; two equal screens side by side become one loop with no
seam; a shorter neighbour makes an outside corner to walk round; negative
coordinates work; screens touching only at a corner stay separate loops;
`nearest` picks the right loop; an absurd inset still leaves a loop.

Creature: walks at its speed; turns the corner onto the next side and its
rotation settles at the segment's; blinks and reopens; a distant cursor is
ignored; a close cursor starts a jump that stays inside the screens and lands
on another edge; squashes on landing then walks; not catchable mid-air;
survives a monitor being unplugged; walks from one monitor onto the next;
falls asleep at night with eyes shut and dozes off at staggered times; wakes
when day breaks; a sleeper ignores the cursor; nap toggle works by day and
persists until dawn; an awake creature cannot be picked up without `evenAwake`;
a carried sleeper drops to the nearest edge still asleep, on any monitor; an
awake carried creature lands awake and is not startled by the hand holding it;
`shortestArc` goes the short way round; meeting stops it facing the other and
`walkOn` restores its course; a chat ends on its own after its limit; the
cursor startles a chatter; a sleeper refuses a chat.

Clock: phases, remaining, skip.

Meetings: a pair bumps once, not every frame; only on the same edge and
monitor; sleepers, jumpers and chatters excluded; the cooldown; the third bump
is a gift and the count restarts (1, 2, 3, 1); three on one edge report the
two adjacent pairs.

Gifts: fly, land after `flightTime`, wilt after the wear time; one flight at a
time; removed creatures lose their flowers; ten distinct flower names.

Paper planes: the wind is the same at the same place and time, bounded, and
smooth; a plane reaches a walking catcher from anywhere within 25 s even in a
wind of 400; every thrown plane has its own wind and about four in five are
quick; a swirling quick plane is always caught at 30 fps; the swirl curls the
path far more than still air; a fast plane cannot skip past its catcher
between frames; the trail is dotted and fades a second after the plane is
gone; the post is due every interval from the last plane, a retry waits 10 s,
zero means never; the catcher is from the farther half; every default
character has a voice with notes, thoughts and answers, and every line fills
in; in a colony: thrown, caught, read out, thought about, logged, free again;
the catcher writes back once to the sender and the answer is not answered; a
bump does not put the next plane off; a plane to a sleeper is dropped; the one
a plane is flying to keeps out of talks; a flower wearer never bumps; turned
off, none goes by itself.

Sparks: 8 per burst; all thrown into the screen at first; gone after about a
second; opacity falls with age; gravity pulls back toward the edge.

Hideout: the whole cycle with the scale at each phase; stragglers forced in
after the cap; recall from hidden opens now; recall during gathering releases
whoever is in; a second hide is ignored. Creature: runs home the short way at
2.5× walking speed and arrives; running wraps across the loop's seam; a sleeper
wakes to run and night does not stop it; a leap lands exactly on the spot and
waits; emerging places it at the door walking the given way.

Banter: placeholders render; unknown ones stay; `cleanLine` strips think tags,
name prefixes, quotes, caps length; `showTime` gives ≈ base for 8 words, caps at
2·base, default 14.

Chat client: LM Studio request has no auth and the right URL and body;
OpenRouter request carries the key, the app headers, custom max_tokens and
temperature; model list URLs per provider; reply parsing; server error in its
own words; garbage → "unexpected reply"; model list shape.

Catalogue: prices per million; exchange cost; multi-word search; empty search
ranks cheapest first with unpriced last; price labels.

Settings: defaults; clamping on load; the OpenRouter key never lands in the
settings file and comes back from the secret store; no key → no client.

Sprites: every animation the creature can play exists in the sheet with every
eye variant; every flower the colony can give is in the flowers sheet;
recolouring leaves the eyes black.
