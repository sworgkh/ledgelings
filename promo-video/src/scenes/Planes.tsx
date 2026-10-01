import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { At, Plane, lift } from "../sprites";
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
const FLY = [16, 112];

/** Where the plane is at frame f: an arc across the screen with one loop in it. */
const flight = (f: number) => {
  const t = interpolate(f, FLY, [0, 1], clamp);
  const x = 230 + (1150 - 230) * t;
  const y = FLOOR - 70 - 200 * Math.sin(Math.PI * t);
  const loop = interpolate(t, [0.38, 0.62], [0, 2 * Math.PI], clamp);
  const r = 80;
  return { x: x + r * Math.sin(loop), y: y - r * (1 - Math.cos(loop)) };
};

export const Planes: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = flight(f);
  const q = flight(f + 1);
  const angle = (Math.atan2(q.y - p.y, q.x - p.x) * 180) / Math.PI;
  const flying = f >= FLY[0] && f < FLY[1];
  const trail = [];
  for (let g = FLY[0]; g < Math.min(f, FLY[1]); g += 3) {
    const age = f - g;
    if (age > 54) continue;
    const d = flight(g);
    trail.push(
      <div
        key={g}
        style={{
          position: "absolute",
          left: d.x - 4,
          top: d.y - 4,
          width: 8,
          height: 8,
          background: "#fff",
          opacity: interpolate(age, [0, 54], [0.9, 0], clamp),
        }}
      />,
    );
  }
  const note = spring({ frame: f - 116, fps, config: { damping: 12 } });
  const noteOut = interpolate(f, [168, 178], [1, 0], clamp);

  return (
    <Backdrop>
      <Headline
        kicker="06 · PAPER PLANES"
        title="When it gets too quiet, notes fly"
        sub="Each plane flies in weather of its own. The catcher reads it out and throws one back."
        colour={C.purple}
      />
      <Monitor
        x={260}
        y={360}
        w={W}
        h={H}
        wallpaper="linear-gradient(165deg, #3a2f6b 0%, #6b4f9e 50%, #d38fb4 100%)"
      >
        <At
          species="blocky-pip"
          x={180}
          y={FLOOR}
          scale={S}
          seed={2}
          pose={f < FLY[0] ? "jump" : "idle"}
        />
        <At species="blocky" x={1220} y={FLOOR} scale={S} flip pose="idle" />
        {trail}
        {flying && (
          <Plane
            scale={7}
            style={{
              position: "absolute",
              left: p.x - 63,
              top: p.y - 49,
              transform: `rotate(${angle}deg) scaleY(${Math.abs(angle) > 90 ? -1 : 1})`,
            }}
          />
        )}
        {f >= FLY[1] && f < 178 && (
          <div
            style={{
              position: "absolute",
              left: 360,
              top: 70,
              width: 680,
              padding: "26px 34px",
              background: C.paper,
              color: "#2a2540",
              border: `4px solid ${C.outline}`,
              boxShadow: `inset -8px -8px 0 ${C.paperShade}, 10px 10px 0 rgba(0,0,0,0.35)`,
              transform: `scale(${note * noteOut}) rotate(-2deg)`,
            }}
          >
            <div
              style={{
                fontFamily: pixelFont,
                fontWeight: 700,
                fontSize: 22,
                color: C.teal,
                WebkitTextStroke: "0.5px #2a2540",
              }}
            >
              A NOTE FROM PIP
            </div>
            <div
              style={{
                fontSize: 36,
                fontWeight: 800,
                marginTop: 8,
                lineHeight: 1.25,
              }}
            >
              The ceiling is AMAZING today! Everything is upside down and I love
              it!
            </div>
          </div>
        )}
        <Bubble
          x={1220}
          y={FLOOR - 70}
          at={180}
          tail={0.8}
          width={640}
          name="BLOCKY, READING IT"
          colour={C.orange}
          text="A paper plane. Flying. Off the edge. Disgraceful. ...Neatly folded, though."
        />
      </Monitor>
      <ChipRow>
        <Chip at={30} colour={C.purple}>
          Every few minutes, you choose
        </Chip>
        <Chip at={70} colour={C.teal}>
          Loops, swirls, a dotted trail
        </Chip>
        <Chip at={180} colour={C.orange}>
          One answer thrown back
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
