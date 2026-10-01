import React from "react";
import { interpolate, interpolateColors, useCurrentFrame } from "remotion";
import { At, Species, Zs, lift } from "../sprites";
import { Backdrop, Headline, Monitor, clamp } from "../ui";
import { C, pixelFont } from "../theme";

const X = 360;
const Y = 350;
const W = 1200;
const H = 500;
const S = 4;
const DUSK = [46, 86];

const sleepers: { species: Species; x0: number; v: number; zAt: number }[] = [
  { species: "blocky-zed", x0: 180, v: 2.2, zAt: 84 },
  { species: "cat", x0: 520, v: 1.6, zAt: 92 },
  { species: "slime", x0: 860, v: 1.9, zAt: 100 },
];

export const DayNight: React.FC = () => {
  const f = useCurrentFrame();
  const n = interpolate(f, DUSK, [0, 1], clamp);
  const top = interpolateColors(
    n,
    [0, 0.5, 1],
    ["#7cc4ff", "#f39a6b", "#141a44"],
  );
  const bottom = interpolateColors(
    n,
    [0, 0.5, 1],
    ["#c9ecff", "#ffcf8a", "#2b2f6e"],
  );
  const night = f > DUSK[0] + 20;
  const sunY = interpolate(f, [0, DUSK[1]], [70, 560], clamp);
  const moonY = interpolate(f, [DUSK[0] + 10, DUSK[1] + 30], [-120, 70], clamp);
  const head = interpolate(f, [0, 180], [0, 1], clamp);

  return (
    <Backdrop>
      <Headline
        kicker="03 · DAY AND NIGHT"
        title="They keep a clock of their own"
        sub="At dusk everyone slumps and floats Zs. At dawn they wake, a few seconds apart."
        colour={C.yellow}
      />
      <Monitor
        x={X}
        y={Y}
        w={W}
        h={H}
        wallpaper={`linear-gradient(180deg, ${top}, ${bottom})`}
      >
        <div
          style={{
            position: "absolute",
            left: 960,
            top: sunY,
            width: 72,
            height: 72,
            background: "#ffd23d",
            boxShadow: "0 0 0 6px #ffe98a, 0 0 60px #ffd23d",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 180,
            top: moonY,
            width: 60,
            height: 60,
            background: "#f4f1da",
            boxShadow:
              "inset -14px -10px 0 #cfcab0, 0 0 40px rgba(255,255,220,0.5)",
          }}
        />
        {[...Array(18)].map((_, i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: (i * 263) % W,
              top: 30 + ((i * 97) % 260),
              width: 6,
              height: 6,
              background: "#fff",
              opacity: n * (0.4 + 0.6 * Math.abs(Math.sin(f / 9 + i))),
            }}
          />
        ))}
        {sleepers.map((s, i) => {
          const x = s.x0 + s.v * Math.min(f, 70);
          const y = H - lift(S);
          return (
            <React.Fragment key={s.species}>
              <At
                species={s.species}
                x={x}
                y={y}
                scale={S}
                seed={i}
                pose={night ? "sleep" : f < 70 ? "walk" : "idle"}
              />
              <Zs x={x + 30} y={y - 80} start={s.zAt} />
            </React.Fragment>
          );
        })}
      </Monitor>
      {/* The colony's clock: three minutes of day, then five of night. */}
      <div
        style={{
          position: "absolute",
          left: X,
          top: Y + H + 52,
          width: W,
          height: 56,
          display: "flex",
          border: `4px solid ${C.outline}`,
        }}
      >
        <div
          style={{
            flex: 3,
            background: C.yellow,
            color: "#3a2a00",
            display: "flex",
            alignItems: "center",
            paddingLeft: 22,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 28,
          }}
        >
          3 min of day
        </div>
        <div
          style={{
            flex: 5,
            background: "#2b2f6e",
            color: C.ink,
            display: "flex",
            alignItems: "center",
            paddingLeft: 22,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 28,
          }}
        >
          5 min of night
        </div>
        <div
          style={{
            position: "absolute",
            left: `${head * 100}%`,
            top: -14,
            width: 8,
            height: 76,
            background: C.ink,
            boxShadow: `0 0 0 3px ${C.outline}`,
          }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: X,
          top: Y + H + 122,
          width: W,
          textAlign: "center",
          fontSize: 26,
          color: C.dim,
          fontWeight: 600,
        }}
      >
        Both lengths are yours to change in Settings.
      </div>
    </Backdrop>
  );
};
