"""tea — the tea party table, built the way the creature is: flat blocks, a 1px
outline that is a dark tint of each block's own colour, a light line along the
top and left, a shade line along the bottom and right. The teapot's handle and
the cups' handles are open rings of their outline colour, the way the house's
doorway is a hole: no curves anywhere, only steps.

The table is 36 px wide against a creature's 22 px body, so with one creature
tucked in at each end the pair reads as sitting down to tea, not as three
things in a row. The cups sit at the very ends, one in front of each of them.
"""

from __future__ import annotations

from PIL import Image, ImageDraw

from ..recipe import Recipe
from .house import block, shades

WOOD = (176, 112, 62)
POT = (84, 150, 214)
CUP = (244, 240, 228)
TEA = (150, 84, 40)
STEAM = (236, 236, 244)

GLYPH_W, GLYPH_H = 36, 28
# The table top, from the floor: the cups and the pot stand on it.
TOP_H = 13


def ring(draw: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int, colour) -> None:
    """A handle: the outline of [x0, x1) x [y0, y1), hollow."""
    draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=colour)


def paint_table(draw: ImageDraw.ImageDraw, ox: int, oy: int, steam: int) -> None:
    """Origin is the glyph's top-left; the floor is the row just below oy + GLYPH_H.
    `steam` 0 or 1: how far the puff has risen."""
    floor = oy + GLYPH_H
    top = floor - TOP_H
    # Two legs, like the creature's feet, then the top laid over them.
    block(draw, ox + 3, top + 4, ox + 8, floor, WOOD)
    block(draw, ox + 28, top + 4, ox + 33, floor, WOOD)
    block(draw, ox, top, ox + GLYPH_W, top + 5, WOOD)

    # A cup at each end, tea showing at the brim, its handle on the outside.
    for cx, handle in ((ox + 3, -1), (ox + GLYPH_W - 9, 1)):
        block(draw, cx, top - 6, cx + 6, top, CUP)
        draw.line([(cx + 1, top - 5), (cx + 4, top - 5)], fill=TEA)
        hx = cx - 3 if handle < 0 else cx + 6
        ring(draw, hx, top - 5, hx + 3, top - 1, shades(CUP)["outline"])

    # The pot in the middle: body, lid, knob, a stepped spout to the right, a ring handle to the left.
    pl, pr = ox + 12, ox + 22
    block(draw, pl, top - 10, pr, top, POT)
    block(draw, pl + 2, top - 13, pr - 2, top - 9, POT)
    draw.rectangle([pl + 5, top - 15, pl + 6, top - 14], fill=shades(POT)["outline"])
    block(draw, pr - 1, top - 7, pr + 3, top - 3, POT)
    block(draw, pr + 1, top - 10, pr + 5, top - 6, POT)
    ring(draw, pl - 3, top - 9, pl + 1, top - 3, shades(POT)["outline"])

    # Steam: two square puffs above the spout, stepping up and over as it rises.
    sx, sy = pr + 2, top - 12
    puffs = [(sx, sy), (sx + 2, sy - 3)] if steam == 0 else [(sx + 1, sy - 2), (sx - 1, sy - 6)]
    for px, py in puffs:
        draw.rectangle([px, py, px + 1, py + 1], fill=STEAM)


def paint(recipe: Recipe) -> Image.Image:
    names = [p for p, _ in recipe.poses]
    if names != ["tea-0", "tea-1"]:
        raise ValueError("the tea painter draws exactly two poses, 'tea-0' and 'tea-1'")
    bx, by, bw, bh = recipe.content_box
    if (bw, bh) != (GLYPH_W, GLYPH_H):
        raise ValueError(f"the tea table needs a {GLYPH_W}x{GLYPH_H} content box, got {bw}x{bh}")
    img = Image.new("RGB", recipe.size, recipe.background)
    draw = ImageDraw.Draw(img)
    for col, row, pose, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        paint_table(draw, cx + bx, cy + by, names.index(pose))
    return img
