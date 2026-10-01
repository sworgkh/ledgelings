import React from "react";
import { Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import blockyMeta from "../public/sprites/blocky.json";
import flowersMeta from "../public/sprites/flowers.json";
import planeMeta from "../public/sprites/plane.json";
import teaMeta from "../public/sprites/tea.json";
import zzzMeta from "../public/sprites/zzz.json";
import houseMeta from "../public/sprites/house.json";

type Rect = { x: number; y: number; w: number; h: number };
type Meta = { frames: Record<string, Rect> };

const sheetSize = (meta: Meta): [number, number] => {
  const rects = Object.values(meta.frames);
  return [
    Math.max(...rects.map((r) => r.x + r.w)),
    Math.max(...rects.map((r) => r.y + r.h)),
  ];
};

/** One frame of an atlas, scaled up with hard pixel edges. Drawn with <Img>, so
 *  the render waits for the sheet to load instead of flashing an empty box. */
export const Sprite: React.FC<{
  sheet: string;
  meta: Meta;
  frame: string;
  scale: number;
  style?: React.CSSProperties;
}> = ({ sheet, meta, frame, scale, style }) => {
  const r = meta.frames[frame];
  const [sw, sh] = sheetSize(meta);
  return (
    <div
      style={{
        width: r.w * scale,
        height: r.h * scale,
        overflow: "hidden",
        position: "relative",
        ...style,
      }}
    >
      <Img
        src={staticFile(`sprites/${sheet}.png`)}
        style={{
          position: "absolute",
          left: -r.x * scale,
          top: -r.y * scale,
          width: sw * scale,
          height: sh * scale,
          imageRendering: "pixelated",
          maxWidth: "none",
        }}
      />
    </div>
  );
};

/** Species sheets, plus Blocky's cast in their own colours (scripts/export-sprites.py). */
export type Species =
  | "blocky"
  | "frog"
  | "cat"
  | "ghost"
  | "slime"
  | "robot"
  | "triangle"
  | "mushroom"
  | "blocky-pip"
  | "blocky-mortimer"
  | "blocky-zed"
  | "blocky-dot"
  | "blocky-ruth";

export type Pose = "idle" | "walk" | "jump" | "land" | "sleep";

/** A creature drawn standing on a floor, facing right, as the app draws it.
 *  `walk` cycles the four crawl frames; everyone blinks now and then. */
export const Creature: React.FC<{
  species: Species;
  pose?: Pose;
  scale?: number;
  flip?: boolean;
  seed?: number;
  style?: React.CSSProperties;
}> = ({ species, pose = "idle", scale = 4, flip = false, seed = 0, style }) => {
  const f = useCurrentFrame() + seed * 37;
  const cycle = (f % 95) - 88; // a blink: half, closed, half, every ~3 s
  const blink =
    pose === "sleep"
      ? "closed"
      : cycle === 0 || cycle === 3
        ? "half"
        : cycle > 0 && cycle < 3
          ? "closed"
          : "open";
  const name =
    pose === "walk"
      ? `walk-${Math.floor(f / 4) % 4}`
      : pose === "sleep"
        ? `sleep-${Math.floor(f / 24) % 2}`
        : pose;
  return (
    <Sprite
      sheet={species}
      meta={blockyMeta}
      frame={`${name}_${blink}`}
      scale={scale}
      style={{ transform: flip ? "scaleX(-1)" : undefined, ...style }}
    />
  );
};

export type FlowerKind =
  | "poppy"
  | "tulip"
  | "daisy"
  | "sunflower"
  | "rose"
  | "bluebell"
  | "dandelion"
  | "lavender"
  | "lily"
  | "forget-me-not";

export const Flower: React.FC<{
  kind: FlowerKind;
  scale?: number;
  style?: React.CSSProperties;
}> = ({ kind, scale = 4, style }) => (
  <Sprite
    sheet="flowers"
    meta={flowersMeta}
    frame={kind}
    scale={scale}
    style={style}
  />
);

export type PlaneFrame =
  | "plane"
  | "letter"
  | "front"
  | "opening"
  | "bank"
  | "top"
  | "tilt"
  | "belly";

export const Plane: React.FC<{
  frame?: PlaneFrame;
  scale?: number;
  style?: React.CSSProperties;
}> = ({ frame = "plane", scale = 4, style }) => (
  <Sprite
    sheet="plane"
    meta={planeMeta}
    frame={frame}
    scale={scale}
    style={style}
  />
);

export const Tea: React.FC<{ scale?: number; style?: React.CSSProperties }> = ({
  scale = 4,
  style,
}) => {
  const f = useCurrentFrame();
  return (
    <Sprite
      sheet="tea"
      meta={teaMeta}
      frame={`tea-${Math.floor(f / 12) % 2}`}
      scale={scale}
      style={style}
    />
  );
};

export const House: React.FC<{
  scale?: number;
  style?: React.CSSProperties;
}> = ({ scale = 4, style }) => (
  <Sprite
    sheet="house"
    meta={houseMeta}
    frame="house"
    scale={scale}
    style={style}
  />
);

/** Zs drifting up from a sleeper, one every `every` frames. */
export const Zs: React.FC<{
  x: number;
  y: number;
  scale?: number;
  every?: number;
  start?: number;
}> = ({ x, y, scale = 3, every = 22, start = 0 }) => {
  const f = useCurrentFrame() - start;
  if (f < 0) return null;
  const zs = [];
  for (
    let i = Math.max(0, Math.floor((f - 60) / every));
    i <= Math.floor(f / every);
    i++
  ) {
    const age = f - i * every;
    if (age < 0 || age > 60) continue;
    zs.push(
      <Sprite
        key={i}
        sheet="zzz"
        meta={zzzMeta}
        frame="z"
        scale={scale * interpolate(age, [0, 60], [0.7, 1.3])}
        style={{
          position: "absolute",
          left: x + age * 0.9 + Math.sin(age / 8) * 6,
          top: y - age * 1.6,
          opacity: interpolate(age, [0, 8, 45, 60], [0, 1, 1, 0]),
        }}
      />,
    );
  }
  return <>{zs}</>;
};

/** The few pixel stars that fly up when two creatures bump. */
export const Stars: React.FC<{ x: number; y: number; at: number }> = ({
  x,
  y,
  at,
}) => {
  const age = useCurrentFrame() - at;
  if (age < 0 || age > 30) return null;
  const colours = [
    "#ffd23d",
    "#fff7e3",
    "#ff6fa3",
    "#3dc7b5",
    "#ffd23d",
    "#9b7bff",
    "#fff7e3",
  ];
  return (
    <>
      {colours.map((c, i) => {
        const a = -Math.PI / 2 + (i - 3) * 0.42;
        const d = interpolate(age, [0, 30], [0, 110], {
          easing: (t) => 1 - (1 - t) ** 3,
        });
        const s = i % 2 ? 10 : 14;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x + Math.cos(a) * d - s / 2,
              top: y + Math.sin(a) * d + age * age * 0.06 - s / 2,
              width: s,
              height: s,
              background: c,
              boxShadow: "0 0 0 3px #0e1020",
              opacity: interpolate(age, [20, 30], [1, 0], {
                extrapolateLeft: "clamp",
              }),
            }}
          />
        );
      })}
    </>
  );
};

/** A creature with its cell centred on (x, y), turned by `angle` degrees. A
 *  creature standing on a floor at height Y has its centre at Y - 11 × scale. */
export const At: React.FC<{
  x: number;
  y: number;
  angle?: number;
  species: Species;
  pose?: Pose;
  scale?: number;
  flip?: boolean;
  seed?: number;
  opacity?: number;
  children?: React.ReactNode;
}> = ({ x, y, angle = 0, scale = 4, opacity = 1, children, ...creature }) => (
  <div
    style={{
      position: "absolute",
      left: x - 16 * scale,
      top: y - 16 * scale,
      transform: `rotate(${angle}deg)`,
      opacity,
    }}
  >
    <Creature scale={scale} {...creature} />
    {children}
  </div>
);

/** Height of a creature's centre above the floor it stands on. */
export const lift = (scale: number) => 11 * scale;
