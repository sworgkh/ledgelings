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


FLOWERS = Path(__file__).resolve().parents[2] / "sprites" / "flowers.yaml"


def test_flowers_recipe_has_ten_single_frame_animations():
    recipe = load_recipe(FLOWERS)
    assert recipe.cols == 10 and recipe.rows == 1
    assert {a.name for a in recipe.animations} == {p for p, _ in recipe.poses}
    assert all(len(a.frames) == 1 for a in recipe.animations)


def test_every_flower_stands_on_the_floor_inside_the_box_and_looks_different():
    recipe = load_recipe(FLOWERS)
    sheet = key_out(get_painter("flowers")(recipe), recipe.background, recipe.tolerance)
    bx, by, bw, bh = recipe.content_box
    seen = []
    for col, row, pose, _ in recipe.cells():
        x, y, w, h = recipe.cell_rect(col, row)
        cell = sheet.crop((x, y, x + w, y + h))
        box = cell.getchannel("A").getbbox()
        assert box, f"{pose} is empty"
        left, top, right, bottom = box
        assert left >= bx and top >= by and right <= bx + bw, f"{pose} leaves the content box"
        assert bottom == by + bh, f"{pose} does not stand on the floor"
        assert cell.tobytes() not in seen, f"{pose} is a copy of another flower"
        seen.append(cell.tobytes())


HOUSE = Path(__file__).resolve().parents[2] / "sprites" / "house.yaml"


def test_the_house_is_blocky_with_a_creature_sized_doorway_on_the_left():
    from spritetool.painters import house as painter

    recipe = load_recipe(HOUSE)
    assert [a.name for a in recipe.animations] == ["house"]
    sheet = key_out(get_painter("house")(recipe), recipe.background, recipe.tolerance)
    bx, by, bw, bh = recipe.content_box
    x, y, w, h = recipe.cell_rect(0, 0)
    cell = sheet.crop((x, y, x + w, y + h))
    left, top, right, bottom = cell.getchannel("A").getbbox()
    assert left >= bx and top >= by and right <= bx + bw
    assert bottom == by + bh, "the house does not stand on the floor"
    # The doorway is a hole of the wall's outline colour, wide enough for a 22px creature.
    assert painter.DOOR_W >= 24 and painter.DOOR_H >= 24
    dark = painter.shades(painter.WALL)["outline"]
    floor = by + bh
    door_row = [cell.getpixel((px, floor - 5))[:3] == dark for px in range(bx, bx + bw)]
    runs, start = [], None
    for i, dark_px in enumerate(door_row + [False]):
        if dark_px and start is None:
            start = i
        elif not dark_px and start is not None:
            runs.append((i - start, start))
            start = None
    width, first = max(runs)           # the wall outline is a 1px run; the door is the long one
    assert first == painter.DOOR_X and width == painter.DOOR_W
    assert cell.getpixel((bx + painter.DOOR_X + painter.DOOR_W // 2, floor - painter.DOOR_H + 1))[:3] == dark
    # Windows are eye-black, like the creature.
    assert (0, 0, 0) in {cell.getpixel((px, py))[:3] for px in range(w) for py in range(h) if cell.getpixel((px, py))[3]}


PLANE = Path(__file__).resolve().parents[2] / "sprites" / "plane.yaml"


def test_the_plane_sheet_has_a_plane_its_unfolding_and_a_letter_in_blocky_rules():
    from spritetool.painters import plane as painter

    recipe = load_recipe(PLANE)
    assert [a.name for a in recipe.animations] == ["fly", "letter", "front", "opening"]
    sheet = key_out(get_painter("plane")(recipe), recipe.background, recipe.tolerance)
    for col, row, pose, _ in recipe.cells():
        x, y, w, h = recipe.cell_rect(col, row)
        cell = sheet.crop((x, y, x + w, y + h))
        box = cell.getchannel("A").getbbox()
        assert box, f"{pose} is empty"
        # The rim is the painter's dark outline, all the way round.
        rgb = cell.convert("RGB")
        left, top, right, bottom = box
        edge = [rgb.getpixel((px, py)) for px in range(left, right) for py in range(top, bottom)
                if cell.getpixel((px, py))[3] and (px in (left, right - 1) or py in (top, bottom - 1))]
        assert painter.RIM in edge, f"{pose} has no dark rim"
    plane_box = painter.glyph_pixels("plane")
    assert max(x for x, _ in plane_box) > 2 * max(y for _, y in plane_box) * 0.7, "a plane is long, nose to tail"
