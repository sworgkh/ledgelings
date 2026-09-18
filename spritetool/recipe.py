"""recipe — load and validate a sprite recipe."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import yaml

__all__ = ["Recipe", "Animation", "RecipeError", "load_recipe", "parse_hex"]


class RecipeError(ValueError):
    """A recipe that cannot be built. The message says which field and why."""


def parse_hex(value: str) -> tuple[int, int, int]:
    text = str(value).lstrip("#")
    if len(text) != 6:
        raise RecipeError(f"colour {value!r} is not a #rrggbb hex string")
    try:
        return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError as exc:
        raise RecipeError(f"colour {value!r} is not a #rrggbb hex string") from exc


@dataclass(frozen=True)
class Animation:
    name: str
    frames: tuple[str, ...]
    fps: float
    loop: bool


@dataclass(frozen=True)
class Recipe:
    name: str
    output: Path
    cell: tuple[int, int]
    content_box: tuple[int, int, int, int]
    background: tuple[int, int, int]
    tolerance: int
    poses: tuple[tuple[str, str], ...]      # (name, prompt)
    variants: tuple[tuple[str, str], ...]   # (name, prompt); ("", "") when unused
    animations: tuple[Animation, ...]
    style: str = ""
    painter: str | None = None
    #: Named colours the painter uses. The app swaps exactly these to recolour a creature.
    palette: tuple[tuple[str, tuple[int, int, int]], ...] = ()
    source: Path = field(default=Path("."))

    @property
    def cols(self) -> int:
        return len(self.poses)

    @property
    def rows(self) -> int:
        return len(self.variants)

    @property
    def size(self) -> tuple[int, int]:
        return self.cols * self.cell[0], self.rows * self.cell[1]

    def frame_name(self, pose: str, variant: str) -> str:
        return f"{pose}_{variant}" if variant else pose

    def cells(self):
        """Yield (col, row, pose, variant) for every cell, row by row."""
        for row, (variant, _) in enumerate(self.variants):
            for col, (pose, _) in enumerate(self.poses):
                yield col, row, pose, variant

    def cell_rect(self, col: int, row: int) -> tuple[int, int, int, int]:
        w, h = self.cell
        return col * w, row * h, w, h


def _named_list(raw, what: str) -> tuple[tuple[str, str], ...]:
    if not isinstance(raw, list) or not raw:
        raise RecipeError(f"`{what}` must be a non-empty list")
    out = []
    for item in raw:
        if isinstance(item, str):
            item = {"name": item}
        if not isinstance(item, dict) or not item.get("name"):
            raise RecipeError(f"every entry of `{what}` needs a `name`")
        name = str(item["name"])
        if "_" in name:
            raise RecipeError(
                f"{what} name {name!r} contains '_', which separates pose from variant"
            )
        out.append((name, str(item.get("prompt", ""))))
    names = [n for n, _ in out]
    if len(set(names)) != len(names):
        raise RecipeError(f"`{what}` has duplicate names")
    return tuple(out)


def load_recipe(path: str | Path) -> Recipe:
    path = Path(path)
    raw = yaml.safe_load(path.read_text())
    if not isinstance(raw, dict):
        raise RecipeError(f"{path} is not a YAML mapping")

    for key in ("name", "output", "grid", "poses"):
        if key not in raw:
            raise RecipeError(f"missing required field `{key}`")

    grid = raw["grid"]
    cell = tuple(int(v) for v in grid.get("cell", ()))
    if len(cell) != 2 or min(cell) <= 0:
        raise RecipeError("`grid.cell` must be [width, height]")
    box = tuple(int(v) for v in grid.get("content_box", (0, 0, *cell)))
    if len(box) != 4:
        raise RecipeError("`grid.content_box` must be [x, y, w, h]")
    if box[0] < 0 or box[1] < 0 or box[0] + box[2] > cell[0] or box[1] + box[3] > cell[1]:
        raise RecipeError("`grid.content_box` does not fit inside the cell")

    bg = raw.get("background", {})
    poses = _named_list(raw["poses"], "poses")
    variants = _named_list(raw["variants"], "variants") if "variants" in raw else (("", ""),)

    pose_names = {n for n, _ in poses}
    animations = []
    for name, spec in (raw.get("animations") or {}).items():
        frames = tuple(str(f) for f in spec.get("frames", ()))
        if not frames:
            raise RecipeError(f"animation `{name}` has no frames")
        unknown = [f for f in frames if f not in pose_names]
        if unknown:
            raise RecipeError(f"animation `{name}` uses unknown poses: {unknown}")
        fps = float(spec.get("fps", 8))
        if fps <= 0:
            raise RecipeError(f"animation `{name}` needs fps > 0")
        animations.append(Animation(str(name), frames, fps, bool(spec.get("loop", True))))

    return Recipe(
        name=str(raw["name"]),
        output=Path(raw["output"]),
        cell=cell,  # type: ignore[arg-type]
        content_box=box,  # type: ignore[arg-type]
        background=parse_hex(bg.get("color", "#ff00ff")),
        tolerance=int(bg.get("tolerance", 60)),
        poses=poses,
        variants=variants,
        animations=tuple(animations),
        style=" ".join(str(raw.get("style", "")).split()),
        painter=raw.get("painter"),
        palette=tuple((str(k), parse_hex(v)) for k, v in (raw.get("palette") or {}).items()),
        source=path,
    )
