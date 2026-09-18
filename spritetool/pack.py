"""pack — turn a painted sheet into the atlas the app loads.

"Opaque first, cut second": the painted sheet is expected on the recipe's flat
key colour. That colour is cut to real transparency HERE, by threshold, rather
than trusting whoever painted it to deliver clean alpha. The sheet may arrive at
any whole-number scale (image models paint big); it is brought down to the
recipe's exact cell size and its alpha is hardened to 1 bit, as pixel art wants.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from .recipe import Recipe

__all__ = ["key_out", "fit_to_recipe", "atlas_json", "pack", "PackError"]


class PackError(ValueError):
    pass


def key_out(img: Image.Image, color: tuple[int, int, int], tolerance: int) -> Image.Image:
    """Make every pixel within `tolerance` of `color` fully transparent."""
    rgb = img.convert("RGB")
    limit = tolerance * tolerance
    out = Image.new("RGBA", rgb.size)
    out.putdata(
        [
            (0, 0, 0, 0)
            if (r - color[0]) ** 2 + (g - color[1]) ** 2 + (b - color[2]) ** 2 <= limit
            else (r, g, b, 255)
            for r, g, b in rgb.getdata()
        ]
    )
    return out


def fit_to_recipe(img: Image.Image, recipe: Recipe) -> Image.Image:
    """Resize an RGBA sheet to the recipe's exact size, keeping alpha 1-bit."""
    if img.size == recipe.size:
        return img
    want = recipe.size[0] / recipe.size[1]
    got = img.size[0] / img.size[1]
    if abs(want - got) / want > 0.02:
        raise PackError(
            f"sheet is {img.size[0]}x{img.size[1]}, which is not the recipe's "
            f"{recipe.cols}x{recipe.rows} grid shape ({recipe.size[0]}x{recipe.size[1]})"
        )
    # Resize with premultiplied colour, so transparent pixels cannot bleed the
    # key colour's neighbours into the edge of the sprite.
    premult = img.convert("RGBa").resize(recipe.size, Image.Resampling.BOX).convert("RGBA")
    r, g, b, a = premult.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: 255 if v >= 128 else 0)))


def atlas_json(recipe: Recipe, image_name: str) -> dict:
    frames = {}
    for col, row, pose, variant in recipe.cells():
        x, y, w, h = recipe.cell_rect(col, row)
        frames[recipe.frame_name(pose, variant)] = {"x": x, "y": y, "w": w, "h": h}
    return {
        "name": recipe.name,
        "image": image_name,
        "cell": list(recipe.cell),
        "contentBox": list(recipe.content_box),
        "variants": [name for name, _ in recipe.variants if name],
        "palette": {name: "#%02x%02x%02x" % rgb for name, rgb in recipe.palette},
        "frames": frames,
        "animations": {
            a.name: {"frames": list(a.frames), "fps": a.fps, "loop": a.loop}
            for a in recipe.animations
        },
    }


def empty_cells(sheet: Image.Image, recipe: Recipe) -> list[str]:
    alpha = sheet.getchannel("A")
    out = []
    for col, row, pose, variant in recipe.cells():
        x, y, w, h = recipe.cell_rect(col, row)
        if alpha.crop((x, y, x + w, y + h)).getbbox() is None:
            out.append(recipe.frame_name(pose, variant))
    return out


def pack(recipe: Recipe, painted: Image.Image, out_dir: Path | None = None) -> tuple[Path, Path]:
    sheet = fit_to_recipe(key_out(painted, recipe.background, recipe.tolerance), recipe)
    blank = empty_cells(sheet, recipe)
    if blank:
        raise PackError(f"these cells came out empty: {', '.join(blank)}")
    out_dir = out_dir or recipe.output
    out_dir.mkdir(parents=True, exist_ok=True)
    png, meta = out_dir / f"{recipe.name}.png", out_dir / f"{recipe.name}.json"
    sheet.save(png)
    meta.write_text(json.dumps(atlas_json(recipe, png.name), indent=2) + "\n")
    return png, meta
