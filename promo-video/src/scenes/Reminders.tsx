import React from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { At, Creature, Plane, lift } from "../sprites";
import { Backdrop, Chip, ChipRow, Headline, Monitor, clamp } from "../ui";
import { C, pixelFont } from "../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);
const SWIRL = [12, 70];
const RUSH = [82, 100];

export const Reminders: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();

  // The plane spirals in to the middle of the screen, turns to face you and rushes at you.
  const t = interpolate(f, SWIRL, [0, 1], {
    ...clamp,
    easing: Easing.inOut(Easing.quad),
  });
  const r = 380 * (1 - t);
  const a = Math.PI * 0.9 + t * Math.PI * 3;
  const px = 700 + r * Math.cos(a);
  const py = 270 + r * 0.55 * Math.sin(a);
  const facing = f >= SWIRL[1];
  const rush = interpolate(f, RUSH, [5, 60], {
    ...clamp,
    easing: Easing.in(Easing.cubic),
  });
  const flash = interpolate(
    f,
    [RUSH[1] - 4, RUSH[1], RUSH[1] + 8],
    [0, 1, 0],
    clamp,
  );
  const letter = spring({
    frame: f - RUSH[1],
    fps,
    config: { damping: 13, stiffness: 120 },
  });
  const peek = interpolate(f, [RUSH[1] + 20, RUSH[1] + 36], [0, 1], clamp);

  return (
    <Backdrop>
      <Headline
        kicker="08 · REMINDERS"
        title="Your reminders arrive by paper plane"
        sub="Tell them what and when. One folds it up and throws it at you."
        colour={C.yellow}
      />
      <Monitor x={260} y={360} w={W} h={H}>
        <At
          species="blocky-ruth"
          x={160}
          y={FLOOR}
          scale={S}
          pose={f < 14 ? "jump" : "idle"}
        />
        {f < RUSH[1] && (
          <Plane
            frame={facing ? (f < RUSH[0] ? "front" : "opening") : "plane"}
            scale={facing ? rush : 5}
            style={{
              position: "absolute",
              left: px - (facing ? 9 * rush : 45),
              top: py - (facing ? 7 * rush : 35),
              transform: facing
                ? undefined
                : `rotate(${(a * 180) / Math.PI + 90}deg)`,
            }}
          />
        )}
      </Monitor>
      {f >= RUSH[1] && (
        <div
          style={{
            position: "absolute",
            left: 960 - 470,
            top: 410,
            width: 940,
            transform: `scale(${letter}) rotate(${(1 - letter) * -8 - 1}deg)`,
          }}
        >
          <div
            style={{
              position: "absolute",
              right: 70,
              top: -88 * peek,
              opacity: peek,
            }}
          >
            <Creature species="blocky-ruth" scale={4} flip />
          </div>
          <div
            style={{
              position: "relative",
              background: C.paper,
              color: "#2a2540",
              border: `4px solid ${C.outline}`,
              boxShadow: `inset -10px -10px 0 ${C.paperShade}, 14px 14px 0 rgba(0,0,0,0.4)`,
              padding: "34px 46px 30px",
              backgroundImage:
                "repeating-linear-gradient(transparent 0 54px, rgba(60,80,160,0.12) 54px 57px)",
            }}
          >
            <div
              style={{
                fontFamily: pixelFont,
                fontWeight: 700,
                fontSize: 24,
                color: "#8a6a2a",
                letterSpacing: 3,
              }}
            >
              REMINDER · 17:00 · EVERY WEEKDAY
            </div>
            <div
              style={{
                fontFamily: pixelFont,
                fontWeight: 700,
                fontSize: 64,
                marginTop: 10,
              }}
            >
              Stand up and stretch
            </div>
            <div
              style={{
                fontSize: 32,
                fontWeight: 600,
                fontStyle: "italic",
                marginTop: 14,
                lineHeight: 1.3,
              }}
            >
              "Item one of one: stand up and stretch. Counted, folded,
              delivered. No jumping about it."
            </div>
            <div
              style={{
                fontFamily: pixelFont,
                fontWeight: 700,
                fontSize: 34,
                color: "#3f8f2a",
                textAlign: "right",
                marginTop: 12,
              }}
            >
              — Ruth
            </div>
          </div>
        </div>
      )}
      <AbsoluteFill style={{ background: "#fff", opacity: flash }} />
      <ChipRow>
        <Chip at={24} colour={C.yellow}>
          Once, daily, weekdays or weekly
        </Chip>
        <Chip at={RUSH[1] + 30} colour={C.green}>
          Signed, in the thrower's own voice
        </Chip>
        <Chip at={RUSH[1] + 60} colour={C.purple}>
          Click it and off it flies
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
