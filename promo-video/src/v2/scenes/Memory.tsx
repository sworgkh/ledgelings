import React from "react";
import { At, Stars } from "../../sprites";
import { Backdrop, Chip, ChipRow, Headline } from "../../ui";
import { C } from "../../theme";
import { Still } from "../Still";

const SIZE: [number, number] = [980, 640];

export const Memory: React.FC = () => (
  <Backdrop>
    <Headline
      kicker="07 · THEY REMEMBER"
      title="Every pair keeps a memory of the other"
      sub="Talks, tea, flowers, games and scores, condensed at nightfall. Watch it in Relationships."
      colour={C.pink}
    />
    <Still
      src="relationships.png"
      size={SIZE}
      crop={{ x: 0, y: 0, w: 280, h: 372 }}
      x={150}
      y={340}
      width={420}
      at={10}
      caption="RELATIONSHIPS"
      colour={C.pink}
    />
    <Still
      src="relationships.png"
      size={SIZE}
      crop={{ x: 290, y: 108, w: 690, h: 74 }}
      x={680}
      y={380}
      width={1080}
      at={40}
      colour={C.purple}
    />
    <Still
      src="relationships.png"
      size={SIZE}
      crop={{ x: 290, y: 392, w: 690, h: 48 }}
      x={680}
      y={560}
      width={1080}
      at={70}
      colour={C.yellow}
    />
    <At species="blocky" x={1040} y={830} scale={4} pose="idle" />
    <At species="ghost" x={1180} y={830} scale={4} pose="idle" flip seed={2} />
    <Stars x={1110} y={760} at={100} />
    <ChipRow>
      <Chip at={30} colour={C.pink}>
        Dated facts, a line a day
      </Chip>
      <Chip at={80} colour={C.purple}>
        150 tokens a prompt
      </Chip>
      <Chip at={130} colour={C.yellow}>
        Every limit is a setting
      </Chip>
    </ChipRow>
  </Backdrop>
);
