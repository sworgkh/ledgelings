"""blocky — a square creature with two black rectangle eyes, drawn in code.

Every pose keeps its feet on the floor line (the bottom of the content box) and
stays horizontally centred in it, so the app can rotate the sprite about the cell
centre when it turns a screen corner.
"""

from __future__ import annotations

from PIL import Image, ImageDraw

from ..recipe import Recipe

EYE = (0, 0, 0)
# Used only when the recipe declares no `palette`.
DEFAULTS = {"body": (255, 138, 61), "light": (255, 178, 122), "shade": (214, 98, 32), "outline": (59, 31, 15)}

# pose -> (body width, body height, lift off the floor, front foot up, back foot up)
POSES = {
    "idle":   (22, 20, 0, False, False),
    "walk-0": (22, 20, 0, False, False),
    "walk-1": (22, 18, 0, True, False),
    "walk-2": (22, 20, 0, False, False),
    "walk-3": (20, 20, 0, False, True),
    "jump":   (18, 22, 0, None, None),   # None = feet tucked away entirely
    "land":   (22, 13, 0, False, False),
    "sleep-0": (22, 16, 0, False, False),  # slumped, breathing in
    "sleep-1": (22, 15, 0, False, False),  # breathing out
}
ALWAYS_SHUT = {"sleep-0", "sleep-1"}
# variant -> eye height as a fraction of the open eye
EYES = {"open": 1.0, "half": 0.5, "closed": 0.0, "": 1.0}


def _paint_cell(draw: ImageDraw.ImageDraw, ox: int, oy: int, recipe: Recipe, pose: str, variant: str):
    colours = {**DEFAULTS, **dict(recipe.palette)}
    OUTLINE, BODY, LIGHT, SHADE = (colours[k] for k in ("outline", "body", "light", "shade"))
    FOOT = OUTLINE
    if pose in ALWAYS_SHUT:
        variant = "closed"
    bx, by, bw, bh = recipe.content_box
    width, height, lift, front_up, back_up = POSES[pose]
    feet = 0 if front_up is None else 2
    floor = oy + by + bh                      # first pixel row BELOW the creature
    left = ox + bx + (bw - width) // 2
    bottom = floor - feet - lift              # first row below the body
    top = bottom - height
    right = left + width

    draw.rectangle([left, top, right - 1, bottom - 1], fill=OUTLINE)
    draw.rectangle([left + 1, top + 1, right - 2, bottom - 2], fill=BODY)
    draw.line([(left + 1, top + 1), (right - 3, top + 1)], fill=LIGHT)
    draw.line([(left + 1, top + 1), (left + 1, bottom - 3)], fill=LIGHT)
    draw.line([(left + 2, bottom - 2), (right - 2, bottom - 2)], fill=SHADE)
    draw.line([(right - 2, top + 2), (right - 2, bottom - 2)], fill=SHADE)

    # Eyes sit right of centre: that offset is what makes "facing right" readable.
    open_h = 7 if pose == "jump" else max(3, min(6, height // 3))
    eye_h = max(1, round(open_h * EYES[variant]))
    eye_top = top + max(3, height // 4) + (open_h - eye_h)   # lids close downwards
    for ex in (left + width // 2 - 2, left + width // 2 + 4):
        draw.rectangle([ex, eye_top, ex + 2, eye_top + eye_h - 1], fill=EYE)

    if feet:
        for fx, up in ((left + 3, back_up), (right - 7, front_up)):
            y = bottom - (1 if up else 0)
            draw.rectangle([fx, y, fx + 3, y + 1], fill=FOOT)


def paint(recipe: Recipe) -> Image.Image:
    missing = [p for p, _ in recipe.poses if p not in POSES]
    if missing:
        raise ValueError(f"the blocky painter cannot draw poses {missing}")
    img = Image.new("RGB", recipe.size, recipe.background)
    draw = ImageDraw.Draw(img)
    for col, row, pose, variant in recipe.cells():
        x, y, _, _ = recipe.cell_rect(col, row)
        _paint_cell(draw, x, y, recipe, pose, variant)
    return img
