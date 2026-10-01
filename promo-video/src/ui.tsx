import React from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, bodyFont, pixelFont } from "./theme";

export const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;

/** Navy desk with a faint pixel grid, the same behind every scene. */
export const Backdrop: React.FC<{ children?: React.ReactNode }> = ({
  children,
}) => (
  <AbsoluteFill
    style={{
      background: C.bg,
      backgroundImage: `linear-gradient(${C.bgGrid} 2px, transparent 2px), linear-gradient(90deg, ${C.bgGrid} 2px, transparent 2px)`,
      backgroundSize: "48px 48px",
      fontFamily: bodyFont,
      color: C.ink,
    }}
  >
    {children}
  </AbsoluteFill>
);

/** Kicker, title and one line of plain words at the top of a scene. */
export const Headline: React.FC<{
  kicker: string;
  title: string;
  sub?: string;
  colour: string;
}> = ({ kicker, title, sub, colour }) => {
  const f = useCurrentFrame();
  const rise = (d: number) => ({
    opacity: interpolate(f, [d, d + 12], [0, 1], clamp),
    transform: `translateY(${interpolate(f, [d, d + 16], [24, 0], { ...clamp, easing: Easing.out(Easing.cubic) })}px)`,
  });
  return (
    <div
      style={{
        position: "absolute",
        top: 58,
        left: 0,
        right: 0,
        textAlign: "center",
      }}
    >
      <div
        style={{
          ...rise(0),
          fontFamily: pixelFont,
          fontSize: 26,
          letterSpacing: 6,
          color: colour,
          fontWeight: 700,
        }}
      >
        {kicker}
      </div>
      <div
        style={{
          ...rise(3),
          fontFamily: pixelFont,
          fontWeight: 700,
          fontSize: 78,
          lineHeight: 1.1,
          marginTop: 10,
        }}
      >
        {title}
      </div>
      {sub && (
        <div
          style={{
            ...rise(8),
            fontSize: 32,
            fontWeight: 600,
            color: C.dim,
            marginTop: 10,
          }}
        >
          {sub}
        </div>
      )}
    </div>
  );
};

/** A screen: bezel, wallpaper, and a coordinate space for whatever walks on it. */
export const Monitor: React.FC<{
  x: number;
  y: number;
  w: number;
  h: number;
  wallpaper?: string;
  children?: React.ReactNode;
  seams?: number[];
}> = ({ x, y, w, h, wallpaper, children, seams = [] }) => (
  <div
    style={{
      position: "absolute",
      left: x - 16,
      top: y - 16,
      width: w + 32,
      height: h + 32,
      background: C.bezel,
      borderRadius: 22,
      boxShadow: `inset 0 0 0 4px ${C.bezelLight}, 0 30px 60px rgba(0,0,0,0.45)`,
    }}
  >
    <div
      style={{
        position: "absolute",
        left: 16,
        top: 16,
        width: w,
        height: h,
        overflow: "hidden",
        borderRadius: 6,
        background:
          wallpaper ??
          "linear-gradient(160deg, #2f3a73 0%, #5a4c8f 55%, #c0729a 100%)",
      }}
    >
      {seams.map((s) => (
        <div
          key={s}
          style={{
            position: "absolute",
            left: s - 8,
            top: 0,
            width: 16,
            height: h,
            background: C.bezel,
          }}
        />
      ))}
      {children}
    </div>
  </div>
);

/** Where a creature walking the inside of a w×h outline is after `s` pixels,
 *  starting bottom-left and going right, up, left, down: the centre of its
 *  cell sits `inset` inside the edge, and it turns smoothly round each corner. */
export const onOutline = (s: number, w: number, h: number, inset: number) => {
  const lx = w - 2 * inset;
  const ly = h - 2 * inset;
  const segs = [lx, ly, lx, ly];
  const p = 2 * (lx + ly);
  let u = ((s % p) + p) % p;
  let k = 0;
  while (u > segs[k]) {
    u -= segs[k];
    k = (k + 1) % 4;
  }
  const corners = [
    [inset, h - inset],
    [w - inset, h - inset],
    [w - inset, inset],
    [inset, inset],
  ];
  const dirs = [
    [1, 0],
    [0, -1],
    [-1, 0],
    [0, 1],
  ];
  const [cx, cy] = corners[k];
  const [dx, dy] = dirs[k];
  const c = inset * 0.9;
  let turn = 0;
  if (u > segs[k] - c) turn = (u - (segs[k] - c)) / (2 * c);
  else if (u < c) turn = u / (2 * c) - 0.5;
  const angle = -90 * (k + turn);
  return { x: cx + dx * u, y: cy + dy * u, angle };
};

/** A speech bubble in the pixel style: a dark 4 px outline and a stepped tail,
 *  typing its line out from `at`. Anchored at the tail tip. */
export const Bubble: React.FC<{
  x: number;
  y: number;
  at: number;
  text: string;
  name?: string;
  colour?: string;
  width?: number;
  until?: number;
  below?: boolean;
  tail?: number;
}> = ({
  x,
  y,
  at,
  text,
  name,
  colour = C.orange,
  width = 560,
  until,
  below = false,
  tail = 0.5,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (f < at || (until !== undefined && f > until + 10)) return null;
  const pop = spring({
    frame: f - at,
    fps,
    config: { damping: 12, stiffness: 180 },
  });
  const out =
    until === undefined
      ? 1
      : interpolate(f, [until, until + 10], [1, 0], clamp);
  const shown = text.slice(0, Math.floor((f - at - 4) * 1.6));
  const tailX = width * tail;
  // A stepped tail: three paper rows, each narrower, outlined at the sides only.
  const tailRows = [28, 18, 8].map((w, i) => (
    <div
      key={i}
      style={{
        position: "absolute",
        left: tailX - w / 2 - 4,
        width: w,
        height: 10,
        [below ? "bottom" : "top"]: `calc(100% - 4px + ${i * 10}px)`,
        background: C.paper,
        borderLeft: `4px solid ${C.outline}`,
        borderRight: `4px solid ${C.outline}`,
        [below ? "borderTop" : "borderBottom"]:
          i === 2 ? `4px solid ${C.outline}` : undefined,
        zIndex: 2,
      }}
    />
  ));
  return (
    <div
      style={{
        position: "absolute",
        left: x - tailX,
        top: below ? y + 34 : undefined,
        bottom: below ? undefined : `calc(100% - ${y - 34}px)`,
        width,
        transform: `scale(${pop * out})`,
        transformOrigin: `${tailX}px ${below ? "-34px" : "calc(100% + 34px)"}`,
        opacity: out,
      }}
    >
      {tailRows}
      <div
        style={{
          position: "relative",
          background: C.paper,
          color: "#1d1f33",
          border: `4px solid ${C.outline}`,
          boxShadow: `inset -6px -6px 0 ${C.paperShade}, 8px 8px 0 rgba(0,0,0,0.35)`,
          padding: "20px 26px 22px",
          fontSize: 34,
          fontWeight: 800,
          lineHeight: 1.25,
        }}
      >
        {name && (
          <div
            style={{
              fontFamily: pixelFont,
              fontSize: 22,
              fontWeight: 700,
              color: colour,
              letterSpacing: 2,
              marginBottom: 6,
              WebkitTextStroke: "0.5px #1d1f33",
            }}
          >
            {name}
          </div>
        )}
        <span>{shown}</span>
        <span style={{ visibility: "hidden" }}>{text.slice(shown.length)}</span>
      </div>
    </div>
  );
};

/** A small rounded label that pops in at `at`. */
export const Chip: React.FC<{
  at: number;
  colour: string;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ at, colour, children, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({
    frame: f - at,
    fps,
    config: { damping: 11, stiffness: 160 },
  });
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 14,
        padding: "14px 26px",
        background: "rgba(255,255,255,0.06)",
        border: `3px solid ${colour}`,
        borderRadius: 999,
        fontSize: 30,
        fontWeight: 800,
        transform: `scale(${s})`,
        opacity: Math.min(1, s * 1.5),
        ...style,
      }}
    >
      <div style={{ width: 14, height: 14, background: colour }} />
      {children}
    </div>
  );
};

/** A row of chips, centred, near the bottom of the frame. */
export const ChipRow: React.FC<{
  children: React.ReactNode;
  bottom?: number;
}> = ({ children, bottom = 46 }) => (
  <div
    style={{
      position: "absolute",
      left: 0,
      right: 0,
      bottom,
      display: "flex",
      justifyContent: "center",
      gap: 26,
    }}
  >
    {children}
  </div>
);

/** The mouse cursor, the colony's sworn enemy. */
export const Cursor: React.FC<{ x: number; y: number; scale?: number }> = ({
  x,
  y,
  scale = 1.6,
}) => (
  <svg
    width={24 * scale}
    height={34 * scale}
    viewBox="0 0 24 34"
    style={{
      position: "absolute",
      left: x,
      top: y,
      filter: "drop-shadow(2px 4px 4px rgba(0,0,0,0.5))",
    }}
  >
    <path
      d="M1 1 L1 27 L7.5 21 L12 32 L16.5 30 L12 19.5 L21 19.5 Z"
      fill="#fff"
      stroke="#000"
      strokeWidth="2"
      strokeLinejoin="round"
    />
  </svg>
);
