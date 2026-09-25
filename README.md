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

**Status:** v0.16 — eight creatures with their own personalities, on every monitor,
talking when they meet from a hundred built-in lines or through a model of your
choice, giving flowers, sending paper planes when it gets too quiet, keeping every
chat and what it cost, going home when asked, and wearing creatures you describe to
any chat model.

**See it move:** the [promo video](https://github.com/sworgkh/ledgelings/releases/download/v0.14.0/Ledgelings-promo-0.14.0.mp4) (50 s, no sound) shows every feature on a clean desktop. It is rendered by the app itself, `scripts/make-promo.sh`.

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
never along the seam between them. Move the cursor near one and it jumps to another
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
the wearer follows the giver around until it wilts.

**Paper planes.** When nobody has bumped into anybody for a while, one folds a
note into a paper plane and throws it to another. The wind swings it across the
screen, a dotted trail behind it; the catcher stops, reads the note out, and thinks
aloud about it. Every character writes about what its soul keeps coming back to:
Blocky about the cursor, Zed about naps, Ruth about counting, Unit 7 in numbers.
macOS only for now.
Every conversation is kept, and every call to the model is priced.

**Eight creatures, and yours.** Blocky, a frog, a cat, a ghost, a slime, a robot, a
triangle and a mushroom come built in, each with its own cast of characters. The
**sprite kit** is a prompt you paste into any chat model with a description of the
creature you want; the model answers in a letter format the app imports as a real
sprite sheet that blinks and takes your colours. See [docs/SPRITES.md](docs/SPRITES.md).

**They can go home.** *Hide Them for a While…* in the menu brings out a house in the
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
