"""play — the props the creatures play with: a basketball, the hoop it is
thrown at, a parachute, a grappling hook and the links of its rope, and a
drop of sweat for whoever is out of breath after a game of tag.

Each prop is a glyph of material letters; the painter shades every patch of
one material the way the creature's body is shaded (a light line along the
top and left, a shade line along the bottom and right) and puts a 1px outline
round the whole glyph in a dark tint of the colour next to it. Strings and
the net are single pixels with no outline, as a string is. No curves: the
ball and the canopy are stepped.

Every prop is drawn in one 32x28 cell. Where it sits in the cell matters to
the app, which keeps the numbers below in step (`Plays.Props`):
- the hoop hangs on a wall to its RIGHT: its board's outline is the cell's
  last column, its rim runs along `RIM_ROW` from `RIM_FROM` to `RIM_TO`;
- the parachute's strings end on the cell's bottom row, in the middle, where
  the creature's head is;
- everything else is centred.
"""

from __future__ import annotations

from PIL import Image

from ..recipe import Recipe
from .house import mix

CELL_W, CELL_H = 32, 28

ORANGE = (226, 118, 46)
WHITE = (244, 241, 230)
RED = (214, 72, 62)
GREY = (150, 150, 162)
ROPE = (190, 140, 80)
BLUE = (110, 180, 240)
STRING = (92, 86, 120)
NET = (200, 200, 212)

MATERIALS = {"o": ORANGE, "w": WHITE, "r": RED, "g": GREY, "n": ROPE, "b": BLUE}
# Lines with no outline round them, drawn after the shading.
THREADS = {"k": STRING, "z": NET}
# A seam on the ball: the ball's own outline colour, inside it.
SEAM = "x"


def outline(colour):
    return mix(colour, (0, 0, 0), 0.76)


def light(colour):
    return mix(colour, (255, 255, 255), 0.36)


def shade(colour):
    return mix(colour, (0, 0, 0), 0.17)


BALL = [
    "...oooo...",
    ".oooooooo.",
    ".oooooooo.",
    "oooooooooo",
    "oooooooooo",
    "oooooooooo",
    "oooooooooo",
    ".oooooooo.",
    ".oooooooo.",
    "...oooo...",
]

# The hoop from the side: a thin white board against the wall on the right, a
# grey bracket, the red rim sticking out to the left, the net hanging under it.
HOOP_W, HOOP_H = 24, 24
RIM_GLYPH_ROW = 12           # the rim's top row, in the glyph
RIM_GLYPH_FROM, RIM_GLYPH_TO = 1, 18   # the rim's first and last column, in the glyph: nearly twice the ball


def hoop(swish: bool) -> list[str]:
    rows = [["."] * HOOP_W for _ in range(HOOP_H)]
    for y in range(0, 19):
        for x in range(21, 24):
            rows[y][x] = "w"
    for y in range(11, 15):
        for x in range(19, 21):
            rows[y][x] = "g"
    for y in (RIM_GLYPH_ROW, RIM_GLYPH_ROW + 1):
        for x in range(RIM_GLYPH_FROM, RIM_GLYPH_TO + 1):
            rows[y][x] = "r"
    # The net: a lattice of threads narrowing under the rim, one step in every
    # second row; it swings a pixel to the side while the ball drops through.
    top = RIM_GLYPH_ROW + 2
    for k in range(7):
        y = top + k
        inset = 1 + k // 2
        left, right = RIM_GLYPH_FROM + inset, RIM_GLYPH_TO - inset
        shift = (1 if k >= 2 else 0) if swish else 0
        for x in range(left, right + 1):
            if (x + k) % 2 == 0 or x in (left, right):
                rows[y][min(x + shift, HOOP_W - 1)] = "z"
    return ["".join(r) for r in rows]


# The parachute: a stepped dome of red and white panels, four strings down to
# the middle of the bottom row.
CHUTE_W, CHUTE_H = 26, 20
CHUTE_DOME = [
    "........oooooooooo........",
    ".....oooooooooooooooo.....",
    "...oooooooooooooooooooo...",
    "..oooooooooooooooooooooo..",
    ".oooooooooooooooooooooooo.",
    "oooooooooooooooooooooooooo",
    "oooooooooooooooooooooooooo",
]


def chute() -> list[str]:
    rows = [["."] * CHUTE_W for _ in range(CHUTE_H)]
    for y, row in enumerate(CHUTE_DOME):
        for x, c in enumerate(row):
            if c != ".":
                # Panels: red, white, red, white, red, about five wide.
                rows[y][x] = "r" if (x * 5 // CHUTE_W) % 2 == 0 else "w"
    bottom = CHUTE_H - 1
    for x0, x1 in ((1, 11), (8, 12), (17, 13), (24, 14)):
        for x, y in line(x0, len(CHUTE_DOME), x1, bottom):
            rows[y][x] = "k"
    return ["".join(r) for r in rows]


HOOK = [
    "g...g...g",
    "g...g...g",
    "ggggggggg",
    "..ggggg..",
    "...ggg...",
    "....g....",
    "....g....",
]

ROPE_LINK = [
    "nn",
    "nn",
]

DROP = [
    ".b.",
    "bbb",
    "bbb",
    ".b.",
]


def line(x0: int, y0: int, x1: int, y1: int) -> list[tuple[int, int]]:
    """A straight run of pixels, stepped, from one end to the other."""
    points, dx, dy = [], abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        points.append((x0, y0))
        if (x0, y0) == (x1, y1):
            return points
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def ball(spin: int) -> list[str]:
    rows = [list(r) for r in BALL]
    n = len(rows)
    if spin == 0:
        seams = [(4, y) for y in range(1, n - 1)] + [(x, 4) for x in range(1, n - 1)]
    else:
        seams = [(k, k) for k in range(2, n - 2)] + [(n - 1 - k, k) for k in range(2, n - 2)]
    return ["".join(r) for r in rows], seams


def paint_glyph(img: Image.Image, cx: int, cy: int, glyph: list[str], ox: int, oy: int, seams=()) -> None:
    """Paint `glyph` with its top-left at (ox, oy) inside the cell at (cx, cy)."""
    ink: dict[tuple[int, int], str] = {}
    for y, row in enumerate(glyph):
        for x, c in enumerate(row):
            if c != ".":
                ink[(ox + x, oy + y)] = c
    solid = {p: c for p, c in ink.items() if c in MATERIALS}
    # The outline: every empty pixel touching a solid one, in that one's dark tint (side neighbours first).
    rim: dict[tuple[int, int], tuple[int, int, int]] = {}
    for (x, y), c in solid.items():
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)):
            p = (x + dx, y + dy)
            if p not in solid and p not in rim and p not in ink:
                rim[p] = outline(MATERIALS[c])
    for (x, y), colour in rim.items():
        if 0 <= x < CELL_W and 0 <= y < CELL_H:
            img.putpixel((cx + x, cy + y), colour)
    for (x, y), c in solid.items():
        same = lambda p: solid.get(p) == c  # noqa: E731
        up_out, left_out = not same((x, y - 1)), not same((x - 1, y))
        down_out, right_out = not same((x, y + 1)), not same((x + 1, y))
        base = MATERIALS[c]
        if (up_out or left_out) and not (down_out or right_out):
            colour = light(base)
        elif (down_out or right_out) and not (up_out or left_out):
            colour = shade(base)
        else:
            colour = base
        img.putpixel((cx + x, cy + y), colour)
    for sx, sy in seams:
        p = (ox + sx, oy + sy)
        if p in solid:
            img.putpixel((cx + p[0], cy + p[1]), outline(MATERIALS[solid[p]]))
    for (x, y), c in ink.items():
        if c in THREADS:
            img.putpixel((cx + x, cy + y), THREADS[c])


def centred(glyph: list[str]) -> tuple[int, int]:
    w, h = len(glyph[0]), len(glyph)
    return (CELL_W - w) // 2, (CELL_H - h) // 2


# Where the hoop's glyph sits: its board's outline in the last column, two rows down.
HOOP_X, HOOP_Y = CELL_W - 1 - HOOP_W, 2
# Where the parachute's glyph sits: strings ending on the bottom row, centred.
CHUTE_X, CHUTE_Y = (CELL_W - CHUTE_W) // 2, CELL_H - CHUTE_H

# What the app needs, in cell pixels from the cell's top-left.
RIM_ROW = HOOP_Y + RIM_GLYPH_ROW
RIM_FROM = HOOP_X + RIM_GLYPH_FROM
RIM_TO = HOOP_X + RIM_GLYPH_TO


def paint_pose(img: Image.Image, cx: int, cy: int, pose: str) -> None:
    if pose in ("ball-0", "ball-1"):
        glyph, seams = ball(int(pose[-1]))
        paint_glyph(img, cx, cy, glyph, *centred(glyph), seams=seams)
    elif pose in ("hoop", "hoop-swish"):
        paint_glyph(img, cx, cy, hoop(pose == "hoop-swish"), HOOP_X, HOOP_Y)
    elif pose == "chute":
        paint_glyph(img, cx, cy, chute(), CHUTE_X, CHUTE_Y)
    elif pose == "hook":
        paint_glyph(img, cx, cy, HOOK, *centred(HOOK))
    elif pose == "rope":
        paint_glyph(img, cx, cy, ROPE_LINK, *centred(ROPE_LINK))
    elif pose == "drop":
        paint_glyph(img, cx, cy, DROP, *centred(DROP))
    else:
        raise ValueError(f"the play painter cannot draw {pose!r}")


def paint(recipe: Recipe) -> Image.Image:
    if tuple(recipe.cell) != (CELL_W, CELL_H):
        raise ValueError(f"the play props need a {CELL_W}x{CELL_H} cell, got {recipe.cell}")
    img = Image.new("RGB", recipe.size, recipe.background)
    for col, row, pose, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        paint_pose(img, cx, cy, pose)
    return img
