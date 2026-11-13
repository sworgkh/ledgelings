# Working on Ledgelings

Read [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing and the macOS/Windows
split, and [SPEC.md](SPEC.md), which is the product. The rules below are the ones
that are easy to forget while adding a feature. Every change keeps all five.

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
- Shown in the settings window on the page it belongs to (the sidebar's `SettingsPage`s, under
  their `SettingsGroup`; a new page when a feature outgrows its host, as Voice, Costs and Ball
  games did: a case, its `title` and `group`, and its view in `SettingsView.page`). Two columns;
  a page fits a laptop screen without scrolling. A footer says what the setting does in plain words.
  Section headings are `SettingsHeader("…")`, so a search can land on them.
- Findable by the settings search: its key, label and section go into `SettingsIndex.sections`
  (a test fails for a saved key in no section).
- A tool that works for the owner rather than being creature behaviour (reminders,
  a clipboard) is a page under the *Tools* group.
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
  Detailed species (cactus, beetle, crystal, sprout, traced from the owner's chosen art) may carry
  fixed-colour details outside the body palette (`paint:` letters in `sprites/text/make.py`).

## 4. Controls say what they do

Nobody should have to remember what a letter on a button means.

- A control that acts is a **picture of what it does** (drawn in the game's style:
  square pixels, flat fill, 1-pixel outline, no curves) or its words, never a bare
  letter, symbol or abbreviation (`R`, `⌘Z`, `→`, `TS`).
- On hover it names the action and its key: "Blur rectangle (X)", "Undo the last
  mark (⌘Z)". Translated like any other text (`tr`, the Russian table).
- Keys stay as shortcuts, unchanged; the picture replaces only the visible letter.
- Mac: SwiftUI `.help(…)` in ordinary windows; in an overlay above the screen
  saver level (the screenshot toolbar) the system tooltip opens underneath, so draw
  the tag in the view itself, as `ShotToolbar` does. Windows: a `ToolTip` on the button.
- A test that every control has its picture and a non-empty tooltip naming its key
  (`ShotButtonTests`).

## 5. New screens use the shared look

Screens drifted apart once: wrapped button words, lists running past their sheet,
a font size per file. [docs/DESIGN.md](docs/DESIGN.md) is the look, and
`Sources/Ledgelings/Design.swift` is the only place it is defined (on Windows,
`win/Ledgelings/UI/Design.cs` and the one ResourceDictionary `Design.xaml`).

- A settings section: `SettingsHeader`, rows, a footer; buttons in a `ButtonRow`,
  a button in a list row is `rowAction()`, an empty list an `EmptyNote`.
- Pixel paper: `PaperTitle`, `PaperHints`, `PaperEmpty`, `PixelBox`, `PixelButtonStyle`,
  `PixelTag`, and the `Pixel.Font` sizes. No `.system(size:)` of its own, no
  `minimumScaleFactor`, nothing below `Pixel.Font.hint`.
- No gap outside the spacing scale (4, 8, 12, 16, 24).
- Words never wrap or truncate on a button, in English or Russian: shorten them, or
  use a picture with a tag (§4). `DesignTests` measures the pixel buttons.
- No settings page scrolls: `--layout-check` in both languages. A page that outgrows
  the window is split into two pages (as Voice and Character voices).
- The menu bar menu holds things to do now and windows to open; a switch or a
  choice belongs in Settings, findable by its search. The one exception is *Hear
  Them Talk*, toggled often.

## Checking your work in the real app

The owner judges the running app, not the diff: a change is done when it is built
with `scripts/make-app.sh`, installed and seen working.

- `build/Ledgelings.app/Contents/MacOS/Ledgelings --settings <page> --snapshot out.png`
  writes a settings page to a PNG (pages: creatures, actions, sprites, beds, flowers, calendar, effects, moments, weather, chases, play, ballgames, surfing, diving,
  talk, chatwithyou, voice, charactervoices, bonds, relationships, twists, tools, reminders, clipboard, screenshots, dictation, translate, savedtranslations, readaloud, costs, chats;
  `--settings-search <words>` searches and opens the first place; `weather` opens the Weather & Sky window and writes it, the page beside it as `out.page.png`;
  `productivity`, the old tools tab, still opens Reminders).
- `--layout-check` opens every settings page in turn and prints whether a column scrolls
  (`layout voice: fits, fits`, `layout sidebar: fits`); exit 1 if a page or the sidebar does
  (Bonds, Costs and Chats are lists and may). Run it with `-language en` and `-language ru`.
- `--menu` prints the menu bar menu as it would open now, one item a line (`---` a separator).
- `--clip-picker [snippets] --snapshot out.png` writes the clipboard picker over the real
  history; `--snippets --snapshot out.png` the Snippets editor.
- For snapshots: `LEDGELINGS_APPEARANCE=light|dark` draws every window in that mode;
  `LEDGELINGS_NO_KEYCHAIN=1` reads no secret, so a new build never waits on the keychain
  prompt; `-language ru` (and any other saved key, `-brainProvider script`) overrides a
  preference for that run only, writing nothing.
- `--say "text"` speaks one line with the current voice settings, cues on stderr.
- `--cast` casts everyone on screen with the brain model and prints the picks.
- `--converse` starts one conversation and prints every line and voice cue with its
  time, then quits once the pair is let go: the way to measure dialogue timing.
  `--converse --invite soccer` opens it with that invitation and waits for the deed
  (`deed Blocky asks Boo: soccer`, `deed Boo accepts soccer from Blocky`, `deed Blocky & Boo start: invite soccer`).
- `--invite-film out.mp4 [soccer|tag|basketball|baseball|surf|tea]` films a letter invitation offscreen, the
  letter written back yes and the game played, printing each step and what the pair remembers of it.
- `--memory [name]` prints every pair's memory (bond, story, facts, games, last days) and the block each
  carries into a prompt, with its tokens; `--memory-seed [--dry-run]` reads the last `seedDays` of the chat
  log into it (the dry run sends nothing, touches no key, changes nothing); `--diary` writes every due
  pair's diary now; `--relationships --snapshot out.png` writes the Relationships window.
- `--twist join|leave|back <name>` makes that change of the gang by hand, as if it had just
  happened, has every conversation bring it up, and prints the roster and the news
  (`gang Boo: away since 8 Nov`, `gang event left Boo today`); with `--converse` the lines follow
  (`twist Blocky hears: News in the gang: …`, `twist built in: Blocky on left Boo`), with `--memory`
  every pair's memory. It writes the event into `bonds.json`: back it up first.
- `--garden-film out.mp4` hands five creatures a flower each and films them offscreen
  until all have planted, printing who planted what and why (`plant Blocky poppy floor`).
- `--bed-film out.mp4` films one creature of each species offscreen from nightfall until all
  are asleep in their beds, then drags one bed to the ceiling, printing each step
  (`bed Blocky walks to crate (floor)`, `bed Morel moved …`).
- `--play-film out.mp4 [tag|rope|parachute|basketball|soccer|baseball|surf]` films each game (or one) offscreen with
  four creatures, the first two old friends, and prints each step with its time
  (`play rope Hopper fires at (639, 576)`, `play basketball Blocky scores`, `play tag over after 7 touches`);
  soccer, baseball or surfing alone is played by 1, 2, 3 and 5 creatures in turn (`play soccer Unit 7 scores 0-2`,
  `play baseball Unit 7 runs to second`, `play surf Hopper rides it out: 84 points`).
- `--surf-film out.mp4` films three surfing offscreen over a pretend window (its text must stay readable through the
  water), printing each step (`surf 13.00  play surf Blocky catches the wave`), writes stills beside it (`…-riding.png`,
  `…-trick.png`, `…-wipeout.png`, `…-board.png`, `…-button.png`, `…-button-tag.png`, `…-stopped.png`); clicks the water
  on the second wave (the surf goes on), clicks the Stop button on the third, then surfs again and presses Stop activity's
  shortcut; exit 1 unless each stop clears the water, boards and score within 0.5 s.
- `--dive-film out.mp4` films a scuba dive offscreen (water rising, the gear, jumps, sea life, a click through the
  water into a window below that stops nothing, the Stop button and its tag, the draining, the climb out), then a second
  dive ended by a click on the Stop button and a third by Stop activity's shortcut, printing each step and how long the
  screen took to clear (`stop button: water, fish and gear gone after 0.03 s`); stills beside it (`…-button.png`, `…-button-tag.png`).
  `--dive [--stop-after 8]` (or `--surf`) runs one on the real screen, printing each step and where the Stop button
  stands (`stop button at (1588, 1042) 330×42 on Built-in Retina Display: Stop · Control + Option + Q`), and quits once
  they are out (or after pressing Stop activity, or a click on the Stop button, printing how long the screen took to clear).
  `--shortcut` lists `shortcut ⌃⌥Q stop activity registered`; pressing it prints `shortcut pressed: stop activity (…)`.
- `--effects-film out.mp4` films every style on Blocky and Boo, then every moment, offscreen, printing each start
  (`fx 3.20 Smitten on Boo`, `fx 9.10 moment goal Blocky`), and writes `…-contact.png` beside it: every effect at its
  height, captioned. `--effect <name> [--on Blocky]` plays one style or moment (`frost`, `goal`, `winter`, or a pixelfx
  id) on the real screen and quits once it is over. `--actions --styles --snapshot out.png` writes Creature Actions › Styles.
- `--weather-film out.mp4 [snow|rain|wind|storm]` films each weather offscreen with four creatures (Blocky and Boo close,
  Sprout small on the top edge) over a pretend window, printing each step (`weather snow starts`, `snow pile bottom 6 px`,
  `rain Blocky & Boo share an umbrella`, `rain Sprout umbrella full, falls`, `wind gust pushes Sprout 6 px`), writes stills
  beside it (`…-snow-window.png`, `…-rain-shared.png`, `…-rain-falling.png`…); exit 1 if a step never happened.
  `--weather <kind> [--stop-after 20]` starts one on the real screen and quits once it is over.
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
- `--translate "text" [--to he] [--model id]` translates through the real call and prints the detection, target,
  time, price and answer; `--translate-bench [--runs 10]` times the candidate models; `--translate-sheet "text"
  [--to he] [--drawer] [--snapshot out.png]` opens the sheet on the real screen and writes it once translated
  (with the drawer of saved translations open beside it); `--translate-film out.mp4` films the sheet offscreen,
  saving two translations, the drawer, a search, a load and a delete (stills beside it, `…-saved.png`, `…-drawer.png`). `LEDGELINGS_FAKE_TRANSLATE=1`: hand-written
  answers, no key, no network (the way to run them headless: a new build reading the key blocks on the keychain).
- `--chat "text" [--to Blocky|all]` sends one message through the real calls and prints each answer, voice cue, price and
  time, then what each remembers; `--chat-window [--to name] [--send "text"] [--snapshot out.png]` opens the chat window on
  the real screen and writes it; `--chat-film out.mp4` films a talk to one and to everyone offscreen with stand-in answers
  (stills beside it, `…-answer.png`, `…-everyone-done.png`, `…-no-model.png`). `LEDGELINGS_FAKE_CHAT=1`: hand-written
  answers, no key, no network. Priced under Chat with you; the memory is `owner-chats.json` beside `bonds.json`: back it up.
- `--read "text" [--preset name] [--engine system] [--out file.m4a] [--mute]` reads through the real calls and prints the provider,
  voice, time to first sound, length and price (`read provider openRouter · Charon on … · first sound after 1.9 s · …`);
  `--read-bench [--models a,b]` asks each candidate speech model for the same EN/RU/HE paragraph without playing it,
  and has the dictation model write each down again; `--read-sheet "text" [--preset name] [--snapshot out.png] [--mute]`
  opens the sheet on the real screen, reads, writes the paper and closes. All priced under Read aloud. `--engine system`
  reads with the Mac's voices: no key, no keychain prompt, free (headless, with `brainProvider` set to `script`).
- `--drag-check [name]` opens every window that moves (or the one named: settings, relationships, snippets, actions,
  reminder, tools, translate, readAloud, clipPicker, chat) on the real screen, drags it 90 points right and 70 down with real
  mouse events, closes and reopens it, and prints each step (`drag tools: top-left (412, 801) → (502, 731), moved 90, -70; saved (502, 731)`,
  `drag tools: reopened at (502, 731), where it was left`); exit 1 if one stayed put or forgot its place. Needs Accessibility
  (as `--paste-check`), an unlocked screen, `LEDGELINGS_FAKE_TRANSLATE=1` and `brainProvider` = `script`; it saves places, so back up the preferences.
- `--tools [--snapshot out.png]` opens the Tools screen on the real screen, prints each tile with its tag
  (`tools 1 translate: Type to translate (1 · ⌃⌥T)`), writes the paper to a PNG and closes.
- `--shortcut` says whether the system took the shortcuts from any app (`shortcut ⌃⌥L registered`,
  `shortcut ⌃⌥V history registered`, `shortcut ⌃⌥B snippets registered`, `shortcut ⌃⌥S screenshot registered`,
  `shortcut ⇧⌘8 full screen registered`, `shortcut ⇧⌘\ last rectangle registered`, `shortcut ⌃⌥D dictation registered`, `shortcut ⌃⌥T translate registered`, `shortcut ⌃⌥K tools registered`,
  `shortcut ⌃⌥R read aloud registered`, `shortcut ⌃⌥C chat registered`),
  then `shortcut pressed: sheet up` when it is pressed, and quits; nothing in 30 s is exit 2.
- `--shot-check` prints whether this build has Screen Recording and whether each monitor's capture
  shows the screen (`shot Built-in Retina Display: 3024×1964 px at 2×, 412 colours in a sample`); exit 1 if
  not. Like `--paste-check`, from a terminal it borrows the terminal's permission.
- `--shot-demo [--snapshot out.png]` takes a toolbar shot of the real screens (a rectangle, box, arrow,
  blur, hand blur, an undo, a text typed and turned 30° with its last key and ⏎ pressed on the real keyboard, the real pointer
  resting on the blur button for its tag, ⌘C), checks the clipboard holds that PNG with the text's pixels inside its turned box
  and nowhere else, takes the last rectangle again, and
  puts the clipboard and settings back; each step with its time. Exit 1 if wrong.
- `--shot-film out.mp4` films the screenshot tool offscreen on two simulated monitors (2× and 1×), writing the
  toolbar beside the film as it stands (`…-toolbar.png`) and with a hover tag (`…-toolbar-tip.png`): a
  rectangle with marks and blurs and a text typed over the blur, given another font, made bigger and turned by
  its handle (stills `…-text-typed.png`, `…-text-font.png`, `…-text-size.png`, `…-text-turned.png`, `…-text-done.png`,
  and the font menu `…-toolbar-fonts.png`), a lasso, all monitors, the last rectangle again; writes each PNG beside
  the film and prints each step (`film 7.40 taken 800×520 px, 4 marks`).
- `--mic-check` prints whether this build may use the microphone and records 1.5 s (`mic heard 1.50 s, 24000 samples
  at 16000 Hz, loudest 0.41`); exit 1 if refused or silent. Like `--paste-check`, from a terminal it borrows the
  terminal's permission: `open build/Ledgelings.app --stderr /dev/stdout --args --mic-check` for the app's own.
- `--dictate-demo [--model id]` has the Mac say a test line into a file and sends its 16 kHz WAV through the real
  dictation call, with the creature on screen; checks the words land on the clipboard and in the history, prints each
  step with its time and price (`dictate 2.31  answered in 1.4 s: 412 tokens in, 21 out, <$0.001`), and puts the
  clipboard, history and settings back. Exit 1 if wrong. Needs the OpenRouter key (the keychain prompt on a new build).
- `--dictate-film out.mp4` films the dictation creature offscreen: the leap with the microphone, the bars following a
  voice, the clock, thinking, *Copied: …* and the hop home, then a round with no key; stills beside it
  (`…-listening.png`, `…-thinking.png`, `…-copied.png`).
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
