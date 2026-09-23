"""plane — a folded paper plane, and the note it opens into.

Glyphs are hand-placed fill pixels; the painter adds the 1px dark rim round
the whole silhouette, as the flowers and the Z do. Paper is off-white with a
light edge along the top and a shade along the fold and the keel, so the
plane reads as blocky's cousin rather than a clip-art icon.
"""

from __future__ import annotations

from PIL import Image

from ..recipe import Recipe

RIM = (40, 34, 58)
INK = {
    "w": (244, 241, 230),    # paper
    "L": (255, 255, 255),    # light edge, top-left
    "s": (196, 192, 206),    # shade: the fold and the underside
    "S": (150, 146, 170),    # deep shade: the keel's far side
    "k": (92, 86, 120),      # scribble on the note
}

GLYPHS = {
    # 15 x 9, tail up-left, nose at the right end of the fold line.
    "plane": [
        "L..............",
        "wLL............",
        "wwwLL..........",
        ".wwwwLL........",
        ".wwwwwwLL......",
        "..wwwwwwwLLL...",
        "..sssssssssssLL",
        "...SSSSSSSss...",
        ".....SSSs......",
    ],
    # 10 x 8, a note with a folded corner, bottom-right.
    "letter": [
        "LLLLLLLLLL",
        "Lwwwwwwwws",
        "Lkkkkkwwws",
        "Lwwwwwwwws",
        "Lkkkkkkkws",
        "Lwwwwwwwws",
        "Lkkkwwwwss",
        "ssssssssS.",
    ],
}


def glyph_pixels(pose: str) -> dict[tuple[int, int], tuple[int, int, int]]:
    glyph = GLYPHS[pose]
    width = len(glyph[0])
    assert all(len(row) == width for row in glyph), pose
    return {(x, y): INK[c] for y, row in enumerate(glyph) for x, c in enumerate(row) if c != "."}


def paint(recipe: Recipe) -> Image.Image:
    missing = [p for p, _ in recipe.poses if p not in GLYPHS]
    if missing:
        raise ValueError(f"the plane painter cannot draw {missing}")
    img = Image.new("RGB", recipe.size, recipe.background)
    w, h = recipe.cell
    bx, by, bw, bh = recipe.content_box
    for col, row, pose, _ in recipe.cells():
        glyph = GLYPHS[pose]
        gw, gh = len(glyph[0]), len(glyph)
        # Glyph plus rim, centred in the content box.
        ox = bx + (bw - (gw + 2)) // 2 + 1
        oy = by + (bh - (gh + 2)) // 2 + 1
        cx, cy, _, _ = recipe.cell_rect(col, row)
        ink = {(ox + x, oy + y): colour for (x, y), colour in glyph_pixels(pose).items()}
        rim = {(x + dx, y + dy) for x, y in ink for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - set(ink)
        for x, y in rim:
            if 0 <= x < w and 0 <= y < h:
                img.putpixel((cx + x, cy + y), RIM)
        for (x, y), colour in ink.items():
            img.putpixel((cx + x, cy + y), colour)
    return img
