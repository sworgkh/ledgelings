import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { At, Flower, FlowerKind, lift } from "../sprites";
import { Backdrop, Chip, ChipRow, Headline, Monitor, clamp } from "../ui";
import { C, pixelFont } from "../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);
const HEAD = H - 22 * S - 4; // top of a creature's head, standing on the floor
const GIVE = [56, 80];
const SWITCH = 140;

/** Three meetings, counted: the third one brings a flower. */
const Meetings: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: 40,
        display: "flex",
        justifyContent: "center",
        gap: 22,
      }}
    >
      {[1, 2, 3].map((n) => {
        const lit = f >= n * 14;
        return (
          <div
            key={n}
            style={{
              width: 150,
              padding: "12px 0",
              textAlign: "center",
              fontFamily: pixelFont,
              fontWeight: 700,
              fontSize: 24,
              background: lit
                ? n === 3
                  ? C.pink
                  : "rgba(255,255,255,0.18)"
                : "rgba(255,255,255,0.05)",
              color: lit
                ? n === 3
                  ? "#2a0d1a"
                  : C.ink
                : "rgba(255,255,255,0.3)",
              border: `4px solid ${C.outline}`,
              transform: `scale(${lit && f < n * 14 + 6 ? 1.15 : 1})`,
            }}
          >
            MEETING {n}
          </div>
        );
      })}
    </div>
  );
};

const Planted: React.FC<{
  kind: FlowerKind;
  x: number;
  at: number;
  ceiling?: boolean;
}> = ({ kind, x, at, ceiling }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const g = spring({
    frame: f - at,
    fps,
    config: { damping: 10, stiffness: 140 },
  });
  return (
    <Flower
      kind={kind}
      scale={S}
      style={{
        position: "absolute",
        left: x - 32,
        top: ceiling ? 0 : H - 64,
        transform: `${ceiling ? "rotate(180deg) " : ""}scaleY(${g})`,
        transformOrigin: "50% 100%",
      }}
    />
  );
};

const Tag: React.FC<{
  x: number;
  y: number;
  at: number;
  colour: string;
  children: React.ReactNode;
}> = ({ x, y, at, colour, children }) => {
  const f = useCurrentFrame();
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        transform: "translateX(-50%)",
        whiteSpace: "nowrap",
        padding: "8px 16px",
        background: C.outline,
        color: colour,
        fontFamily: pixelFont,
        fontWeight: 700,
        fontSize: 24,
        opacity: interpolate(f, [at, at + 10], [0, 1], clamp),
      }}
    >
      {children}
    </div>
  );
};

export const Flowers: React.FC = () => {
  const f = useCurrentFrame();
  const a = interpolate(f, [SWITCH - 10, SWITCH], [1, 0], clamp);
  const b = interpolate(f, [SWITCH, SWITCH + 10], [0, 1], clamp);

  // Act one: Blocky gives Ruth a flower, and Ruth follows Blocky about.
  const walk = Math.max(0, f - 92) * 4.5;
  const giverX = 560 + walk;
  const wearerX = 780 + Math.max(0, walk - 90);
  const k = interpolate(f, GIVE, [0, 1], clamp);
  const flowerX = 560 + (wearerX - 560) * k;
  const flowerY = HEAD - 150 * Math.sin(Math.PI * k) - 64;

  return (
    <Backdrop>
      <Headline
        kicker="05 · FLOWERS"
        title="Every third meeting, a flower"
        sub="The wearer follows the giver around, then plants it where it likes."
        colour={C.pink}
      />
      <Monitor
        x={260}
        y={360}
        w={W}
        h={H}
        wallpaper="linear-gradient(170deg, #36557a 0%, #6a7fa8 60%, #a6b9c9 100%)"
      >
        <div style={{ opacity: a }}>
          <Meetings />
          <At
            species="blocky"
            x={giverX}
            y={FLOOR}
            scale={S}
            pose={f > 92 ? "walk" : "idle"}
          />
          <At
            species="blocky-ruth"
            x={wearerX}
            y={FLOOR}
            scale={S}
            flip={f < 100}
            seed={3}
            pose={f > 100 ? "walk" : "idle"}
          />
          {f >= GIVE[0] && (
            <Flower
              kind="rose"
              scale={S}
              style={{ position: "absolute", left: flowerX - 32, top: flowerY }}
            />
          )}
        </div>
        <div style={{ opacity: b }}>
          <At species="blocky" x={260} y={FLOOR} scale={S} pose="idle" />
          <Planted kind="sunflower" x={360} at={SWITCH + 12} />
          <Tag x={320} y={H - 210} at={SWITCH + 20} colour={C.orange}>
            BLOCKY · THE FLOOR, ONLY
          </Tag>

          <At
            species="blocky-pip"
            x={720}
            y={lift(S)}
            angle={-180}
            scale={S}
            pose="idle"
            seed={5}
          />
          <Planted kind="tulip" x={620} at={SWITCH + 40} ceiling />
          <Tag x={680} y={190} at={SWITCH + 48} colour={C.teal}>
            PIP · THE CEILING
          </Tag>

          <At
            species="blocky-ruth"
            x={1240}
            y={FLOOR}
            scale={S}
            flip
            pose="idle"
            seed={2}
          />
          {[0, 1, 2].map((i) => (
            <Planted
              key={i}
              kind="daisy"
              x={960 + i * 76}
              at={SWITCH + 66 + i * 7}
            />
          ))}
          <Tag x={1080} y={H - 210} at={SWITCH + 74} colour={C.green}>
            RUTH · A NEAT ROW
          </Tag>
        </div>
      </Monitor>
      <ChipRow>
        <Chip at={20} colour={C.pink}>
          Ten kinds of flowers
        </Chip>
        <Chip at={100} colour={C.green}>
          The wearer follows the giver
        </Chip>
        <Chip at={SWITCH + 20} colour={C.yellow}>
          Each plants where its character likes
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
