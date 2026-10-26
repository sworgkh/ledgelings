import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { At, Plane, lift } from "../../sprites";
import { Backdrop, Chip, ChipRow, Headline, Monitor, clamp } from "../../ui";
import { C, pixelFont } from "../../theme";
import { Still } from "../Still";

const W = 1000;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);
const BLOCKY = 150;
const UNIT7 = 850;
const ASK = 14;
const ANSWER = 118;

/** A paper plane thrown from `from` to `to`, starting at `at`, 30 frames in the air. */
const Throw: React.FC<{ from: number; to: number; at: number }> = ({
  from,
  to,
  at,
}) => {
  const t = useCurrentFrame() - at;
  if (t < 0 || t > 30) return null;
  const k = t / 30;
  return (
    <Plane
      scale={4}
      style={{
        position: "absolute",
        left: from + (to - from) * k - 64,
        top: FLOOR - 120 - Math.sin(Math.PI * k) * 160,
        transform: `scaleX(${to < from ? -1 : 1})`,
      }}
    />
  );
};

/** A letter opened beside the screen it was thrown on: the words, and who wrote it. */
const Letter: React.FC<{
  at: number;
  until: number;
  text: string;
  by: string;
  colour: string;
  x: number;
  y: number;
}> = ({ at, until, text, by, colour, x, y }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (f < at || f > until + 10) return null;
  const open = spring({
    frame: f - at,
    fps,
    config: { damping: 12, stiffness: 150 },
  });
  const out = interpolate(f, [until, until + 10], [1, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 560,
        padding: "26px 30px",
        background: C.paper,
        color: "#1d1f33",
        border: `4px solid ${C.outline}`,
        boxShadow: `inset -6px -6px 0 ${C.paperShade}, 10px 10px 0 rgba(0,0,0,0.35)`,
        fontSize: 36,
        fontWeight: 800,
        lineHeight: 1.3,
        transform: `scaleY(${open * out}) rotate(-1.5deg)`,
        transformOrigin: "top",
      }}
    >
      {text}
      <div
        style={{
          marginTop: 14,
          fontFamily: pixelFont,
          fontSize: 26,
          color: colour,
          textAlign: "right",
          WebkitTextStroke: "0.5px #1d1f33",
        }}
      >
        — {by}
      </div>
    </div>
  );
};

export const Deeds: React.FC = () => {
  const f = useCurrentFrame();
  const walk = interpolate(f, [196, 250], [0, 1], clamp);
  return (
    <Backdrop>
      <Headline
        kicker="06 · THEY DO WHAT THEY SAY"
        title="A letter says soccer? A yes, then a game"
        sub="Invite, accept, decline, visit, bring a flower: talk and letters turn into deeds."
        colour={C.yellow}
      />
      <Monitor x={110} y={380} w={W} h={H}>
        <At
          species="blocky"
          x={BLOCKY + walk * 260}
          y={FLOOR}
          scale={S}
          pose={walk > 0 && walk < 1 ? "walk" : "idle"}
        />
        <At
          species="robot"
          x={UNIT7 - walk * 260}
          y={FLOOR}
          scale={S}
          flip
          seed={3}
          pose={walk > 0 && walk < 1 ? "walk" : "idle"}
        />
        <Throw from={BLOCKY} to={UNIT7} at={ASK} />
        <Throw from={UNIT7} to={BLOCKY} at={ANSWER} />
      </Monitor>
      <Letter
        at={ASK + 30}
        until={ANSWER - 6}
        x={1220}
        y={420}
        text="Unit 7. Soccer. Bottom edge. Unless you're scared of losing."
        by="BLOCKY"
        colour={C.orange}
      />
      <Letter
        at={ANSWER + 30}
        until={192}
        x={1220}
        y={420}
        text="Accepted, Blocky. Soccer. Recalculating odds: 63%."
        by="UNIT 7"
        colour={C.teal}
      />
      <Still
        src="invite-goal.png"
        size={[1280, 720]}
        crop={{ x: 0, y: 540, w: 700, h: 180 }}
        x={1170}
        y={580}
        width={660}
        at={200}
        caption="…AND THE GAME"
        colour={C.yellow}
        angle={1.5}
      />
      <Still
        src="invite-goal.png"
        size={[1280, 720]}
        crop={{ x: 430, y: 0, w: 420, h: 60 }}
        x={1250}
        y={440}
        width={500}
        at={216}
        colour={C.yellow}
        angle={-1}
      />
      <ChipRow>
        <Chip at={40} colour={C.orange}>
          Built-in invitations per character
        </Chip>
        <Chip at={ANSWER + 30} colour={C.teal}>
          Or the model&apos;s own words
        </Chip>
        <Chip at={210} colour={C.yellow}>
          Deeds from Talk, in the menu
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
