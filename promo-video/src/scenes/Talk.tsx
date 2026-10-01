import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { At, Stars, lift } from "../sprites";
import {
  Backdrop,
  Bubble,
  Chip,
  ChipRow,
  Headline,
  Monitor,
  clamp,
} from "../ui";
import { C, pixelFont } from "../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);
const MEET = 52;

/** Equaliser bars that move while someone is speaking out loud. */
const Voice: React.FC<{ from: number; to: number; colour: string }> = ({
  from,
  to,
  colour,
}) => {
  const f = useCurrentFrame();
  const on = f >= from && f <= to;
  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-end",
        gap: 6,
        height: 44,
        opacity: on ? 1 : 0.25,
      }}
    >
      {[0, 1, 2, 3, 4].map((i) => (
        <div
          key={i}
          style={{
            width: 10,
            height: on ? 10 + 30 * Math.abs(Math.sin(f / 3 + i * 1.7)) : 8,
            background: colour,
            boxShadow: `0 0 0 3px ${C.outline}`,
          }}
        />
      ))}
    </div>
  );
};

export const Talk: React.FC = () => {
  const f = useCurrentFrame();
  const bx = interpolate(f, [0, MEET], [120, 600], clamp);
  const px = interpolate(f, [0, MEET], [1280, 800], clamp);
  const walking = f < MEET;
  return (
    <Backdrop>
      <Headline
        kicker="04 · THEY TALK"
        title="When two bump into each other, they talk"
        sub="One says a line, the other answers back, each in character."
        colour={C.teal}
      />
      <Monitor x={260} y={360} w={W} h={H}>
        <At
          species="blocky"
          x={bx}
          y={FLOOR}
          scale={S}
          pose={walking ? "walk" : "idle"}
        />
        <At
          species="blocky-pip"
          x={px}
          y={FLOOR}
          scale={S}
          flip
          seed={4}
          pose={walking ? "walk" : "idle"}
        />
        <Stars x={700} y={FLOOR - 40} at={MEET} />
        <Bubble
          x={600}
          y={FLOOR - 70}
          at={62}
          until={132}
          tail={0.62}
          width={540}
          name="BLOCKY"
          colour={C.orange}
          text="Do you ever wonder what's past the edge?"
        />
        <Bubble
          x={800}
          y={FLOOR - 70}
          at={136}
          tail={0.3}
          width={520}
          name="PIP"
          colour={C.teal}
          text="Wallpaper. It's always wallpaper."
        />
        <div
          style={{
            position: "absolute",
            right: 34,
            top: 28,
            display: "flex",
            alignItems: "center",
            gap: 18,
            opacity: interpolate(f, [56, 66], [0, 1], clamp),
          }}
        >
          <div
            style={{
              fontFamily: pixelFont,
              fontWeight: 700,
              fontSize: 24,
              color: C.ink,
            }}
          >
            OUT LOUD
          </div>
          <Voice from={62} to={130} colour={C.orange} />
          <div style={{ width: 70 }} />
          <Voice from={136} to={200} colour={C.teal} />
        </div>
      </Monitor>
      <ChipRow>
        <Chip at={70} colour={C.orange}>
          100 built-in conversations
        </Chip>
        <Chip at={110} colour={C.teal}>
          Or a model: LM Studio, OpenRouter
        </Chip>
        <Chip at={160} colour={C.purple}>
          Read aloud, each in its own voice
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
