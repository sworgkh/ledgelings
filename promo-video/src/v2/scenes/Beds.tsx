import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { At, BED_LIFT, Bed, BedKind, Species, Zs, lift } from "../../sprites";
import {
  Backdrop,
  Bubble,
  Chip,
  ChipRow,
  Headline,
  Monitor,
  clamp,
} from "../../ui";
import { C, pixelFont } from "../../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - 8;
const ARRIVE = 70;

// Each character's own bed, as `Bed.forCharacter` in Beds.swift gives them.
const SLEEPERS: { sp: Species; bed: BedKind; x: number; from: number }[] = [
  { sp: "blocky", bed: "crate", x: 200, from: -100 },
  { sp: "frog", bed: "lilypad", x: 460, from: -260 },
  { sp: "ghost", bed: "cloud", x: 720, from: 1560 },
  { sp: "cat", bed: "box", x: 960, from: 1700 },
  { sp: "robot", bed: "dock", x: 1200, from: 1520 },
];

export const Beds: React.FC = () => {
  const f = useCurrentFrame();
  const night = interpolate(f, [0, 90], [0, 1], clamp);
  const hour = Math.floor(interpolate(f, [0, 90], [20, 23], clamp));
  const minute = Math.floor(interpolate(f, [0, 90], [10, 47], clamp) % 60);
  return (
    <Backdrop>
      <Headline
        kicker="03 · BEDTIME"
        title="Every character sleeps in its own bed"
        sub="A crate, a lily pad, a cloud, a charging dock. Drag one, and that is its place now."
        colour={C.purple}
      />
      <Monitor
        x={260}
        y={360}
        w={W}
        h={H}
        wallpaper={`linear-gradient(180deg, rgb(${40 - 26 * night}, ${58 - 40 * night}, ${115 - 60 * night}) 0%, rgb(${190 - 140 * night}, ${110 - 70 * night}, ${150 - 70 * night}) 100%)`}
      >
        <div
          style={{
            position: "absolute",
            right: 140,
            top: 50,
            width: 56,
            height: 56,
            background: C.paper,
            boxShadow: `-14px 0 0 0 ${C.paperShade} inset`,
            opacity: night,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 30,
            top: 26,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 34,
            color: C.ink,
          }}
        >
          {hour}:{String(minute).padStart(2, "0")}
        </div>
        {SLEEPERS.map(({ sp, bed, x, from }, i) => {
          const at = ARRIVE + i * 6;
          const cx = interpolate(f, [0, at], [from, x], clamp);
          const asleep = f >= at + 10;
          const y = asleep
            ? FLOOR - BED_LIFT[bed] * S - lift(S)
            : FLOOR - lift(S);
          return (
            <React.Fragment key={sp}>
              <Bed kind={bed} x={x} floor={FLOOR} scale={S} />
              <At
                species={sp}
                x={cx}
                y={y}
                scale={S}
                flip={from > x}
                seed={i}
                pose={f < at ? "walk" : asleep ? "sleep" : "idle"}
              />
              {asleep && <Zs x={x + 30} y={y - 60} start={at + 10 + i * 5} />}
            </React.Fragment>
          );
        })}
        <Bubble
          x={1200}
          y={FLOOR - 120}
          at={110}
          until={170}
          tail={0.8}
          width={560}
          name="UNIT 7"
          colour={C.teal}
          text="Docked. Charge 12%. Expected full: 0600. Sleep mode: on."
        />
        <Bubble
          x={200}
          y={FLOOR - 120}
          at={176}
          tail={0.2}
          width={560}
          name="BLOCKY"
          colour={C.orange}
          text="My crate. On the bottom edge. Where a bed belongs."
        />
      </Monitor>
      <ChipRow>
        <Chip at={30} colour={C.purple}>
          Bedtime follows your clock
        </Chip>
        <Chip at={90} colour={C.yellow}>
          The date and holidays you tick
        </Chip>
        <Chip at={150} colour={C.teal}>
          Each learns its spot
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
