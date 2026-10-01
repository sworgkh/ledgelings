"""Copy the app's sprite sheets into public/sprites, each species recoloured the
way SpriteAtlas.recoloured(around:) does it, so the video shows the real art.

    python3 scripts/export-sprites.py
"""
import json, re, shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Sources/Ledgelings/Resources/sprites"
TEXT = ROOT / "sprites/text"
OUT = Path(__file__).resolve().parents[1] / "public/sprites"


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def close(a, b):
    return all(abs(x - y) <= 8 for x, y in zip(a, b))


def recolour(sheet, palette, body):
    targets = {"body": body, "light": mix(body, (255,) * 3, 0.36),
               "shade": mix(body, (0,) * 3, 0.17), "outline": mix(body, (0,) * 3, 0.76)}
    swaps = [(rgb(v), targets[k]) for k, v in palette.items() if k in targets]
    px = sheet.load()
    for y in range(sheet.height):
        for x in range(sheet.width):
            r, g, b, a = px[x, y]
            if a != 255:
                continue
            for frm, to in swaps:
                if close(frm, (r, g, b)):
                    px[x, y] = (*to, 255)
                    break
    return sheet


OUT.mkdir(parents=True, exist_ok=True)
for meta_path in SRC.glob("*.json"):
    name = meta_path.stem
    meta = json.loads(meta_path.read_text())
    sheet = Image.open(SRC / meta["image"]).convert("RGBA")
    text = TEXT / f"{name}.txt"
    colour = re.search(r"^colour:\s*(#[0-9a-fA-F]{6})", text.read_text(), re.M) if text.exists() else None
    if colour and meta.get("palette"):
        sheet = recolour(sheet, meta["palette"], rgb(colour.group(1)))
    sheet.save(OUT / f"{name}.png")
    shutil.copy(meta_path, OUT / f"{name}.json")
    print(name, "recoloured" if colour else "as painted")

# Blocky's cast wear the app's default colours (AppSettings.defaultColors); Blocky is the sheet as painted.
CAST = {"pip": "#3dc7b5", "mortimer": "#ff6fa3",
        "zed": "#ffd23d", "dot": "#9b7bff", "ruth": "#7bd65a"}
meta = json.loads((SRC / "blocky.json").read_text())
for who, colour in CAST.items():
    sheet = recolour(Image.open(SRC / "blocky.png").convert("RGBA"), meta["palette"], rgb(colour))
    sheet.save(OUT / f"blocky-{who}.png")
    print(f"blocky-{who}", colour)
