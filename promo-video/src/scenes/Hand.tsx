import React from "react";
import { Easing, interpolate, useCurrentFrame } from "remotion";
import { At, lift } from "../sprites";
import {
  Backdrop,
  Bubble,
  Chip,
  ChipRow,
  Cursor,
  Headline,
  Monitor,
  clamp,
} from "../ui";
import { C, pixelFont } from "../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);
// Where Blocky is put down each time: picked up five times in a row.
const SPOTS = [700, 380, 1020, 520, 900, 640];
const START = 12;
const EVERY = 24;
const CARRY = 15;
const GRUMBLE = START + EVERY * 5 + 6;

/** Blocky's place on frame f, and whether the hand is holding it. */
const carried = (f: number) => {
  const i = Math.floor((f - START) / EVERY);
  if (f < START)
    return { x: SPOTS[0], lift: 0, held: false, landing: false, picks: 0 };
  if (i >= 5)
    return {
      x: SPOTS[5],
      lift: 0,
      held: false,
      landing: f - START - 5 * EVERY < 5,
      picks: 5,
    };
  const u = f - START - i * EVERY;
  const k = interpolate(u, [0, CARRY], [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.quad),
  });
  return {
    x: SPOTS[i] + (SPOTS[i + 1] - SPOTS[i]) * k,
    lift: u < CARRY ? 40 + 150 * Math.sin(Math.PI * k) : 0,
    held: u < CARRY,
    landing: u >= CARRY && u < CARRY + 5,
    picks: i + 1,
  };
};

export const Hand: React.FC = () => {
  const f = useCurrentFrame();
  const b = carried(f);
  const by = FLOOR - b.lift;
  const cursorX =
    b.held || f < GRUMBLE ? b.x - 6 : b.x + 380 + (f - GRUMBLE) * 0.8;
  const cursorY = b.held || f < GRUMBLE ? by - 70 : by - 40;
  return (
    <Backdrop>
      <Headline
        kicker="02 · YOUR HAND"
        title="Pick them up. Just not too often."
        sub="Shift-drag one anywhere. Do it five times in a row and it tells you off."
        colour={C.pink}
      />
      <Monitor
        x={260}
        y={360}
        w={W}
        h={H}
        wallpaper="linear-gradient(160deg, #283c6b 0%, #4c5f96 55%, #8c8fc4 100%)"
      >
        <At
          species="blocky"
          x={b.x}
          y={by}
          scale={S}
          pose={b.held ? "jump" : b.landing ? "land" : "idle"}
        />
        <Cursor x={cursorX} y={cursorY} />
        <div
          style={{
            position: "absolute",
            left: 30,
            top: 28,
            padding: "10px 18px",
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 26,
            background: b.held ? C.yellow : "rgba(255,255,255,0.12)",
            color: b.held ? "#2a2000" : C.ink,
            border: `4px solid ${C.outline}`,
            boxShadow: b.held ? "none" : `0 6px 0 ${C.outline}`,
            transform: `translateY(${b.held ? 6 : 0}px)`,
          }}
        >
          SHIFT
        </div>
        <div
          style={{
            position: "absolute",
            right: 30,
            top: 28,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 30,
            color: b.picks >= 5 ? C.pink : C.ink,
          }}
        >
          PICKED UP ×{b.picks}
        </div>
        <Bubble
          x={b.x}
          y={FLOOR - 70}
          at={GRUMBLE}
          tail={0.5}
          width={600}
          name="BLOCKY"
          colour={C.orange}
          text="5 times. I have written every one of them down. Back off."
        />
      </Monitor>
      <ChipRow>
        <Chip at={20} colour={C.pink}>
          Shift-drag to carry them anywhere
        </Chip>
        <Chip at={60} colour={C.teal}>
          Hold Shift and nobody flees
        </Chip>
        <Chip at={GRUMBLE} colour={C.orange}>
          How patient they are is up to you
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
