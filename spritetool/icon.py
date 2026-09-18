"""icon — a macOS app icon from one frame of a packed atlas.

Writes an `.iconset` folder; `iconutil -c icns` turns that into the `.icns` the
app bundle wants. The creature is scaled by a WHOLE number at every size, so its
pixels stay square even at 16x16.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

# Apple's icon grid: the rounded square sits inside the canvas with a margin.
PLATE = 824 / 1024
RADIUS = 185 / 1024
CREATURE = 0.60            # share of the plate's width the creature may fill
SIZES = [16, 32, 128, 256, 512]


def render_icon(sheet: Image.Image, meta: dict, frame: str, size: int,
                plate: tuple[int, int, int], floor: tuple[int, int, int]) -> Image.Image:
    f = meta["frames"][frame]
    bx, by, bw, bh = meta["contentBox"]
    creature = sheet.crop((f["x"] + bx, f["y"] + by, f["x"] + bx + bw, f["y"] + by + bh))
    creature = creature.crop(creature.getbbox())

    # Draw big, then shrink: smooth plate edges at every size.
    work = max(size, 256) * 4
    icon = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)
    side = round(work * PLATE)
    left = (work - side) // 2
    box = [left, left, left + side, left + side]
    draw.rounded_rectangle(box, radius=round(work * RADIUS), fill=(*plate, 255))

    scale = max(1, int(side * CREATURE) // creature.width)
    big = creature.resize((creature.width * scale, creature.height * scale), Image.Resampling.NEAREST)
    x = (work - big.width) // 2
    floor_y = left + round(side * 0.74)
    # The edge it lives on: a floor line across the plate, clipped to the plate's shape.
    mask = Image.new("L", (work, work), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=round(work * RADIUS), fill=255)
    ground = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    ImageDraw.Draw(ground).rectangle([left, floor_y, left + side, left + side], fill=(*floor, 255))
    icon.paste(ground, (0, 0), Image.composite(ground.getchannel("A"), Image.new("L", (work, work), 0), mask))
    icon.alpha_composite(big, (x, floor_y - big.height))
    return icon.resize((size, size), Image.Resampling.LANCZOS)


def write_iconset(atlas_png: Path, atlas_json: Path, out_dir: Path, frame: str,
                  plate=(43, 36, 64), floor=(27, 22, 42)) -> Path:
    sheet = Image.open(atlas_png).convert("RGBA")
    meta = json.loads(atlas_json.read_text())
    if frame not in meta["frames"]:
        raise ValueError(f"no frame called {frame!r}; try one of {sorted(meta['frames'])[:4]}...")
    out_dir.mkdir(parents=True, exist_ok=True)
    for size in SIZES:
        render_icon(sheet, meta, frame, size, plate, floor).save(out_dir / f"icon_{size}x{size}.png")
        render_icon(sheet, meta, frame, size * 2, plate, floor).save(out_dir / f"icon_{size}x{size}@2x.png")
    return out_dir
