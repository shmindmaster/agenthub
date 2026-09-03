import type { FC } from "react";
import "./index.css";
import { CalculateMetadataFunction, Composition } from "remotion";
import { Briefing, BriefingProps, sampleScenes } from "./Briefing";

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

export const RemotionRoot: FC = () => {
  return (
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
  );
};
