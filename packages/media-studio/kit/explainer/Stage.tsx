/**
 * Everything a shot is cut against: the backdrop, two slow fogs, a vignette,
 * grain, and one light pool that belongs to the shot on screen.
 *
 * The measured difference between a weak and a strong cut in this kit was not
 * motion — 0.47 against 0.56 frames changed — but composition: one hero, one
 * light on it, depth behind it. So this layer animates no layout and asks for no
 * attention. It exists so the hero has something to be lit against and so a cut
 * lands on a field that was already there.
 *
 * Backdrops are CSS gradients on purpose. A canvas, an image or a per-frame
 * filter would cost the render more than the atmosphere is worth, and
 * feTurbulence re-rasterises the whole frame every frame.
 */
import type { FC } from 'react';
import { AbsoluteFill, useCurrentFrame, useVideoConfig } from 'remotion';
import { layoutFor } from './layout.mjs';
import { framesOf } from './motion.mjs';
import {
  T,
  accentOf,
  alpha,
  shotAtFrame,
  type Backdrop as BackdropKind,
  type ExplainerFilm,
  type ExplainerShot,
} from './types';

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));

/* ------------------------------------------------------------- backdrops -- */

/** Two dot scales drifting against each other; the beat between them keeps the
 * field from reading as wallpaper. */
const Dots: FC<{ frame: number }> = ({ frame }) => (
  <div
    style={{
      position: 'absolute',
      inset: -40,
      backgroundImage: `radial-gradient(${alpha(T.color.ink, 0.2)} 1.5px, transparent 1.6px), radial-gradient(${alpha(T.color.ink, 0.09)} 1px, transparent 1.1px)`,
      backgroundSize: '38px 38px, 21px 21px',
      backgroundPosition: `${Math.round(frame * 0.16)}px ${Math.round(frame * 0.07)}px, ${Math.round(-frame * 0.09)}px ${Math.round(frame * 0.12)}px`,
    }}
  />
);

/** Two star scales at different opacities. Prime tile sizes (137, 89) never
 * line up, so the field does not show its grid. */
const Stars: FC<{ frame: number }> = ({ frame }) => (
  <>
    <div
      style={{
        position: 'absolute',
        inset: -40,
        backgroundImage: `radial-gradient(${alpha(T.color.ink, 0.5)} 1.7px, transparent 1.8px)`,
        backgroundSize: '137px 137px',
        backgroundPosition: `${Math.round(frame * 0.05)}px ${Math.round(frame * 0.03)}px`,
      }}
    />
    <div
      style={{
        position: 'absolute',
        inset: -40,
        backgroundImage: `radial-gradient(${alpha(T.color.ink, 0.24)} 1.1px, transparent 1.2px)`,
        backgroundSize: '89px 89px',
        backgroundPosition: `${Math.round(-frame * 0.04)}px ${Math.round(frame * 0.02)}px`,
      }}
    />
  </>
);

/**
 * A plane receding to a horizon. Only its background offset moves, so the
 * perspective is painted once per frame instead of re-laying out the grid.
 */
const Grid: FC<{ frame: number }> = ({ frame }) => {
  const line = alpha(T.color.ink, 0.13);
  const mask = 'linear-gradient(to bottom, transparent 0%, #000 24%, #000 100%)';
  return (
    <div
      style={{
        position: 'absolute',
        left: '-25%',
        right: '-25%',
        bottom: 0,
        height: '58%',
        perspective: 640,
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: 0,
          height: '190%',
          transformOrigin: '50% 0%',
          transform: 'rotateX(63deg)',
          backgroundImage: `repeating-linear-gradient(90deg, ${line} 0 1px, transparent 1px 92px), repeating-linear-gradient(0deg, ${line} 0 1px, transparent 1px 92px)`,
          backgroundPosition: `0px ${Math.round(frame * 0.6) % 92}px`,
          maskImage: mask,
          WebkitMaskImage: mask,
        }}
      />
    </div>
  );
};

const BackdropField: FC<{ kind: BackdropKind; frame: number }> = ({
  kind,
  frame,
}) => {
  if (kind === 'dots') return <Dots frame={frame} />;
  if (kind === 'stars') return <Stars frame={frame} />;
  if (kind === 'grid') return <Grid frame={frame} />;
  return null;
};

/* ------------------------------------------------------------------ field -- */

/** Two large washes in the film's two colours, counter-drifting. Alpha stays
 * inside 8-16/255: visible as depth, never as a coloured light. */
const Fog: FC<{ frame: number; accent: string; alt: string }> = ({
  frame,
  accent,
  alt,
}) => {
  const breathe = 0.045 + 0.015 * Math.sin(frame / 90);
  return (
    <>
      <AbsoluteFill
        style={{
          background: `radial-gradient(58% 54% at 26% 30%, ${alpha(accent, breathe)} 0%, transparent 70%)`,
          translate: `${Math.sin(frame / 120) * 3}% ${Math.cos(frame / 156) * 2}%`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(52% 50% at 78% 74%, ${alpha(alt, breathe)} 0%, transparent 72%)`,
          translate: `${Math.sin(frame / 134 + 2) * -3}% ${Math.cos(frame / 168 + 1) * -2}%`,
        }}
      />
    </>
  );
};

const Vignette: FC = () => (
  <AbsoluteFill
    style={{
      background:
        'radial-gradient(118% 96% at 50% 44%, rgba(0,0,0,0) 40%, rgba(0,0,0,0.5) 78%, rgba(0,0,0,0.78) 100%)',
    }}
  />
);

/** A dot lattice at 3% instead of noise: the grain reads as film at this size
 * and costs one static layer instead of a filtered one per frame. */
const Grain: FC = () => (
  <AbsoluteFill
    style={{
      backgroundImage: `radial-gradient(${alpha('#FFFFFF', 0.5)} 0.6px, transparent 0.7px)`,
      backgroundSize: '3px 3px',
      opacity: 0.03,
      pointerEvents: 'none',
    }}
  />
);

/* ------------------------------------------------------------------ light -- */

/**
 * Where the light sits, as a fraction of the frame. Type-led families get a
 * pool behind the words; the diagram families get the hero box the layout
 * already reserves; media gets nothing, because the picture carries its own.
 */
const anchorFor = (
  family: string,
  film: ExplainerFilm,
): { x: number; y: number } | null => {
  if (family === 'media') return null;
  if (family === 'statement' || family === 'quote' || family === 'chapter' || family === 'sting') {
    return { x: 0.4, y: 0.46 };
  }
  if (family === 'number' || family === 'end') return { x: 0.5, y: 0.44 };
  const boxed = ['contrast', 'mechanism', 'layers', 'timeline', 'evidence', 'checklist'];
  if (boxed.indexOf(family) >= 0) {
    // A light is atmosphere. If the layout refuses this family or this canvas,
    // the film must still render, so the pool falls back to the centre.
    try {
      const { hero } = layoutFor(family, film) as {
        hero: { x: number; y: number; w: number; h: number };
        safe: { x: number; y: number; w: number; h: number };
      };
      return {
        x: (hero.x + hero.w / 2) / film.width,
        y: (hero.y + hero.h / 2) / film.height,
      };
    } catch {
      return { x: 0.5, y: 0.45 };
    }
  }
  return { x: 0.5, y: 0.45 };
};

/**
 * One pool, one colour, one shot. It arrives eight frames after the hero lands,
 * breathes on a 30-frame cycle and dies over the last six frames so the hard
 * cut lands out of darkness rather than out of a flash.
 */
export const Light: FC<{ film: ExplainerFilm; shots: ExplainerShot[] }> = ({
  film,
  shots,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const shot = shotAtFrame(shots, frame);
  if (!shot) return null;
  const anchor = anchorFor(shot.family, film);
  if (!anchor) return null;

  const local = frame - shot.startFrame;
  const landsAt = Math.round((shot.heroAtSeconds ?? 0) * fps);
  const ramp = clamp01((local - landsAt) / Math.max(1, framesOf('settle', fps)));
  const breath = 1 + 0.15 * Math.sin(((local - landsAt) / 30) * Math.PI * 2);
  const tail = shot.durationFrames - local;
  const die = tail < 6 ? clamp01(tail / 6) : 1;
  const intensity = clamp01(ramp * breath * die);
  const accent = accentOf(shot, film);

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(52% 50% at ${(anchor.x * 100).toFixed(1)}% ${(anchor.y * 100).toFixed(1)}%, ${alpha(accent, 0.16 * intensity)} 0%, ${alpha(accent, 0.05 * intensity)} 44%, transparent 74%)`,
        mixBlendMode: 'screen',
        pointerEvents: 'none',
      }}
    />
  );
};

/* ------------------------------------------------------------------ stage -- */

export const Stage: FC<{ film: ExplainerFilm; shots: ExplainerShot[] }> = ({
  film,
  shots,
}) => {
  const frame = useCurrentFrame();
  const accent = film.accent ?? T.color.accent;
  return (
    <AbsoluteFill
      style={{ backgroundColor: T.color.base, overflow: 'hidden' }}
    >
      <BackdropField kind={film.backdrop} frame={frame} />
      <Fog frame={frame} accent={accent} alt={T.color.accentAlt} />
      <Vignette />
      <Grain />
      <Light film={film} shots={shots} />
    </AbsoluteFill>
  );
};
