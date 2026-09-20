"""The built-in creatures, written in the app's letter format.

Each creature is a solid shape per pose; the outline, the light line (top and
left) and the shade line (bottom and right) are derived from the shape, the
same rule the built-in square and the house follow. Details (eyes `k`, black
`x`) go on top. Run it to rewrite the .txt files next to it:

    python3 sprites/text/make.py

The app rebuilds its shipped sheets from these with
    LEDGELINGS_BUILD_CREATURES=1 swift test --filter ShippedCreaturesTests
"""

from __future__ import annotations

import math
from pathlib import Path

W = 32
L, R, TOP, FLOOR = 5, 26, 5, 26          # the body box, 0-based, inclusive; FLOOR is the last row with ink
POSES = ["idle", "walk-0", "walk-1", "walk-2", "walk-3", "jump", "land", "sleep-0", "sleep-1"]


def style(mask: set, details: dict, feet: set) -> list[str]:
    """Solid mask → outline / light / shade / body, then details and feet."""
    g = [["."] * W for _ in range(W)]
    def inside(x, y): return (x, y) in mask
    for (x, y) in mask:
        edge = not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1))
        g[y][x] = "o" if edge else "b"
    for (x, y) in mask:
        if g[y][x] != "b":
            continue
        if g[y - 1][x] == "o" or g[y][x - 1] == "o":
            g[y][x] = "l"
        elif g[y + 1][x] == "o" or g[y][x + 1] == "o":
            g[y][x] = "s"
    for (x, y), ch in details.items():
        g[y][x] = ch
    for (x, y) in feet:
        g[y][x] = "o"
    return ["".join(r) for r in g]


def rect(x0, y0, x1, y1):
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}


def dome(cx, top, bottom, half_w):
    """A rounded top over a flat-sided body."""
    pts = set()
    height = bottom - top + 1
    for y in range(top, bottom + 1):
        t = (y - top) / max(1, height - 1)
        w = half_w if t > 0.45 else int(round(half_w * (0.35 + 0.65 * (t / 0.45) ** 0.5)))
        pts |= {(x, y) for x in range(cx - w, cx + w + 1)}
    return pts


def eyes(cx, y, h, gap=4, w=2):
    return {(x, yy): "k" for yy in range(y, y + h) for x in list(range(cx - gap - w + 1, cx - gap + 1)) + list(range(cx + gap, cx + gap + w))}


def line(x0, x1, y, ch="x"):
    return {(x, y): ch for x in range(x0, x1 + 1)}


def feet_at(left, right, y=FLOOR, size=4, lx=7, rx=None):
    f = set()
    if left: f |= {(x, y) for x in range(lx, lx + size)}
    if right:
        rx = 25 - size if rx is None else rx
        f |= {(x, y) for x in range(rx, rx + size)}
    return f


def ellipse(cx, cy, rx, ry):
    return {(x, y) for x in range(cx - rx, cx + rx + 1) for y in range(cy - ry, cy + ry + 1)
            if ((x - cx) / (rx + 0.5)) ** 2 + ((y - cy) / (ry + 0.5)) ** 2 <= 1}


def ring(cx, cy, rx, ry, inner, outer, degrees, ch="o"):
    """Pixels of an ellipse between two fractions of its radius, within a span of
    screen angles (clockwise from 3 o'clock, since y points down)."""
    lo, hi = degrees
    out = {}
    for x in range(cx - rx, cx + rx + 1):
        for y in range(cy - ry, cy + ry + 1):
            d = math.hypot((x - cx) / (rx + 0.5), (y - cy) / (ry + 0.5))
            a = math.degrees(math.atan2(y - cy, x - cx)) % 360
            if inner <= d <= outer and (lo <= a <= hi or (lo > hi and (a >= lo or a <= hi))):
                out[(x, y)] = ch
    return out


# ---- creatures: pose → (mask, details, feet). Squash/stretch by moving the top.

def frog(top, bottom, lf, rf, eye_h=3, mouth=True):
    body = rect(L, top, R, bottom)
    bumps = rect(8, top - 4, 11, top) | rect(20, top - 4, 23, top)
    d = eyes(10, top - 3, eye_h, gap=0, w=2) | eyes(22, top - 3, eye_h, gap=0, w=2)
    if mouth: d |= line(10, 21, bottom - 4)
    return body | bumps, d, feet_at(lf, rf)


def cat(top, bottom, lf, rf, eye_h=3):
    body = rect(L + 1, top, R - 1, bottom)
    ears = set()
    for k in range(6):                                   # two triangles growing down onto the body
        ears |= rect(L + 1, top - 5 + k, L + 1 + k, top - 5 + k)
        ears |= rect(R - 1 - k, top - 5 + k, R - 1, top - 5 + k)
    eye_y = min(top + 4, bottom - 5)
    d = eyes(16, eye_y, eye_h, gap=3, w=2)
    d |= {(15, eye_y + 4): "x", (16, eye_y + 4): "x"}                  # nose
    for wy in (eye_y + 3, eye_y + 5):                                   # whisker stubs
        d |= line(L + 2, L + 4, wy) | line(R - 4, R - 2, wy)
    return body | ears, d, feet_at(lf, rf, size=3)


def ghost(top, bottom, wave):
    body = dome(16, top, bottom, 10)
    # a wavy hem: every other 4px tooth on the bottom row is cut away
    hem = {(x, bottom) for x in range(6, 27) if ((x + wave) // 4) % 2 == 0}
    body -= hem
    d = eyes(16, top + 7, 4, gap=3, w=3)
    d |= {(14, top + 13): "x", (15, top + 13): "x", (16, top + 13): "x", (17, top + 13): "x"}
    return body, d, set()


def slime(top, bottom, lf, rf, eye_h=2):
    body = dome(16, top, bottom, 10)
    body |= rect(L, bottom - 3, R, bottom)
    drip = rect(23, top + 3, 24, min(top + 7, bottom))
    eye_y = min(top + 6, bottom - 5)
    d = eyes(16, eye_y, eye_h, gap=3, w=2)
    d |= line(13, 19, eye_y + eye_h + 1)
    return body | drip, d, feet_at(lf, rf, size=2)


def robot(top, bottom, lf, rf, eye_h=3):
    body = rect(L + 1, top, R - 1, bottom)
    antenna = rect(15, top - 5, 16, top)
    d = {(15, top - 5): "x", (16, top - 5): "x"}
    eye_y = min(top + 4, bottom - 6)
    d |= eyes(16, eye_y, eye_h, gap=3, w=3)
    d |= line(11, 20, eye_y + eye_h + 2)                                 # a slot mouth
    d |= {(x, bottom - 2): "x" for x in range(9, 24, 3)}                 # a row of rivets
    return body | antenna, d, feet_at(lf, rf, size=3)


# ---- the blocky rules, for creatures that are squares with something on them.

def cut_rect(x0, y0, x1, y1, cuts=()):
    """A rectangle with its corners stepped off: cuts[i] pixels on row i from the top and the bottom."""
    pts = rect(x0, y0, x1, y1)
    for i, c in enumerate(cuts):
        for y in (y0 + i, y1 - i):
            pts -= {(x, y) for x in range(x0, x0 + c)} | {(x, y) for x in range(x1 - c + 1, x1 + 1)}
    return pts


def blocky_eyes(top, height, eye_h=None):
    """Two 3-wide black eyes right of centre, a quarter of the way down, like the built-in square."""
    h = eye_h if eye_h else max(3, min(6, height // 3))
    return eyes(18, top + max(3, height // 4), h, gap=2, w=3)


def blocky_feet(left, right, bottom):
    """Two 4×2 blocks under the body; a raised foot loses its lower row. None = tucked away."""
    f = set()
    for x0, up in ((8, left), (20, right)):
        if up is None: continue
        y = bottom + (0 if up else 1)
        f |= rect(x0, y, x0 + 3, y + 1)
    return f


def rabbit(top, bottom, lf, rf, ear_h=8, lean=0, eye_h=None):
    """The square with two tall ears; `lean` bends the ears back by that many pixels at the tip."""
    body = rect(L, top, R, bottom)
    ears, d = set(), {}
    for k in range(ear_h):
        y = top - 1 - k
        dx = -round(lean * k / max(1, ear_h - 1))
        ears |= rect(8 + dx, y, 12 + dx, y) | rect(19 + dx, y, 23 + dx, y)
    height = bottom - top + 1
    d |= blocky_eyes(top, height, eye_h)
    eye_bottom = top + max(3, height // 4) + (eye_h or max(3, min(6, height // 3)))
    if eye_bottom + 3 <= bottom - 1:
        d |= line(14, 21, eye_bottom + 1)                                   # mouth
        d |= {(x, y): "l" for x in (16, 17, 19, 20) for y in (eye_bottom + 2, eye_bottom + 3)}   # two big teeth
    return body | ears, d, blocky_feet(lf, rf, bottom)


def pig(top, bottom, lf, rf, eye_h=None):
    """The square with two ear blocks on top and a snout block on its face."""
    body = rect(L, top, R, bottom)
    ears = rect(6, top - 3, 9, top) | rect(22, top - 3, 25, top)
    height = bottom - top + 1
    d = blocky_eyes(top, height, eye_h)
    sy = top + max(3, height // 4) + (eye_h or max(3, min(6, height // 3))) + 1
    if sy + 3 <= bottom - 1:                                                # the snout: an outlined block with two nostrils
        d |= {(x, y): "o" for x in range(13, 22) for y in (sy, sy + 3)}
        d |= {(x, y): "o" for x in (13, 21) for y in (sy + 1, sy + 2)}
        d |= {(x, y): "b" for x in range(14, 21) for y in (sy + 1, sy + 2)}
        d |= {(x, y): "x" for x in (15, 16, 18, 19) for y in (sy + 1, sy + 2)}
    elif sy + 1 <= bottom - 1:
        d |= {(x, y): "x" for x in (15, 16, 18, 19) for y in (sy, sy + 1)}
    return body | ears, d, blocky_feet(lf, rf, bottom)


def triangle(top, bottom, lf, rf, lean=0, band=3, widths=(1, 3, 5, 7, 9, 10, 10), eye_h=None):
    """A stepped pyramid: bands of `band` rows, each wider than the one above. `lean` shifts the upper bands sideways."""
    mask, eye_y = set(), None
    bands = (bottom - top) // band + 1
    for y in range(top, bottom + 1):
        i = (y - top) // band
        hw = widths[min(i, len(widths) - 1)]
        cx = 16 + round(lean * (1 - i / max(1, bands - 1)))
        mask |= rect(cx - hw, y, cx + hw, y)
        if eye_y is None and hw >= 7:
            eye_y = y + 1
    height = bottom - top + 1
    h = eye_h or max(3, min(6, height // 3))
    d = eyes(18, min(eye_y, bottom - h - 1), h, gap=2, w=3)
    return mask, d, blocky_feet(lf, rf, bottom)


def ball(top, bottom, x0=L, x1=R, corner=0, cuts=(6, 4, 3, 2, 1, 1), eye_h=None):
    """A square with its corners stepped off, and a dark panel that moves round the corners as it rolls."""
    body = cut_rect(x0, top, x1, bottom, cuts)
    height = bottom - top + 1
    px = (x1 - 7, x1 - 7, x0 + 3, x0 + 3)[corner]
    py = (top + 2, bottom - 6, bottom - 6, top + 2)[corner]
    d = {(x, y): "s" for x in range(px, px + 5) for y in range(py, py + 5) if (x, y) in body}
    d |= {(x, y): "o" for x in range(px + 1, px + 4) for y in range(py + 1, py + 4) if (x, y) in body}
    d |= blocky_eyes(top, height, eye_h)
    return body, d, set()


def mushroom(top, cap_h, bottom, lf, rf, eye_h=None):
    """A wide flat cap with stepped corners on a pale stem; the eyes are on the stem."""
    cap_bottom = top + cap_h - 1
    cap = cut_rect(L, top, R, cap_bottom, (3, 1))
    stem = rect(9, cap_bottom, 24, bottom)
    d = line(9, 24, cap_bottom, "o")                                        # where the cap meets the stem
    d |= {(x, y): "l" for x in range(10, 24) for y in range(cap_bottom + 1, bottom)}
    d |= {(x, y): "l" for sx in (8, 15, 21) for x in (sx, sx + 1) for y in (top + 3, top + 4) if (x, y) in cap}   # spots
    stem_h = bottom - cap_bottom + 1
    d |= blocky_eyes(cap_bottom, stem_h, eye_h)
    return cap | stem, d, blocky_feet(lf, rf, bottom)


def snail(shell_top, head_x0, stalk_h, cuts=(4, 2, 1), eye_h=3, bottom=FLOOR):
    """A flat foot, a square shell with a square spiral, a head in front with block eyes on two stalks."""
    foot = rect(L, bottom - 3, R, bottom)
    head = rect(head_x0, bottom - 9, R, bottom)
    shell = cut_rect(6, shell_top, 19, bottom - 3, cuts)
    d = {(19, y): "o" for y in range(bottom - 9, bottom - 2)}               # the shell's edge against the head
    sy0, sy1 = shell_top + 3, bottom - 6                                    # the spiral: a square ring open on the left
    if sy1 - sy0 >= 4:
        d |= line(9, 16, sy0, "o") | line(9, 16, sy1, "o")
        d |= {(16, y): "o" for y in range(sy0, sy1 + 1)} | {(9, y): "o" for y in range(sy0 + 3, sy1 + 1)}
        my = (sy0 + sy1) // 2
        d |= {(x, y): "o" for x in (12, 13) for y in (my, my + 1)}
    stalks = set()
    if stalk_h > 0:
        s_top = bottom - 10 - stalk_h + 1
        stalks = rect(21, s_top, 22, bottom - 10) | rect(25, s_top, 26, bottom - 10)
        d |= {(x, y): "k" for x in (20, 21, 22, 24, 25, 26) for y in range(s_top - eye_h, s_top)}
    else:
        d |= {(x, y): "k" for x in (20, 21, 22, 24, 25) for y in range(bottom - 8, bottom - 8 + eye_h)}
    return foot | head | shell | stalks, d, set()


CREATURES = {
    "frog": (
        "#6cbf4a",
        "a fat green frog with two bulging eyes and a wide mouth",
        [("Hopper", "Bouncy and loud. Brags about how far it can jump, then jumps nowhere."),
         ("Mossy", "Slow and damp. Answers everything with a proverb about ponds."),
         ("Croak", "Grumpy. Finds the screen edge too dry and says so.")],
        {"idle": frog(13, 25, 1, 1), "walk-0": frog(13, 25, 1, 1), "walk-1": frog(15, 25, 1, 0),
         "walk-2": frog(13, 25, 1, 1), "walk-3": frog(11, 25, 0, 1), "jump": frog(10, 26, 0, 0, eye_h=4),
         "land": frog(21, 25, 1, 1, eye_h=2), "sleep-0": frog(17, 25, 1, 1, eye_h=2), "sleep-1": frog(18, 25, 1, 1, eye_h=2)},
    ),
    "cat": (
        None,
        "a small square cat with pointed ears and whiskers",
        [("Whiskers", "Aloof. Pretends not to care, then asks what you are doing."),
         ("Mittens", "Sweet and sleepy. Purrs in words. Wants the warm side of the screen."),
         ("Sir Pounce", "Dramatic. Announces every step as a hunt.")],
        {"idle": cat(12, 25, 1, 1), "walk-0": cat(12, 25, 1, 1), "walk-1": cat(14, 25, 1, 0),
         "walk-2": cat(12, 25, 1, 1), "walk-3": cat(11, 25, 0, 1), "jump": cat(10, 26, 0, 0, eye_h=4),
         "land": cat(19, 25, 1, 1, eye_h=2), "sleep-0": cat(16, 25, 1, 1, eye_h=2), "sleep-1": cat(17, 25, 1, 1, eye_h=2)},
    ),
    "ghost": (
        "#cfd3ea",
        "a little round ghost with a wavy hem, hovering just above the edge",
        [("Boo", "Tries to be scary, is adorable. Says boo a lot."),
         ("Wisp", "Wistful and poetic. Remembers monitors that are gone."),
         ("Sheet", "Deadpan. Points out it is technically not walking.")],
        {"idle": ghost(7, 26, 0), "walk-0": ghost(7, 26, 0), "walk-1": ghost(8, 26, 2),
         "walk-2": ghost(7, 26, 0), "walk-3": ghost(6, 26, 2), "jump": ghost(5, 26, 0),
         "land": ghost(12, 26, 0), "sleep-0": ghost(9, 26, 0), "sleep-1": ghost(10, 26, 2)},
    ),
    "slime": (
        "#4fd1a3",
        "a wobbly blue-green slime blob with a drip on one side",
        [("Goop", "Cheerful and simple. Everything is 'nice' or 'sticky'."),
         ("Puddle", "Anxious. Worried about drying out, evaporating, or being stepped on."),
         ("Blorp", "Speaks in sound effects and short words. Very pleased with itself.")],
        {"idle": slime(12, 25, 1, 1), "walk-0": slime(12, 25, 1, 1), "walk-1": slime(14, 25, 1, 0),
         "walk-2": slime(12, 25, 1, 1), "walk-3": slime(11, 25, 0, 1), "jump": slime(9, 26, 0, 0, eye_h=3),
         "land": slime(19, 25, 1, 1, eye_h=1), "sleep-0": slime(16, 25, 1, 1, eye_h=1), "sleep-1": slime(17, 25, 1, 1, eye_h=1)},
    ),
    "robot": (
        "#9aa5b1",
        "a boxy little robot with an antenna, square eyes and a row of rivets",
        [("Unit 7", "Literal and precise. Reports its own status in numbers."),
         ("Sprocket", "Enthusiastic about maintenance. Offers to tighten everyone's bolts."),
         ("Glitch", "Occasionally repeats a word word. Suspects the cursor is a virus.")],
        {"idle": robot(12, 25, 1, 1), "walk-0": robot(12, 25, 1, 1), "walk-1": robot(14, 25, 1, 0),
         "walk-2": robot(12, 25, 1, 1), "walk-3": robot(11, 25, 0, 1), "jump": robot(10, 26, 0, 0, eye_h=4),
         "land": robot(19, 25, 1, 1, eye_h=2), "sleep-0": robot(16, 25, 1, 1, eye_h=2), "sleep-1": robot(17, 25, 1, 1, eye_h=2)},
    ),
    "rabbit": (
        None,
        "a square rabbit with two tall ears and big front teeth",
        [("Thumper", "Jumpy and easily startled. Everything is a possible fox."),
         ("Clover", "Gentle and hungry. Asks whether anything on the screen is edible."),
         ("Bramble", "Fast talker. Brags about ear length and speed, in that order.")],
        {"idle": rabbit(13, 24, 0, 0), "walk-0": rabbit(13, 24, 0, 0), "walk-1": rabbit(15, 24, 0, 1, lean=1),
         "walk-2": rabbit(13, 24, 0, 0), "walk-3": rabbit(12, 24, 1, 0, ear_h=7),
         "jump": rabbit(11, 26, None, None, ear_h=6, lean=1, eye_h=6), "land": rabbit(19, 24, 0, 0, ear_h=6, lean=1, eye_h=3),
         "sleep-0": rabbit(16, 24, 0, 0, ear_h=6, lean=1, eye_h=3), "sleep-1": rabbit(17, 24, 0, 0, ear_h=6, lean=1, eye_h=3)},
    ),
    "pig": (
        "#f2a2b8",
        "a square pink pig with a big snout and little square ears",
        [("Truffle", "Content and greedy. Rates everything by how it would taste."),
         ("Muddy", "Loves mess. Suggests rolling in things. Cannot see the appeal of clean."),
         ("Professor Oink", "Very proud of being clever for a pig. Corrects people, kindly.")],
        {"idle": pig(8, 24, 0, 0), "walk-0": pig(8, 24, 0, 0), "walk-1": pig(10, 24, 0, 1),
         "walk-2": pig(8, 24, 0, 0), "walk-3": pig(8, 24, 1, 0), "jump": pig(8, 26, None, None, eye_h=6),
         "land": pig(15, 24, 0, 0, eye_h=3), "sleep-0": pig(12, 24, 0, 0, eye_h=3), "sleep-1": pig(13, 24, 0, 0, eye_h=3)},
    ),
    "triangle": (
        None,
        "a stepped triangle creature, point up, that rocks from side to side as it walks",
        [("Spike", "Sharp-tongued. Has a point and makes it."),
         ("Wedge", "Stable and stubborn. Refuses to be tipped over, in arguments too."),
         ("Delta", "Thinks in changes and differences. Notices what moved since last time.")],
        {"idle": triangle(5, 24, 0, 0), "walk-0": triangle(5, 24, 0, 0, lean=1), "walk-1": triangle(7, 24, 0, 1, lean=2),
         "walk-2": triangle(5, 24, 0, 0, lean=-1), "walk-3": triangle(5, 24, 1, 0, lean=-2, widths=(1, 3, 5, 7, 9, 9, 9)),
         "jump": triangle(5, 26, None, None, widths=(1, 2, 4, 6, 8, 9, 9, 9), eye_h=6),
         "land": triangle(14, 24, 0, 0, band=2, widths=(2, 5, 8, 10, 10, 10), eye_h=3),
         "sleep-0": triangle(9, 24, 0, 0, band=2, widths=(1, 3, 5, 7, 9, 10, 10, 10), eye_h=3),
         "sleep-1": triangle(10, 24, 0, 0, band=2, widths=(1, 3, 5, 7, 9, 10, 10, 10), eye_h=3)},
    ),
    "ball": (
        None,
        "a round bouncy ball with a face; it rolls along instead of walking",
        [("Bounce", "Restless. Cannot stay still, says so in every sentence."),
         ("Roly", "Easygoing. Goes wherever the slope goes and is fine with it."),
         ("Dot", "Small talk expert. Asks lots of questions, rolls away before the answers.")],
        {"idle": ball(7, 26, corner=0), "walk-0": ball(7, 26, corner=0), "walk-1": ball(8, 26, corner=1),
         "walk-2": ball(7, 26, corner=2), "walk-3": ball(6, 26, L + 1, R - 1, corner=3),
         "jump": ball(5, 26, L + 2, R - 2, corner=0, eye_h=7), "land": ball(13, 26, corner=0, cuts=(4, 2, 1), eye_h=4),
         "sleep-0": ball(10, 26, corner=0, cuts=(5, 3, 2, 1), eye_h=4), "sleep-1": ball(11, 26, corner=0, cuts=(5, 3, 2, 1), eye_h=4)},
    ),
    "mushroom": (
        "#d9483b",
        "a small red mushroom with light spots on its flat cap and a face on its pale stem",
        [("Morel", "Quiet and earthy. Speaks slowly about damp places and patience."),
         ("Puff", "Giggly. Threatens to release spores when excited."),
         ("Cap", "Old and wise, or thinks so. Starts sentences with 'in my day'.")],
        {"idle": mushroom(5, 8, 24, 0, 0), "walk-0": mushroom(5, 8, 24, 0, 0), "walk-1": mushroom(7, 8, 24, 0, 1),
         "walk-2": mushroom(5, 8, 24, 0, 0), "walk-3": mushroom(5, 7, 24, 1, 0), "jump": mushroom(5, 7, 26, None, None, eye_h=6),
         "land": mushroom(13, 6, 24, 0, 0, eye_h=3), "sleep-0": mushroom(9, 7, 24, 0, 0, eye_h=3), "sleep-1": mushroom(10, 7, 24, 0, 0, eye_h=3)},
    ),
    "snail": (
        "#c98a4b",
        "a slow snail with a square spiral shell and eyes on two stalks",
        [("Shelby", "Unhurried. Takes a long pause before every answer and says so."),
         ("Gary", "Homebody. Points out it is already home, wherever it is."),
         ("Turbo", "Convinced it is the fastest thing on the screen. It is not.")],
        {"idle": snail(10, 19, 3), "walk-0": snail(10, 19, 3), "walk-1": snail(11, 20, 3),
         "walk-2": snail(10, 19, 3), "walk-3": snail(10, 18, 3), "jump": snail(8, 19, 4),
         "land": snail(14, 19, 1, cuts=(3, 1)), "sleep-0": snail(11, 19, 0), "sleep-1": snail(12, 19, 0)},
    ),
}


def main() -> None:
    here = Path(__file__).parent
    for name, (colour, kind, cast, poses) in CREATURES.items():
        lines = [f"name: {name}", f"kind: {kind}"] + ([f"colour: {colour}"] if colour else [])
        lines += [f"character: {n}: {p}" for n, p in cast]
        for pose in POSES:
            mask, details, feet = poses[pose]
            assert all(L <= x <= R and TOP <= y <= FLOOR for (x, y) in mask | set(details) | feet), (name, pose)
            assert any(y == FLOOR for (_, y) in mask | feet), (name, pose, "not on the floor")
            lines.append(f"pose: {pose}")
            lines += style(mask, details, feet)
        (here / f"{name}.txt").write_text("\n".join(lines) + "\n")
        print("wrote", name)


if __name__ == "__main__":
    main()
