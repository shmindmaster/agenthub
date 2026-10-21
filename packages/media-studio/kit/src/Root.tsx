import type { FC } from "react";
import "./index.css";
import { CalculateMetadataFunction, Composition } from "remotion";
import { Briefing, BriefingProps, sampleScenes } from "./Briefing";
import { MarketingAd, MarketingAdProps, sampleMarketingAd } from "./MarketingAd";

const FPS = 30;
const WIDTH = 1600;
const HEIGHT = 1000;

const calculateMetadata: CalculateMetadataFunction<BriefingProps> = ({
  props,
}) => {
  const seconds = props.scenes.reduce(
    (sum, scene) => sum + Math.max(0.5, scene.durationSeconds),
    0,
  );
  return {
    durationInFrames: Math.max(FPS, Math.round(seconds * FPS)),
    fps: FPS,
    width: WIDTH,
    height: HEIGHT,
  };
};

// MarketingAd (kit/marketing, mvg): frame size and length come from the props the generator writes per ratio.
const marketingMetadata: CalculateMetadataFunction<MarketingAdProps> = ({
  props,
}) => ({
  durationInFrames: Math.max(FPS, Math.round(props.durationSec * props.fps)),
  fps: props.fps,
  width: props.width,
  height: props.height,
});

export const RemotionRoot: FC = () => {
  return (
    <>
      <Composition
        id="Briefing"
        component={Briefing}
        durationInFrames={8 * FPS}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
        defaultProps={{ scenes: sampleScenes }}
        calculateMetadata={calculateMetadata}
      />
      <Composition
        id="MarketingAd"
        component={MarketingAd}
        durationInFrames={6 * FPS}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={sampleMarketingAd}
        calculateMetadata={marketingMetadata}
      />
    </>
  );
};
