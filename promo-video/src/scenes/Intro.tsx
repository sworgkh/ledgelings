import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { At, Species, Stars, lift } from "../sprites";
import { Backdrop, clamp } from "../ui";
import { C, pixelFont } from "../theme";

const FLOOR = 690;
const S = 4;
const TITLE = "Ledgelings";
const LETTER_COLOURS = [C.orange, C.teal, C.pink, C.yellow, C.purple, C.green];

// Blocky's cast walk in from both sides and bump in the middle.
const LEFT: Species[] = ["blocky", "blocky-pip", "blocky-mortimer"];
const RIGHT: Species[] = ["blocky-zed", "blocky-dot", "blocky-ruth"];

export const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const walking = f < 78;
  const floorW = interpolate(f, [0, 22], [0, 1360], clamp);

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
      {LEFT.map((sp, i) => {
        const end = 820 - i * 150;
        const x = interpolate(f, [8 + i * 4, 78], [-160 - i * 150, end], clamp);
        const hop = sp === "blocky" ? jump(f - 104) : 0;
        return (
          <At
            key={sp}
            species={sp}
            x={x}
            y={FLOOR - lift(S) - hop}
            scale={S}
            seed={i}
            pose={
              walking
                ? "walk"
                : hop > 0
                  ? "jump"
                  : f - 104 > 18 && f - 104 < 24
                    ? "land"
                    : "idle"
            }
          />
        );
      })}
      {RIGHT.map((sp, i) => {
        const end = 1100 + i * 150;
        const x = interpolate(f, [8 + i * 4, 78], [2080 + i * 150, end], clamp);
        const hop = sp === "blocky-dot" ? jump(f - 112) : 0;
        return (
          <At
            key={sp}
            species={sp}
            x={x}
            y={FLOOR - lift(S) - hop}
            scale={S}
            flip
            seed={i + 3}
            pose={walking ? "walk" : hop > 0 ? "jump" : "idle"}
          />
        );
      })}
      <Stars x={960} y={FLOOR - 90} at={78} />

      <div
        style={{
          position: "absolute",
          top: 250,
          left: 0,
          right: 0,
          textAlign: "center",
          fontFamily: pixelFont,
          fontWeight: 700,
          fontSize: 200,
        }}
      >
        {TITLE.split("").map((ch, i) => {
          const s = spring({
            frame: f - 82 - i * 3,
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
          top: FLOOR + 70,
          left: 0,
          right: 0,
          textAlign: "center",
          fontSize: 44,
          fontWeight: 800,
          color: C.ink,
          opacity: interpolate(f, [112, 126], [0, 1], clamp),
          transform: `translateY(${interpolate(f, [112, 128], [20, 0], clamp)}px)`,
        }}
      >
        Tiny pixel creatures that live on the{" "}
        <span style={{ color: C.orange }}>edges of your screen</span>.
      </div>
    </Backdrop>
  );
};

/** Height of a 20-frame hop that started `t` frames ago. */
export const jump = (t: number, high = 110) =>
  t >= 0 && t <= 18 ? high * Math.sin((Math.PI * t) / 18) : 0;
