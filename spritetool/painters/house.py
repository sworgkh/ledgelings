"""house — a cottage built the way the creature is: flat blocks, a 1px outline
that is a dark tint of each block's own colour, a light line along the top and
left, a shade line along the bottom and right. Windows are black squares like
the creature's eyes. The doorway is an open, dark hole wide enough for a
creature (22px body) to walk into.

The door sits on the LEFT of the house, because the house stands in the
bottom-right corner of the screen and everyone arrives along the floor.
"""

from __future__ import annotations

from PIL import Image, ImageDraw

from ..recipe import Recipe

EYE = (0, 0, 0)
WALL = (246, 226, 188)
ROOF = (214, 72, 62)
STONE = (150, 150, 162)

GLYPH_W, GLYPH_H = 64, 58
# Door opening, in glyph pixels: x, width, height (from the floor). The app
# steers creatures to the middle of this; keep Colony+Hideout in step.
DOOR_X, DOOR_W, DOOR_H = 4, 26, 28


def mix(a: tuple[int, int, int], b: tuple[int, int, int], k: float) -> tuple[int, int, int]:
    return tuple(round(x * (1 - k) + y * k) for x, y in zip(a, b))


def shades(colour):
    """The creature's recipe: light, shade and outline from one body colour."""
    return {
        "body": colour,
        "light": mix(colour, (255, 255, 255), 0.36),
        "shade": mix(colour, (0, 0, 0), 0.17),
        "outline": mix(colour, (0, 0, 0), 0.76),
    }


def block(draw: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int, colour) -> None:
    """A filled block [x0, x1) x [y0, y1) drawn exactly like the creature's body."""
    c = shades(colour)
    draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=c["outline"])
    draw.rectangle([x0 + 1, y0 + 1, x1 - 2, y1 - 2], fill=c["body"])
    draw.line([(x0 + 1, y0 + 1), (x1 - 3, y0 + 1)], fill=c["light"])
    draw.line([(x0 + 1, y0 + 1), (x0 + 1, y1 - 3)], fill=c["light"])
    draw.line([(x0 + 2, y1 - 2), (x1 - 2, y1 - 2)], fill=c["shade"])
    draw.line([(x1 - 2, y0 + 2), (x1 - 2, y1 - 2)], fill=c["shade"])


def paint_house(draw: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    """Origin is the glyph's top-left; the floor is the row just below oy + GLYPH_H."""
    floor = oy + GLYPH_H
    # Wall: 60 wide, 36 tall, on the floor.
    wall_l, wall_r, wall_t = ox + 2, ox + 62, floor - 36
    block(draw, wall_l, wall_t, wall_r, floor, WALL)
    # Roof: two slabs, the lower one hanging over the wall by 2px each side.
    block(draw, ox, wall_t - 10, ox + 64, wall_t + 1, ROOF)
    block(draw, ox + 10, wall_t - 18, ox + 54, wall_t - 9, ROOF)
    # Chimney: a small stone block through the upper slab, on the right.
    block(draw, ox + 44, wall_t - 22, ox + 52, wall_t - 12, STONE)
    # Doorway: an open hole in the wall colour's outline, corners knocked off.
    dark = shades(WALL)["outline"]
    dl, dr, dt = ox + DOOR_X, ox + DOOR_X + DOOR_W, floor - DOOR_H
    draw.rectangle([dl, dt, dr - 1, floor - 1], fill=dark)
    for x, y in ((dl, dt), (dr - 1, dt), (dl, dt + 1), (dr - 1, dt + 1), (dl + 1, dt), (dr - 2, dt)):
        draw.point((x, y), fill=shades(WALL)["body"])
    # Two windows like the eyes: black squares with a thin frame of the wall's light.
    for wx in (ox + 36, ox + 50):
        wy = wall_t + 8
        draw.rectangle([wx - 1, wy - 1, wx + 8, wy + 8], fill=shades(WALL)["light"])
        draw.rectangle([wx, wy, wx + 7, wy + 7], fill=EYE)


def paint(recipe: Recipe) -> Image.Image:
    if [p for p, _ in recipe.poses] != ["house"]:
        raise ValueError("the house painter draws exactly one pose, 'house'")
    bx, by, bw, bh = recipe.content_box
    if (bw, bh) != (GLYPH_W, GLYPH_H):
        raise ValueError(f"the house needs a {GLYPH_W}x{GLYPH_H} content box, got {bw}x{bh}")
    img = Image.new("RGB", recipe.size, recipe.background)
    draw = ImageDraw.Draw(img)
    for col, row, _, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        paint_house(draw, cx + bx, cy + by)
    return img
