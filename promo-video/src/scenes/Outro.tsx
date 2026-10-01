import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { At, House, Species, lift } from "../sprites";
import { Backdrop, clamp } from "../ui";
import { C, pixelFont } from "../theme";

const FLOOR = 900;
const S = 4;
const DOOR = 1650;

const PARADE: Species[] = [
  "blocky",
  "frog",
  "blocky-pip",
  "cat",
  "blocky-mortimer",
  "ghost",
  "blocky-zed",
  "slime",
  "blocky-dot",
  "robot",
  "blocky-ruth",
  "triangle",
  "mushroom",
];

export const Outro: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const title = spring({
    frame: f - 20,
    fps,
    config: { damping: 11, stiffness: 120 },
  });
  const rise = (d: number) => interpolate(f, [d, d + 14], [0, 1], clamp);
  return (
    <Backdrop>
      <div
        style={{
          position: "absolute",
          left: 120,
          right: 120,
          top: FLOOR,
          height: 8,
          background: C.bezelLight,
          boxShadow: `0 8px 0 ${C.bezel}`,
        }}
      />
      <House
        scale={4}
        style={{ position: "absolute", left: DOOR - 120, top: FLOOR - 240 }}
      />
      {PARADE.map((sp, i) => {
        const x = -120 - i * 150 + f * 9;
        if (x > DOOR + 10) return null;
        return (
          <At
            key={sp}
            species={sp}
            x={x}
            y={FLOOR - lift(S)}
            scale={S}
            pose="walk"
            seed={i}
            opacity={interpolate(x, [DOOR - 40, DOOR + 10], [1, 0], clamp)}
          />
        );
      })}
      <div
        style={{
          position: "absolute",
          top: 170,
          left: 0,
          right: 0,
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 180,
            transform: `scale(${title})`,
            color: C.orange,
            textShadow: `8px 8px 0 ${C.outline}`,
          }}
        >
          Ledgelings
        </div>
        <div
          style={{
            fontSize: 46,
            fontWeight: 800,
            marginTop: 30,
            opacity: rise(44),
          }}
        >
          Tiny friends for the edges of your screen.
        </div>
        <div
          style={{
            fontSize: 32,
            fontWeight: 600,
            color: C.dim,
            marginTop: 22,
            opacity: rise(70),
          }}
        >
          …and when you ask, they all go home.
        </div>
        <div
          style={{
            display: "inline-block",
            marginTop: 46,
            padding: "16px 34px",
            border: `3px solid ${C.teal}`,
            borderRadius: 999,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 30,
            letterSpacing: 2,
            opacity: rise(100),
          }}
        >
          macOS 26+ · Windows 10/11 · MIT licensed
        </div>
      </div>
    </Backdrop>
  );
};
