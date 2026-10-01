import React from "react";
import { AbsoluteFill, Html5Audio, staticFile } from "remotion";
import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { Intro } from "./scenes/Intro";
import { Edges } from "./scenes/Edges";
import { Hand } from "./scenes/Hand";
import { DayNight } from "./scenes/DayNight";
import { Talk } from "./scenes/Talk";
import { Flowers } from "./scenes/Flowers";
import { Planes } from "./scenes/Planes";
import { TeaParty } from "./scenes/TeaParty";
import { Reminders } from "./scenes/Reminders";
import { Numbers } from "./scenes/Numbers";
import { Outro } from "./scenes/Outro";

/** The scenes in order, with how long each one plays, in frames at 30 fps. */
const SCENES: [React.FC, number][] = [
  [Intro, 150],
  [Edges, 270],
  [Hand, 230],
  [DayNight, 180],
  [Talk, 250],
  [Flowers, 270],
  [Planes, 250],
  [TeaParty, 210],
  [Reminders, 230],
  [Numbers, 200],
  [Outro, 230],
];

export const TRANSITION = 14;
export const DURATION =
  SCENES.reduce((sum, [, d]) => sum + d, 0) - TRANSITION * (SCENES.length - 1);

export const Promo: React.FC = () => (
  <AbsoluteFill>
    <Html5Audio src={staticFile("music.wav")} volume={0.8} />
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
