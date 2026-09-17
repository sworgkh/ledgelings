# Ledgelings — project brief

Small native macOS app. Little creatures live on the **edges of your screens**: they
walk along the top/bottom/left/right borders, sit on the menu bar, drop down, climb
back up, and occasionally react to you. Always on top, always click-through except
where you deliberately touch them.

Think Shimeji / eSheep / Bonzi, but: native, tasteful, multi-display aware, and not
eating your battery.

## What it is

- A menu-bar-only app (no Dock icon, `LSUIElement`).
- One transparent, click-through, always-on-top overlay window **per screen**.
- N creatures crawling the **perimeter** of each screen, able to cross between
  screens through shared edges.
- Each creature has a small behaviour brain: idle, walk, pause, look around, sleep,
  react to the cursor.

## What it is NOT (say no early)

- Not a desktop pet that walks over your windows (edges only — that's the identity).
- Not a widget/notification/productivity tool. It's ambience.
- Not a game. No score, no feeding, no levels. (Maybe later. Probably not.)
- Not Electron. Native or nothing.

## Target platform

- macOS 26+ (dev machine is macOS 26.6, Xcode 27).
- Swift 6, SwiftUI shell + AppKit where the overlay windows need it.
- Apple Silicon.

## The hard parts (the real work is here)

| # | Problem | Why it's hard | Direction |
|---|---|---|---|
| 1 | Click-through overlay per screen | Must never steal clicks, must stay above full-screen apps and Spaces | `NSWindow` subclass, `ignoresMouseEvents`, `.statusBar`/`.screenSaver` level, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` |
| 2 | Hit-testing only the creature | Overlay covers the whole screen but only the sprite should be clickable | Toggle `ignoresMouseEvents` per frame, or a small tracking window that follows the creature |
| 3 | Multi-display geometry | macOS global coordinates are bottom-left origin, screens can be at odd offsets and scales | One geometry layer that owns the perimeter path; creatures move along a 1-D "edge parameter", not in x/y |
| 4 | Screen hot-plug | Dock a laptop, screens appear/disappear mid-walk | Observe `NSApplication.didChangeScreenParametersNotification`, rebuild the perimeter graph, re-home stranded creatures |
| 5 | Idle cost | This thing runs 24/7 | Sprite animation via `CADisplayLink`/`CVDisplayLink`, throttle to ~15–30 fps, pause entirely when no creature is visibly moving, drop to 0 Hz on battery + idle |
| 6 | Art | Cuteness is the whole product | Sprite sheets (PNG atlas) or vector/SF-Symbols-ish shapes. Decide before writing the renderer |

## Perimeter model (the core idea)

Treat every screen's border as a closed loop. A creature's position is a single
number `t ∈ [0, perimeterLength)`, plus a screen id. Corners are just points on the
loop where the creature's rotation changes. Walking = `t += speed * dt`.

Screens that touch each other get **portals**: a range on screen A's loop maps to a
range on screen B's loop, so a creature can walk from one monitor onto the next.

This keeps the movement code trivial and pushes all the pain into one geometry
module that can be unit-tested without a window on screen.

## MVP (v0.1) — what "done" means

1. Menu bar icon, quit, "creature count" slider, launch-at-login.
2. One overlay window per screen, click-through, survives Spaces and full-screen apps.
3. One creature type, walking the perimeter of the main screen, correct orientation
   at corners.
4. Multi-screen: creatures cross between adjacent screens.
5. Hot-plug doesn't crash or strand anyone.
6. Idle CPU under ~2% with 3 creatures, near 0% when everything is asleep.

## Later (v0.2+, explicitly out of MVP)

- Several creature species with different gaits.
- Cursor reactions: follow, flee, peek.
- Click to pet / pick up and drop.
- Creatures reacting to system state (low battery, build finished, Do Not Disturb).
- User-supplied sprite packs.
- Notarised DMG / Sparkle updates.

## Repo layout (proposed)

```
Ledgelings/
  App/            menu bar app, settings, launch-at-login
  Overlay/        NSWindow subclass, per-screen overlay controller
  Geometry/       perimeter loops, portals, screen graph  ← pure, unit-tested
  Creatures/      behaviour state machine, species definitions
  Rendering/      sprite atlas, animation, display link
  Resources/      sprite sheets
Tests/
  GeometryTests/  the only part worth heavy tests up front
```

## Open questions for the next session

1. Sprite art or procedural/vector creatures? (Blocks the renderer.)
2. SpriteKit for the overlay content, or plain `CALayer`? SpriteKit is easier for
   animation, heavier at idle.
3. Menu bar creature — does one live *on* the menu bar, in front of the clock?
4. Distribution: personal use only, or eventually a signed/notarised build?
5. Name: "Ledgelings" is a placeholder. Alternatives: Edgelings, Screenmites,
   Bordercrawlers, Marginalia.
