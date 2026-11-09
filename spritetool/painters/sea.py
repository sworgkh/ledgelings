"""sea — what the divers meet under the water, and what they wear: three
kinds of fish (each with a real flick of the tail for its second frame), a
jellyfish pulsing, a crab walking and raising its claws, a turtle rowing, an
octopus sitting and spreading its arms, a puff of its ink; air bubbles in
three sizes; the splash of a diver going in; the scuba gear, a mask and a tank,
as props over any body; and a coral clump for the floor.

Traced by hand from Wixel's pictures (the fish and the splash it drew for us),
then drawn the way the play props are: material letters, each patch shaded
like the creature's body (a light line top-left, a shade line bottom-right), a
1px outline round the whole glyph in a dark tint of the colour next to it; eyes
and bubbles' glints are single pixels with no outline. No curves.

Every picture is drawn in one 32x28 cell, centred, facing RIGHT; the app
mirrors it to swim left. The mask's glass is centred where a creature's eyes
are when the gear's cell is laid over the body's middle (`Dive.Gear`).
"""

from __future__ import annotations

from PIL import Image

from ..recipe import Recipe
from . import play
from .house import mix

CELL_W, CELL_H = 32, 28

TEAL = (40, 160, 168)
PALE = (170, 222, 222)
YELLOW = (240, 196, 60)
STRIPE = (60, 70, 110)
CORAL = (232, 104, 72)
PINK = (236, 150, 200)
LILAC = (200, 170, 232)
RED = (214, 72, 62)
GREEN = (98, 168, 84)
SHELL = (122, 96, 58)
PURPLE = (150, 92, 176)
INK = (87, 53, 168)
WATER = (150, 210, 246)
FOAM = (226, 244, 252)
GLASS = (83, 133, 218)
STRAP = (52, 52, 60)
TANK = (240, 180, 40)
STEEL = (150, 150, 162)
ROCK = (130, 120, 140)
CORALPINK = (240, 120, 140)

MATERIALS = {
    "t": TEAL, "p": PALE, "y": YELLOW, "s": STRIPE, "c": CORAL, "j": PINK, "l": LILAC, "r": RED,
    "g": GREEN, "h": SHELL, "u": PURPLE, "i": INK, "w": WATER, "f": FOAM, "a": GLASS, "m": STRAP,
    "n": TANK, "e": STEEL, "o": ROCK, "q": CORALPINK,
    "O": (236, 99, 49), "B": (247, 173, 120), "v": (95, 81, 141), "P": (240, 132, 127),
    "T": (36, 112, 102), "S": (96, 183, 170), "C": (197, 237, 219), "G": (148, 167, 126), "I": (128, 86, 211),
}
# Single pixels with no outline round them: eyes, tentacles, a glint, the hose.
THREADS = {"k": (16, 16, 20), "z": (160, 130, 200), "x": (255, 255, 255), "d": (60, 60, 68), "v": (150, 210, 246)}


def outline(colour):
    return mix(colour, (0, 0, 0), 0.76)


# Fish A: Wixel's teal fish, its tail spread (0) and flicked (1).
FISH_A = [
    [
        ".t.....tttt....",
        ".tt..tttttttt..",
        ".ttt.tttttttttt",
        "..tttttttttkkt.",
        "..ttttttttttttt",
        ".ttt.tppppppppt",
        "..t..tpppppp...",
    ],
    [
        ".t.............",
        ".tt..ttttttt...",
        ".tt..tttttttt..",
        "..tttttttttkkt.",
        "..tt.ttttttttttt",
        ".tt..tppppppp..",
        ".t...tppppp....",
    ],
]

# Fish B: Wixel's orange fish, a pale belly, the tail up (0) and down (1).
FISH_B = [
    [
        ".O...OOOOOO..",
        ".OO..OOOOOOO.",
        "..OOOOOOOOOkO",
        "..OOOOOOOOOOO",
        ".OOOOOOBBBOOO",
        ".OO..OBBBBBO.",
        "......BBBBB..",
    ],
    [
        ".....OOOOOO..",
        ".....OOOOOOO.",
        "..OOOOOOOOOkO",
        "..OOOOOOOOOOO",
        ".OOOOOOBBBOOO",
        ".OOO.OBBBBBO.",
        ".O....BBBBB..",
    ],
]

# Fish C: Wixel's slim lilac fish, darker fins, the tail up (0) and down (1).
FISH_C = [
    [
        "v.....vvvvvvv...",
        "vv...vlllllllv..",
        ".lvvlllllllllllv",
        ".lllllllllllkll.",
        "..vvllllllllllv.",
        "......lllllll...",
    ],
    [
        "......vvvvvvv...",
        ".....vlllllllv..",
        ".lvvlllllllllllv",
        ".lllllllllllkll.",
        "vlvvllllllllllv.",
        "vv....lllllll...",
    ],
]

# The jellyfish: Wixel's lilac bell, its tentacles curling one way (0) and the other (1).
JELLY = [
    [
        "...lllll...",
        "..lllllll..",
        ".lllllllll.",
        ".llkllllkl.",
        ".lllllllll.",
        "..lllllll..",
        "..z.z.z.z..",
        ".z.z..z..z.",
        ".z..z.z.z..",
        "..z.z..z.z.",
        "..z..z.z..z",
    ],
    [
        "...........",
        "...lllll...",
        "..lllllll..",
        ".llkllllkl.",
        ".lllllllll.",
        "..lllllll..",
        "...z.z.z.z.",
        "..z..z.z..z",
        "...z.z..z.z",
        "..z..z.z..z",
        ".z..z..z.z.",
    ],
]

# The crab: Wixel's, eyes on top, legs stepping (0); claws raised (1).
CRAB = [
    [
        "..rrrrrrrrrr...",
        ".rrrrrrrrrrrr..",
        ".rrrrrrrkrkrr..",
        "..rrrrrrrrrrr..",
        ".rrrrrrrrrrrr.r",
        "rr.rrrrrr.r.rr.",
        "r...rrrrr.r.rr.",
        "r.rrr...rrr....",
        "...r.....rr....",
    ],
    [
        "rr...........rr",
        "rr.rrrrrrrrr.rr",
        ".rrrrrrrrrrrrr.",
        "..rrrrrrkrkrr..",
        "..rrrrrrrrrrr..",
        "..rrrrrrrrrrr..",
        "..r.r.rr.r.r.r.",
        ".r..r..rr..r...",
    ],
]

# The turtle: Wixel's, from the side, swimming right: a dark shell, pale skin,
# flippers rowing down (0) and swept back (1).
TURTLE = [
    [
        "...TTTTT.......",
        "..TTTTTTT.TSSST",
        ".TTTTTTTTTSSkST",
        "TTTTTTTTTSSSSST",
        ".TTTTTTTTSSCCTT",
        ".TTTTTTCCCTTTT.",
        ".SSSTCCCST.....",
        "TSST..TSST.....",
        "TCT....TSST....",
        "TT......TST....",
        ".........TT....",
    ],
    [
        "...............",
        "...TTTTT.......",
        "..TTTTTTT.TSSST",
        ".TTTTTTTTTSSkST",
        "TTTTTTTTTSSSSST",
        ".TTTTTTTTSSCCTT",
        ".TTTTTTCCCTTTT.",
        "SSSSTCCCSSSS...",
        "TSST...TSSSST..",
        "TT.......TTT...",
        "...............",
    ],
]

# The octopus: Wixel's coral one, arms curled under it (0) and spread wide in a fright (1).
OCTOPUS = [
    [
        "...PPPPPP....",
        "..PPPPPPPP...",
        "..PPPPPPPP...",
        "..PPPPPPPP...",
        "..PPPkPPkP...",
        "...PPPPPPP...",
        "...PPPPPP....",
        ".PPPPPPP.PPP.",
        ".PPPPP.PP.PP.",
        "...PPP.PPP...",
        "...PP...PP...",
    ],
    [
        "...PPPPPP....",
        "..PPPPPPPP...",
        "..PPPPPPPP...",
        "..PPPPPPPP...",
        "..PPPkPPkP...",
        "...PPPPPPP...",
        "P.PPPPPPPP.P.",
        "PPPPPPPPPPPPP",
        "P..PP.PP.PP.P",
        "P.P..P..P..PP",
        ".P..P....P...",
    ],
]

INK_PUFF = [
    "....iii....",
    "..iiiii....",
    "..iIIIii...",
    "iiiiIIiii..",
    "IIIiiiiiii.",
    "IIIiiiiiii.",
    "iiiiiiiiiii",
    "iiiiiiiii..",
    "i.iiiii....",
    "..iiiii....",
    ".iiiii.....",
]

BUBBLES = [
    ["w"],
    [".w.", "wxw", ".w."],
    [".ww.", "wxww", "wwww", ".ww."],
]

# The splash of a diver going in, from Wixel's: a crown of drops (0) and the drops falling back (1).
SPLASH = [
    [
        "...w......w.......w...",
        "....ww....w...w.......",
        ".w...w...fw..ww...w...",
        ".....ww..fw..w...ww...",
        "..w...w..ff.ww..w.....",
        "......wf.ff.wf..w..w..",
        "...ww.wfffffff.ww.....",
        "..wwwffffffffffffww...",
        ".wwwffffffffffffffwww.",
        "..wwwwwwwwwwwwwwwwww..",
    ],
    [
        "......................",
        "..w...............w...",
        "......w.......w.......",
        "...w......w.......w...",
        "......................",
        "....w..f.......f.w....",
        "......ff.......ff.....",
        "..ww.fffff..fffff.ww..",
        ".wwwffffffffffffffwww.",
        "..wwwwwwwwwwwwwwwwww..",
    ],
]

# The scuba gear, laid over a creature's body cell: a mask over the eyes (its
# glass where the eyes are), the strap round the head; a tank on the back with
# its hose. Separate cells, so the tank is drawn behind the body and the mask in front.
MASK = [
    ".......aaaaaaaaaaaaaaa",
    ".......a.............a",
    ".......a......x......a",
    "mmmmmmma.............a",
    "mmmmmmma.............a",
    ".......a.............a",
    ".......a.............a",
    ".......a.............a",
    ".......a.............a",
    ".......aaaaaaaaaaaaaaa",
]
TANK_GLYPH = [
    ".ee.",
    "nnnn",
    "nnnn",
    "nnnn",
    "nnnn",
    "eeee",
    "nnnn",
    "nnnn",
    "nnnn",
    "nnnn",
    "nnnn",
    ".nn.",
]

# A coral clump and a rock, for the floor between the seaweed.
CORAL_CLUMP = [
    "....qq..............",
    "....oqq.............",
    "qq...oq.............",
    "qq..ooq..q..........",
    ".qq...q.qq..o.......",
    "..qq.qqqq....G......",
    "..oq.qqqo..GG.......",
    "qoqoqqqq....Go..oqq.",
    "ooqqqqq.....GG..q.q.",
    "..ooqqq.oo..GG..qqq.",
    "....qqq.Goo.oqo.qq.G",
    "...oqoGGGGo.q.q.q.GG",
    "..GoGGooGGGGG.q.GGG.",
    ".GGoGGooGGGGoooGGGG.",
    ".GGoGooGGGGGooGGGGG.",
    "...ooooooGGGooooooo.",
]


def paint_glyph(img: Image.Image, cx: int, cy: int, glyph: list[str], ox: int, oy: int) -> None:
    """As the play props are painted, with the sea's materials."""
    saved = play.MATERIALS, play.THREADS
    play.MATERIALS, play.THREADS = MATERIALS, THREADS
    try:
        play.paint_glyph(img, cx, cy, glyph, ox, oy)
    finally:
        play.MATERIALS, play.THREADS = saved


def centred(glyph: list[str]) -> tuple[int, int]:
    w, h = max(len(r) for r in glyph), len(glyph)
    return (CELL_W - w) // 2, (CELL_H - h) // 2


# Where the gear sits in its cell, so that laid over a 32x28 cell centred on the
# body (a 22-px body box from (5, 5) of a 32x32 creature cell) the glass covers
# the eyes, right of centre a quarter down, and the tank hangs on the back.
MASK_AT = (4, 6)
TANK_AT = (1, 8)


def glyph_for(pose: str) -> tuple[list[str], tuple[int, int] | None]:
    name, _, frame = pose.rpartition("-")
    tables = {"fish-a": FISH_A, "fish-b": FISH_B, "fish-c": FISH_C, "jelly": JELLY, "crab": CRAB,
              "turtle": TURTLE, "octopus": OCTOPUS, "splash": SPLASH, "bubble": BUBBLES}
    if name in tables and frame.isdigit():
        return tables[name][int(frame)], None
    fixed = {"ink": (INK_PUFF, None), "mask": (MASK, MASK_AT), "tank": (TANK_GLYPH, TANK_AT), "coral": (CORAL_CLUMP, None)}
    if pose in fixed:
        return fixed[pose]
    raise ValueError(f"the sea painter cannot draw {pose!r}")


def paint(recipe: Recipe) -> Image.Image:
    if tuple(recipe.cell) != (CELL_W, CELL_H):
        raise ValueError(f"the sea needs a {CELL_W}x{CELL_H} cell, got {recipe.cell}")
    img = Image.new("RGB", recipe.size, recipe.background)
    for col, row, pose, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        glyph, at = glyph_for(pose)
        paint_glyph(img, cx, cy, glyph, *(at or centred(glyph)))
    return img
