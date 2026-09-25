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
- Shown in the settings window on the tab it belongs to (Creatures, Sprites, Talk,
  Voice, Costs, Chats; a new tab when a feature outgrows its host, as Voice and
  Costs did). Two columns; a tab fits a laptop screen without scrolling. A footer
  says what the setting does in plain words.
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
  writes a settings tab to a PNG (tabs: creatures, sprites, talk, voice, costs, chats).
- `--say "text"` speaks one line with the current voice settings, cues on stderr.
- `--cast` casts everyone on screen with the brain model and prints the picks.
- `--converse` starts one conversation and prints every line and voice cue with its
  time, then quits once the pair is let go: the way to measure dialogue timing.
- `swift build` does not update `build/Ledgelings.app`; run `scripts/make-app.sh`.
- The app's preferences are shared with the owner's running copy. Back them up
  (`defaults export com.alterman.ledgelings file.plist`) before a test changes
  them, and restore with `defaults import` **plus** deleting any key the test added:
  import does not remove keys.
- A new ad-hoc build reading the OpenRouter key blocks on the keychain prompt; for a
  headless run set `brainProvider` to `script` (or LM Studio) and restore it after.
