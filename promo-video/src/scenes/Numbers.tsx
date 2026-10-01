import React from "react";
import {
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Creature, Flower, House, Plane, Species, Tea } from "../sprites";
import { Backdrop, Headline, clamp } from "../ui";
import { C, pixelFont } from "../theme";

type Tile = {
  n: number;
  prefix?: string;
  label: string;
  colour: string;
  icon: React.ReactNode;
};

const creature = (s: Species) => <Creature species={s} scale={4} />;

const TILES: Tile[] = [
  {
    n: 8,
    label: "species, each with its own cast",
    colour: C.orange,
    icon: creature("robot"),
  },
  {
    n: 27,
    label: "characters, each with a persona",
    colour: C.teal,
    icon: creature("blocky-pip"),
  },
  {
    n: 100,
    label: "built-in conversations, no model needed",
    colour: C.pink,
    icon: <Tea scale={3} />,
  },
  {
    n: 10,
    label: "kinds of flowers to give and to plant",
    colour: C.yellow,
    icon: <Flower kind="daisy" scale={6} />,
  },
  {
    n: 0,
    prefix: "$",
    label: "on built-in lines, and every model call is priced",
    colour: C.green,
    icon: <Plane scale={6} />,
  },
  {
    n: 2,
    label: "native apps, macOS and Windows, one spec",
    colour: C.purple,
    icon: <House scale={1.6} />,
  },
];

export const Numbers: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Backdrop>
      <Headline
        kicker="09 · IN THE BOX"
        title="A whole colony, ready to go"
        colour={C.teal}
      />
      <div
        style={{
          position: "absolute",
          left: 140,
          top: 280,
          width: 1640,
          display: "grid",
          gridTemplateColumns: "repeat(3, 1fr)",
          gap: 40,
        }}
      >
        {TILES.map((t, i) => {
          const at = 10 + i * 9;
          const pop = spring({
            frame: f - at,
            fps,
            config: { damping: 12, stiffness: 150 },
          });
          const count = Math.round(
            interpolate(f, [at, at + 34], [0, t.n], {
              ...clamp,
              easing: Easing.out(Easing.cubic),
            }),
          );
          return (
            <div
              key={i}
              style={{
                height: 330,
                position: "relative",
                padding: "30px 34px",
                background: "rgba(255,255,255,0.05)",
                border: `4px solid ${t.colour}`,
                boxShadow: `10px 10px 0 ${C.outline}`,
                transform: `scale(${pop}) translateY(${(1 - pop) * 40}px)`,
                opacity: Math.min(1, pop * 1.6),
              }}
            >
              <div
                style={{
                  fontFamily: pixelFont,
                  fontWeight: 700,
                  fontSize: 128,
                  lineHeight: 1,
                  color: t.colour,
                }}
              >
                {t.prefix}
                {count}
              </div>
              <div
                style={{
                  fontSize: 32,
                  fontWeight: 800,
                  marginTop: 20,
                  maxWidth: 360,
                  lineHeight: 1.2,
                }}
              >
                {t.label}
              </div>
              <div style={{ position: "absolute", right: 26, top: 26 }}>
                {t.icon}
              </div>
            </div>
          );
        })}
      </div>
    </Backdrop>
  );
};
