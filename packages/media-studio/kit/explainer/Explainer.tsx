/**
 * The explainer composition: one stage, one sequence per shot, chrome on top.
 *
 * The props rendered here are written by kit/explainer/build-explainer.mjs and gated
 * by kit/explainer/validate-explainer-release.mjs — this file places them on a clock
 * and does not decide timing, order or which shot exists.
 *
 * There is no caption layer, deliberately. Captions travel as a sidecar .srt;
 * an explainer that burned its words into the picture would have to be
 * re-rendered to ship without them.
 */
import type { FC } from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile } from 'remotion';
import { Hud, Progress } from './Chrome';
import { Stage } from './Stage';
import { Shot } from './shots';
import { T, type ExplainerProps } from './types';

export const Explainer: FC<ExplainerProps> = ({
  film,
  shots,
  voiceoverFile,
}) => {
  return (
    <AbsoluteFill
      style={{
        backgroundColor: T.color.base,
        color: T.color.ink,
        fontFamily: T.type.family,
      }}
    >
      {voiceoverFile ? <Audio src={staticFile(voiceoverFile)} /> : null}
      <Stage film={film} shots={shots} />
      {shots.map((shot, index) => (
        <Sequence
          key={shot.id}
          from={shot.startFrame}
          durationInFrames={shot.durationFrames}
          name={`${shot.id} ${shot.archetype}`}
        >
          <Shot shot={shot} film={film} index={index} />
        </Sequence>
      ))}
      <Hud film={film} shots={shots} />
      <Progress film={film} shots={shots} />
    </AbsoluteFill>
  );
};
