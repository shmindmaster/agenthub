import type { FC } from "react";
import "./index.css";
import { CalculateMetadataFunction, Composition } from "remotion";
import { Briefing, BriefingProps, sampleScenes } from "./Briefing";
import { MarketingAd, MarketingAdProps, sampleMarketingAd } from "./MarketingAd";
import { Explainer } from "../explainer/Explainer";
import type { ExplainerProps } from "../explainer/types";

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

// Explainer (kit/explainer): the props carry every shot's frame range, so the
// composition length is the sum of the shots — never a second, hand-kept clock.
const explainerMetadata: CalculateMetadataFunction<ExplainerProps> = ({
  props,
}) => ({
  durationInFrames: Math.max(
    1,
    props.shots.reduce((sum, shot) => sum + shot.durationFrames, 0),
  ),
  fps: props.film.fps,
  width: props.film.width,
  height: props.film.height,
});

const sampleExplainer: ExplainerProps = {
  film: {
    id: "sample",
    title: "Explainer sample",
    backdrop: "dots",
    width: WIDTH,
    height: HEIGHT,
    fps: FPS,
    chapters: [
      {
        id: "c1",
        label: "The sample",
        startSeconds: 0,
        endSeconds: 8,
        startFrame: 0,
        endFrame: 8 * FPS,
      },
    ],
  },
  shots: [
    {
      id: "S01",
      archetype: "cold-open",
      family: "statement",
      chapterId: "c1",
      startSeconds: 0,
      durationSeconds: 8,
      startFrame: 0,
      durationFrames: 8 * FPS,
      kicker: "SAMPLE",
      title: "One revision lands overnight.",
      sub: "The explainer composition, from the props build-explainer.mjs writes.",
      chrome: "minimal",
      heroAtSeconds: 0.15,
      holdSeconds: 7.85,
      beats: [],
    },
  ],
  totalSeconds: 8,
};

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
      <Composition
        id="Explainer"
        component={Explainer}
        durationInFrames={8 * FPS}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
        defaultProps={sampleExplainer}
        calculateMetadata={explainerMetadata}
      />
    </>
  );
};
