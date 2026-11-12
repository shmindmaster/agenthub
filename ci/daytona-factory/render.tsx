import React from "react";
import { AbsoluteFill, Composition, OffthreadVideo, registerRoot, staticFile } from "remotion";

function Capture() {
  return <AbsoluteFill><OffthreadVideo src={staticFile("capture.webm")} muted /></AbsoluteFill>;
}

function Root() {
  return (
    <Composition
      id="Capture"
      component={Capture}
      fps={25}
      width={2}
      height={2}
      durationInFrames={1}
      defaultProps={{ frames: 1, width: 2, height: 2 }}
      calculateMetadata={({ props }) => ({
        durationInFrames: props.frames,
        width: props.width,
        height: props.height,
      })}
    />
  );
}

registerRoot(Root);
