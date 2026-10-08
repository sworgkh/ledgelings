# Ledgelings for Windows

The same creatures, the same art, the same rules as the macOS app in the root of
this repo, running as a Windows tray app. Everything in [SPEC.md](../SPEC.md) applies;
this folder is its Windows implementation.

**Status:** feature parity with the macOS app v0.29, except what is listed under
*Not on Windows* below: eight creatures across every
monitor, day and night, meetings with stars and flowers (the wearer trails the
giver), talk from the built-in lines (the default: no model needed) or through
LM Studio or OpenRouter, lines they rarely repeat, room for a thinking model,
built-in lines when LM Studio is not running, model-only settings greyed out
without a model, bonds and their plots, the calendar (time of day, date,
holidays), paper planes, reminders delivered by plane with the paper note to
write them on, the chat log and spend ledger, hiding in the house, imported
creatures from the sprite kit, planting flowers where each character likes (the
Flowers tab), complaints when pushed around, tea parties, voices (Windows' own,
OpenRouter or a local speech server) and the Costs tab.

## Stack

- **C# on .NET 10**, Windows only. No Electron, no web view.
- **Overlays**: one raw Win32 *layered window* per monitor (`WS_EX_LAYERED |
  WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`), drawn by
  GDI+ into a per-pixel-alpha DIB and pushed to the compositor with
  `UpdateLayeredWindowIndirect`, one dirty rectangle at a time. Layered windows
  hit-test their own alpha, so a click on empty glass falls through by itself; the
  colony clears `WS_EX_TRANSPARENT` only while the cursor is on a creature you can
  act on (§10.4 of the spec).
- **Settings window**: WPF, one tab per area as on the Mac, plain bindings.
- **Tray icon and menu**: `Shell_NotifyIcon` + `TrackPopupMenu`, rebuilt each time it opens.
- **Secrets**: the OpenRouter key lives in the Windows Credential Manager as
  `Ledgelings/openRouterKey`, never in the settings file.
- **Tests**: xUnit. `win/LedgelingsCore.Tests` is the acceptance suite from SPEC.md
  §14, ported test for test from the Swift; `win/Ledgelings.Tests` covers the chat
  client, the model catalogue, settings, the atlas and the sprite library.

Why not WPF for the overlays too: a WPF window with `AllowsTransparency` is rendered
in software and re-uploaded whole every frame, which on a 4K monitor is the CPU cost
the macOS app was built to avoid. The hand-rolled layered window uploads only the
few hundred pixels that changed, and idles at about 1 % CPU with three creatures.

## Run it

```powershell
dotnet run --project win/Ledgelings          # from the repo root; quit from the tray menu
dotnet test win                              # every test, core and app
powershell -ExecutionPolicy Bypass -File win/publish.ps1              # win/build/Ledgelings.exe (needs the .NET 10 runtime)
powershell -ExecutionPolicy Bypass -File win/publish.ps1 -SingleFile  # one exe that needs nothing installed
```

Requires the .NET 10 SDK to build, Windows 10 or 11 to run. The sprite sheets are
not copied into this folder: the project links `Sources/Ledgelings/Resources/sprites`
and copies them next to the exe at build time, so there is one set of art for both platforms.

Everything is under the tray icon, the creature itself: the day/night line,
**Creature Actions…** (a pixel-paper sheet with a picture tile and a letter key for
jump, talk, tea, plane, reminder, hide, sleep/wake and clear flowers), the next
reminder, **Hear Them Talk**, the last talk status, **Chat History…**, the spend
line, **Settings…**, **Quit**. Left- or right-click the icon. Ctrl+Alt+R adds a
reminder from anywhere. When Windows has tucked the icon into the overflow, **Ctrl+Alt+L**
in any app brings Creature Actions… up (and puts it away), and so does starting
Ledgelings again; the sheet has the menu's switches, Settings and Quit.

## Where things live

| What | Where |
|---|---|
| Settings | `%APPDATA%\Ledgelings\settings.json` |
| Chats | `%APPDATA%\Ledgelings\chats\YYYY-MM-DD.jsonl` (same format as the Mac) |
| Spend | `%APPDATA%\Ledgelings\spend.jsonl` |
| Bonds and plots | `%APPDATA%\Ledgelings\bonds.json` (same format as the Mac) |
| Reminders | `%APPDATA%\Ledgelings\reminders.json` (same format as the Mac) |
| Kept OpenRouter voices | `%APPDATA%\Ledgelings\voices\` |
| Saved built-in line voices | `%APPDATA%\Ledgelings\line-voices\` |
| Imported creatures | `%APPDATA%\Ledgelings\sprites\<name>\` |
| OpenRouter key | Credential Manager › Windows Credentials › `Ledgelings/openRouterKey` |
| Start at login | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Ledgelings` (Task Manager › Startup apps) |

## How the spec maps onto Windows

| Need (SPEC.md §1.1) | Here |
|---|---|
| Transparent, always-on-top, click-through window per monitor | `OverlayWindow`: layered Win32 window, per-pixel alpha, topmost, non-activating |
| Toggle click-through per frame | `WS_EX_TRANSPARENT` set or cleared in `SetClickable` |
| Global cursor, no permission prompt | `GetCursorPos` |
| How long the user has been away (an open letter waits) | `GetLastInputInfo` |
| Add a Reminder… from anywhere | `RegisterHotKey` (Ctrl+Alt+R) on a hidden window of the UI thread |
| The shortcut from any app (§11) | `RegisterHotKey` again (`App.Shortcut`), re-registered as the setting changes; a failure is shown in Settings › Actions |
| Opening the app again shows the sheet (§11) | the second copy sets the named event `Ledgelings.ShowActions` and exits; the first waits on it |
| Shift and Control polled each frame | `GetAsyncKeyState` |
| Monitor geometry and change notice | `EnumDisplayMonitors` + `GetMonitorInfo`; `SystemEvents.DisplaySettingsChanged` |
| A 30 fps frame timer, 12 fps asleep | `FrameClock`: a high-resolution waitable timer on its own thread, ticking the UI thread |
| Tray icon with a menu | `TrayIcon` |
| Settings window | WPF `SettingsWindow` |
| Key-value settings store | `JsonSettingsStore` |
| Secret store | `CredentialStore` |
| HTTPS client | `HttpClient` |
| The computer's own voices | SAPI through `System.Speech`, rendered to a WAV |
| Playing a clip | WPF `MediaPlayer` from a temp file (`%TEMP%\ledgelings-*`, cleaned up) |
| Nearest-neighbour scaling, rotation, mirror, opacity | GDI+ `Graphics` with `InterpolationMode.NearestNeighbor`, a transform per sprite, `ColorMatrix` for opacity |

The simulation is the spec's coordinate space unchanged: global points, origin
bottom-left, **y up**. Windows counts y downwards, so `Desktop` flips once
(`yUp = -yDown`) for monitor rectangles and the cursor, and `ScreenOverlay` flips
back when it draws; rotations are mirrored there and nowhere else. That is why the
core tests are the Swift tests line for line.

## Differences from the Mac, on purpose

- **Languages** (SPEC §1.2). Tray › Language and the Creatures tab switch English and
  Русский live. The words are the Mac's: `Sources/LedgelingsCore/l10n/ru.json`, exported
  by the Mac's `SharedTextTests`, is embedded into LedgelingsCore and looked up by the
  same English (`L10n.Tr`). Only Windows-only wording lives in
  `LedgelingsCore/Russian/WindowsStrings*.cs`. Russian speech needs the Russian speech pack
  (Microsoft Irina Desktop); the voices Narrator uses are not open to System.Speech.

- **Pixels and dpi.** The app is per-monitor-DPI aware, so a "point" is a real
  pixel. To keep "3×" the size it is on a Mac, creature scale is multiplied by the
  primary monitor's scale factor snapped to a half step (1.5 at 150 %, 2 at 200 %);
  bubble text grows with each monitor's dpi. Everything else (flee radius, gaps,
  star sizes) is in pixels as the spec states them.
- **Start at login** uses the per-user Run key instead of a login item; any build
  can register, not only an installed one.
- **Open in Terminal** opens Windows Terminal if it is installed, else a command prompt.
- **Fullscreen apps.** A topmost window sits above borderless full-screen windows
  but not above an exclusive-fullscreen game; that is Windows, not a setting.
- **One instance.** A second launch shows a message and exits.
- Bubble text is Consolas Bold 12 pt; the Mac uses the system monospaced font.
- **Marks in a line.** A bubble shows the plain text of `*sighs*` and `**bold**`
  (SPEC §6.3.1): GDI+ draws one face per call.
- **Settings layout.** Each tab is one scrolling column; the Mac lays a tab out
  in two columns on one screen.
- **The OpenRouter key** is read at launch: the Credential Manager never prompts,
  so there is nothing to save the user from by reading it late.
- **Steppers are sliders** (lines not repeated, story length, holiday look-ahead);
  same ranges and steps.
- **Reveal in Finder** is **Show in Explorer**; the Reminders tab's file box has one too.
- **Add a Reminder…** is **Ctrl+Alt+R**, system-wide (`RegisterHotKey`). The Mac's
  ⌘R would be Ctrl+R here, which every browser uses to reload. If another app holds
  Ctrl+Alt+R, the shortcut quietly does nothing and the menu stops showing it.
- **The shortcut from any app** is **Ctrl+Alt+L** and written the Windows way; the Mac's
  Command is the Windows key, Option is Alt. Windows refuses keys any other app holds, so
  the red line in Settings › Actions is reliable here (macOS cannot tell). The tray menu
  shows the shortcut beside Creature Actions… only while it is registered. On the sheet,
  Settings is Ctrl+, and Quit is Ctrl+Q. Switching the language on the sheet rebuilds it.
- **The paper note** opens centred on the whole monitor under the cursor (the Mac
  uses the screen's area below the menu bar). Its **When** is a date picker and a
  24-hour time field. The letter's writing is Consolas Bold at the Mac's sizes.
- **The calendar** uses .NET's `HebrewCalendar` (renumbered so the months count
  the Mac's way) and `UmAlQuraCalendar`, whose tables end in 2077: after that no
  Muslim holidays are mentioned. The footers say "your PC's clock".

- **Voices.** Windows' own voices are SAPI's (`System.Speech`): only the voices
  Windows offers desktop programs are listed, so the newer "natural" voices may
  be missing. Windows has no novelty voices (the Mac's Grandpa, Zarvox…), so
  *Cartoon voices* only lifts the pitch. A SAPI line is rendered to a WAV first,
  so its bubble types out evenly over the clip rather than word by word. SAPI's
  rate is `10·log₃(speed)`; with *speed follows pitch* off, pitch is asked of SAPI
  as an SSML percentage, which not every voice honours. A WAV is lifted like a
  tape by resampling (`WaveTape`); an MP3 (MiniMax only) plays at
  `SpeedRatio = pitch`, which keeps its pace but probably not the lift.
- **Every paid voice line is priced**, played or not: it goes into the spend file
  the moment its audio comes back (AGENTS.md rule 1). The Mac records a line only
  when it plays. The Chats tab notes a line's cost only once it is played, as on
  the Mac.
- **Hear Them Talk** has no shortcut (⌘V on the Mac); a tray menu has no key
  equivalents.
- **Copy Setup Command** (local speech server) copies a PowerShell line that
  clones Kokoro-FastAPI and runs `start-cpu.ps1`.

## Not on Windows

- **The films and the promo video** (`--garden-film`, `--tea-film`, the reminder
  film, `scripts/make-promo.sh`): they render offscreen with the Mac's video APIs.
- **The command-line checks** (`--settings … --snapshot`, `--say`, `--cast`,
  `--converse`, `--tea`, `--plot`, `--remind`, `--note`). A Windows colony always
  opens real overlay windows, so the Mac's colony-level tests (`ColonyTalkTests`)
  are not ported either; the core tests are.

## Layout

```
win/
  LedgelingsCore/        pure logic, no Win32, one class per Swift file:
                           EdgeLoop, EdgeWorld, Creature, DayNight, Meetings, Gifts, Sparks, Script,
                           Hideout, Banter, ChatLog, Spend, SpriteText, LineMemory, Bonds, Almanac,
                           Voices, PaperPlanes, Letters, Reminders,
                           Garden, Complaints, TeaParty, Casting, VoiceArchive, SpeechReveal (+ Geometry: Pt, Vec, Rect)
  Ledgelings/            the app:
                           Colony (+ .Frame .Render .Hand .Meetings .Talk .Converse .Script .Hideout
                                     .Bonds .Planes .Reminders .Garden .Complaints .TeaParty .Voice)
                           OverlayWindow, ScreenOverlay (+ .Draw .Bubble .Mail .Garden .Tea), FrameClock, Desktop
                           TrayIcon, App (+ .Reminders, .Shortcut), GlobalHotkey, ShortcutKeys, Program
                           AppSettings (+ .Talk .Bonds .Calendar .Planes .Reminders .Flowers .Patience .TeaParties .Voice),
                           SettingsStore, LaunchAtLogin
                           ChatClient (+ .Network), ModelCatalog, ChatHistory, SpendLedger, BondBook, ReminderBook
                           Voice (+ .Casting .System .Playback), SpeechClient, WaveTape
                           SpriteAtlas, SpriteLibrary (+ .Kit), PngIO
                           Native/Win32, Native/CredentialStore
                           UI/SettingsWindow.xaml (+ .Sprites .Talk .Script .Cast .Chats .Bonds .Calendar .Model .Reminders .Flowers .Voice .Costs),
                           ReminderNote, ActionsSheet, ColourDialog
  LedgelingsCore.Tests/  the §14 acceptance tests
  Ledgelings.Tests/      app-side tests
  publish.ps1            a release build under win/build
```
