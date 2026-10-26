# Ledgelings

Tiny pixel creatures crawl around the **edges of your screens**: along the borders,
over the corners, from one monitor onto the next. They sleep at night, bump into
each other and trade a line written by a language model, give each other flowers,
and go home to a little house when you ask them to.

Ambient, click-through, living in the menu bar or the tray. Not a game, not a widget.

**Two native apps, one spec, one set of art:**

| Platform | Stack | Where |
|---|---|---|
| macOS 26+ | Swift 6, AppKit overlays, SwiftUI settings | [Sources/](Sources), [Package.swift](Package.swift) |
| Windows 10/11 | C# / .NET 10, Win32 layered overlays, WPF settings | [win/](win), [win/README.md](win/README.md) |

Everything the app does is written down once, platform-neutrally, in
[SPEC.md](SPEC.md); both apps implement it and both run the same acceptance tests.

**Status:** v0.60 — eight creatures with their own personalities, on every monitor or on
the one you choose, talking when they meet (out loud, each in a voice of its own) from a
hundred built-in lines or through a model of your choice, in English or Russian. They do
what they talk about, remember each other, grow little stories from everything they have
lived through together, know your time of day and your holidays, give each other flowers
and plant them, send paper planes and throw your reminders at you, sit down to tea,
sleep in beds of their own, play tag, ninja rope, parachute, basketball, soccer and
baseball, and take the cursor as a friend or a nemesis, counting every hunt and riding
it in revenge. They bring you a clipboard manager, a screenshot tool and dictation, go
home when asked, and wear creatures you describe to any image model. Every chat is kept and every
model call priced.

**See it move:** the [promo video](https://github.com/sworgkh/ledgelings/releases/download/v0.18.0/Ledgelings-promo-motion.mp4) is a 78-second motion infographic of the features, with music, made from [promo-video/](promo-video). The older [50-second screen recording](https://github.com/sworgkh/ledgelings/releases/download/v0.14.0/Ledgelings-promo-0.14.0.mp4) (no sound) is rendered by the app itself, `scripts/make-promo.sh`.

**Download:** the newest macOS `.pkg` and `.dmg` are on the [latest release](https://github.com/sworgkh/ledgelings/releases/latest).

## Quick start

macOS, from a terminal (Xcode 26 / Swift 6 installed):

```bash
swift run Ledgelings
```

Windows, from a terminal (.NET 10 SDK installed):

```bash
dotnet run --project win/Ledgelings
```

Ctrl-C stops a terminal run; a built app quits from its menu. To install a proper
app instead of running from source, see [docs/INSTALL.md](docs/INSTALL.md).

## What it does

**They walk the edges.** Each creature crawls the outline of your desktop, turns
the corners, stops now and then, blinks. Monitors that touch are fused into one
outline, so a creature walks from one screen onto the next along a shared floor and
never along the seam between them. Rather they kept to one monitor? Pick it with
*SCREEN* in Creature Actions… (or Settings › Creatures › *Live on*): everyone on the
other screens hops off and parachutes onto it. Move the cursor near one and it jumps to another
edge, on any monitor. The overlay never takes a click that is not meant for a creature.

**Day and night.** One clock for the colony: three minutes of day, then five of
night, forever (both adjustable). At dusk everyone slumps and floats Zs; at dawn
they wake a few seconds apart.

**Your hand.** Hold Shift and nobody flees. Shift-click a creature and it says
something to whoever is nearest. Shift-drag any creature, or plain-drag a sleeper,
to carry it to another edge or monitor. Shift-right-click puts one down for a nap.
The full list is in [docs/SETTINGS.md](docs/SETTINGS.md#what-your-hand-can-do).

**They talk.** When two creatures walk into each other, a few pixel stars fly up,
both stop and face each other, one says a line and the other answers. Out of the
box the words come from a hundred built-in conversations, editable in Settings;
paste the **agent prompt** into any chat model to get more in the same format. Or
wire up a model of your choice: a small one running locally in
[LM Studio](https://lmstudio.ai), or anything on [OpenRouter](https://openrouter.ai).
Every third meeting of the same pair, one gives the other a flower to wear, and
the wearer follows the giver around for a while, walking past everyone without
bumping, then goes off to plant it in the edge wherever its character likes:
Blocky on the bottom edge, Pip on the ceiling, Ruth in a neat row beside the
others, Dot straight away, Zed once it gets dark.

**They go to bed.** Each one has a bed of its own: Blocky a crate of straw, Mittens a
cat basket, Hopper a lily pad, Unit 7 a charging dock, Puddle a teacup. At nightfall
it walks to its favourite place, puts the bed down and sleeps on it, and the more
nights it spends there the likelier it goes back. Drag a sleeper's bed somewhere else
and that is its place from now on.

**They play.** Now and then, and more often between old friends, they play Worms-style
games, with nobody hurt: two chase each other round the edges at catch me if you can,
one fires a ninja rope into the ceiling and swings across the screen, one jumps off
the ceiling and floats down under a little parachute, and one hangs a hoop on the wall
and shoots some baskets (friends take turns). A line from whoever starts it, in its
own voice, and a game two played goes into their story. Settings › Play; *Activities…*
in the menu to start one now.

**Ball games.** They pick the widest edge for a soccer pitch and play as teams, best
friends on one side: one alone juggles and shoots at the end of the edge, two go one on
one, three share one goal with a keeper who changes after every goal, six or more get a
keeper each. Baseball is played across the whole screen: home and the three bases on
window edges far apart, runners hopping edge to edge, fielders leaping for the catch,
and a ball out of the top of the screen is a home run with fireworks. Tackles take the
ball, never the player. Each celebrates and grumbles in its own voice, a pixel
scoreboard keeps count. Settings › Ball games; both are in *Activities…*.

**They do what they say, and remember.** A letter that asks "soccer?" gets a written yes
or no, and a yes walks them to the pitch: from talk and letters they can invite each other
to a game or tea, accept or decline, bring a flower, write back, visit, follow or go to
sleep. Games played go into each pair's record and the day they talk about ("lost 2–3
to Zed this morning"). Every pair keeps a small long-term memory (a few dated facts, a
line per day, their games), condensed at nightfall and sent to the model only in a
budgeted few lines, so it stays cheap. It can start from the last two weeks of their
chat log on your computer. Watch friendships form in the **Relationships** window; every
limit and budget is in Settings › Relationships, and *Deeds from Talk* in the menu turns
the doing off.

**Play with them.** *Creature Actions…* in the menu (or ⌃⌥L in any app on a Mac, Ctrl+Alt+L on Windows, or opening
the app again, for when the menu bar has no room for the icon) opens a sheet of the same pixel
paper as the letters, a creature peeking over the top: one picture for everything you
can ask of them (jump, talk, tea, a plane, a reminder, hide, sleep or wake, clear the
flowers), each with a letter key, and under them the menu's switches, Activities (the
games, each with Play now), Settings and Quit.

**Hear them.** Switch on *Hear Them Talk* in the menu and every bubble is read out
loud, each character in a voice of its own: the computer's own voices (free,
offline), or a speech model on OpenRouter (Kokoro by default, a fraction of a cent
per hundred lines), or a speech server on your computer. The built-in lines are voiced
once each and saved, so they play again instantly and for free. Voice, speed,
pitch and volume are in Settings › Voice.

**They get to know each other.** Creatures who share the screen for an hour (you
choose how long) get a small story from the model: a rivalry, a secret, a favour
owed. It colours their next few conversations and ends; the next grows from how
they get on and from **everything they have lived through together**: every talk,
tea party, flower, paper plane, game and cursor grab is kept, and folded with each new story
into a short chronicle of "their story so far", so a new story can bring back the
poppy Pip gave Blocky three weeks ago and never contradicts what came before. Only
the chronicle and the latest moments reach the prompt, so a long friendship costs
little more than a new one. With the built-in lines there is no model, and the stories
are made from those moments instead ("Since Pip gave Blocky the poppy yesterday…").
Settings › Bonds shows every pair, its story and its chronicle.

**They know what day it is.** Your clock, the date and the holidays you tick
(Jewish, Christian, Muslim) go into every line and paper plane: "late evening
(22:40)", "Today is day 1 of Sukkot", "Hanukkah is in 3 days". The dates come from
the Hebrew and Islamic calendars built into macOS and Windows, nothing is looked up
online. Each is a checkbox in Settings › Calendar.

**Paper planes.** Every few minutes (you choose how often) one folds a note into a
paper plane and throws it to another. Each plane flies in weather of its own,
swirling and looping across the screen with a dotted trail, mostly fast, banking
into its turns and rolling over when it comes round; the
catcher stops, reads the note out, thinks aloud about it, and throws one answer
back. Every character writes about what its soul keeps coming back to:
Blocky about the cursor, Zed about naps, Ruth about counting, Unit 7 in numbers.

**They have limits.** Chase one with the cursor or pick it up more than four times
in a row and it turns round and tells you off, in its own voice: Blocky keeps a list,
Zed just wants to sleep, Unit 7 reports its annoyance in percent. How patient they
are is in Settings › Creatures.

**The cursor can be a friend.** Out of the box the cursor is their nemesis. Set
*The cursor is* (Settings › Creatures, or the menu) to *A playmate* and every chase
becomes a game of tag they love winning, or to *Just there* and they hop aside
without a thought. Their lines, tea stories, letters, complaints and whatever a
model writes for them all follow it, in English and Russian.

**They keep count.** Every chase and pick-up is counted, per creature: today, this
week and in all, and they know it. Blocky keeps a list of grievances, Unit 7 a
status report, and a playmate brags about the score. The numbers turn up in what
they say (compared with yesterday and the week, with a record day), a round number
gets said out loud, and a much-chased creature keeps its distance. See the count,
and reset it, in Settings › Chases.

**They take revenge.** Chase one around too often (ten times in two minutes) and it
jumps on your cursor and rides along on it wherever you move, telling you every so
often exactly what it thinks of you. Wiggle the mouse back and forth to throw it
off; it tumbles down with a last word. Escape lets go, and *Cursor Revenge* in the
menu turns it off. In Settings › Chases you can make it hold the pointer still
instead (ten seconds at most), give it a time limit, and make the shake gentler or
harder.

**Reminders.** Tell them what to remind you of and when (once, every day, every
weekday, every week). When the time comes, one of them folds it into a paper plane
and throws it at you: it swirls to the middle of your screen, turns to face you,
rushes at you and unfolds into a letter with your reminder, a note in the thrower's
own voice and its signature. Click it to send it flying away. A letter that
arrives while you are away waits for you. *Add a Reminder* in Creature Actions… (⌘R
there, Ctrl+Alt+R anywhere on Windows) opens a paper note of the same pixel paper to
write it on, a creature peeking over the edge; the list is in Settings › Productivity
tools › Reminders.

**A clipboard manager.** Everything you copy is kept in a history, pictures too
(screenshots, *Copy Image*, Preview), each shown as a little pixel thumbnail; password
managers' secrets never are. Texts you paste often live as snippets, in folders. Press
**⌃⌥V** in any app for the history, **⌃⌥B** for the snippets: a creature leaps over with
a sheet of pixel paper, you type to search copies and snippets at once, ⏎ pastes into the
app you were in, and the sheet collapses into your text cursor. ⌘1–9, ⇥, ⌘P to pin: no
mouse needed. A **protected** snippet keeps its words in the Keychain and is pasted only
after **Touch ID**; a copy of those words in the history is shown only as
`PWD:{Name}: [N] chars` on a faint tint. Clipy's snippets import in one go. Nothing
copied ever leaves the computer. Settings › Productivity tools › Clipboard. On Windows
the same, with Ctrl+Alt+V / Ctrl+Alt+B, protected snippets in Credential Manager and no
fingerprint step.

Pasting for you means pressing ⌘V in the other app, which macOS allows only with
**Accessibility**: press *Allow…* in Productivity tools › Clipboard and switch on
Ledgelings in System Settings › Privacy & Security › Accessibility. Since v0.54 the
grant survives reinstalls. Until it is given the picker only copies, and says so.

**Screenshots** (macOS for now). **⌃⌥S** freezes every screen under a tiny pixel
toolbar: a rectangle, a freehand lasso, the screen under the cursor or all monitors as
one image; then boxes, arrows, a highlight, and a blur (pixel blocks, so the text cannot
be read back) by rectangle or by brush, in six colours. Every button is an icon that
names itself and its key on hover. ⏎ copies the PNG, ⌘S also saves it to
~/Desktop/Screenshots. **⌘⇧8** takes the full screen at once, **⌘⇧\\** the last
rectangle again; all shortcuts and the folder are in Settings › Productivity tools ›
Screenshots. A creature carries the shot home. It needs **Screen Recording**: *Allow…*
on that tab.

**Dictation.** **⌃⌥D** (Ctrl+Alt+D on Windows) starts listening from any app: a creature
leaps to the middle of the screen with a pixel microphone, its meter bars following your
voice and a clock counting. ⌃⌥D again or ⏎ stops, ⎋ throws it away; *Hold to talk* listens
only while the keys are down. An OpenRouter audio model (by default Gemini 2.5 Flash Lite,
about $0.0007 a minute) writes it down, leaving out the ums and false starts, and the text
lands on the clipboard and in its history, or is pasted straight into the app you were in.
The recording stays in memory and is never saved. Model, language, shortcut and longest
recording are in Settings › Productivity tools › Dictation, with *Allow…* for the
microphone.

**Eight creatures, and yours.** Blocky, a frog, a cat, a ghost, a slime, a robot, a
triangle and a mushroom come built in, each with its own cast of characters. The
**sprite kit** is a small form (what it is, a name, a colour, three characters; *Refine
with AI* fills it in with an OpenRouter key), a prompt built from it, and two pictures
to attach: Blocky's nine poses and an empty template. Paste them into an image model,
import the picture it paints at whatever size it comes, and the app turns it into a real
sprite sheet that blinks and takes your colours. See [docs/SPRITES.md](docs/SPRITES.md).

**Every word is accounted for.** Every conversation is kept (Settings › Chats), and
every call to a model is priced and labelled with the feature that made it (Settings ›
Costs: today, this month, all time).

**They have tea.** Now and then two who bump into each other put a little table out
between them and sit down to tea for a few minutes, taking turns to tell each other
stories from their lives, each in its own voice (Settings › Creatures › Tea parties,
or *Have a Tea Party* in the menu's Creature Actions…).

**In English or Russian.** Menu › Language switches the whole app at once: menus,
settings, and what the creatures say, write and ask a model for, each character in its
own voice in either language. Prompts you edited stay as you wrote them. More languages
can be added (CONTRIBUTING.md › Adding a language). The Windows app speaks the same Russian: the tray menu has the same switch.

**They can go home.** *Hide Them for a While* in Creature Actions… brings out a house in the
bottom-right corner of the main screen; everyone runs in, the house packs itself
away, and when the time is up it comes back and they walk out one by one.

## Documentation

| Read this | For |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | Installing on macOS and Windows, setting up LM Studio or OpenRouter, where the app keeps its files, uninstalling |
| [docs/SETTINGS.md](docs/SETTINGS.md) | Every setting, the menu, what your hand can do, the chat log and the spend ledger |
| [docs/SPRITES.md](docs/SPRITES.md) | The sprite kit for your own creatures, and `spritetool` for the built-in art |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Building, testing and changing either app; the rules that keep the two in step |
| [SPEC.md](SPEC.md) | The full specification: every number, formula and judgement call |
| [BRIEF.md](BRIEF.md) | The original project brief and how its plan turned out |
| [win/README.md](win/README.md) | How the Windows app is put together |

## Layout

```
Sources/LedgelingsCore/   macOS: pure logic, no AppKit (geometry, creature brain, clock, meetings, gifts, house, banter, logs, sprite text)
Sources/Ledgelings/       macOS: the app (colony, overlays, chat client, settings, sprite library, views)
Tests/                    macOS: unit tests for both
win/LedgelingsCore/       Windows: the same logic, class for class
win/Ledgelings/           Windows: the app
win/*.Tests/              Windows: the same tests
sprites/                  sprite recipes and the built-in creatures as text
spritetool/               the sprite sheet tool (Python: Pillow + PyYAML)
scripts/                  macOS packaging: make-app.sh, make-installer.sh
win/publish.ps1           Windows packaging
docs/                     the guides listed above
```

Not yet: sheets with a different cell size.

## Licence

MIT, see [LICENSE](LICENSE).
