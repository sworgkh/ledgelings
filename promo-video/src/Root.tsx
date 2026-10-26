import React from "react";
import { Composition } from "remotion";
import { DURATION, Promo } from "./Promo";
import { DURATION_V2, PromoV2 } from "./v2/PromoV2";
import { FPS } from "./theme";

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="Promo"
      component={Promo}
      durationInFrames={DURATION}
      fps={FPS}
      width={1920}
      height={1080}
    />
    <Composition
      id="PromoV2"
      component={PromoV2}
      durationInFrames={DURATION_V2}
      fps={FPS}
      width={1920}
      height={1080}
    />
  </>
);
