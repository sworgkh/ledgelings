# The shared look

Every screen of Ledgelings is one of two kinds, and each kind has one set of
rules. They live in code in `Sources/Ledgelings/Design.swift`; this page says what
each part is for.
A new screen uses these parts. It does not set its own font size, gap or button
look: if something is missing, it is added here and in `Design.swift` first.

| Kind | Screens | Drawn with |
|---|---|---|
| Ordinary window | Settings, Weather & Sky, Relationships, Snippets | the system's own controls, laid out by `Look` |
| Pixel paper | Creature Actions, the reminder note, the clipboard picker, Tools, Translate, Read aloud, Chat, the screenshot toolbar | Blocky's style, by `Pixel` |

## Spacing

One scale for both kinds: **4, 8, 12, 16, 24** points (`Look.Space.xs…xl`).
Every gap and margin is one of these. The paper's margins are fixed by the rim
and the folded corner: 27 left and right, 22 top, 18 bottom, and 48 kept clear
on the right of the bottom row for the corner (`Pixel.margin`, `Pixel.cornerRoom`).

## Ordinary windows

**The settings window** is 1360×880 (`Look.settingsSize`): the sidebar, 220 wide,
and two columns of about 570. With its title bar it fits under the menu bar of
a 1470×956 screen, the smallest a current Mac laptop shows by default (13-inch
MacBook Air).

- **A page never scrolls, nor does the sidebar.** `--layout-check` opens every page
  and fails if a column runs past the window; run it in English and Russian. Only
  the columns that are lists growing with use scroll (Bonds' pairs, Costs, Chats).
- **A page that outgrows the window is split**, by a new page in the sidebar, as
  Voice was into *Voice* and *Character voices*. A list inside a section (the
  model search, the script) has a fixed height and scrolls in its own frame.
- **A section** is a heading (`SettingsHeader("…")`, so the search can land on it),
  its rows, and a footer in plain words saying what the settings do.
- **A row** is a label on the left and its control on the right: a switch, a
  slider with its value (`SliderRow`, the value never wraps), a picker, a stepper.
- **Buttons under a section's rows** go in a `ButtonRow`: the actions on the left,
  a reset or clear pushed to the right. A button's words stay on one line
  (`settingsButton()`); when they do not fit, the words are shortened, in every
  language, or the row becomes two rows. Never a truncated "Сохранить…" with dots.
- **A button inside a list row** (Forget, Reset, Send Now, Delete) is
  `rowAction()`: small and bordered, the same on every page. Not a blue link.
- **An empty list** says so in its place (`EmptyNote`).
- Fonts are the system's: the section heading, the row's body text, the footer's
  small grey text. Nothing sets its own size except `.caption` for a row's second
  line.

## Pixel paper

Drawn in Blocky's rules (AGENTS.md §3): square pixels three points wide
(`Pixel.px`), flat fill, a 1-pixel dark rim, a light line top-left and a shade
line bottom-right, stepped corners, never round.

**Fonts**, all monospaced and heavy, as the creatures' lines (`Pixel.Font`):

| Part | Size | Used for |
|---|---|---|
| `title` | 11 bold | the sheet's name, top left, in capitals: CLIPBOARD |
| `label` | 11 heavy | a label beside controls, a group's heading in a list: TO:, RECENT |
| `body` | 12 semibold | what is read: a row, a line, a message |
| `field` | 18 heavy | the big search field at the top of a picker |
| `button` / `smallButton` | 13 / 11 heavy | words on buttons |
| `hint` | 10 heavy | the keys line, a row's detail, a hover tag |

Nothing on the paper is smaller than `hint`, and nothing is shrunk to fit
(`minimumScaleFactor` is not used): a keys line that is too long wraps to a second
line (`PaperHints`) or loses its least useful keys.

**Boxes** (`PixelBox`): *raised* for a button or a card, *pressed* while held,
*chosen* (Blocky's orange) for the choice made and the button that does the main
thing, *well* for a field or a list, lit the other way so it reads as pressed in.

**Buttons** (`PixelButtonStyle`): words at 38 high, small words at 30, a square
picture at 34 (AGENTS.md §4: an action is a picture of what it does or its words,
never a bare letter). Words stay on one line; a label that does not fit is reworded.
A picture button names its action and key in a `PixelTag` on hover.

**A sheet** is: `PaperTitle` (its name, and on the right a count or the close
button), its content, then `PaperHints`, the keys, at the bottom. A list on paper
sits in a well; its rows keep their trailing pictures in fixed slots so they line
up, and a chosen row's orange box stays inside the well. An empty list says what
to do (`PaperEmpty`).

## Window sizes

| Window | Size (points) |
|---|---|
| Settings, Weather & Sky | 1360×880 (Weather & Sky in three columns) |
| Relationships | 980×640 |
| Snippets | 860×540 |
| Creature Actions, the reminder note | 564 wide |
| Clipboard picker | 600×484 |
| Translate, Read aloud, Chat | 760×470 |
| Tools | as many 124×128 tiles as there are tools, four to a row |

## Checking

- `--layout-check` (English and Russian): no settings page or the sidebar scrolls.
- `LEDGELINGS_APPEARANCE=light|dark` puts every window in that mode for a snapshot;
  `LEDGELINGS_NO_KEYCHAIN=1` keeps a new build from asking for the keychain.
- The tests measure every pixel button's words in their font against the room they
  have, in English and Russian (`DesignTests`).
