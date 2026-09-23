# Installing Ledgelings

Two apps, one for each platform. Pick yours; the [brain setup](#a-brain-for-the-talking)
at the end applies to both.

## macOS

**Requirements:** macOS 26 or later on Apple Silicon, and, to build, Xcode 26 (Swift 6).

### Download

Every version is on the [releases page](https://github.com/sworgkh/ledgelings/releases):
`Ledgelings-<version>.pkg` (double-click installer, puts the app in Applications),
`Ledgelings-<version>.dmg` (drag the app onto Applications) and a `SHA256SUMS` file.
The app is not notarised, so the first time you open it right-click it (or the
`.pkg`) and choose **Open**. Or build it yourself:

### Run from source

```bash
git clone https://github.com/sworgkh/ledgelings.git
cd ledgelings
swift run Ledgelings
```

A filled square appears in the menu bar. Ctrl-C in the terminal stops it. Settings
saved this way are the same ones the installed app reads.

### Build a real app

```bash
scripts/make-app.sh
open build/Ledgelings.app
```

`make-app.sh` builds a release binary, wraps it as a menu-bar-only `.app` with the
creature as its icon (drawn from the sprite atlas by `spritetool`, which needs
Python 3 with `pip install -r spritetool/requirements.txt`), and ad-hoc signs it.
Drag `build/Ledgelings.app` to `/Applications` if you want to keep it.

### Build an installer

```bash
scripts/make-installer.sh                    # version 0.16.0
VERSION=0.13.0 scripts/make-installer.sh     # any version you like
```

| File | What it is |
|---|---|
| `build/Ledgelings-<version>.pkg` | Double-click installer. Puts `Ledgelings.app` in `/Applications` |
| `build/Ledgelings-<version>.dmg` | Disk image. Open it and drag the app onto Applications |

The app is ad-hoc signed, not notarised. On the Mac that built it, it just opens.
On another Mac, Gatekeeper objects the first time: right-click the app or the
`.pkg` and choose **Open**.

### Start at login

Settings › Creatures › **Start Ledgelings when you log in**. This uses the system's
Login Items list (System Settings › General › Login Items), so only an installed
`.app` can register; a `swift run` binary reports "not available here".

### Where it keeps things

| What | Where |
|---|---|
| Settings | `~/Library/Preferences/com.alterman.ledgelings.plist` (UserDefaults) |
| OpenRouter key | your login keychain, service `Ledgelings`, account `openRouterKey` |
| Chats | `~/Library/Application Support/Ledgelings/chats/YYYY-MM-DD.jsonl` |
| Spend | `~/Library/Application Support/Ledgelings/spend.jsonl` |
| Imported creatures | `~/Library/Application Support/Ledgelings/sprites/<name>/` |

### Uninstall

Quit from the menu, delete `Ledgelings.app` from `/Applications`, and if you want
a clean slate delete the folder under Application Support, the preferences file and
the keychain item above.

## Windows

**Requirements:** Windows 10 or 11, 64-bit. To build: the
[.NET 10 SDK](https://dotnet.microsoft.com/download). To run a published build:
the .NET 10 Desktop Runtime, or nothing at all if you publish the single-file build.

### Run from source

```powershell
git clone https://github.com/sworgkh/ledgelings.git
cd ledgelings
dotnet run --project win/Ledgelings
```

The creature appears in the notification area (the tray, bottom right; it may be
under the `^` overflow). Left- or right-click it for the menu; **Quit Ledgelings**
stops it. Ctrl-C in the terminal works too.

### Build an app you can keep

```powershell
powershell -ExecutionPolicy Bypass -File win/publish.ps1
```

This puts a release `Ledgelings.exe` and its files under `win/build`. It needs the
.NET 10 Desktop Runtime on the machine that runs it. For one file that needs nothing
installed:

```powershell
powershell -ExecutionPolicy Bypass -File win/publish.ps1 -SingleFile
```

Copy the `build` folder (or the single exe) wherever you like, for example
`%LOCALAPPDATA%\Programs\Ledgelings`, and make a shortcut. The exe carries the
creature as its icon. It is not code-signed: SmartScreen may ask once on a machine
that has not seen it; choose **More info › Run anyway**.

A second launch while one is running shows a message and exits; there is only ever
one colony.

### Start at login

Settings › Creatures › **Start Ledgelings when you log in**. This writes the exe's
path to the per-user Run key, which is the list Task Manager shows under
**Startup apps**, so any build can register, not only an installed one. If you move
the exe, untick and tick it again.

### Where it keeps things

| What | Where |
|---|---|
| Settings | `%APPDATA%\Ledgelings\settings.json` |
| OpenRouter key | Credential Manager › Windows Credentials › `Ledgelings/openRouterKey` |
| Chats | `%APPDATA%\Ledgelings\chats\YYYY-MM-DD.jsonl` |
| Spend | `%APPDATA%\Ledgelings\spend.jsonl` |
| Imported creatures | `%APPDATA%\Ledgelings\sprites\<name>\` |

The chat and spend files are the same format on both platforms, so a folder copied
from a Mac reads on Windows and back.

### Uninstall

Quit from the tray menu, untick *Start at login* first if it was on (or delete the
`Ledgelings` value under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`),
delete the exe folder, and for a clean slate delete `%APPDATA%\Ledgelings` and the
Credential Manager entry.

### Good to know

- The app is per-monitor-DPI aware. Creature sizes scale with the primary monitor's
  scale factor (in half steps), so "3×" is about the size it is on a Mac.
- A topmost window sits above borderless full-screen apps, but an exclusive
  fullscreen game covers it; that is Windows, not a setting.
- Idle cost is about 1 % CPU with three creatures, and less when they all sleep.

## A brain for the talking

Out of the box the creatures talk from a hundred **built-in lines** and need
nothing set up; Settings › Talk shows and edits them. Pick a model instead when
you want them to improvise. With a model chosen but not reachable they walk,
sleep, meet and give flowers in silence, and the menu's status line says why.

### LM Studio (local, free, private)

Install [LM Studio](https://lmstudio.ai), then get the default model and start its
local server:

```bash
lms get google/gemma-3-1b --mlx     # macOS (Apple Silicon)
lms get google/gemma-3-1b           # Windows
lms server start
```

Or do the same from LM Studio's window: download `google/gemma-3-1b` and turn on the
server in the Developer tab. Settings › Talk › **Check** tells you whether the app
can see the server and whether the model is installed; the **Installed** list next
to the model field lets you pick any model the server has. Any model works; the
1B Gemma is the smallest that writes a decent line.

### OpenRouter (any model, a few cents a day)

1. Make a key at [openrouter.ai/keys](https://openrouter.ai/keys). Give it a
   spending limit; it is cheap, but a limit is free.
2. Settings › Talk › Brain › **OpenRouter**, paste the key. It goes to your keychain
   or Credential Manager, never to a settings file.
3. Pick a model. The default is `anthropic/claude-haiku-4.5`. The catalogue below
   the field is fetched live and sorted cheapest first: search "flash lite",
   "gemma", "free" and click a row. For one-line banter,
   `google/gemini-2.5-flash-lite` costs about a tenth of Haiku and is quicker.
4. **Check** confirms the key, shows what it has spent, and confirms the model exists.

One meeting is two calls of about 300 tokens in and 80 out. Settings › Talk › Spend
and the menu show what it has cost so far.
