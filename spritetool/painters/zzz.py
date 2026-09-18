"""zzz — one pixel "Z", white with a dark rim so it reads on any wallpaper."""

from __future__ import annotations

from PIL import Image

from ..recipe import Recipe

FILL = (255, 255, 255)
RIM = (30, 27, 58)
GLYPH = [
    "XXXXXX",
    "XXXXXX",
    "...XXX",
    "..XXX.",
    ".XXX..",
    "XXX...",
    "XXXXXX",
    "XXXXXX",
]


def paint(recipe: Recipe) -> Image.Image:
    img = Image.new("RGB", recipe.size, recipe.background)
    w, h = recipe.cell
    ox, oy = (w - len(GLYPH[0])) // 2, (h - len(GLYPH)) // 2
    ink = {(ox + x, oy + y) for y, row in enumerate(GLYPH) for x, c in enumerate(row) if c == "X"}
    rim = {(x + dx, y + dy) for x, y in ink for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - ink
    for col, row, _, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        for x, y in rim:
            if 0 <= x < w and 0 <= y < h:
                img.putpixel((cx + x, cy + y), RIM)
        for x, y in ink:
            img.putpixel((cx + x, cy + y), FILL)
    return img
