import React from "react";
import { AbsoluteFill, Html5Audio, staticFile } from "remotion";
import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { TRANSITION } from "../Promo";
import { Outro } from "../scenes/Outro";
import { IntroV2 } from "./scenes/IntroV2";
import { Kit } from "./scenes/Kit";
import { Screens } from "./scenes/Screens";
import { Beds } from "./scenes/Beds";
import { Games } from "./scenes/Games";
import { Revenge } from "./scenes/Revenge";
import { Deeds } from "./scenes/Deeds";
import { Memory } from "./scenes/Memory";
import { ClipShot } from "./scenes/ClipShot";
import { Words } from "./scenes/Words";
import { ToolsSheet } from "./scenes/ToolsSheet";
import { Costs } from "./scenes/Costs";

const OutroV2: React.FC = () => (
  <Outro
    line="Now they sleep, play, remember, and help."
    sub="Every feature has its settings. Every call has its price."
  />
);

/** Everything new since the first promo (v0.18.0), in order, with how long each
 *  scene plays, in frames at 30 fps. */
const SCENES: [React.FC, number][] = [
  [IntroV2, 150],
  [Kit, 210],
  [Screens, 190],
  [Beds, 230],
  [Games, 260],
  [Revenge, 250],
  [Deeds, 270],
  [Memory, 180],
  [ClipShot, 220],
  [Words, 240],
  [ToolsSheet, 140],
  [Costs, 160],
  [OutroV2, 180],
];

export const DURATION_V2 =
  SCENES.reduce((sum, [, d]) => sum + d, 0) - TRANSITION * (SCENES.length - 1);

export const PromoV2: React.FC = () => (
  <AbsoluteFill>
    <Html5Audio src={staticFile("music-v2.wav")} volume={0.8} />
    <TransitionSeries>
      {SCENES.flatMap(([Scene, frames], i) => [
        ...(i === 0
          ? []
          : [
              <TransitionSeries.Transition
                key={`t${i}`}
                presentation={
                  i % 3 === 0 ? slide({ direction: "from-right" }) : fade()
                }
                timing={linearTiming({ durationInFrames: TRANSITION })}
              />,
            ]),
        <TransitionSeries.Sequence key={`s${i}`} durationInFrames={frames}>
          <Scene />
        </TransitionSeries.Sequence>,
      ])}
    </TransitionSeries>
  </AbsoluteFill>
);
