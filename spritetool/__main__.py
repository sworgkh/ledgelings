"""python -m spritetool <command> <recipe.yaml>"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

from .icon import write_iconset
from .pack import PackError, pack
from .painters import get_painter
from .preview import write_previews
from .recipe import RecipeError, load_recipe
from .template import render_template, template_prompt


def _work(recipe) -> Path:
    path = Path("work") / recipe.name
    path.mkdir(parents=True, exist_ok=True)
    return path


def cmd_template(args) -> None:
    recipe = load_recipe(args.recipe)
    work = _work(recipe)
    render_template(recipe, args.scale, labels=not args.no_labels).save(work / "template.png")
    (work / "prompt.txt").write_text(template_prompt(recipe))
    print(f"layout  {work / 'template.png'}")
    print(f"prompt  {work / 'prompt.txt'}")
    print("Paint into the layout, then:  python -m spritetool pack "
          f"{args.recipe} --from <painted.png>")


def cmd_draw(args) -> Path:
    recipe = load_recipe(args.recipe)
    if not recipe.painter:
        sys.exit(f"{args.recipe} declares no `painter`; paint it from the template instead")
    path = _work(recipe) / "painted.png"
    get_painter(recipe.painter)(recipe).save(path)
    print(f"painted {path}")
    return path


def cmd_pack(args, source: Path | None = None) -> None:
    recipe = load_recipe(args.recipe)
    source = source or Path(args.source)
    png, meta = pack(recipe, Image.open(source))
    print(f"atlas   {png}")
    print(f"meta    {meta}")
    for path in write_previews(png, meta, _work(recipe)):
        print(f"preview {path}")


def cmd_icon(args) -> None:
    recipe = load_recipe(args.recipe)
    out = write_iconset(recipe.output / f"{recipe.name}.png", recipe.output / f"{recipe.name}.json",
                        Path(args.out), args.frame)
    print(f"iconset {out}")
    print(f"Then:   iconutil -c icns {out}")


def cmd_build(args) -> None:
    cmd_pack(args, source=cmd_draw(args))


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(prog="spritetool", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("template", help="draw the layout PNG and the prompt that goes with it")
    p.add_argument("recipe")
    p.add_argument("--scale", type=int, help="pixels per sprite pixel (default: fit ~2048px)")
    p.add_argument("--no-labels", action="store_true")
    p.set_defaults(run=cmd_template)

    p = sub.add_parser("draw", help="fill the sheet with the recipe's procedural painter")
    p.add_argument("recipe")
    p.set_defaults(run=cmd_draw)

    p = sub.add_parser("pack", help="cut a painted sheet into the atlas the app loads")
    p.add_argument("recipe")
    p.add_argument("--from", dest="source", required=True, help="the painted sheet, at any whole scale")
    p.set_defaults(run=cmd_pack)

    p = sub.add_parser("build", help="draw + pack + preview, for recipes with a painter")
    p.add_argument("recipe")
    p.set_defaults(run=cmd_build)

    p = sub.add_parser("icon", help="a macOS .iconset from one frame of the packed atlas")
    p.add_argument("recipe")
    p.add_argument("--frame", default="idle_open")
    p.add_argument("--out", default="build/AppIcon.iconset")
    p.set_defaults(run=cmd_icon)

    args = parser.parse_args(argv)
    try:
        args.run(args)
    except (RecipeError, PackError) as exc:
        sys.exit(f"error: {exc}")


if __name__ == "__main__":
    main()
