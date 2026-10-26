import React from "react";
import { Backdrop, Chip, ChipRow, Headline } from "../../ui";
import { C } from "../../theme";
import { Still } from "../Still";

const SIZE: [number, number] = [1280, 760];

export const Costs: React.FC = () => (
  <Backdrop>
    <Headline
      kicker="11 · NO MONEY IN THE DARK"
      title="Every model call is priced, per feature"
      sub="Talk, voices, games, memory, dictation, translation: Settings › Costs adds it up."
      colour={C.green}
    />
    <Still
      src="costs.png"
      size={SIZE}
      crop={{ x: 241, y: 76, w: 490, h: 152 }}
      x={140}
      y={400}
      width={780}
      at={10}
      caption="SPENT"
      colour={C.green}
    />
    <Still
      src="costs.png"
      size={SIZE}
      crop={{ x: 241, y: 282, w: 490, h: 330 }}
      x={1040}
      y={380}
      width={740}
      at={40}
      caption="BY FEATURE"
      colour={C.teal}
    />
    <ChipRow>
      <Chip at={30} colour={C.green}>
        Built-in lines cost nothing
      </Chip>
      <Chip at={70} colour={C.teal}>
        LM Studio is free, and recorded at $0
      </Chip>
    </ChipRow>
  </Backdrop>
);
