import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { At, lift } from "../../sprites";
import { Backdrop, Chip, ChipRow, Headline, clamp } from "../../ui";
import { C } from "../../theme";
import { Still } from "../Still";

const FLOOR = 940;

export const ToolsSheet: React.FC = () => {
  const f = useCurrentFrame();
  const x = interpolate(f, [0, 50], [-80, 330], clamp);
  return (
    <Backdrop>
      <Headline
        kicker="10 · ALL THE TOOLS"
        title="One shortcut opens every tool"
        sub="⌃⌥K brings the Tools sheet: translate, dictate, capture, paste, remind."
        colour={C.yellow}
      />
      <Still
        src="tools.png"
        size={[1184, 768]}
        x={480}
        y={300}
        width={900}
        at={8}
        colour={C.yellow}
      />
      <div
        style={{
          position: "absolute",
          left: 100,
          top: FLOOR,
          width: 360,
          height: 8,
          background: C.bezelLight,
          boxShadow: `0 8px 0 ${C.bezel}`,
        }}
      />
      <At
        species="blocky"
        x={x}
        y={FLOOR - lift(4)}
        scale={4}
        pose={f < 50 ? "walk" : "idle"}
      />
      <ChipRow>
        <Chip at={40} colour={C.yellow}>
          Pick one by its number
        </Chip>
        <Chip at={80} colour={C.orange}>
          Or the wrench in Creature Actions
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
