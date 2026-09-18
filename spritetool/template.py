"""template — draw the sheet's layout as an image to paint into.

A grid is a spatial fact, and a spatial fact cannot be paraphrased. So instead of
describing "7 poses by 3 eye states" to an artist or an image model, show it:
every cell outlined, labelled with its frame name, with the box the creature must
stay inside and the floor line its feet must touch. The background is the exact
key colour, so whoever paints has it by example.
"""

from __future__ import annotations

from PIL import Image, ImageDraw, ImageFont

from .recipe import Recipe

GRID = (255, 255, 255)
BOX = (0, 200, 255)
FLOOR = (255, 230, 0)
LABEL = (255, 255, 255)
SHADOW = (0, 0, 0)
MAX_EDGE = 2048


def _font(px: int):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def _dashed(draw, box, color, width, dash=10, gap=7) -> None:
    left, top, right, bottom = box
    for x in range(int(left), int(right), dash + gap):
        x2 = min(x + dash, right)
        draw.line([(x, top), (x2, top)], fill=color, width=width)
        draw.line([(x, bottom), (x2, bottom)], fill=color, width=width)
    for y in range(int(top), int(bottom), dash + gap):
        y2 = min(y + dash, bottom)
        draw.line([(left, y), (left, y2)], fill=color, width=width)
        draw.line([(right, y), (right, y2)], fill=color, width=width)


def _label(draw, xy, text, font) -> None:
    x, y = xy
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        draw.text((x + dx, y + dy), text, font=font, fill=SHADOW)
    draw.text((x, y), text, font=font, fill=LABEL)


def template_scale(recipe: Recipe, scale: int | None = None) -> int:
    if scale:
        return scale
    return max(1, min(16, MAX_EDGE // max(recipe.size)))


def render_template(recipe: Recipe, scale: int | None = None, labels: bool = True) -> Image.Image:
    s = template_scale(recipe, scale)
    cw, ch = recipe.cell[0] * s, recipe.cell[1] * s
    img = Image.new("RGB", (recipe.cols * cw, recipe.rows * ch), recipe.background)
    draw = ImageDraw.Draw(img)
    font = _font(max(9, ch // 11))
    bx, by, bw, bh = (v * s for v in recipe.content_box)

    for col, row, pose, variant in recipe.cells():
        x, y = col * cw, row * ch
        draw.rectangle([x, y, x + cw - 1, y + ch - 1], outline=GRID, width=max(1, s // 4))
        _dashed(draw, (x + bx, y + by, x + bx + bw, y + by + bh), BOX, max(1, s // 5))
        floor_y = y + by + bh
        draw.line([(x + s, floor_y), (x + cw - s, floor_y)], fill=FLOOR, width=max(2, s // 3))
        if labels:
            _label(draw, (x + s, y + s // 2), recipe.frame_name(pose, variant), font)
    return img


def template_prompt(recipe: Recipe) -> str:
    """The words that go with the template image. Layout is shown, not described."""
    lines = [
        f"Paint a {recipe.cols}x{recipe.rows} sprite sheet into the attached layout.",
        "Draw ONE creature per cell, the same creature in every cell.",
        "Keep each one inside its dashed cyan box, with its feet exactly on the yellow floor line.",
        "The creature faces RIGHT in every cell.",
        "Keep the background exactly the flat colour it already is. No shadows on it.",
        "Then delete every label, grid line, dashed box and floor line.",
        "",
        f"Style: {recipe.style}" if recipe.style else "",
        "",
        "Columns, left to right (pose):",
    ]
    lines += [f"  {i + 1}. {name} - {prompt}" for i, (name, prompt) in enumerate(recipe.poses)]
    if recipe.variants != (("", ""),):
        lines += ["", "Rows, top to bottom (the only thing that changes between rows):"]
        lines += [f"  {i + 1}. {name} - {prompt}" for i, (name, prompt) in enumerate(recipe.variants)]
    return "\n".join(line for line in lines if line is not None).strip() + "\n"
