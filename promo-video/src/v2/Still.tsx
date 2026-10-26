import React from "react";
import {
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { clamp } from "../ui";
import { C, pixelFont } from "../theme";

type Crop = { x: number; y: number; w: number; h: number };

/** A picture the app wrote of itself (public/stills, made by
 *  scripts/capture-stills.sh), cropped to `crop`, shown `width` wide with a dark
 *  pixel frame and a caption tab, popping in at `at`. Nothing in it is drawn here. */
export const Still: React.FC<{
  src: string;
  size: [number, number];
  crop?: Crop;
  x: number;
  y: number;
  width: number;
  at: number;
  caption?: string;
  colour?: string;
  until?: number;
  angle?: number;
}> = ({
  src,
  size,
  crop,
  x,
  y,
  width,
  at,
  caption,
  colour = C.teal,
  until,
  angle = 0,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (f < at) return null;
  const c = crop ?? { x: 0, y: 0, w: size[0], h: size[1] };
  const k = width / c.w;
  const pop = spring({
    frame: f - at,
    fps,
    config: { damping: 13, stiffness: 140 },
  });
  const out =
    until === undefined
      ? 1
      : interpolate(f, [until, until + 10], [1, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        transform: `translateY(${(1 - pop) * 60}px) rotate(${angle}deg) scale(${0.85 + 0.15 * pop})`,
        opacity: Math.min(1, pop * 1.6) * out,
      }}
    >
      <div
        style={{
          width: c.w * k,
          height: c.h * k,
          overflow: "hidden",
          position: "relative",
          border: `6px solid ${C.outline}`,
          boxShadow: `10px 10px 0 rgba(0,0,0,0.4), 0 0 0 4px ${colour}`,
          background: C.outline,
        }}
      >
        <Img
          src={staticFile(`stills/${src}`)}
          style={{
            position: "absolute",
            left: -c.x * k,
            top: -c.y * k,
            width: size[0] * k,
            height: size[1] * k,
            maxWidth: "none",
          }}
        />
      </div>
      {caption && (
        <div
          style={{
            position: "absolute",
            left: 18,
            top: -26,
            padding: "6px 14px",
            background: colour,
            color: C.outline,
            fontFamily: pixelFont,
            fontWeight: 700,
            fontSize: 24,
            letterSpacing: 1,
            border: `4px solid ${C.outline}`,
          }}
        >
          {caption}
        </div>
      )}
    </div>
  );
};
