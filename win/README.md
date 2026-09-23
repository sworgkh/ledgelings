# Ledgelings for Windows

The same creatures, the same art, the same rules as the macOS app in the root of
this repo, running as a Windows tray app. Everything in [SPEC.md](../SPEC.md) applies;
this folder is its Windows implementation.

**Status:** v0.15 feature parity with the macOS app: eight creatures across every
monitor, day and night, meetings with stars and flowers (the wearer trails the
giver), talk from the built-in lines (the default: no model needed) or through
LM Studio or OpenRouter, the chat log and spend ledger, hiding in the house,
imported creatures from the sprite kit, the settings window with its four tabs.

## Stack

- **C# on .NET 10**, Windows only. No Electron, no web view.
- **Overlays**: one raw Win32 *layered window* per monitor (`WS_EX_LAYERED |
  WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`), drawn by
  GDI+ into a per-pixel-alpha DIB and pushed to the compositor with
  `UpdateLayeredWindowIndirect`, one dirty rectangle at a time. Layered windows
  hit-test their own alpha, so a click on empty glass falls through by itself; the
  colony clears `WS_EX_TRANSPARENT` only while the cursor is on a creature you can
  act on (§10.4 of the spec).
- **Settings window**: WPF, four tabs, plain bindings.
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
**Put Them to Sleep Now / Wake Them Up Now**, **Make Them Jump**, **Hide Them for a
While…**, **Make Someone Talk**, the last talk status, **Chat History…**, the spend
line, **Settings…**, **Quit**. Left- or right-click the icon.

## Where things live

| What | Where |
|---|---|
| Settings | `%APPDATA%\Ledgelings\settings.json` |
| Chats | `%APPDATA%\Ledgelings\chats\YYYY-MM-DD.jsonl` (same format as the Mac) |
| Spend | `%APPDATA%\Ledgelings\spend.jsonl` |
| Imported creatures | `%APPDATA%\Ledgelings\sprites\<name>\` |
| OpenRouter key | Credential Manager › Windows Credentials › `Ledgelings/openRouterKey` |
| Start at login | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Ledgelings` (Task Manager › Startup apps) |

## How the spec maps onto Windows

| Need (SPEC.md §1.1) | Here |
|---|---|
| Transparent, always-on-top, click-through window per monitor | `OverlayWindow`: layered Win32 window, per-pixel alpha, topmost, non-activating |
| Toggle click-through per frame | `WS_EX_TRANSPARENT` set or cleared in `SetClickable` |
| Global cursor, no permission prompt | `GetCursorPos` |
| Shift and Control polled each frame | `GetAsyncKeyState` |
| Monitor geometry and change notice | `EnumDisplayMonitors` + `GetMonitorInfo`; `SystemEvents.DisplaySettingsChanged` |
| A 30 fps frame timer, 12 fps asleep | `FrameClock`: a high-resolution waitable timer on its own thread, ticking the UI thread |
| Tray icon with a menu | `TrayIcon` |
| Settings window | WPF `SettingsWindow` |
| Key-value settings store | `JsonSettingsStore` |
| Secret store | `CredentialStore` |
| HTTPS client | `HttpClient` |
| Nearest-neighbour scaling, rotation, mirror, opacity | GDI+ `Graphics` with `InterpolationMode.NearestNeighbor`, a transform per sprite, `ColorMatrix` for opacity |

The simulation is the spec's coordinate space unchanged: global points, origin
bottom-left, **y up**. Windows counts y downwards, so `Desktop` flips once
(`yUp = -yDown`) for monitor rectangles and the cursor, and `ScreenOverlay` flips
back when it draws; rotations are mirrored there and nowhere else. That is why the
core tests are the Swift tests line for line.

## Differences from the Mac, on purpose

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
- **No promo video.** The Mac can render its own promo (`scripts/make-promo.sh`);
  Windows cannot.

## Layout

```
win/
  LedgelingsCore/        pure logic, no Win32, one class per Swift file:
                           EdgeLoop, EdgeWorld, Creature, DayNight, Meetings, Gifts, Sparks, Script,
                           Hideout, Banter, ChatLog, Spend, SpriteText (+ Geometry: Pt, Vec, Rect)
  Ledgelings/            the app:
                           Colony (+ .Frame .Render .Hand .Meetings .Talk .Converse .Script .Hideout)
                           OverlayWindow, ScreenOverlay (+ .Draw .Bubble), FrameClock, Desktop
                           TrayIcon, App, Program
                           AppSettings (+ .Talk), SettingsStore, LaunchAtLogin
                           ChatClient (+ .Network), ModelCatalog, ChatHistory, SpendLedger
                           SpriteAtlas, SpriteLibrary (+ .Kit), PngIO
                           Native/Win32, Native/CredentialStore
                           UI/SettingsWindow.xaml (+ .Sprites .Talk .Script .Cast .Chats), HideDialog, ColourDialog
  LedgelingsCore.Tests/  the §14 acceptance tests
  Ledgelings.Tests/      app-side tests
  publish.ps1            a release build under win/build
```
