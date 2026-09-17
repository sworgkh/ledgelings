"""preview — look at a packed atlas before it goes anywhere near the app."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


def _checker(size: tuple[int, int], square: int = 8) -> Image.Image:
    img = Image.new("RGBA", size, (58, 58, 66, 255))
    draw = ImageDraw.Draw(img)
    for y in range(0, size[1], square):
        for x in range(0, size[0], square):
            if (x // square + y // square) % 2:
                draw.rectangle([x, y, x + square - 1, y + square - 1], fill=(74, 74, 84, 255))
    return img


def contact_sheet(sheet: Image.Image, meta: dict, scale: int = 6) -> Image.Image:
    big = sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)
    out = _checker(big.size, scale * 2)
    out.alpha_composite(big)
    draw = ImageDraw.Draw(out)
    for name, f in meta["frames"].items():
        x, y = f["x"] * scale, f["y"] * scale
        draw.rectangle([x, y, x + f["w"] * scale - 1, y + f["h"] * scale - 1], outline=(255, 255, 255, 90))
        draw.text((x + 3, y + 2), name, fill=(255, 255, 255, 255))
    return out


def animation_gif(sheet: Image.Image, meta: dict, name: str, path: Path, variant: str, scale: int = 6) -> None:
    anim = meta["animations"][name]
    frames = []
    for pose in anim["frames"]:
        f = meta["frames"][f"{pose}_{variant}" if variant else pose]
        cell = sheet.crop((f["x"], f["y"], f["x"] + f["w"], f["y"] + f["h"]))
        cell = cell.resize((cell.width * scale, cell.height * scale), Image.Resampling.NEAREST)
        bg = _checker(cell.size, scale * 2)
        bg.alpha_composite(cell)
        frames.append(bg.convert("P", palette=Image.Palette.ADAPTIVE))
    frames[0].save(
        path, save_all=True, append_images=frames[1:], loop=0,
        duration=max(20, round(1000 / anim["fps"])), disposal=2,
    )


def write_previews(atlas_png: Path, atlas_json: Path, out_dir: Path) -> list[Path]:
    sheet = Image.open(atlas_png).convert("RGBA")
    meta = json.loads(atlas_json.read_text())
    out_dir.mkdir(parents=True, exist_ok=True)
    written = [out_dir / "contact.png"]
    contact_sheet(sheet, meta).save(written[0])
    variant = meta["variants"][0] if meta["variants"] else ""
    for name in meta["animations"]:
        path = out_dir / f"{name}.gif"
        animation_gif(sheet, meta, name, path, variant)
        written.append(path)
    return written
