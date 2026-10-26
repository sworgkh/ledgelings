import React from "react";
import { Backdrop, Chip, ChipRow, Headline } from "../../ui";
import { C } from "../../theme";
import { Still } from "../Still";

const SWAP = 130;

export const Words: React.FC = () => (
  <Backdrop>
    <Headline
      kicker="09 · TOOLS · SPEAK AND TRANSLATE"
      title="Say it, or type it in another language"
      sub="Dictation writes your words onto the clipboard. Translate guesses the ending as you type."
      colour={C.teal}
    />
    <Still
      src="dictate-listening.png"
      size={[716, 360]}
      x={110}
      y={330}
      width={600}
      at={10}
      caption="⌃⌥D  LISTENING"
      colour={C.green}
    />
    <Still
      src="dictate-copied.png"
      size={[716, 360]}
      x={190}
      y={640}
      width={560}
      at={60}
      caption="COPIED"
      colour={C.yellow}
    />
    <Still
      src="translate-russian.png"
      size={[1000, 618]}
      x={880}
      y={340}
      width={920}
      at={30}
      until={SWAP}
      caption="⌃⌥T  TRANSLATE"
      colour={C.teal}
    />
    <Still
      src="translate-hebrew.png"
      size={[1000, 618]}
      x={880}
      y={340}
      width={920}
      at={SWAP + 4}
      caption="⌃⌥T  INTO HEBREW"
      colour={C.purple}
    />
    <ChipRow>
      <Chip at={40} colour={C.green}>
        Ums and false starts left out
      </Chip>
      <Chip at={90} colour={C.teal}>
        English, Russian, Hebrew
      </Chip>
      <Chip at={SWAP + 10} colour={C.purple}>
        Priced call by call
      </Chip>
    </ChipRow>
  </Backdrop>
);
