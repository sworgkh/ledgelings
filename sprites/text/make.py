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


def rabbit(top, bottom, lf, rf, ear_h=9, lean=0, eye_h=3):
    """A square body under two tall ears; `lean` bends the ears back (left) by that many pixels at the tip."""
    body = rect(L + 1, top, R - 1, bottom)
    ears, d = set(), {}
    for k in range(ear_h):
        y = top - 1 - k
        dx = -round(lean * k / max(1, ear_h - 1))
        ears |= rect(9 + dx, y, 12 + dx, y) | rect(19 + dx, y, 22 + dx, y)
        if 2 <= k < ear_h - 2:                                              # the inner ear
            d |= {(10 + dx, y): "s", (11 + dx, y): "s", (20 + dx, y): "s", (21 + dx, y): "s"}
    eye_y = min(top + 3, bottom - eye_h - 1)
    d |= eyes(16, eye_y, eye_h, gap=3, w=2)
    if eye_y + eye_h + 3 <= bottom - 1:
        d |= {(15, eye_y + eye_h + 1): "x", (16, eye_y + eye_h + 1): "x"}   # nose
        d |= line(13, 18, eye_y + eye_h + 2)                                # mouth
        d |= {(15, eye_y + eye_h + 3): "l", (16, eye_y + eye_h + 3): "l"}   # two big teeth
    return body | ears, d, feet_at(lf, rf, size=3)


def pig(top, bottom, lf, rf, eye_h=2):
    body = dome(16, top, bottom, 10) | rect(L, bottom - 3, R, bottom)
    ears = rect(7, top + 1, 9, top + 4) | rect(23, top + 1, 25, top + 4)
    tall = bottom - top >= 13
    eye_y = top + 5 if tall else top + 3
    d = eyes(16, eye_y, eye_h, gap=4, w=2)
    sy = eye_y + eye_h + 2
    if tall:                                                                # the snout: an outlined block with two nostrils
        for x in range(12, 20):
            d[(x, sy)] = "o"; d[(x, sy + 3)] = "o"
        for y in range(sy + 1, sy + 3):
            d[(12, y)] = "o"; d[(19, y)] = "o"
            d[(14, y)] = "x"; d[(17, y)] = "x"
    else:
        d |= {(14, sy - 1): "x", (17, sy - 1): "x"}
    return body | ears, d, feet_at(lf, rf, size=3)


def triangle(top, bottom, lf, rf, half_w=10, lean=0, eye_h=3):
    """Apex up; `lean` moves the apex sideways so it rocks as it walks."""
    h = max(1, bottom - top)
    mask = set()
    for y in range(top, bottom + 1):
        t = (y - top) / h
        w, cx = round(half_w * t), 16 + round(lean * (1 - t))
        mask |= rect(cx - w, y, cx + w, y)
    ey = top + round(h * 0.6)
    ecx = 16 + round(lean * 0.4)
    d = eyes(ecx, ey, eye_h, gap=2, w=2)
    if ey + eye_h + 2 <= bottom - 1:
        d |= line(ecx - 2, ecx + 2, ey + eye_h + 1)
    return mask, d, feet_at(lf, rf, size=3)


def ball(cy, rx, ry, seam, eye_h=3):
    """A round ball; the dark patch on its rim moves round the walk cycle so it looks like it rolls."""
    body = ellipse(16, cy, rx, ry)
    d = ring(16, cy, rx, ry, 0.6, 0.85, ((seam - 24) % 360, (seam + 24) % 360))
    d |= eyes(16, cy - 3, eye_h, gap=3, w=2)
    d |= line(14, 18, cy + 2)
    return body, d, set()


def mushroom(top, cap_h, bottom, lf, rf, eye_h=3):
    """A wide cap on a pale stem; the eyes are on the stem."""
    cap_bottom = top + cap_h - 1
    cap = dome(16, top, cap_bottom, 10)
    stem = rect(11, cap_bottom, 20, bottom)
    d = line(11, 20, cap_bottom, "o")                                       # where the cap meets the stem
    d |= {(x, y): "l" for x in range(12, 20) for y in range(cap_bottom + 1, bottom)}
    for (sx, sy) in ((9, top + 4), (15, top + 1), (21, top + 4)):          # spots on the cap
        d |= {(x, y): "l" for x in range(sx, sx + 2) for y in range(sy, sy + 2) if (x, y) in cap}
    eye_y = min(cap_bottom + 3, bottom - eye_h - 1)
    d |= eyes(16, eye_y, eye_h, gap=2, w=2)
    if eye_y + eye_h + 2 <= bottom - 1:
        d |= line(14, 17, eye_y + eye_h + 1)
    return cap | stem, d, feet_at(lf, rf, size=3, lx=11, rx=18)


def snail(shell_ry, head_x0, stalk_h, eye_h=2, bottom=FLOOR):
    """A flat foot, a round shell at the back, a head in front with eyes on stalks."""
    foot = rect(L, bottom - 2, R, bottom)
    head = rect(head_x0, bottom - 6, R, bottom)
    cy = bottom - 2 - shell_ry
    shell = ellipse(13, cy, 7, shell_ry)
    d = ring(13, cy, 7, shell_ry, 0.42, 0.62, (270, 180))                   # the spiral, three quarters of a ring
    d[(13, cy)] = "o"
    stalks = set()
    if stalk_h > 0:
        top = bottom - 7 - stalk_h + 1
        stalks = rect(22, top, 22, bottom - 7) | rect(25, top, 25, bottom - 7)
        d |= {(x, y): "k" for x in (22, 23, 25, 26) for y in range(top - eye_h, top)}
    else:
        d |= {(x, y): "k" for x in (22, 23, 25, 26) for y in range(bottom - 5, bottom - 5 + eye_h)}
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
        {"idle": rabbit(15, 25, 1, 1), "walk-0": rabbit(15, 25, 1, 1), "walk-1": rabbit(17, 25, 1, 0, ear_h=8, lean=1),
         "walk-2": rabbit(15, 25, 1, 1), "walk-3": rabbit(14, 25, 0, 1, ear_h=9, lean=-1),
         "jump": rabbit(13, 26, 0, 0, ear_h=8, lean=1, eye_h=4), "land": rabbit(21, 25, 1, 1, ear_h=4, lean=1, eye_h=2),
         "sleep-0": rabbit(18, 25, 1, 1, ear_h=6, lean=1, eye_h=2), "sleep-1": rabbit(19, 25, 1, 1, ear_h=6, lean=1, eye_h=2)},
    ),
    "pig": (
        "#f2a2b8",
        "a round pink pig with a big snout and little square ears",
        [("Truffle", "Content and greedy. Rates everything by how it would taste."),
         ("Muddy", "Loves mess. Suggests rolling in things. Cannot see the appeal of clean."),
         ("Professor Oink", "Very proud of being clever for a pig. Corrects people, kindly.")],
        {"idle": pig(11, 25, 1, 1), "walk-0": pig(11, 25, 1, 1), "walk-1": pig(13, 25, 1, 0),
         "walk-2": pig(11, 25, 1, 1), "walk-3": pig(10, 25, 0, 1), "jump": pig(8, 26, 0, 0, eye_h=3),
         "land": pig(18, 25, 1, 1, eye_h=1), "sleep-0": pig(15, 25, 1, 1, eye_h=1), "sleep-1": pig(16, 25, 1, 1, eye_h=1)},
    ),
    "triangle": (
        None,
        "a pointy triangle creature, apex up, that rocks from side to side as it walks",
        [("Spike", "Sharp-tongued. Has a point and makes it."),
         ("Wedge", "Stable and stubborn. Refuses to be tipped over, in arguments too."),
         ("Delta", "Thinks in changes and differences. Notices what moved since last time.")],
        {"idle": triangle(6, 25, 1, 1), "walk-0": triangle(6, 25, 1, 1, lean=1), "walk-1": triangle(8, 25, 1, 0, lean=2),
         "walk-2": triangle(6, 25, 1, 1, lean=-1), "walk-3": triangle(5, 25, 0, 1, lean=-2, half_w=9),
         "jump": triangle(5, 26, 0, 0, half_w=8, eye_h=4), "land": triangle(14, 25, 1, 1, eye_h=2),
         "sleep-0": triangle(10, 25, 1, 1, eye_h=2), "sleep-1": triangle(11, 25, 1, 1, eye_h=2)},
    ),
    "ball": (
        None,
        "a round bouncy ball with a face; it rolls along instead of walking",
        [("Bounce", "Restless. Cannot stay still, says so in every sentence."),
         ("Roly", "Easygoing. Goes wherever the slope goes and is fine with it."),
         ("Dot", "Small talk expert. Asks lots of questions, rolls away before the answers.")],
        {"idle": ball(16, 10, 10, 315), "walk-0": ball(16, 10, 10, 315), "walk-1": ball(17, 10, 9, 45),
         "walk-2": ball(16, 10, 10, 135), "walk-3": ball(16, 9, 10, 225), "jump": ball(16, 8, 10, 315, eye_h=4),
         "land": ball(19, 10, 7, 315, eye_h=2), "sleep-0": ball(17, 10, 9, 315, eye_h=2), "sleep-1": ball(18, 10, 8, 315, eye_h=2)},
    ),
    "mushroom": (
        "#d9483b",
        "a small red mushroom with light spots on its cap and a face on its pale stem",
        [("Morel", "Quiet and earthy. Speaks slowly about damp places and patience."),
         ("Puff", "Giggly. Threatens to release spores when excited."),
         ("Cap", "Old and wise, or thinks so. Starts sentences with 'in my day'.")],
        {"idle": mushroom(6, 8, 25, 1, 1), "walk-0": mushroom(6, 8, 25, 1, 1), "walk-1": mushroom(8, 8, 25, 1, 0),
         "walk-2": mushroom(6, 8, 25, 1, 1), "walk-3": mushroom(5, 8, 25, 0, 1), "jump": mushroom(5, 7, 26, 0, 0, eye_h=4),
         "land": mushroom(14, 7, 25, 1, 1, eye_h=2), "sleep-0": mushroom(10, 8, 25, 1, 1, eye_h=2), "sleep-1": mushroom(11, 8, 25, 1, 1, eye_h=2)},
    ),
    "snail": (
        "#c98a4b",
        "a slow snail with a spiral shell and eyes on two stalks",
        [("Shelby", "Unhurried. Takes a long pause before every answer and says so."),
         ("Gary", "Homebody. Points out it is already home, wherever it is."),
         ("Turbo", "Convinced it is the fastest thing on the screen. It is not.")],
        {"idle": snail(7, 21, 3), "walk-0": snail(7, 21, 3), "walk-1": snail(6, 22, 3),
         "walk-2": snail(7, 21, 3), "walk-3": snail(7, 20, 3), "jump": snail(8, 21, 4),
         "land": snail(5, 21, 1, eye_h=2), "sleep-0": snail(6, 21, 0, eye_h=2), "sleep-1": snail(6, 22, 0, eye_h=2)},
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
