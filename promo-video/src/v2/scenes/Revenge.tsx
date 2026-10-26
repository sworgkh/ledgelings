import React from "react";
import { Easing, interpolate, useCurrentFrame } from "remotion";
import { At, Stars, lift } from "../../sprites";
import {
  Backdrop,
  Bubble,
  Chip,
  ChipRow,
  Cursor,
  Headline,
  Monitor,
  clamp,
} from "../../ui";
import { C, pixelFont } from "../../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);
const GRAB = 96;
const SHAKE = 186;
const DROP = 206;
// The cursor touches Blocky three times while it flees: hunts 5, 6 and 7 today.
const HUNTS = [22, 48, 74];

export const Revenge: React.FC = () => {
  const f = useCurrentFrame();
  const hunts = 4 + HUNTS.filter((h) => f >= h).length;

  // The cursor: chasing along the floor, then carried about, then shaken.
  const chaseX = interpolate(f, [0, GRAB], [160, 900], clamp);
  const rideX = interpolate(f, [GRAB + 10, SHAKE], [900, 620], {
    ...clamp,
    easing: Easing.inOut(Easing.sin),
  });
  const shake = f >= SHAKE && f < DROP ? Math.sin(f * 1.7) * 46 : 0;
  const cx = (f < GRAB + 10 ? chaseX : rideX) + shake;
  const cy =
    f < GRAB
      ? FLOOR - 30 + Math.sin(f / 5) * 18
      : interpolate(f, [GRAB, GRAB + 30], [FLOOR - 30, 330], {
          ...clamp,
          easing: Easing.out(Easing.quad),
        });

  // Blocky: a step ahead of the cursor, then on top of it, then back on the floor.
  const fleeX = chaseX + 110 + Math.max(0, Math.sin(f / 9)) * 20;
  let bx = fleeX;
  let by = FLOOR;
  let pose: "walk" | "jump" | "idle" | "land" = "walk";
  if (f >= GRAB && f < DROP) {
    const k = interpolate(f, [GRAB, GRAB + 12], [0, 1], clamp);
    bx = fleeX + (cx + 14 - fleeX) * k;
    by = FLOOR + (cy - 38 - FLOOR) * k - Math.sin(Math.PI * k) * 80;
    pose = k < 1 ? "jump" : "idle";
  } else if (f >= DROP) {
    const k = interpolate(f, [DROP, DROP + 14], [0, 1], {
      ...clamp,
      easing: Easing.in(Easing.quad),
    });
    bx = 620 + 14 + k * 60;
    by = cy - 38 + (FLOOR - (cy - 38)) * k;
    pose = k < 1 ? "jump" : f < DROP + 20 ? "land" : "idle";
  }
  const flip = f >= GRAB && f < DROP && Math.sin(f / 10) < 0;

  return (
    <Backdrop>
      <Headline
        kicker="05 · THE CURSOR"
        title="Hunt them too often, and they hunt back"
        sub="Every chase is counted. Seven today? Blocky rides your cursor until you shake it off."
        colour={C.pink}
      />
      <Monitor
        x={260}
        y={360}
        w={W}
        h={H}
        wallpaper="linear-gradient(160deg, #3b2a5a 0%, #6a3f78 55%, #c0617a 100%)"
      >
        <At
          species="blocky"
          x={bx}
          y={by}
          scale={S}
          pose={pose}
          flip={flip}
          angle={f >= SHAKE && f < DROP ? shake / 3 : 0}
        />
        <Cursor x={cx} y={cy} scale={2} />
        {HUNTS.map((h) => (
          <Stars key={h} x={chaseX + 90} y={FLOOR - 40} at={h} />
        ))}
        <div
          style={{
            position: "absolute",
            left: 30,
            top: 26,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 30,
            color: hunts >= 7 ? C.pink : C.ink,
          }}
        >
          HUNTS TODAY ×{hunts}
        </div>
        <Bubble
          x={760}
          y={236}
          at={GRAB + 18}
          until={SHAKE - 4}
          tail={0.2}
          width={640}
          name="BLOCKY"
          colour={C.orange}
          text="Got it. Your cursor is MINE now. 7 times today. How does it feel?"
        />
        <Bubble
          x={700}
          y={FLOOR - 70}
          at={DROP + 16}
          tail={0.4}
          width={620}
          name="BLOCKY"
          colour={C.orange}
          text="Fine. Take your cursor. This isn't over. It's written down."
        />
      </Monitor>
      <ChipRow>
        <Chip at={20} colour={C.teal}>
          Cursor mood: playmate, just there, menace
        </Chip>
        <Chip at={70} colour={C.yellow}>
          Hunts today, this week, in all
        </Chip>
        <Chip at={SHAKE} colour={C.pink}>
          Shake to get it back
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
