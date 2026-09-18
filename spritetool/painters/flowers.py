"""flowers — ten small flowers on stems, each a hand-placed pixel glyph.

A glyph is 12 wide and 13 tall, drawn in fill colours only. The painter adds
the 1px dark rim around the whole silhouette, the same rim the Z wears, so
every flower shares the game's outline style without anyone drawing it twice.
The glyph sits so that its rim's bottom row is the floor of the content box.
"""

from __future__ import annotations

from PIL import Image

from ..recipe import Recipe

RIM = (40, 30, 50)
INK = {
    "g": (74, 140, 60),      # stem
    "l": (120, 190, 80),     # leaf
    "r": (222, 52, 60),      # red
    "R": (150, 26, 42),      # dark red
    "k": (30, 25, 35),       # black centre
    "y": (250, 210, 60),     # yellow
    "Y": (232, 150, 40),     # orange-yellow
    "w": (250, 250, 245),    # white
    "W": (200, 200, 212),    # grey-white
    "p": (240, 110, 160),    # pink
    "P": (196, 58, 118),     # deep pink
    "b": (96, 134, 232),     # blue
    "B": (52, 82, 190),      # deep blue
    "v": (156, 104, 222),    # violet
    "V": (104, 62, 172),     # deep violet
    "o": (245, 140, 50),     # orange
    "O": (140, 60, 30),      # spot on the lily
    "n": (110, 70, 40),      # brown
    "c": (150, 190, 250),    # light blue
}

GLYPHS = {
    "poppy": [
        "............",
        "....rrrr....",
        "...rrrrrr...",
        "..rrrrrrrr..",
        "..rrrkkrrr..",
        "..rrrkkrrr..",
        "..rrrrrrrr..",
        "...rrRRrr...",
        "....RRRR....",
        ".....g......",
        ".....gl.....",
        "....lg......",
        ".....g......",
    ],
    "tulip": [
        "............",
        "..r......r..",
        "..rr.rr.rr..",
        "..rrrrrrrr..",
        "..rrrrrrrr..",
        "..rRrrrrRr..",
        "...rrrrrr...",
        "....rrrr....",
        ".....g......",
        ".....g.l....",
        ".....gl.....",
        "..l..g......",
        "...llg......",
    ],
    "daisy": [
        "............",
        "....w..w....",
        ".w.wwwwww.w.",
        "..wwwwwwww..",
        "..wwwyywww..",
        ".wwwyyyywww.",
        ".wwwyyyywww.",
        "..wwwyywww..",
        "..wwwwwwww..",
        ".w.wwwwww.w.",
        "....w.gw....",
        ".....gl.....",
        ".....g......",
    ],
    "sunflower": [
        ".....y......",
        "..y.yyy.y...",
        "...yyyyyy...",
        "..yynnnnyy..",
        ".yyynnnnyyy.",
        ".yyynnnnyyy.",
        "..yynnnnyy..",
        "...yyyyyy...",
        "..y.yyy.y...",
        ".....g......",
        "...l.g......",
        "....lg.l....",
        ".....g......",
    ],
    "rose": [
        "............",
        "....pppp....",
        "...pPpppp...",
        "..ppPPPppp..",
        "..pPpPPpPp..",
        "..pPpPpPPp..",
        "..ppPPPPpp..",
        "...pppppp...",
        "....PPPP....",
        ".....g......",
        ".....gl.....",
        "....lg......",
        ".....g......",
    ],
    "bluebell": [
        "............",
        "......ggg...",
        ".....g...g..",
        ".....g...bb.",
        "....l...bbbb",
        "........bBBb",
        "........bbbb",
        ".......bBbBb",
        ".......b.b.b",
        ".....g......",
        ".....g......",
        "....lg......",
        ".....g......",
    ],
    "dandelion": [
        "............",
        "....w..w....",
        ".w..wwww..w.",
        "..w.wwww.w..",
        "...wwwwww...",
        ".wwwwWwwwww.",
        ".wwwwWWwwww.",
        "...wwwwww...",
        "..w.wwww.w..",
        ".w..wgww..w.",
        "....wgw.....",
        ".....g......",
        ".....g......",
    ],
    "lavender": [
        "............",
        ".....vv.....",
        "....vVvv....",
        "....vvVv....",
        ".....vv.....",
        "....vVvv....",
        "....vvVv....",
        ".....vv.....",
        "....vVvv....",
        ".....g......",
        ".....g.l....",
        ".....gl.....",
        ".....g......",
    ],
    "lily": [
        "............",
        ".....o......",
        ".o...o...o..",
        "..o..o..o...",
        "...o.o.o....",
        "..ooooooo...",
        ".oooOoOooo..",
        "..ooooooo...",
        "...o.o.o....",
        "..o..g..o...",
        ".....g......",
        "....lg......",
        ".....g......",
    ],
    "forget-me-not": [
        "............",
        "....c...c...",
        "...cyc.cyc..",
        "....c...c...",
        "......c.....",
        ".....cyc....",
        "......c.....",
        "......g.....",
        ".....lg.....",
        "......g.l...",
        "......g.....",
        "......g.....",
        "......g.....",
    ],
}
GLYPH_W, GLYPH_H = 12, 13


def paint(recipe: Recipe) -> Image.Image:
    missing = [p for p, _ in recipe.poses if p not in GLYPHS]
    if missing:
        raise ValueError(f"the flowers painter cannot draw {missing}")
    img = Image.new("RGB", recipe.size, recipe.background)
    w, h = recipe.cell
    bx, by, bw, bh = recipe.content_box
    # Glyph plus rim is 14 x 15; centre it in the box, rim's bottom on the floor.
    ox = bx + (bw - (GLYPH_W + 2)) // 2 + 1
    oy = by + bh - 1 - GLYPH_H
    for col, row, pose, _ in recipe.cells():
        glyph = GLYPHS[pose]
        assert len(glyph) == GLYPH_H and all(len(r) == GLYPH_W for r in glyph), pose
        cx, cy, _, _ = recipe.cell_rect(col, row)
        ink = {(ox + x, oy + y): INK[c] for y, r in enumerate(glyph) for x, c in enumerate(r) if c != "."}
        rim = {(x + dx, y + dy) for x, y in ink for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - set(ink)
        for x, y in rim:
            if 0 <= x < w and 0 <= y < h:
                img.putpixel((cx + x, cy + y), RIM)
        for (x, y), colour in ink.items():
            img.putpixel((cx + x, cy + y), colour)
    return img
