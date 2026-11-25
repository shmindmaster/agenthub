/**
 * The two pieces of furniture a film is allowed: a title/chapter line at the
 * top and a chapter-segmented progress bar at the bottom edge.
 *
 * There is deliberately no caption component here. The owner's media policy
 * keeps captions as a sidecar .srt, so nothing in this file may draw words over
 * the picture — a subtitle band burned into the frame would have to be removed
 * before delivery, and it would sit exactly where the compositions put their
 * sub-line.
 */
import type { FC } from 'react';
import { useCurrentFrame, useVideoConfig } from 'remotion';
import { progress } from './motion.mjs';
import {
  T,
  accentOf,
  shotAtFrame,
  type ExplainerFilm,
  type ExplainerShot,
} from './types';

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));

/** Top-left film title, top-right chapter. Absent for three seconds so a cold
 * open is type only, and absent whenever the shot asked for no chrome.
 *
 * It sits at the frame edge rather than inside the safe area: every family's
 * first type row starts at 7.5% of the height, and the HUD ends by 5% so the two
 * never read as one block. Like the progress bar, this is chrome on the edge of
 * the picture, not content. A film whose one chapter carries the film's own
 * title prints it once. */
export const Hud: FC<{ film: ExplainerFilm; shots: ExplainerShot[] }> = ({
  film,
  shots,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (film.chrome?.hud === false) return null;
  const shot = shotAtFrame(shots, frame);
  if (!shot || shot.chrome === 'none') return null;
  const appear = progress('fade', frame, fps, 3);
  if (appear <= 0) return null;
  const chapter = film.chapters.find((c) => c.id === shot.chapterId);
  const inset = Math.round(film.width * 0.075);

  return (
    <div
      style={{
        position: 'absolute',
        left: inset,
        right: inset,
        top: Math.round(film.height * 0.026),
        display: 'flex',
        alignItems: 'baseline',
        justifyContent: 'space-between',
        gap: 32,
        opacity: 0.55 * appear,
        pointerEvents: 'none',
        fontFamily: T.type.family,
        color: T.color.ink,
        textTransform: 'uppercase',
        whiteSpace: 'nowrap',
      }}
    >
      <div
        style={{
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: '0.26em',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
        }}
      >
        {film.title}
      </div>
      <div
        style={{
          fontSize: 18,
          fontWeight: 600,
          letterSpacing: '0.2em',
          color: T.color.muted,
          flexShrink: 0,
        }}
      >
        {chapter && chapter.label !== film.title ? chapter.label : ''}
      </div>
    </div>
  );
};

/**
 * A bar split by chapter, not one continuous run: the viewer should be able to
 * see how many movements the film has and which one they are in. The current
 * segment fills with the shot's accent; earlier ones stay full; later ones are
 * a 12% track.
 */
export const Progress: FC<{ film: ExplainerFilm; shots: ExplainerShot[] }> = ({
  film,
  shots,
}) => {
  const frame = useCurrentFrame();
  if (film.chrome?.progress === false) return null;
  const shot = shotAtFrame(shots, frame);
  if (!shot) return null;
  // The chapter family is chrome 'none', but its grammar note is explicit that
  // the bar ticks over while the card is up — and a bar that blinks out at every
  // chapter boundary reads as a fault, not as restraint. It survives that one
  // family and nothing else.
  if (shot.chrome === 'none' && shot.family !== 'chapter') return null;
  const accent = accentOf(shot, film);

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 0,
        height: 4,
        display: 'flex',
        gap: 2,
        pointerEvents: 'none',
      }}
    >
      {film.chapters.map((chapter) => {
        const span = Math.max(1, chapter.endFrame - chapter.startFrame);
        const reached = clamp01((frame - chapter.startFrame) / span);
        const fill = frame >= chapter.endFrame ? 1 : reached;
        return (
          <div
            key={chapter.id}
            style={{
              position: 'relative',
              flex: span,
              flexBasis: 0,
              background: 'rgba(255,255,255,0.12)',
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                position: 'absolute',
                left: 0,
                top: 0,
                bottom: 0,
                width: `${fill * 100}%`,
                background: accent,
              }}
            />
          </div>
        );
      })}
    </div>
  );
};
