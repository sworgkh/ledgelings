import React from "react";
import { useCurrentFrame } from "remotion";
import { At, Tea, lift } from "../sprites";
import { Backdrop, Bubble, Chip, ChipRow, Headline, Monitor } from "../ui";
import { C } from "../theme";

const W = 1400;
const H = 540;
const S = 4;
const FLOOR = H - lift(S);

export const TeaParty: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <Backdrop>
      <Headline
        kicker="07 · TEA PARTIES"
        title="Now and then, they sit down to tea"
        sub="Two who bump into each other tell each other their life stories."
        colour={C.green}
      />
      <Monitor
        x={260}
        y={360}
        w={W}
        h={H}
        wallpaper="linear-gradient(170deg, #3f3a5e 0%, #7a5a6e 55%, #d6a27a 100%)"
      >
        <At species="blocky" x={520} y={FLOOR} scale={S} pose="idle" />
        <Tea
          scale={5}
          style={{ position: "absolute", left: 700 - 90, top: H - 140 }}
        />
        <At
          species="blocky-pip"
          x={880}
          y={FLOOR}
          scale={S}
          flip
          seed={6}
          pose={f > 150 && f < 168 ? "jump" : "idle"}
        />
        <Bubble
          x={520}
          y={FLOOR - 70}
          at={14}
          until={112}
          tail={0.55}
          width={620}
          name="BLOCKY"
          colour={C.orange}
          text="I was the first one here. Before the colours, before the cursor. Those were good days."
        />
        <Bubble
          x={880}
          y={FLOOR - 70}
          at={118}
          tail={0.35}
          width={560}
          name="PIP"
          colour={C.teal}
          text="Ooh! That's amazing, Blocky! Tell me more! More more more!"
        />
      </Monitor>
      <ChipRow>
        <Chip at={30} colour={C.green}>
          A story for each of them
        </Chip>
        <Chip at={110} colour={C.yellow}>
          Then they walk on
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
