from pathlib import Path

import pytest
from PIL import Image

from spritetool.pack import PackError, atlas_json, fit_to_recipe, key_out, pack
from spritetool.painters import get_painter
from spritetool.recipe import RecipeError, load_recipe
from spritetool.template import render_template, template_prompt

RECIPE = Path(__file__).resolve().parents[2] / "sprites" / "blocky.yaml"


@pytest.fixture
def recipe():
    return load_recipe(RECIPE)


def test_recipe_grid_is_poses_by_variants(recipe):
    assert (recipe.cols, recipe.rows) == (9, 3)
    assert recipe.size == (288, 96)
    assert recipe.frame_name("walk-1", "half") == "walk-1_half"


def test_recipe_rejects_animation_with_unknown_pose(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text(
        "name: x\noutput: out\ngrid: {cell: [8, 8]}\nposes: [a]\n"
        "animations: {walk: {frames: [a, nope]}}\n"
    )
    with pytest.raises(RecipeError, match="nope"):
        load_recipe(bad)


def test_recipe_rejects_content_box_outside_cell(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("name: x\noutput: out\ngrid: {cell: [8, 8], content_box: [4, 4, 8, 8]}\nposes: [a]\n")
    with pytest.raises(RecipeError, match="content_box"):
        load_recipe(bad)


def test_template_is_an_exact_multiple_of_the_sheet_on_the_key_colour(recipe):
    img = render_template(recipe, scale=4)
    assert img.size == (288 * 4, 96 * 4)
    # the centre of a cell is untouched background
    assert img.getpixel((16 * 4, 16 * 4)) == recipe.background


def test_template_prompt_names_every_pose_and_variant(recipe):
    text = template_prompt(recipe)
    for name, _ in recipe.poses + recipe.variants:
        assert name in text


def test_painter_keeps_every_pose_inside_the_content_box_and_on_the_floor(recipe):
    sheet = key_out(get_painter("blocky")(recipe), recipe.background, recipe.tolerance)
    bx, by, bw, bh = recipe.content_box
    for col, row, pose, variant in recipe.cells():
        x, y, w, h = recipe.cell_rect(col, row)
        left, top, right, bottom = sheet.crop((x, y, x + w, y + h)).getchannel("A").getbbox()
        assert left >= bx and top >= by and right <= bx + bw, (pose, variant)
        assert bottom == by + bh, f"{pose}_{variant} does not stand on the floor line"


def test_blink_variants_differ_only_in_the_eyes(recipe):
    sheet = get_painter("blocky")(recipe)
    open_ = sheet.crop((0, 0, 32, 32))
    closed = sheet.crop((0, 64, 32, 96))
    assert open_.tobytes() != closed.tobytes()
    black = lambda im: sum(1 for p in im.getdata() if p == (0, 0, 0))
    assert black(open_) > black(closed) > 0


def test_pack_accepts_an_upscaled_sheet_and_cuts_the_background(recipe, tmp_path):
    painted = get_painter("blocky")(recipe)
    big = painted.resize((painted.width * 4, painted.height * 4), Image.Resampling.NEAREST)
    png, meta = pack(recipe, big, tmp_path)
    out = Image.open(png)
    assert out.size == recipe.size and out.mode == "RGBA"
    assert set(out.getchannel("A").getdata()) == {0, 255}
    assert out.getpixel((0, 0))[3] == 0
    assert meta.exists()


def test_pack_refuses_a_sheet_of_the_wrong_shape(recipe):
    with pytest.raises(PackError, match="grid shape"):
        fit_to_recipe(Image.new("RGBA", (500, 500)), recipe)


def test_pack_refuses_empty_cells(recipe, tmp_path):
    with pytest.raises(PackError, match="empty"):
        pack(recipe, Image.new("RGB", recipe.size, recipe.background), tmp_path)


def test_atlas_json_lists_every_frame(recipe):
    meta = atlas_json(recipe, "blocky.png")
    assert len(meta["frames"]) == 27
    assert meta["frames"]["land_closed"] == {"x": 192, "y": 64, "w": 32, "h": 32}
    assert meta["animations"]["walk"]["frames"] == ["walk-0", "walk-1", "walk-2", "walk-3"]


def test_sleeping_poses_keep_their_eyes_shut_in_every_row(recipe):
    sheet = get_painter("blocky")(recipe)
    col = [name for name, _ in recipe.poses].index("sleep-0")
    rows = [sheet.crop((col * 32, r * 32, col * 32 + 32, r * 32 + 32)).tobytes() for r in range(3)]
    assert rows[0] == rows[1] == rows[2]


def test_atlas_carries_the_palette_the_painter_really_used(recipe):
    meta = atlas_json(recipe, "blocky.png")
    assert meta["palette"]["body"] == "#ff8a3d"
    used = set(get_painter("blocky")(recipe).getdata())
    for _, rgb in recipe.palette:
        assert rgb in used


def test_zzz_recipe_builds(tmp_path):
    zzz = load_recipe(RECIPE.parent / "zzz.yaml")
    png, _ = pack(zzz, get_painter("zzz")(zzz), tmp_path)
    assert Image.open(png).size == (10, 10)


def test_icon_set_has_every_size_macos_asks_for_with_the_creature_on_it(recipe, tmp_path):
    from spritetool.icon import write_iconset

    png, meta = pack(recipe, get_painter("blocky")(recipe), tmp_path)
    out = write_iconset(png, meta, tmp_path / "AppIcon.iconset", "idle_open")
    names = {p.name for p in out.iterdir()}
    assert len(names) == 10 and "icon_512x512@2x.png" in names and "icon_16x16.png" in names
    big = Image.open(out / "icon_512x512@2x.png")
    assert big.size == (1024, 1024)
    assert big.getpixel((0, 0))[3] == 0                     # transparent outside the rounded plate
    assert (255, 138, 61, 255) in set(big.getdata())        # the creature's exact orange survived
