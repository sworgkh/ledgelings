import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { At } from "../../sprites";
import { Backdrop, Chip, ChipRow, Headline, clamp } from "../../ui";
import { C } from "../../theme";
import { Still } from "../Still";

/** The creature that brought the picker, holding its top-left corner, as
 *  `--clip-film` shows it: it leaps in with the sheet, then hangs on. */
const Bringer: React.FC = () => {
  const f = useCurrentFrame();
  const k = interpolate(f, [0, 12], [0, 1], clamp);
  return (
    <At
      species="robot"
      x={-60 + 160 * k}
      y={360 + 30 - Math.sin(Math.PI * k) * 120}
      scale={4}
      pose={k < 1 ? "jump" : "idle"}
    />
  );
};

export const ClipShot: React.FC = () => (
  <Backdrop>
    <Headline
      kicker="08 · TOOLS · COPY AND CAPTURE"
      title="A creature brings your clipboard"
      sub="Recent copies, pictures and snippets. Screenshots marked up with boxes, arrows and blur."
      colour={C.orange}
    />
    <Still
      src="clip-picker.png"
      size={[1100, 934]}
      crop={{ x: 180, y: 200, w: 920, h: 734 }}
      x={150}
      y={360}
      width={640}
      at={10}
      caption="⌃⌥V  CLIPBOARD"
      colour={C.orange}
    />
    <Bringer />
    <Still
      src="shot-toolbar-tip.png"
      size={[1512, 164]}
      x={850}
      y={350}
      width={960}
      at={70}
      caption="⌃⌥S  SCREENSHOT"
      colour={C.teal}
    />
    <Still
      src="shot-rectangle.png"
      size={[800, 520]}
      x={1030}
      y={530}
      width={600}
      at={100}
      colour={C.yellow}
      angle={-1.5}
    />
    <ChipRow>
      <Chip at={30} colour={C.orange}>
        Pictures kept, pasted back as they were
      </Chip>
      <Chip at={60} colour={C.pink}>
        Passwords shown as PWD:{"{Name}"}
      </Chip>
      <Chip at={110} colour={C.teal}>
        Pixel blur for what is private
      </Chip>
    </ChipRow>
  </Backdrop>
);
