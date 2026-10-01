import React from "react";
import { Easing, interpolate, useCurrentFrame } from "remotion";
import { At, Species, lift } from "../sprites";
import {
  Backdrop,
  Chip,
  ChipRow,
  Cursor,
  Headline,
  Monitor,
  clamp,
  onOutline,
} from "../ui";
import { C } from "../theme";

const W = 1600;
const H = 540;
const S = 4;
const IN = lift(S);

const walkers: { species: Species; s0: number; v: number }[] = [
  { species: "frog", s0: 1300, v: 6 },
  { species: "ghost", s0: 2150, v: 7.5 },
  { species: "robot", s0: 3050, v: 6.5 },
  { species: "slime", s0: 700, v: 5.5 },
];

// Blocky walks the floor until the cursor comes near, then jumps to the ceiling.
const JUMP_AT = 150;
const JUMP_LEN = 22;
const S_TOP = W - 2 * IN + (H - 2 * IN) + (W - IN - 760); // a spot on the ceiling, x ≈ 760

const blocky = (t: number) => {
  if (t < JUMP_AT)
    return { ...onOutline(260 + 7 * t, W, H, IN), pose: "walk" as const };
  if (t >= JUMP_AT + JUMP_LEN)
    return {
      ...onOutline(S_TOP + 7 * (t - JUMP_AT - JUMP_LEN), W, H, IN),
      pose: "walk" as const,
    };
  const a = onOutline(260 + 7 * JUMP_AT, W, H, IN);
  const b = onOutline(S_TOP, W, H, IN);
  const k = interpolate(t, [JUMP_AT, JUMP_AT + JUMP_LEN], [0, 1], {
    easing: Easing.inOut(Easing.quad),
  });
  return {
    x: a.x + (b.x - a.x) * k,
    y: a.y + (b.y - a.y) * k,
    angle: a.angle + (-180 - a.angle) * k,
    pose: "jump" as const,
  };
};

export const Edges: React.FC = () => {
  const f = useCurrentFrame();
  const b = blocky(f);
  const cx = interpolate(f, [90, 140, 175, 230], [1450, 1290, 1240, 1500], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });
  const cy = interpolate(f, [90, 140, 175, 230], [120, 420, 430, 300], {
    ...clamp,
    easing: Easing.inOut(Easing.cubic),
  });

  return (
    <Backdrop>
      <Headline
        kicker="01 · THE EDGES"
        title="They crawl the edges of your screen"
        sub="Round the corners, over the ceiling, from one monitor onto the next."
        colour={C.orange}
      />
      <Monitor x={160} y={360} w={W} h={H} seams={[W / 2]}>
        {walkers.map((w, i) => {
          const p = onOutline(w.s0 + w.v * f, W, H, IN);
          return (
            <At
              key={w.species}
              species={w.species}
              x={p.x}
              y={p.y}
              angle={p.angle}
              pose="walk"
              seed={i}
              scale={S}
            />
          );
        })}
        <At
          species="blocky"
          x={b.x}
          y={b.y}
          angle={b.angle}
          pose={b.pose}
          scale={S}
          seed={9}
        />
        <div style={{ opacity: interpolate(f, [86, 96], [0, 1], clamp) }}>
          <Cursor x={cx} y={cy} />
        </div>
      </Monitor>
      <ChipRow>
        <Chip at={40} colour={C.orange}>
          Every edge and corner
        </Chip>
        <Chip at={70} colour={C.teal}>
          Across all your monitors
        </Chip>
        <Chip at={160} colour={C.pink}>
          Cursor too close? They jump away
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
