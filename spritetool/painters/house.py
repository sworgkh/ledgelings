"""house — a small cottage, built from shapes rather than a hand-typed glyph.

Fill colours only; the painter adds the same 1px dark rim the flowers and the
Z wear. The rim's bottom row is the floor of the content box.
"""

from __future__ import annotations

from PIL import Image

from ..recipe import Recipe

RIM = (40, 30, 50)
INK = {
    "r": (214, 72, 62),      # roof tile
    "R": (150, 40, 44),      # tile line
    "w": (246, 232, 200),    # wall
    "W": (252, 252, 246),    # window frame and cross
    "c": (150, 200, 250),    # glass
    "n": (146, 92, 52),      # door
    "N": (92, 56, 30),       # door planks
    "y": (250, 210, 60),     # knob
    "s": (158, 158, 170),    # chimney stone
    "S": (118, 118, 132),    # chimney cap
    "m": (120, 176, 90),     # doormat grass
}
GLYPH_W, GLYPH_H = 34, 30


def glyph() -> list[list[str]]:
    g = [["."] * GLYPH_W for _ in range(GLYPH_H)]

    def put(x: int, y: int, ch: str) -> None:
        if 0 <= x < GLYPH_W and 0 <= y < GLYPH_H:
            g[y][x] = ch

    # Walls: rows 12..29, cols 2..31.
    for y in range(12, GLYPH_H):
        for x in range(2, 32):
            put(x, y, "w")
    # Roof: a triangle that widens by three pixels a row, tile lines every third row.
    for y in range(0, 12):
        half = 1 + y * 3 // 2
        for x in range(17 - half, 17 + half):
            put(x, y, "R" if y % 3 == 2 else "r")
    # Eave: the roof's last row hangs over the walls.
    for x in range(0, GLYPH_W):
        put(x, 11, "R")
    # Chimney on the right, poking through the roof.
    for y in range(2, 9):
        for x in range(25, 29):
            put(x, y, "s")
    for x in range(24, 30):
        put(x, 2, "S")
    # Door: an arch, planks, a knob.
    for y in range(18, GLYPH_H):
        for x in range(14, 20):
            put(x, y, "n")
    for x in range(15, 19):
        put(x, 17, "n")
    for y in range(19, GLYPH_H, 3):
        for x in range(14, 20):
            put(x, y, "N")
    put(18, 24, "y")
    # Two windows with a white frame and a cross.
    for wx in (5, 23):
        for y in range(15, 22):
            for x in range(wx, wx + 6):
                edge = x in (wx, wx + 5) or y in (15, 21) or x == wx + 2 or y == 18
                put(x, y, "W" if edge else "c")
    # A strip of grass either side of the door.
    for x in list(range(2, 13)) + list(range(21, 32)):
        put(x, GLYPH_H - 1, "m")
    return g


def paint(recipe: Recipe) -> Image.Image:
    if [p for p, _ in recipe.poses] != ["house"]:
        raise ValueError("the house painter draws exactly one pose, 'house'")
    img = Image.new("RGB", recipe.size, recipe.background)
    w, h = recipe.cell
    bx, by, bw, bh = recipe.content_box
    ox = bx + (bw - (GLYPH_W + 2)) // 2 + 1
    oy = by + bh - 1 - GLYPH_H
    rows = glyph()
    for col, row, _, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        ink = {(ox + x, oy + y): INK[c] for y, r in enumerate(rows) for x, c in enumerate(r) if c != "."}
        rim = {(x + dx, y + dy) for x, y in ink for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - set(ink)
        for x, y in rim:
            if 0 <= x < w and 0 <= y < h:
                img.putpixel((cx + x, cy + y), RIM)
        for (x, y), colour in ink.items():
            img.putpixel((cx + x, cy + y), colour)
    return img
