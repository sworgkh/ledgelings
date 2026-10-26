import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { At, Species, Stars, lift } from "../../sprites";
import { Backdrop, clamp } from "../../ui";
import { C, pixelFont } from "../../theme";
import { jump } from "../../scenes/Intro";

const FLOOR = 700;
const S = 4;
const TITLE = "Ledgelings";
const LETTER_COLOURS = [C.orange, C.teal, C.pink, C.yellow, C.purple, C.green];

// One of each species, four from each side, meeting in the middle.
const LEFT: Species[] = ["blocky", "frog", "cat", "ghost"];
const RIGHT: Species[] = ["robot", "slime", "triangle", "mushroom"];

export const IntroV2: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const walking = f < 70;
  const floorW = interpolate(f, [0, 20], [0, 1500], clamp);
  const tag = spring({
    frame: f - 104,
    fps,
    config: { damping: 10, stiffness: 150 },
  });

  const side = (list: Species[], fromLeft: boolean) =>
    list.map((sp, i) => {
      const end = fromLeft ? 850 - i * 140 : 1070 + i * 140;
      const start = fromLeft ? -150 - i * 140 : 2070 + i * 140;
      const x = interpolate(f, [4 + i * 3, 70], [start, end], clamp);
      const hop = jump(f - 96 - i * 5, 80);
      return (
        <At
          key={sp}
          species={sp}
          x={x}
          y={FLOOR - lift(S) - hop}
          scale={S}
          flip={!fromLeft}
          seed={i + (fromLeft ? 0 : 4)}
          pose={walking ? "walk" : hop > 0 ? "jump" : "idle"}
        />
      );
    });

  return (
    <Backdrop>
      <div
        style={{
          position: "absolute",
          left: 960 - floorW / 2,
          top: FLOOR,
          width: floorW,
          height: 8,
          background: C.bezelLight,
          boxShadow: `0 8px 0 ${C.bezel}`,
        }}
      />
      {side(LEFT, true)}
      {side(RIGHT, false)}
      <Stars x={960} y={FLOOR - 90} at={70} />
      <div
        style={{
          position: "absolute",
          top: 210,
          left: 0,
          right: 0,
          textAlign: "center",
          fontFamily: pixelFont,
          fontWeight: 700,
          fontSize: 190,
        }}
      >
        {TITLE.split("").map((ch, i) => {
          const s = spring({
            frame: f - 74 - i * 3,
            fps,
            config: { damping: 9, stiffness: 170 },
          });
          return (
            <span
              key={i}
              style={{
                display: "inline-block",
                transform: `translateY(${(1 - s) * 90}px) scale(${0.4 + 0.6 * s})`,
                opacity: Math.min(1, s * 2),
                color: LETTER_COLOURS[i % LETTER_COLOURS.length],
                textShadow: `8px 8px 0 ${C.outline}`,
              }}
            >
              {ch}
            </span>
          );
        })}
      </div>
      <div
        style={{
          position: "absolute",
          top: 470,
          left: 0,
          right: 0,
          textAlign: "center",
        }}
      >
        <div
          style={{
            display: "inline-block",
            padding: "12px 30px",
            background: C.yellow,
            color: C.outline,
            border: `5px solid ${C.outline}`,
            boxShadow: `8px 8px 0 rgba(0,0,0,0.4)`,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 44,
            transform: `scale(${tag}) rotate(-2deg)`,
          }}
        >
          0.18 → 0.62
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: FLOOR + 70,
          left: 0,
          right: 0,
          textAlign: "center",
          fontSize: 46,
          fontWeight: 800,
          opacity: interpolate(f, [112, 126], [0, 1], clamp),
          transform: `translateY(${interpolate(f, [112, 128], [20, 0], clamp)}px)`,
        }}
      >
        Since the last film they learned to{" "}
        <span style={{ color: C.orange }}>sleep</span>,{" "}
        <span style={{ color: C.teal }}>play</span>,{" "}
        <span style={{ color: C.pink }}>remember</span> and{" "}
        <span style={{ color: C.yellow }}>help</span>.
      </div>
    </Backdrop>
  );
};
