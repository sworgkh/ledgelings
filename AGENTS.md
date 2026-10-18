# Working on Ledgelings

Read [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing and the macOS/Windows
split, and [SPEC.md](SPEC.md), which is the product. The rules below are the ones
that are easy to forget while adding a feature. Every change keeps all three.

## 1. Every model call is priced, and says which feature made it

The owner reads **Settings › Costs** to see what each feature costs. A call that is
not recorded there is money spent in the dark.

- Every call to a model (chat, speech, casting, anything added later) is recorded
  with `SpendLedger.record(provider:model:usage:purpose:)`. `purpose` has no
  default on purpose: add a case to `Spend.Purpose` (with its `title`) for a new
  feature rather than borrowing another's.
- Record the call even when its answer turns out empty or unusable: it was paid for.
- OpenRouter chat replies carry their price (`usage.include`). OpenRouter speech
  replies are audio and carry none: look the price up by `X-Generation-Id` at
  `/generation`, as `Voice.charge` does. LM Studio, a local speech server and the
  Mac's own voices are free: record LM Studio at `$0`; the others need no record.
- When the call belongs to a conversation, also note it where the Chats tab can put
  it beside that conversation (`ChatLog.Exchange.cost`, or `ChatHistory.recordVoice`).
- Test the new purpose lands in `Spend.summarise(...).byPurpose`.

## 2. Every feature has its settings

Nothing the creatures do is hard-wired if someone could want it otherwise.

- An on/off toggle, and every number a person might tune (how often, how long,
  how loud), in `AppSettings`: `@Published`, saved on change, clamped to its range
  on load, with a default that is chosen, not accidental.
- Shown in the settings window on the tab it belongs to (Creatures, Actions, Chases, Beds, Play, Sprites, Talk, Flowers,
  Productivity tools, Voice, Costs, Chats; a new tab when a feature outgrows its host, as Voice and
  Costs did). Two columns; a tab fits a laptop screen without scrolling. A footer
  says what the setting does in plain words.
- A tool that works for the owner rather than being creature behaviour (reminders,
  a clipboard) is a section of Productivity tools: a `ProductivityTool` case, its
  `title`, and its view in `ProductivitySettingsView.page`.
- Something toggled often (voice on/off) also gets a menu item.
- Documented in `docs/SETTINGS.md` (the table: setting, default, range, notes) and
  in SPEC §12's settings table, with the key name.
- A settings test: the default, and that a changed value survives a relaunch.

## 3. The characters stay themselves

A character is a **name and a persona** in its species' cast, plus the species'
`kind` ("a boxy little robot…"). Everything a character produces follows both.

- Lines, notes, replies: the prompts carry `{speakerPersona}` and `{speakerKind}`;
  a new kind of utterance does the same. Built-in lines are written per character,
  in its voice (Blocky grumpy about the cursor, Zed drifting to sleep, Unit 7 in numbers).
- Voice: automatic voices are cast from the persona and kind (`Casting`), so write
  personas in words that say how someone sounds: old, slow, tiny, fast, cheerful,
  grumpy, anxious, he/she; a robot or ghost species. Settings follow the character's
  name, so a rename is a new character.
- Looks: every creature is drawn in Blocky's style (`spritetool/painters/blocky.py`):
  a square body, flat fill, 1-pixel dark-tint outline, light line top-left, shade
  line bottom-right, black square eyes (3 wide) right of centre a quarter down, 4×2
  feet, no mouth, no curves (curves become stepped corners). Six creatures drawn with
  curves and small eyes were once sent back as "a different style".

## Checking your work in the real app

The owner judges the running app, not the diff: a change is done when it is built
with `scripts/make-app.sh`, installed and seen working.

- `build/Ledgelings.app/Contents/MacOS/Ledgelings --settings <tab> --snapshot out.png`
  writes a settings tab to a PNG (tabs: creatures, actions, chases, beds, play, sprites, talk, flowers, productivity, voice, costs, chats;
  `reminders` still opens productivity, its old name; `clipboard` and `screenshots` open it on that tool).
- `--say "text"` speaks one line with the current voice settings, cues on stderr.
- `--cast` casts everyone on screen with the brain model and prints the picks.
- `--converse` starts one conversation and prints every line and voice cue with its
  time, then quits once the pair is let go: the way to measure dialogue timing.
- `--garden-film out.mp4` hands five creatures a flower each and films them offscreen
  until all have planted, printing who planted what and why (`plant Blocky poppy floor`).
- `--bed-film out.mp4` films one creature of each species offscreen from nightfall until all
  are asleep in their beds, then drags one bed to the ceiling, printing each step
  (`bed Blocky walks to crate (floor)`, `bed Morel moved …`).
- `--play-film out.mp4 [tag|rope|parachute|basketball]` films each game (or one) offscreen with
  four creatures, the first two old friends, and prints each step with its time
  (`play rope Hopper fires at (639, 576)`, `play basketball Blocky scores`, `play tag over after 7 touches`).
- `--screens` prints every monitor (id, name, frame, `home`), the choice, the colony's bounds and
  where each creature is; `--screens all|N` also makes the choice live (N = monitor number left to
  right, from 1; saved like the menu does), prints every step of the move (`move Blocky hops off DELL U2415 (1)`,
  `… comes down at 812`, `… lands at (812, 37)`) and the state once they have landed. Exit 1 if anyone is left off.
- `--screens-film out.mp4` films two simulated monitors side by side offscreen: everyone moves to the
  right one, then the left, then all screens again, printing each step.
- `--actions --activities --snapshot out.png` writes the Creature Actions sheet's Activities page.
- `--grab` makes the first creature grab the real cursor now and prints each step
  with its time (`grab Blocky`, `let go Blocky: shaken`), then quits once it lets go.
- `--tea` starts a tea party on the real screen and prints every line with its time,
  then quits once the pair walks on; `--tea-film out.mp4` films a one-minute party
  offscreen (built-in lines, or a local server named by `LEDGELINGS_TEA_SERVER`),
  which works even while the display sleeps and the live display link stops.
- `--clip-demo [--snapshot out.png]` runs the clipboard manager on the real pasteboard with its own
  history, snippets and keychain secret (removed after, the pasteboard put back), never pressing ⌘V:
  copies kept and skipped, a picture kept as files and pasted back as the same PNG and TIFF, a search, ⇥ ↓ ⏎ in the picker, a protected paste concealed and taken back,
  each step with its time (`clip 1.94 picker: would paste Wi-Fi password after 70 ms, concealed`). Exit 1 if wrong.
- `--paste-check` prints whether this build has Accessibility and presses a real ⌘V into a text
  field of its own (`paste ⌘V pressed, field now "…" after 327 ms`, `paste pasted for real`); exit 1
  if nothing landed. Started from a terminal it borrows the terminal's permission: to see the app's
  own, `open build/Ledgelings.app --stderr /dev/stdout --args --paste-check`.
- `--clip-film out.mp4` films the clipboard picker brought by a creature offscreen: the leap to the
  sheet's corner, the unfold, a search, the collapse into a text cursor and the leap home, then a round
  with no cursor known, printing each step (`film 1.00 clip Whiskers leaps to (245, 558) in 0.31 s`).
- `--shortcut` says whether the system took the shortcuts from any app (`shortcut ⌃⌥L registered`,
  `shortcut ⌃⌥V history registered`, `shortcut ⌃⌥B snippets registered`, `shortcut ⌃⌥S screenshot registered`,
  `shortcut ⇧⌘8 full screen registered`, `shortcut ⇧⌘\ last rectangle registered`),
  then `shortcut pressed: sheet up` when it is pressed, and quits; nothing in 30 s is exit 2.
- `--shot-check` prints whether this build has Screen Recording and whether each monitor's capture
  shows the screen (`shot Built-in Retina Display: 3024×1964 px at 2×, 412 colours in a sample`); exit 1 if
  not. Like `--paste-check`, from a terminal it borrows the terminal's permission.
- `--shot-demo [--snapshot out.png]` takes a toolbar shot of the real screens (a rectangle, box, arrow,
  blur, hand blur, an undo, ⌘C), checks the clipboard holds that PNG, takes the last rectangle again, and
  puts the clipboard and settings back; each step with its time. Exit 1 if wrong.
- `--shot-film out.mp4` films the screenshot tool offscreen on two simulated monitors (2× and 1×): a
  rectangle with marks and blurs, a lasso, all monitors, the last rectangle again; writes each PNG beside
  the film and prints each step (`film 7.40 taken 800×520 px, 4 marks`).
- `--kit-images <folder>` writes the sprite kit's two pictures and the prompt (from the saved
  form) and quits; `--kit-import <picture>` imports one picture with the saved form, as
  Import… does, and prints the name, colour and idle pose it read (it adds the species).
- `swift build` does not update `build/Ledgelings.app`; run `scripts/make-app.sh`.
- The app's preferences are shared with the owner's running copy. Back them up
  (`defaults export com.alterman.ledgelings file.plist`) before a test changes
  them, and restore with `defaults import` **plus** deleting any key the test added:
  import does not remove keys.
- A new ad-hoc build reading the OpenRouter key blocks on the keychain prompt; for a
  headless run set `brainProvider` to `script` (or LM Studio) and restore it after.
