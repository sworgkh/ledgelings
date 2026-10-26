import React from "react";
import { Easing, interpolate, useCurrentFrame } from "remotion";
import { At, Prop, Species, lift } from "../../sprites";
import { Backdrop, Chip, ChipRow, Headline, Monitor, clamp } from "../../ui";
import { C, pixelFont } from "../../theme";

const W = 800;
const H = 470;
const S = 3.5;
const FLOOR = H - lift(S);
const CHOOSE = 50;

// Who lives on the left screen until the right one is chosen, and where they land.
const MOVERS: { sp: Species; x: number; to: number }[] = [
  { sp: "frog", x: 180, to: 200 },
  { sp: "cat", x: 420, to: 330 },
  { sp: "ghost", x: 620, to: 470 },
];
const STAYERS: { sp: Species; x: number }[] = [
  { sp: "blocky", x: 600 },
  { sp: "robot", x: 680 },
];

export const Screens: React.FC = () => {
  const f = useCurrentFrame();
  const chosen = f >= CHOOSE;
  return (
    <Backdrop>
      <Headline
        kicker="02 · YOUR SCREENS"
        title="Every monitor, or the one you choose"
        sub="Pick a screen in Creature Actions, and the rest of the colony parachutes over."
        colour={C.teal}
      />
      <Monitor x={110} y={400} w={W} h={H}>
        {MOVERS.map(({ sp, x }, i) => {
          const t = f - CHOOSE - 8 - i * 10;
          const up = t > 0 ? interpolate(t, [0, 22], [0, 620], clamp) : 0;
          return (
            <At
              key={sp}
              species={sp}
              x={x}
              y={FLOOR - up}
              scale={S}
              seed={i}
              pose={t > 0 ? "jump" : "walk"}
            />
          );
        })}
      </Monitor>
      <Monitor
        x={1010}
        y={400}
        w={W}
        h={H}
        wallpaper="linear-gradient(160deg, #283c6b 0%, #4c5f96 55%, #8c8fc4 100%)"
      >
        {STAYERS.map(({ sp, x }, i) => (
          <At
            key={sp}
            species={sp}
            x={x - (i === 0 ? Math.sin(f / 20) * 30 : 0)}
            y={FLOOR}
            scale={S}
            seed={i + 5}
            flip
          />
        ))}
        {MOVERS.map(({ sp, to }, i) => {
          const t = f - CHOOSE - 34 - i * 14;
          if (t < 0) return null;
          const y = interpolate(t, [0, 70], [-120, FLOOR], {
            ...clamp,
            easing: Easing.out(Easing.quad),
          });
          const landed = t >= 70;
          const sway = landed ? 0 : Math.sin(t / 7) * 8;
          return (
            <React.Fragment key={sp}>
              {!landed && (
                <Prop
                  frame="chute"
                  x={to + sway * 2}
                  y={y - 88}
                  scale={S}
                  angle={sway}
                />
              )}
              <At
                species={sp}
                x={to + sway * 2}
                y={y}
                angle={sway}
                scale={S}
                seed={i}
                pose={landed ? (t < 76 ? "land" : "idle") : "jump"}
              />
            </React.Fragment>
          );
        })}
        <div
          style={{
            position: "absolute",
            left: 24,
            top: 22,
            padding: "8px 16px",
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 26,
            background: chosen ? C.yellow : "rgba(255,255,255,0.12)",
            color: chosen ? C.outline : C.ink,
            border: `4px solid ${C.outline}`,
          }}
        >
          {chosen ? "★ THEIR SCREEN" : "SCREEN 2"}
        </div>
      </Monitor>
      <ChipRow>
        <Chip at={20} colour={C.teal}>
          All screens as one floor
        </Chip>
        <Chip at={CHOOSE} colour={C.yellow}>
          Or one, chosen from the sheet
        </Chip>
        <Chip at={CHOOSE + 70} colour={C.pink}>
          The rest come down by parachute
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
