"""beds — one little bed for every built-in character, built the way the
creature is: flat blocks, a 1px outline that is a dark tint of each block's own
colour, a light line along the top and left, a shade line along the bottom and
right. Round things (a cushion, a cloud, a pot) get stepped corners, never curves.

Every bed is 36 wide and 16 tall against a creature's 22 px body, standing on
the floor of its cell. The sleeper is drawn IN FRONT of its bed, centred and
lifted to the bed's `LIFT` (pixels above the floor its feet rest on), so what
shows is the mattress under its feet and whatever rises at the two ends: a
headboard, a basket's rim, grass. `LIFT` is read by the app (`Beds.Kind.lift`);
keep the two in step.
"""

from __future__ import annotations

from PIL import Image, ImageDraw

from ..recipe import Recipe
from .house import block, mix, shades

GLYPH_W, GLYPH_H = 36, 16
F = GLYPH_H            # the floor: one row below the last
EYE = (0, 0, 0)


def flat(draw, x0, y0, x1, y1, colour) -> None:
    """A plain fill of [x0, x1) x [y0, y1): a stripe, a pip, a stitch."""
    if x1 > x0 and y1 > y0:
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=colour)


def dot(draw, x, y, colour) -> None:
    draw.point((x, y), fill=colour)


def outline(colour):
    return shades(colour)["outline"]


def rounded(draw, ox, oy, x0, y0, x1, y1, colour, bg) -> None:
    """A block with its four corners stepped off: one pixel of background at the
    corner, the outline moved one pixel in, so the rim stays unbroken. Glyph
    coordinates, from the glyph's top-left at (ox, oy)."""
    block(draw, ox + x0, oy + y0, ox + x1, oy + y1, colour)
    o = outline(colour)
    for cx, cy, ix, iy in ((x0, y0, x0 + 1, y0 + 1), (x1 - 1, y0, x1 - 2, y0 + 1),
                           (x0, y1 - 1, x0 + 1, y1 - 2), (x1 - 1, y1 - 1, x1 - 2, y1 - 2)):
        dot(draw, ox + cx, oy + cy, bg)
        dot(draw, ox + ix, oy + iy, o)


# ---------------------------------------------------------------- the beds
# Each painter draws one bed with its glyph's top-left at (ox, oy); `bg` is the
# key colour, for stepping corners off.

WOOD = (176, 112, 62)
STRAW = (238, 206, 104)


def crate(d, ox, oy, bg):
    """Blocky: a sturdy wooden crate stuffed with straw. Square, like him."""
    f = oy + F
    for x in (3, 9, 16, 22, 28):
        flat(d, ox + x, f - 9, ox + x + 1, f - 6, STRAW)          # straw poking up over the rim
        dot(d, ox + x + 1, f - 10, STRAW)
    block(d, ox + 1, f - 7, ox + 35, f, WOOD)
    flat(d, ox + 2, f - 4, ox + 34, f - 3, outline(WOOD))       # the plank seam
    block(d, ox + 1, f - 11, ox + 5, f, WOOD)                   # corner posts
    block(d, ox + 31, f - 11, ox + 35, f, WOOD)


def hammock(d, ox, oy, bg):
    """Pip: a striped hammock slung between two posts, for swinging and laughing."""
    f = oy + F
    post = (150, 98, 58)
    block(d, ox, f - 15, ox + 4, f, post)
    block(d, ox + 32, f - 15, ox + 36, f, post)
    rope = outline(post)
    for k in range(4):                                           # ropes stepping down to the cloth
        dot(d, ox + 4 + k, f - 13 + k, rope)
        dot(d, ox + 31 - k, f - 13 + k, rope)
    block(d, ox + 6, f - 9, ox + 30, f - 4, (236, 92, 84))
    for x in range(10, 28, 6):
        flat(d, ox + x, f - 8, ox + x + 3, f - 5, (250, 244, 232))  # stripes
    flat(d, ox + 6, f - 9, ox + 8, f - 8, bg)                    # the cloth's ends lift a step
    flat(d, ox + 28, f - 9, ox + 30, f - 8, bg)


def quilt(d, ox, oy, bg):
    """Mortimer: an old patchwork quilt on a low mattress, a pillow at one end."""
    f = oy + F
    block(d, ox + 1, f - 6, ox + 35, f, (226, 214, 190))
    colours = [(196, 92, 84), (96, 140, 196), (232, 196, 96), (120, 170, 110)]
    for k, x in enumerate(range(9, 33, 6)):
        flat(d, ox + x, f - 5, ox + x + 6, f - 2, colours[k % 4])
        flat(d, ox + x, f - 2, ox + x + 6, f - 1, mix(colours[(k + 2) % 4], (0, 0, 0), 0.17))
    block(d, ox + 1, f - 11, ox + 10, f - 5, (246, 244, 236))    # the pillow
    dot(d, ox + 1, f - 11, bg); dot(d, ox + 2, f - 10, outline((246, 244, 236)))
    dot(d, ox + 9, f - 11, bg); dot(d, ox + 8, f - 10, outline((246, 244, 236)))


def pillow(d, ox, oy, bg):
    """Zed: the biggest, fluffiest pillow there is, with a stitched seam. For napping."""
    f = oy + F
    blue = (176, 200, 240)
    block(d, ox + 1, f - 8, ox + 35, f, blue)
    for cx, cy, ix, iy in ((1, f - 8, 2, f - 7), (34, f - 8, 33, f - 7), (1, f - 1, 2, f - 2), (34, f - 1, 33, f - 2)):
        dot(d, ox + cx, cy, bg); dot(d, ox + ix, iy, outline(blue))
    for x in range(4, 33, 3):
        dot(d, ox + x, f - 4, shades(blue)["shade"])             # the seam
    # Two corner tufts, and a sleepy little moon on the side.
    flat(d, ox, f - 9, ox + 2, f - 8, outline(blue))
    flat(d, ox + 34, f - 9, ox + 36, f - 8, outline(blue))
    flat(d, ox + 30, f - 7, ox + 32, f - 5, (250, 220, 90))
    dot(d, ox + 31, f - 6, blue)


def matchbox(d, ox, oy, bg):
    """Dot: a matchbox tray, because Dot is tiny. A match laid in for a pillow."""
    f = oy + F
    red = (214, 70, 52)
    block(d, ox + 5, f - 6, ox + 31, f, red)
    flat(d, ox + 6, f - 3, ox + 30, f - 2, (120, 70, 50))        # the striker
    flat(d, ox + 8, f - 5, ox + 12, f - 4, (250, 236, 120))     # the label's star
    block(d, ox + 2, f - 8, ox + 9, f - 5, (232, 200, 150))     # the match
    flat(d, ox + 2, f - 8, ox + 5, f - 5, (200, 40, 40))


def bed(d, ox, oy, bg):
    """Ruth: a proper little bed, neatly made, the blanket folded back square."""
    f = oy + F
    frame = (130, 88, 60)
    block(d, ox, f - 15, ox + 5, f, frame)                      # headboard
    block(d, ox + 31, f - 10, ox + 36, f, frame)                # footboard
    block(d, ox + 4, f - 6, ox + 32, f - 2, (248, 248, 244))    # the mattress, white sheet
    block(d, ox + 13, f - 7, ox + 32, f - 2, (110, 170, 120))   # blanket
    flat(d, ox + 13, f - 6, ox + 15, f - 3, (248, 248, 244))    # folded back
    block(d, ox + 5, f - 9, ox + 12, f - 6, (248, 248, 244))    # pillow
    flat(d, ox + 6, f - 2, ox + 8, f, outline(frame))           # legs
    flat(d, ox + 28, f - 2, ox + 30, f, outline(frame))


def box(d, ox, oy, bg):
    """Whiskers: a cardboard box. It is not for sleeping in. It is being slept in."""
    f = oy + F
    card = (200, 160, 110)
    block(d, ox + 3, f - 10, ox + 33, f, card)
    block(d, ox, f - 13, ox + 6, f - 9, card)                  # flaps, open
    block(d, ox + 30, f - 13, ox + 36, f - 9, card)
    flat(d, ox + 4, f - 5, ox + 32, f - 4, (226, 210, 160))    # tape


def catbed(d, ox, oy, bg):
    """Mittens: a round basket bed with a warm cream cushion. The warm side."""
    f = oy + F
    rim = (200, 120, 170)
    rounded(d, ox, oy, 1, F - 11, 8, F, rim, bg)
    rounded(d, ox, oy, 28, F - 11, 35, F, rim, bg)
    block(d, ox + 3, f - 6, ox + 33, f, rim)
    block(d, ox + 6, f - 8, ox + 30, f - 4, (250, 236, 206))   # the cushion
    for x in (4, 31):
        dot(d, ox + x, f - 8, (250, 236, 206))                  # a paw print stitched on the rim
    flat(d, ox + 10, f - 3, ox + 26, f - 2, shades(rim)["light"])


def cushion(d, ox, oy, bg):
    """Sir Pounce: a royal red cushion, gold piping, a tassel at each corner."""
    f = oy + F
    red, gold = (176, 36, 52), (240, 196, 70)
    block(d, ox + 3, f - 7, ox + 33, f, red)
    flat(d, ox + 4, f - 4, ox + 32, f - 3, gold)
    for x in (0, 33):
        block(d, ox + x, f - 10, ox + x + 3, f - 6, gold)
        flat(d, ox + x + 1, f - 6, ox + x + 2, f - 3, outline(gold))
    dot(d, ox + 17, f - 8, gold); dot(d, ox + 18, f - 8, gold)  # a crown pip


def lilypad(d, ox, oy, bg):
    """Hopper: a lily pad on a strip of pond, with a pink flower to brag about."""
    f = oy + F
    water, pad = (90, 150, 214), (96, 176, 84)
    flat(d, ox + 1, f - 2, ox + 35, f, water)
    flat(d, ox + 6, f - 1, ox + 10, f, shades(water)["light"])
    block(d, ox + 2, f - 5, ox + 34, f - 1, pad)
    flat(d, ox + 20, f - 5, ox + 22, f - 3, bg)                # the notch
    dot(d, ox + 20, f - 3, outline(pad)); dot(d, ox + 21, f - 3, outline(pad))
    block(d, ox + 28, f - 9, ox + 34, f - 5, (240, 130, 176))  # the flower
    flat(d, ox + 30, f - 8, ox + 32, f - 7, (250, 220, 90))


def moss(d, ox, oy, bg):
    """Mossy: a soft green mound of moss, lumpy, a pebble at its foot."""
    f = oy + F
    green = (92, 150, 72)
    block(d, ox + 2, f - 6, ox + 34, f, green)
    block(d, ox + 1, f - 9, ox + 11, f - 5, green)
    block(d, ox + 25, f - 8, ox + 35, f - 5, green)
    for x, y in ((5, 3), (12, 2), (19, 3), (27, 2), (30, 4), (8, 1)):
        dot(d, ox + x, f - y, shades(green)["light"])
    block(d, ox + 13, f - 3, ox + 18, f, (150, 150, 162))


def puddle(d, ox, oy, bg):
    """Croak: a puddle, finally. Wet. And a bulrush to lean on."""
    f = oy + F
    water, reed = (82, 140, 210), (110, 150, 70)
    block(d, ox + 1, f - 3, ox + 35, f, water)
    for x in (6, 15, 24):
        flat(d, ox + x, f - 2, ox + x + 3, f - 1, shades(water)["light"])
    flat(d, ox + 32, f - 13, ox + 33, f - 3, reed)
    block(d, ox + 31, f - 15, ox + 35, f - 9, (130, 84, 52))   # the bulrush head


def cloud(d, ox, oy, bg):
    """Boo: a little cloud to float on. Spooky, if you squint. Do not squint."""
    f = oy + F
    white = (244, 246, 252)
    rounded(d, ox, oy, 1, F - 7, 35, F, white, bg)
    rounded(d, ox, oy, 2, F - 11, 10, F - 5, white, bg)
    rounded(d, ox, oy, 26, F - 12, 34, F - 5, white, bg)
    flat(d, ox + 3, f - 5, ox + 33, f - 4, white)              # one cloud, not three blocks
    flat(d, ox + 3, f - 6, ox + 9, f - 5, white)
    flat(d, ox + 27, f - 6, ox + 33, f - 5, white)


def leaf(d, ox, oy, bg):
    """Wisp: a big autumn leaf, fallen from a tree it remembers."""
    f = oy + F
    orange = (232, 132, 52)
    block(d, ox + 3, f - 5, ox + 33, f, orange)
    block(d, ox + 8, f - 7, ox + 27, f - 4, orange)
    flat(d, ox + 4, f - 3, ox + 32, f - 2, shades(orange)["shade"])  # the middle vein
    for x in (10, 17, 24):
        dot(d, ox + x, f - 4, shades(orange)["shade"])
    flat(d, ox + 33, f - 3, ox + 36, f - 2, (120, 80, 40))     # the stalk
    dot(d, ox + 3, f - 5, bg); dot(d, ox + 4, f - 4, outline(orange))


def blanket(d, ox, oy, bg):
    """Sheet: a folded check blanket. Technically a bed. Technically."""
    f = oy + F
    base, check = (230, 226, 216), (110, 130, 200)
    block(d, ox + 2, f - 7, ox + 34, f, base)
    for x in range(4, 32, 4):
        flat(d, ox + x, f - 6, ox + x + 2, f - 1, check)
    flat(d, ox + 3, f - 4, ox + 33, f - 3, check)
    flat(d, ox + 3, f - 4, ox + 33, f - 3, mix(check, (255, 255, 255), 0.3))
    block(d, ox + 2, f - 10, ox + 12, f - 6, base)            # the folded corner
    flat(d, ox + 4, f - 9, ox + 6, f - 7, check)
    flat(d, ox + 8, f - 9, ox + 10, f - 7, check)


def log(d, ox, oy, bg):
    """Morel: a slice of old log, its rings at one end, a tiny mushroom sprouting."""
    f = oy + F
    bark, ring = (120, 84, 56), (214, 176, 120)
    block(d, ox + 6, f - 7, ox + 35, f, bark)
    for x in (12, 20, 28):
        flat(d, ox + x, f - 5, ox + x + 3, f - 4, outline(bark))
    rounded(d, ox, oy, 1, F - 8, 10, F, ring, bg)
    flat(d, ox + 4, f - 5, ox + 7, f - 3, shades(ring)["shade"])  # the rings
    dot(d, ox + 5, f - 4, ring)
    block(d, ox + 29, f - 12, ox + 35, f - 9, (214, 64, 60))   # the mushroom's cap
    flat(d, ox + 31, f - 9, ox + 33, f - 7, (240, 230, 210))
    dot(d, ox + 31, f - 11, (250, 250, 245))


def grass(d, ox, oy, bg):
    """Puff: a tuft of soft grass with a daisy in it. Nice to giggle in."""
    f = oy + F
    green, dark = (110, 186, 80), (74, 140, 60)
    block(d, ox + 1, f - 4, ox + 35, f, green)
    for x, h in ((1, 9), (3, 12), (5, 8), (7, 10), (28, 10), (30, 13), (32, 8), (34, 11)):
        flat(d, ox + x, f - h, ox + x + 1, f - 3, dark)
        dot(d, ox + x, f - h, green)
    for x in range(9, 28, 3):
        dot(d, ox + x, f - 5, dark)
    flat(d, ox + 30, f - 14, ox + 33, f - 13, (250, 250, 245))  # the daisy on top
    dot(d, ox + 31, f - 15, (250, 250, 245)); dot(d, ox + 31, f - 13, (250, 210, 60))


def flowerpot(d, ox, oy, bg):
    """Cap: a terracotta pot of good dark soil, the way they did it in his day."""
    f = oy + F
    clay, soil = (206, 112, 70), (90, 60, 44)
    block(d, ox + 5, f - 6, ox + 31, f, clay)
    block(d, ox + 2, f - 10, ox + 34, f - 6, clay)
    flat(d, ox + 4, f - 10, ox + 32, f - 9, soil)
    flat(d, ox + 3, f - 11, ox + 33, f - 10, soil)
    flat(d, ox + 3, f - 12, ox + 6, f - 11, (110, 186, 80))     # a sprout
    flat(d, ox + 31, f - 13, ox + 32, f - 11, (110, 186, 80))


def dock(d, ox, oy, bg):
    """Unit 7: a charging dock. Green lights: 3 of 3. Charge: in progress."""
    f = oy + F
    grey, green = (150, 156, 170), (90, 220, 110)
    block(d, ox + 1, f - 5, ox + 35, f, grey)
    for x in (5, 9, 13):
        flat(d, ox + x, f - 3, ox + x + 2, f - 2, green)
    block(d, ox, f - 12, ox + 5, f - 4, grey)                  # the two charging posts
    block(d, ox + 31, f - 12, ox + 36, f - 4, grey)
    for x in (2, 33):
        flat(d, ox + x, f - 10, ox + x + 1, f - 8, (250, 220, 90))
    flat(d, ox + 24, f - 3, ox + 30, f - 2, (60, 64, 76))       # the cable slot


def toolbox(d, ox, oy, bg):
    """Sprocket: a red toolbox, every bolt tightened, a spanner left out."""
    f = oy + F
    red, steel = (204, 56, 48), (170, 176, 190)
    block(d, ox + 3, f - 8, ox + 33, f, red)
    flat(d, ox + 4, f - 5, ox + 32, f - 4, outline(red))       # the lid's line
    for x in (8, 26):
        block(d, ox + x, f - 6, ox + x + 3, f - 3, steel)       # latches
    block(d, ox + 30, f - 11, ox + 36, f - 8, steel)            # the spanner
    dot(d, ox + 35, f - 11, bg); dot(d, ox + 35, f - 9, bg)


def spacebar(d, ox, oy, bg):
    """Glitch: a big spacebar keycap. Press press to sleep."""
    f = oy + F
    key, top = (120, 124, 140), (196, 200, 214)
    block(d, ox + 1, f - 7, ox + 35, f, key)
    block(d, ox + 4, f - 9, ox + 32, f - 4, top)
    flat(d, ox + 6, f - 2, ox + 30, f - 1, (90, 240, 160))      # a glow underneath, glitchy
    flat(d, ox + 12, f - 2, ox + 14, f - 1, key)


def sponge(d, ox, oy, bg):
    """Goop: a sponge, green scrubby side up. Nice. Sticky. Nice."""
    f = oy + F
    yellow, green = (246, 210, 80), (80, 168, 96)
    block(d, ox + 3, f - 8, ox + 33, f, yellow)
    flat(d, ox + 4, f - 7, ox + 32, f - 5, green)
    for x, y in ((7, 3), (13, 2), (19, 3), (25, 2), (29, 3), (10, 4)):
        dot(d, ox + x, f - y, shades(yellow)["shade"])


def teacup(d, ox, oy, bg):
    """Puddle: a teacup on its saucer. Never dries out, never gets stepped on."""
    f = oy + F
    china, band = (244, 240, 228), (110, 150, 220)
    block(d, ox + 1, f - 3, ox + 35, f, china)                 # saucer
    block(d, ox + 5, f - 11, ox + 31, f - 1, china)
    flat(d, ox + 6, f - 8, ox + 30, f - 7, band)
    flat(d, ox + 6, f - 10, ox + 30, f - 9, (150, 84, 40))      # tea at the brim
    d.rectangle([ox + 31, f - 9, ox + 34, f - 4], outline=outline(china))  # the handle, an open ring


def bubblewrap(d, ox, oy, bg):
    """Blorp: a sheet of bubble wrap. Pop. Pop. Blorp."""
    f = oy + F
    wrap = (186, 222, 240)
    block(d, ox + 1, f - 4, ox + 35, f, wrap)
    for x in range(2, 34, 4):
        block(d, ox + x, f - 7, ox + x + 4, f - 3, wrap)
        dot(d, ox + x + 1, f - 6, (255, 255, 255))


def pincushion(d, ox, oy, bg):
    """Spike: a tomato pincushion. The pins make the point."""
    f = oy + F
    red, steel = (214, 60, 60), (190, 196, 210)
    for x, h, head in ((3, 13, (250, 210, 60)), (7, 11, (96, 134, 232)), (29, 12, (240, 110, 160)), (33, 14, (110, 186, 80))):
        flat(d, ox + x, f - h, ox + x + 1, f - 6, steel)
        flat(d, ox + x - 1, f - h - 1, ox + x + 1, f - h + 1, head)
    rounded(d, ox, oy, 1, F - 8, 35, F, red, bg)
    for x in (9, 18, 27):
        flat(d, ox + x, f - 7, ox + x + 1, f - 1, shades(red)["shade"])
    flat(d, ox + 16, f - 9, ox + 20, f - 8, (80, 160, 70))      # the leaf on top


def books(d, ox, oy, bg):
    """Wedge: a stack of three thick books. Stable. Will not be tipped over."""
    f = oy + F
    block(d, ox + 1, f - 3, ox + 33, f, (60, 100, 170))
    block(d, ox + 3, f - 6, ox + 35, f - 3, (176, 56, 56))
    block(d, ox + 2, f - 9, ox + 32, f - 6, (90, 150, 90))
    for y in (2, 5, 8):
        flat(d, ox + 30, f - y, ox + 32, f - y + 1, (244, 240, 228))  # the pages' edge


def sock(d, ox, oy, bg):
    """Delta: one striped sock, lying down. Its pair moved. Delta noticed."""
    f = oy + F
    base, stripe = (240, 236, 226), (120, 96, 200)
    block(d, ox + 1, f - 6, ox + 30, f, base)
    block(d, ox + 26, f - 7, ox + 35, f, base)                # the toe
    for x in range(4, 26, 5):
        flat(d, ox + x, f - 5, ox + x + 2, f - 1, stripe)
    flat(d, ox + 27, f - 6, ox + 34, f - 4, (236, 92, 84))     # a red toe cap
    dot(d, ox + 34, f - 7, bg); dot(d, ox + 33, f - 6, outline(base))


BEDS = {
    "crate": crate, "hammock": hammock, "quilt": quilt, "pillow": pillow, "matchbox": matchbox,
    "bed": bed, "box": box, "catbed": catbed, "cushion": cushion, "lilypad": lilypad, "moss": moss,
    "puddle": puddle, "cloud": cloud, "leaf": leaf, "blanket": blanket, "log": log, "grass": grass,
    "flowerpot": flowerpot, "dock": dock, "toolbox": toolbox, "spacebar": spacebar, "sponge": sponge,
    "teacup": teacup, "bubblewrap": bubblewrap, "pincushion": pincushion, "books": books, "sock": sock,
}

# Pixels above the floor the sleeper's feet rest on: the top of the mattress.
LIFT = {
    "crate": 6, "hammock": 8, "quilt": 5, "pillow": 7, "matchbox": 5, "bed": 6, "box": 3, "catbed": 6,
    "cushion": 6, "lilypad": 4, "moss": 5, "puddle": 2, "cloud": 6, "leaf": 4, "blanket": 6, "log": 6,
    "grass": 3, "flowerpot": 10, "dock": 4, "toolbox": 7, "spacebar": 8, "sponge": 7, "teacup": 9,
    "bubblewrap": 6, "pincushion": 7, "books": 8, "sock": 6,
}


def paint(recipe: Recipe) -> Image.Image:
    missing = [p for p, _ in recipe.poses if p not in BEDS]
    if missing:
        raise ValueError(f"the beds painter cannot draw {missing}")
    bx, by, bw, bh = recipe.content_box
    if (bw, bh) != (GLYPH_W, GLYPH_H):
        raise ValueError(f"a bed needs a {GLYPH_W}x{GLYPH_H} content box, got {bw}x{bh}")
    img = Image.new("RGB", recipe.size, recipe.background)
    draw = ImageDraw.Draw(img)
    for col, row, pose, _ in recipe.cells():
        cx, cy, _, _ = recipe.cell_rect(col, row)
        BEDS[pose](draw, cx + bx, cy + by, recipe.background)
    return img
