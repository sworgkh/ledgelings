# Ledgelings — full specification

A platform-neutral description of the whole product, precise enough to
re-implement it on Linux, Windows or anywhere else without reading the Swift.
Every number here is the one the macOS app ships with (v0.7). Where the
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
bump into each other, stop to trade a line of dialogue written by a language
model, and every third meeting one gives the other a flower to wear.

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
- Colour: creature `i` wears colour `i mod colours.count`. Character: `i mod
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
   past their time (§7.3). Age the sparks (§7.4). Release the chatting pair if
   it is over (§7.2). Detect bumps and handle them (§7.1).
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

Three editable templates with `{placeholders}`: `speaker`, `speakerPersona`,
`listener`, `listenerPersona`, `situation`, `line`. Unknown placeholders are
left as written.

System prompt (default):

```
You are {speaker}, a small square creature who lives on the edge of a computer screen. {speakerPersona}
You are talking to {listener}, another creature on the same edge. {listenerPersona}
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

`talk(speaker, listener, event?)`. Refused (returns false) if a conversation is
already running, an index is invalid, or no brain is configured (§8). Then, in
the background:

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
 "lines": [{"speaker": "Dot", "text": "Move, boulder."}, {"speaker": "Blocky", "text": "Says the pebble."}]}
```

A one-sided exchange (the reply failed or came back empty) is still written
with its one line. Reading: list days = files named `YYYY-MM-DD.jsonl`, newest
first; a day's exchanges are its lines in file order; a line that does not
parse is skipped. The viewer (Settings › Chats, also "Chat History…" in the
menu) lists days on the left, naming today and yesterday, and shows each
exchange as time, model, situation, then `**Name:** text` per line, with
buttons that open the folder in the file manager and in a terminal.

### 6.6 Menu and poke

"Make Someone Talk" picks a random awake, non-jumping creature (anyone if none
is awake), the nearest other creature listens. A Shift-poke (§11) does the same
with the poked creature as speaker. Both first **hold** the pair (§7.2). If the
talk could not start, release after 1 s.

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
  largest creature. It stands flush in the primary monitor's bottom-right
  corner: centre `x = maxX + 2·s − 68·s/2`, centre `y = minY + 60·s/2` with
  `s = maxSize`. `scale` ramps 0→1 during appearing and growing, 1→0 during
  shrinking and vanishing, 1 while gathering and releasing, 0 otherwise. Drawn
  **in front of** the creatures, so they vanish into the doorway.
- **Doorway**: on the house's left, 26 px wide and 28 px tall from the floor,
  its middle 19 sheet px from the cell's left edge. The door point is that
  middle on the floor; each creature's door spot is the nearest point of its
  own world to it.
- **Gathering**, every frame, for every creature not yet inside: if held, let
  go; if in the air, wait; if on another loop than its door, `leap` to the
  door; else if within 6 points of the door along the loop, or `hasArrived`,
  it is **inside** (skipped by update and render from now on); else if not
  already running, `run` to the door. Cursor is ignored by everyone while the
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
temperature: 0.9, max_tokens: 80}`, 60 s timeout. Reply text =
`choices[0].message.content`. Callers may pass other `max_tokens` and
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

`brainProvider` (`lmStudio` | `openRouter`), `talkServer`, `talkModel`,
`openRouterModel`, `openRouterKey` (secret store only). `chatClient()` returns
nil with a reason when the server address is not a URL or the OpenRouter key is
empty; the reason is shown as the talk status.

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

### 9.2 Recolouring

Per creature colour `C`, make a copy of the sheet where every fully opaque
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
└─ hat      (flower, bounds 16·size, position (0, bodyHeight/2 + hatHeight/2 − size))
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

Text: monospaced, semibold, 12 pt, white, wrapped at 250 pt. Plate: text size +
8 pt padding all round, background `rgba(43, 36, 64, 0.96)`, 1 pt border white
at 35 %, corner radius 6. Centre = `position + inward · (16·size + hatHeight +
10 + plate/2 along inward)`, then clamped so the plate stays 6 pt inside its
monitor. Bubbles are not rotated. A bubble is hit-testable for click-to-close.

### 9.6 Flower in flight and stars

Flight: one sprite layer, bounds 16·size, at the flight position (§7.3),
rotated like the receiver. Stars: a pool of square layers, one per live star,
coloured and faded per §7.4, z above creatures.

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
| Menu: Put Them to Sleep Now / Wake Them Up Now | skip to the next phase (hidden when night = 0) |
| Menu: Hide Them for a While… / Bring Them Back Now | §7.5; while hiding the item shows the time left |
| Menu: Chat History… | the settings window on the Chats tab (§6.5) |
| Menu: Settings… | the settings window |

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
| brainProvider | lmStudio | lmStudio, openRouter |
| talkServer | `http://localhost:1234` | must parse as a URL with a host |
| talkModel | `google/gemma-3-1b` | |
| openRouterModel | `anthropic/claude-haiku-4.5` | |
| openRouterKey | empty | **secret store**, never the settings file; empty = removed |
| bubbleSeconds | 14 | 4–60, clamped on load |
| flowerMinutes | 2 | 0.5–30, clamped on load |
| characters | the six above | ≥ 2; JSON |
| systemPrompt / linePrompt / replyPrompt | §6.1 | free text; "Reset Prompts" restores |

Settings window: two tabs. **Creatures**: count, smallest/largest sliders,
colour swatches (add/remove/reset), day/night sliders. **Talk**: talk toggle,
bubble and flower sliders; Brain picker; for LM Studio: server, model,
"Installed" menu of ids, Check, status; for OpenRouter: masked key, model,
Check (validates the key, shows label and spend), then a search box and a
scrolling list of the whole catalogue (§8.3), 60 rows at a time, click to
pick, free models tinted green, current model highlighted; characters editor;
prompt editors with a placeholder legend.

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
  the tests in §14 first; the macOS app has 63 such tests and 31 app-side ones.

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
