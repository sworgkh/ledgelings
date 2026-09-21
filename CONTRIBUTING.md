# Contributing

Ledgelings is two native apps that must stay the same app. This page is how to
build and test each, and the few rules that keep them in step.

## The one rule

**[SPEC.md](SPEC.md) is the product.** Every number, formula and judgement call
lives there, platform-neutrally. A behaviour change is a spec change first, then
the same change in both apps, then the same test in both test suites. If you only
have one platform, that is fine: make the spec change, change the app you can
build, port the test to both suites where you can (the core tests need no window on
either side), and say in the pull request what is left for the other platform.

A bug fix that makes one app agree with the spec needs no spec change; say which
section it restores.

## Building and testing

### macOS

Requires Xcode 26 (Swift 6). No Xcode project; Swift Package Manager does it all.

```bash
swift build
swift run Ledgelings                       # Ctrl-C to stop
swift test                                 # geometry, brain, recolouring, prompts, settings
LEDGELINGS_LIVE=1 swift test --filter ChatClientLiveTests            # a real line through LM Studio
OPENROUTER_API_KEY=sk-or-… swift test --filter ChatClientLiveTests   # and through OpenRouter
scripts/make-app.sh                        # build/Ledgelings.app
scripts/make-installer.sh                  # .pkg and .dmg
```

Inside a [dev3](https://dev3.h0x91b.com) task, `.dev3/config.json` makes
`dev3 dev-server start` run `swift run Ledgelings` from the task's worktree, so a
dev build walks beside the installed one.

### Windows

Requires the .NET 10 SDK. The solution is `win/Ledgelings.slnx`.

```powershell
dotnet build win
dotnet run --project win/Ledgelings        # quit from the tray menu, or Ctrl-C
dotnet test win                            # both suites
dotnet test win/LedgelingsCore.Tests       # only the spec's acceptance tests
powershell -ExecutionPolicy Bypass -File win/publish.ps1
```

A running `Ledgelings.exe` locks its `bin` folder; quit it before a Debug rebuild,
or build with `-c Release`. The Windows app links the sprite sheets from
`Sources/Ledgelings/Resources/sprites` at build time; do not copy them into `win/`.

### The sprite tool

Python 3 with `pip install -r spritetool/requirements.txt`; `python -m pytest
spritetool -q`. See [docs/SPRITES.md](docs/SPRITES.md).

## Where things go

Both apps have the same two halves, file for file:

| | macOS | Windows |
|---|---|---|
| Pure logic, no window, everything worth a unit test | `Sources/LedgelingsCore` | `win/LedgelingsCore` |
| The app: overlays, tray, settings, chat client, sprite library | `Sources/Ledgelings` | `win/Ledgelings` |
| Tests | `Tests/LedgelingsCoreTests`, `Tests/LedgelingsTests` | `win/LedgelingsCore.Tests`, `win/Ledgelings.Tests` |

Keep the core pure: no AppKit, no Win32, no files it was not handed a path to. A
creature is a value updated by `update(dt, cursor, isNight, rng)`; the colony feeds
it and reads back what to draw. If a feature needs the screen, it belongs in the
app half, behind a snapshot the core does not know about.

The core is written in **y-up global points** (AppKit's space) on both platforms.
The Windows app flips once at the window boundary (`Desktop`, `ScreenOverlay`) and
nowhere else; that is what lets the core tests be the same tests. Do not "fix" a
sign in the core to suit one platform.

## Porting a change to the other app

The two code bases mirror each other by name: `Colony+Talk.swift` is
`Colony.Talk.cs`, `EdgeWorld.swift` is `EdgeWorld.cs`, and so on. When you change
one, open the twin. The mapping of platform APIs (windows, cursor, timers, secrets)
is the table in [SPEC.md §1.1](SPEC.md) and, for Windows, [win/README.md](win/README.md).

Tests are ported test for test, with the same names, numbers and tolerances, so a
failing test fails the same way on both sides. Swift's seeded RNG and C#'s
`new Random(seed)` differ, so a probabilistic test may need a different seed on one
side; keep the assertion's meaning.

## Style

- Comments explain *why* and read as prose, not as restated code. A file starts with
  a paragraph on what it is for.
- Names say what a thing is in the product's own words: `walkOn`, `Hideout`,
  `bumped`, `letGo`. The two apps use the same names, cased for their language.
- No new dependencies in the apps. The Mac app is AppKit and SwiftUI; the Windows
  app is the .NET desktop framework and Win32. No Electron, no web view, no
  third-party UI kit.
- Keep the idle cost low: the overlays must draw only what changed and drop to
  12 fps when everyone sleeps. Measure before and after anything in the frame loop.
- Sprites are pixel art: nearest-neighbour scaling, 1-bit alpha, the four-colour
  palette so recolouring works.

## Adding a creature

Write it in the text format (see [docs/SPRITES.md](docs/SPRITES.md)) into
`sprites/text/<name>.txt` with a `kind`, a `colour` if it should always wear one,
and three `character` lines; add the name to `SpriteLibrary.builtIn` in both apps
and to the sheet list in the spec; rebuild the sheet with
`LEDGELINGS_BUILD_CREATURES=1 swift test --filter ShippedCreaturesTests` (the test
without the variable, on both platforms, then guards that the sheet matches the
text). The sheet must stand on the floor, face right, and stay inside the body box.

## Pull requests

- One change per pull request, with a title that says what changed in plain words
  ("Count what the talking costs", "Six more creatures, and a sheet may own its
  colour"), and a description that says why and what was tested where.
- Run the tests of every side you changed. Say plainly if a side is untested.
- Update the docs that describe what you changed: `docs/SETTINGS.md` for anything a
  user sees, `SPEC.md` for any behaviour, the READMEs for anything about building.
- Do not commit build output (`build/`, `.build/`, `win/**/bin`, `win/**/obj`),
  secrets, or the `work/` folders the sprite tool writes.

## Reporting a bug

Open an issue with the platform and version, what you did, what happened, what you
expected, and, for anything about talking, the menu's status line and the last
lines of the day's chat file. For a crash on macOS include the report from
Console; on Windows the message shown, or the Windows Event Viewer entry under
Application for `Ledgelings.exe`.
