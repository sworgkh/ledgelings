import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { Backdrop, Chip, ChipRow, Headline, clamp } from "../../ui";
import { C, pixelFont } from "../../theme";
import { Still } from "../Still";

// The first line of the prompt the kit writes (`--kit-images`, prompt.txt).
const PROMPT = "Paint me a new creature for a pixel-art desktop toy.";

export const Kit: React.FC = () => {
  const f = useCurrentFrame();
  const typed = PROMPT.slice(0, Math.max(0, Math.floor((f - 70) * 1.4)));
  const arrow = interpolate(f, [110, 130], [0, 1], clamp);
  return (
    <Backdrop>
      <Headline
        kicker="01 · YOUR OWN SPECIES"
        title="Describe a creature, any image model paints it"
        sub="The sprite kit writes the prompt and two pictures. Import… reads the painting back."
        colour={C.orange}
      />
      <Still
        src="kit-poses.png"
        size={[1728, 288]}
        x={90}
        y={390}
        width={860}
        at={14}
        colour={C.orange}
      />
      <Still
        src="kit-template.png"
        size={[1728, 288]}
        x={90}
        y={620}
        width={860}
        at={34}
        colour={C.pink}
      />
      <div
        style={{
          position: "absolute",
          left: 90,
          top: 820,
          width: 860,
          padding: "16px 22px",
          background: C.paper,
          color: "#1d1f33",
          border: `4px solid ${C.outline}`,
          boxShadow: `inset -6px -6px 0 ${C.paperShade}, 8px 8px 0 rgba(0,0,0,0.35)`,
          fontSize: 30,
          fontWeight: 800,
          opacity: f >= 66 ? 1 : 0,
        }}
      >
        <span style={{ color: C.purple, fontFamily: pixelFont }}>PROMPT </span>
        {typed}
        <span style={{ visibility: "hidden" }}>
          {PROMPT.slice(typed.length)}
        </span>
      </div>
      <div
        style={{
          position: "absolute",
          left: 975,
          top: 600,
          fontFamily: pixelFont,
          fontWeight: 700,
          fontSize: 64,
          color: C.yellow,
          opacity: arrow,
          transform: `translateX(${(1 - arrow) * -30}px)`,
          textShadow: `5px 5px 0 ${C.outline}`,
        }}
      >
        ▶
      </div>
      <Still
        src="sprites.png"
        size={[1280, 760]}
        crop={{ x: 241, y: 82, w: 490, h: 292 }}
        x={1070}
        y={400}
        width={760}
        at={124}
        caption="SETTINGS › SPRITES"
        colour={C.teal}
      />
      <ChipRow>
        <Chip at={40} colour={C.orange}>
          Name, colour, three characters
        </Chip>
        <Chip at={90} colour={C.pink}>
          ChatGPT, Gemini, any image model
        </Chip>
        <Chip at={140} colour={C.teal}>
          Imported at any size
        </Chip>
      </ChipRow>
    </Backdrop>
  );
};
