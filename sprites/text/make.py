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


def feet_at(left, right, y=FLOOR, size=4):
    f = set()
    if left: f |= {(x, y) for x in range(7, 7 + size)}
    if right: f |= {(x, y) for x in range(25 - size, 25)}
    return f


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


CREATURES = {
    "frog": (
        "a fat green frog with two bulging eyes and a wide mouth",
        [("Hopper", "Bouncy and loud. Brags about how far it can jump, then jumps nowhere."),
         ("Mossy", "Slow and damp. Answers everything with a proverb about ponds."),
         ("Croak", "Grumpy. Finds the screen edge too dry and says so.")],
        {"idle": frog(13, 25, 1, 1), "walk-0": frog(13, 25, 1, 1), "walk-1": frog(15, 25, 1, 0),
         "walk-2": frog(13, 25, 1, 1), "walk-3": frog(11, 25, 0, 1), "jump": frog(10, 26, 0, 0, eye_h=4),
         "land": frog(21, 25, 1, 1, eye_h=2), "sleep-0": frog(17, 25, 1, 1, eye_h=2), "sleep-1": frog(18, 25, 1, 1, eye_h=2)},
    ),
    "cat": (
        "a small square cat with pointed ears and whiskers",
        [("Whiskers", "Aloof. Pretends not to care, then asks what you are doing."),
         ("Mittens", "Sweet and sleepy. Purrs in words. Wants the warm side of the screen."),
         ("Sir Pounce", "Dramatic. Announces every step as a hunt.")],
        {"idle": cat(12, 25, 1, 1), "walk-0": cat(12, 25, 1, 1), "walk-1": cat(14, 25, 1, 0),
         "walk-2": cat(12, 25, 1, 1), "walk-3": cat(11, 25, 0, 1), "jump": cat(10, 26, 0, 0, eye_h=4),
         "land": cat(19, 25, 1, 1, eye_h=2), "sleep-0": cat(16, 25, 1, 1, eye_h=2), "sleep-1": cat(17, 25, 1, 1, eye_h=2)},
    ),
    "ghost": (
        "a little round ghost with a wavy hem, hovering just above the edge",
        [("Boo", "Tries to be scary, is adorable. Says boo a lot."),
         ("Wisp", "Wistful and poetic. Remembers monitors that are gone."),
         ("Sheet", "Deadpan. Points out it is technically not walking.")],
        {"idle": ghost(7, 26, 0), "walk-0": ghost(7, 26, 0), "walk-1": ghost(8, 26, 2),
         "walk-2": ghost(7, 26, 0), "walk-3": ghost(6, 26, 2), "jump": ghost(5, 26, 0),
         "land": ghost(12, 26, 0), "sleep-0": ghost(9, 26, 0), "sleep-1": ghost(10, 26, 2)},
    ),
    "slime": (
        "a wobbly blue-green slime blob with a drip on one side",
        [("Goop", "Cheerful and simple. Everything is 'nice' or 'sticky'."),
         ("Puddle", "Anxious. Worried about drying out, evaporating, or being stepped on."),
         ("Blorp", "Speaks in sound effects and short words. Very pleased with itself.")],
        {"idle": slime(12, 25, 1, 1), "walk-0": slime(12, 25, 1, 1), "walk-1": slime(14, 25, 1, 0),
         "walk-2": slime(12, 25, 1, 1), "walk-3": slime(11, 25, 0, 1), "jump": slime(9, 26, 0, 0, eye_h=3),
         "land": slime(19, 25, 1, 1, eye_h=1), "sleep-0": slime(16, 25, 1, 1, eye_h=1), "sleep-1": slime(17, 25, 1, 1, eye_h=1)},
    ),
    "robot": (
        "a boxy little robot with an antenna, square eyes and a row of rivets",
        [("Unit 7", "Literal and precise. Reports its own status in numbers."),
         ("Sprocket", "Enthusiastic about maintenance. Offers to tighten everyone's bolts."),
         ("Glitch", "Occasionally repeats a word word. Suspects the cursor is a virus.")],
        {"idle": robot(12, 25, 1, 1), "walk-0": robot(12, 25, 1, 1), "walk-1": robot(14, 25, 1, 0),
         "walk-2": robot(12, 25, 1, 1), "walk-3": robot(11, 25, 0, 1), "jump": robot(10, 26, 0, 0, eye_h=4),
         "land": robot(19, 25, 1, 1, eye_h=2), "sleep-0": robot(16, 25, 1, 1, eye_h=2), "sleep-1": robot(17, 25, 1, 1, eye_h=2)},
    ),
}


def main() -> None:
    here = Path(__file__).parent
    for name, (kind, cast, poses) in CREATURES.items():
        lines = [f"name: {name}", f"kind: {kind}"] + [f"character: {n}: {p}" for n, p in cast]
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
