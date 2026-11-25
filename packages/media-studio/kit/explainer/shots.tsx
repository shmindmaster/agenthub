/**
 * One renderer per composition family, and the blocks they share.
 *
 * The kit this replaces declared 22 archetypes and composed exactly one of
 * them; every other storyboard fell through to the same slide. Here the family
 * decides the composition, and every family is built to the same four rules:
 * one hero at 45-75% of the frame, one light on it, one thing that keeps moving
 * while the line is spoken, and a hold at the end. Nothing enters without a
 * named motion from motion.mjs and nothing animates its way out — the next
 * shot's entrance is the transition.
 *
 * Every box comes from layout.mjs. A pixel position written here would be a
 * second layout that drifts from the one the gates check.
 */
import type { CSSProperties, FC, ReactNode } from 'react';
import {
  AbsoluteFill,
  Img,
  Interactive,
  OffthreadVideo,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import { Diagram } from '../src/Diagram';
import { VisualBody, isVideoSrc, phase, type Visual } from '../src/Visuals';
import {
  checklistLayout,
  contrastLayout,
  contrastSides,
  fitTitle,
  fitVisual,
  numberSize,
  numberWords,
  pictureBox,
  timelineLayout,
} from './fit.mjs';
import { fitHeadline, layoutFor } from './layout.mjs';
import { EASINGS, enter, progress, staggerFrames } from './motion.mjs';
import {
  T,
  accentOf,
  alpha,
  type Beat,
  type ExplainerFilm,
  type ExplainerShot,
} from './types';

export type ShotProps = {
  shot: ExplainerShot;
  film: ExplainerFilm;
  index: number;
};

type Region = {
  x: number;
  y: number;
  w: number;
  h: number;
  align: 'left' | 'center';
  valign?: 'top' | 'center' | 'bottom';
};

type Regions = {
  hero: Region;
  kicker: Region | null;
  title: Region | null;
  sub: Region | null;
  safe: Region;
};

const ROOT: CSSProperties = {
  backgroundColor: 'transparent',
  color: T.color.ink,
  fontFamily: T.type.family,
  overflow: 'hidden',
};

const ShotRoot: FC<{ children: ReactNode }> = ({ children }) => (
  <AbsoluteFill style={ROOT}>{children}</AbsoluteFill>
);

const clamp01 = (value: number) => Math.min(1, Math.max(0, value));

/** layout.mjs is plain JS; its regions are resolved pixels, so this is the one
 * place the result gets a type instead of being re-derived per family. */
const regionsFor = (family: string, film: ExplainerFilm): Regions =>
  layoutFor(family, film) as Regions;

const two = (value: number) => (value < 10 ? `0${value}` : String(value));

/** The frame the hero lands: the shot's own heroAtSeconds, local to its
 * Sequence, and the frame the light arrives on. A family with a title row opens
 * on that row before this (OPENING_SECONDS). */
const beatAt = (shot: ExplainerShot, fps: number): number =>
  Math.round((shot.heroAtSeconds ?? 0) * fps);

/** The frame an item lands. Falls back to the same curve VisualBody uses, so a
 * shell and its body never disagree about when a beat is due. */
const landAt = (
  item: { at?: number },
  i: number,
  count: number,
  shot: ExplainerShot,
  from: number,
  fps: number,
): number =>
  Math.round((item.at ?? phase(i, count, shot.durationSeconds, from)) * fps);

/** `enter("wipe")` clips left to right. A seam, an upright rule or a bar beside
 * a title needs the same curve on scaleY, so the timing still comes from
 * motion.mjs and only the axis differs. */
const wipeDown = (p: number) => ({
  transform: `scaleY(${p})`,
  transformOrigin: 'top',
});

/**
 * The schema carries no `emphasis` field yet. A storyboard that adds one is
 * still honoured; otherwise the last content word takes the accent so the eye
 * has exactly one place to land.
 */
const emphasisOf = (shot: ExplainerShot): string | undefined =>
  (shot as ExplainerShot & { emphasis?: string }).emphasis;

const accentIndexFor = (words: string[], emphasis?: string | null): number => {
  if (emphasis === null) return -1;
  const clean = (word: string) =>
    word.replace(/[^A-Za-z0-9'’%-]/g, '').toLowerCase();
  if (emphasis) {
    for (let i = words.length - 1; i >= 0; i -= 1) {
      if (clean(words[i]) === clean(emphasis)) return i;
    }
  }
  for (let i = words.length - 1; i >= 0; i -= 1) {
    if (/[A-Za-z0-9]/.test(words[i])) return i;
  }
  return -1;
};

type StatSpec = {
  prefix: string;
  suffix: string;
  value: number;
  decimals: number;
  grouped: boolean;
};

/** Split "49%", "$2.4M" or "1,000,000" into the parts a count-up has to keep. */
const parseStat = (raw: string): StatSpec | null => {
  const match = /^([^0-9]*)([0-9][0-9,]*(?:\.[0-9]+)?)(.*)$/.exec(raw.trim());
  if (!match) return null;
  const digits = match[2];
  const parts = digits.split('.');
  const value = Number(
    `${parts[0].split(',').join('')}${parts.length > 1 ? `.${parts[1]}` : ''}`,
  );
  if (!Number.isFinite(value)) return null;
  return {
    prefix: match[1],
    suffix: match[3],
    value,
    decimals: parts.length > 1 ? parts[1].length : 0,
    grouped: digits.indexOf(',') >= 0,
  };
};

const formatStat = (spec: StatSpec, t: number): string => {
  const fixed = (spec.value * t).toFixed(spec.decimals);
  const dot = fixed.indexOf('.');
  const whole = dot >= 0 ? fixed.slice(0, dot) : fixed;
  const fraction = dot >= 0 ? fixed.slice(dot + 1) : '';
  const grouped = spec.grouped
    ? whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
    : whole;
  return `${spec.prefix}${grouped}${fraction ? `.${fraction}` : ''}${spec.suffix}`;
};

const recentBeat = (beats: Beat[], seconds: number): Beat | null => {
  let best: Beat | null = null;
  for (const beat of beats) {
    if (beat.atSeconds <= seconds && (!best || beat.atSeconds >= best.atSeconds)) {
      best = beat;
    }
  }
  return best;
};

/* ---------------------------------------------------------------- blocks -- */

const Box: FC<{ r: Region; style?: CSSProperties; children?: ReactNode }> = ({
  r,
  style,
  children,
}) => (
  <div
    style={{
      position: 'absolute',
      left: r.x,
      top: r.y,
      width: r.w,
      height: r.h,
      display: 'flex',
      flexDirection: 'column',
      justifyContent:
        r.valign === 'center'
          ? 'center'
          : r.valign === 'bottom'
            ? 'flex-end'
            : 'flex-start',
      alignItems: r.align === 'center' ? 'center' : 'flex-start',
      textAlign: r.align,
      ...style,
    }}
  >
    {children}
  </div>
);

/**
 * XL type, one accent word, word by word. The wrap is computed once from the
 * full text and each line is a nowrap row, so a word that has landed can never
 * be pushed to the next line by the words still arriving.
 */
const Headline: FC<{
  text: string;
  accent: string;
  at: number;
  maxWidth: number;
  maxSize?: number;
  minSize?: number;
  maxLines?: number;
  align?: 'left' | 'center';
  accentWord?: string | null;
  lineHeight?: number;
  weight?: number;
}> = ({
  text,
  accent,
  at,
  maxWidth,
  maxSize,
  minSize = 84,
  maxLines = 3,
  align = 'left',
  accentWord,
  lineHeight,
  weight = 800,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const tracking = T.type.tracking.display;
  const fitted = fitHeadline(text, {
    maxWidth: Math.floor(maxWidth * 0.88),
    maxLines,
    maxSize: maxSize ?? T.type.xl,
    minSize,
    tracking,
  });
  const lines = fitted.lines.map((line) => line.split(' ').filter(Boolean));
  const flat = lines.reduce<string[]>((all, line) => all.concat(line), []);
  const lit = accentIndexFor(flat, accentWord);
  if (!flat.length) return null;
  let k = 0;

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: align === 'center' ? 'center' : 'flex-start',
        width: '100%',
      }}
    >
      {lines.map((line, li) => (
        <div
          key={li}
          style={{
            display: 'flex',
            justifyContent: align === 'center' ? 'center' : 'flex-start',
            columnGap: Math.round(fitted.size * 0.26),
            whiteSpace: 'nowrap',
            fontSize: fitted.size,
            fontWeight: weight,
            lineHeight: lineHeight ?? T.type.lineHeight.display,
            letterSpacing: `${tracking}em`,
            color: T.color.ink,
          }}
        >
          {line.map((word) => {
            const wordIndex = k;
            k += 1;
            const p = progress(
              'rise',
              frame,
              fps,
              (at + staggerFrames(wordIndex)) / fps,
            );
            return (
              <span
                key={wordIndex}
                style={{
                  ...enter('rise', p),
                  display: 'inline-block',
                  color: wordIndex === lit ? accent : undefined,
                }}
              >
                {word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};

const Kicker: FC<{
  text?: string;
  at: number;
  color?: string;
  align?: 'left' | 'center';
}> = ({ text, at, color, align = 'left' }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (!text) return null;
  return (
    <div
      style={{
        ...enter('fade', progress('fade', frame, fps, at / fps)),
        fontSize: T.type.label,
        fontWeight: 700,
        letterSpacing: `${T.type.tracking.label}em`,
        textTransform: 'uppercase',
        color: color ?? T.color.muted,
        textAlign: align,
      }}
    >
      {text}
    </div>
  );
};

const Sub: FC<{
  text?: string;
  at: number;
  size?: number;
  align?: 'left' | 'center';
  maxWidth?: number;
}> = ({ text, at, size = T.type.caption, align = 'left', maxWidth }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (!text) return null;
  return (
    <div
      style={{
        ...enter('rise', progress('rise', frame, fps, at / fps)),
        fontSize: size,
        lineHeight: 1.32,
        fontWeight: 500,
        color: T.color.muted,
        textAlign: align,
        maxWidth,
      }}
    >
      {text}
    </div>
  );
};

const Rule: FC<{
  accent: string;
  at: number;
  width?: number;
  thickness?: number;
}> = ({ accent, at, width = 220, thickness = 2 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        width,
        height: thickness,
        background: accent,
        borderRadius: thickness,
        ...enter('wipe', progress('wipe', frame, fps, at / fps)),
      }}
    />
  );
};

/** A quiet frame for content that is evidence rather than type: one hairline,
 * an inner backlight, no card. */
const HeroFrame: FC<{ accent: string; at: number }> = ({ accent, at }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        borderRadius: T.radius.card,
        border: `1px solid ${alpha(T.color.ink, 0.09)}`,
        boxShadow: `inset 0 1px 0 ${alpha(T.color.ink, 0.06)}, 0 30px 80px rgba(0,0,0,0.35)`,
        background: `linear-gradient(180deg, ${alpha(accent, 0.05)} 0%, transparent 55%)`,
        pointerEvents: 'none',
        ...enter('bloom', progress('bloom', frame, fps, at / fps)),
      }}
    />
  );
};

/** Every shot opens on its own furniture: the kicker, the title and the frame
 * the picture will fill are up at this moment, whatever the first spoken beat
 * is. Waiting for the beat left two or three seconds of empty frame. */
const OPENING_SECONDS = 0.1;

const openingAt = (fps: number): number => Math.round(OPENING_SECONDS * fps);

/** The kicker and the line a shot is about, the same on every family that has
 * a title row. The size comes from fit.mjs, so the builder has already refused
 * a title that does not fit. */
const ShotHead: FC<{ shot: ExplainerShot; r: Regions }> = ({ shot, r }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const open = openingAt(fps);
  const fit = r.title ? fitTitle(shot.title ?? '', r.title) : null;
  return (
    <>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={open} />
        </Box>
      ) : null}
      {r.title && fit ? (
        <Box r={r.title}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, open / fps)),
              fontSize: fit.size,
              fontWeight: 800,
              lineHeight: 1.02,
              whiteSpace: 'nowrap',
            }}
          >
            {fit.lines.map((line: string, i: number) => (
              <div key={i}>{line}</div>
            ))}
          </div>
        </Box>
      ) : null}
    </>
  );
};

/** A kit body at the largest size its region holds, centred in that region. */
const FittedBody: FC<{
  visual: Visual;
  box: { x: number; y: number; w: number; h: number };
  accent: string;
  shot: ExplainerShot;
}> = ({ visual, box, accent, shot }) => {
  const fit = fitVisual(visual, box, shot.visualScale);
  return (
    <div
      style={{
        position: 'absolute',
        left: box.x,
        top: box.y,
        width: box.w,
        height: box.h,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
      }}
    >
      <div style={{ zoom: fit.zoom, width: fit.width }}>
        <VisualBody
          visual={visual}
          accent={accent}
          durationSeconds={shot.durationSeconds}
          box={{ w: box.w, h: box.h }}
        />
      </div>
    </div>
  );
};

/* ------------------------------------------------------------- statement -- */

const Statement: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('statement', film);
  const accent = accentOf(shot, film);
  const hero = shot.visual && shot.visual.kind === 'hero' ? shot.visual : null;
  const card =
    shot.visual && shot.visual.kind === 'lower-third' ? shot.visual : null;
  const title = hero ? hero.title : shot.title ?? '';
  const sub = shot.sub ?? (hero ? hero.sub : undefined);
  const at = beatAt(shot, fps);

  return (
    <ShotRoot>
      <Box r={r.hero}>
        <Headline
          text={title}
          accent={accent}
          at={at}
          maxWidth={r.hero.w}
          maxSize={T.type.xl}
          minSize={84}
          maxLines={3}
          align={r.hero.align}
          accentWord={emphasisOf(shot)}
        />
        {sub ? (
          <div style={{ marginTop: 34, maxWidth: Math.round(r.hero.w * 0.66) }}>
            <Sub text={sub} at={at + 14} size={T.type.caption} align={r.hero.align} />
          </div>
        ) : null}
      </Box>
      {hero && hero.kicker ? (
        <div
          style={{
            position: 'absolute',
            left: r.hero.x,
            top: r.hero.y - 62,
          }}
        >
          <Kicker text={hero.kicker} at={Math.max(0, at - 10)} />
        </div>
      ) : null}
      {card ? (
        <div
          style={{
            position: 'absolute',
            left: r.safe.x,
            top: Math.round(film.height * 0.7),
            display: 'flex',
            gap: 20,
          }}
        >
          <div
            style={{
              width: 3,
              background: accent,
              ...wipeDown(progress('wipe', frame, fps, (at + 4) / fps)),
            }}
          />
          <div
            style={{
              ...enter('slide', progress('slide', frame, fps, (at + 4) / fps)),
            }}
          >
            <div style={{ fontSize: T.type.caption, fontWeight: 800 }}>
              {card.name}
            </div>
            {card.title ? (
              <div
                style={{
                  marginTop: 6,
                  fontSize: T.type.label,
                  letterSpacing: '0.06em',
                  color: T.color.muted,
                }}
              >
                {card.title}
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </ShotRoot>
  );
};

/* ---------------------------------------------------------------- number -- */

const NumberShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('number', film);
  const accent = accentOf(shot, film);
  const stat = shot.visual && shot.visual.kind === 'stat' ? shot.visual : null;
  const value = stat ? stat.value : shot.title ?? '';
  const label = stat ? stat.label : shot.sub ?? '';
  const extra = stat ? stat.sub : undefined;
  const at = beatAt(shot, fps);
  const open = openingAt(fps);
  const spec = parseStat(value);
  const size = numberSize(value, r.hero.w);
  const counted = spec
    ? formatStat(spec, EASINGS.out(clamp01((frame - at) / 20)))
    : value;
  const entryP = progress(spec ? 'settle' : 'pop', frame, fps, at / fps);
  // The ring and the words are up before the number is spoken, so the frame
  // says what is about to be counted instead of standing empty.
  const ringP = progress('bloom', frame, fps, open / fps);
  // Consecutive number shots breathe out of phase, so a cut never lands on the
  // same point of the cycle twice.
  const breath = 1 + 0.02 * Math.sin(((frame - at) / 30 + index) * Math.PI * 2);
  const ring = Math.round(r.hero.h * 0.93);
  const words = numberWords(label, extra, r.sub ?? r.hero);

  return (
    <ShotRoot>
      <Box r={r.hero}>
        <div
          style={{
            position: 'absolute',
            left: '50%',
            top: '50%',
            width: ring,
            height: ring,
            marginLeft: -ring / 2,
            marginTop: -ring / 2,
            boxSizing: 'border-box',
            borderRadius: T.radius.pill,
            border: `2px solid ${alpha(accent, 0.32)}`,
            ...enter('bloom', ringP),
            scale: String((0.97 + 0.03 * ringP) * breath),
          }}
        />
        <Interactive.Div
          name={`Number ${shot.id}`}
          style={{
            position: 'relative',
            ...enter(spec ? 'settle' : 'pop', entryP),
            fontSize: size,
            fontWeight: 900,
            lineHeight: 0.9,
            letterSpacing: '-0.03em',
            color: accent,
            fontVariantNumeric: 'tabular-nums',
          }}
        >
          {counted}
        </Interactive.Div>
      </Box>
      {r.sub ? (
        <Box r={r.sub}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, open / fps)),
              fontSize: words.labelSize,
              fontWeight: 700,
              color: T.color.ink,
              textAlign: 'center',
            }}
          >
            {label}
          </div>
          {extra ? (
            <div
              style={{
                ...enter('rise', progress('rise', frame, fps, (at + 16) / fps)),
                marginTop: 12,
                maxWidth: Math.round(r.sub.w * 0.8),
                fontSize: words.extraSize,
                lineHeight: 1.3,
                color: T.color.muted,
                textAlign: 'center',
              }}
            >
              {extra}
            </div>
          ) : null}
        </Box>
      ) : null}
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={open} align="center" />
        </Box>
      ) : null}
    </ShotRoot>
  );
};

/* -------------------------------------------------------------- contrast -- */

type Side = { title: string; items: { text: string; at?: number }[] };

const Contrast: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('contrast', film);
  const accent = accentOf(shot, film);
  // Split keeps its two sides; a before/after becomes the same left/right pair,
  // because the seam is what makes the frame legible at a glance.
  const sides = contrastSides(shot.visual) as { left: Side; right: Side } | null;
  if (!sides) return <Statement shot={shot} film={film} index={index} />;

  const from = shot.visual?.revealFrom ?? 0;
  const open = openingAt(fps);
  const fit = contrastLayout(sides, r.hero);
  const top = r.hero.y + Math.round((r.hero.h - fit.panelH) / 2);
  const mid = r.hero.x + Math.round(r.hero.w / 2);
  const seamP = progress('wipe', frame, fps, (open + 4) / fps);

  const panel = (side: Side, lit: boolean, x: number) => {
    const p = progress('rise', frame, fps, (open + (lit ? 6 : 2)) / fps);
    return (
      <div
        style={{
          ...enter('rise', p),
          position: 'absolute',
          left: x,
          top,
          width: fit.panelW,
          height: fit.panelH,
          boxSizing: 'border-box',
          display: 'flex',
          flexDirection: 'column',
          padding: fit.pad,
          borderRadius: T.radius.card,
          border: `2px solid ${lit ? alpha(accent, 0.75) : alpha(T.color.ink, 0.16)}`,
          background: lit
            ? `linear-gradient(180deg, ${alpha(accent, 0.12)} 0%, ${alpha(accent, 0.02)} 100%)`
            : alpha(T.color.ink, 0.03),
          boxShadow: lit ? `0 0 60px ${alpha(accent, 0.1)}` : undefined,
          color: lit ? T.color.ink : T.color.inkSoft,
          opacity: (lit ? 1 : 0.8) * p,
        }}
      >
        <div
          style={{
            fontSize: fit.titleSize,
            fontWeight: 800,
            lineHeight: 1.1,
            color: lit ? accent : T.color.inkSoft,
          }}
        >
          {side.title}
        </div>
        <div
          style={{
            marginTop: 28,
            display: 'flex',
            flexDirection: 'column',
            gap: Math.round(fit.itemSize * 0.5),
            // The lines sit in the middle of what the panel has left, so a
            // short side does not hang from its title.
            flex: 1,
            justifyContent: 'center',
          }}
        >
          {side.items.map((item, i) => {
            const start = landAt(item, i, side.items.length, shot, from, fps);
            return (
              <div
                key={i}
                style={{
                  ...enter('rise', progress('rise', frame, fps, start / fps)),
                  position: 'relative',
                  paddingLeft: fit.bullet,
                  fontSize: fit.itemSize,
                  lineHeight: 1.24,
                  fontWeight: 600,
                }}
              >
                <span
                  style={{
                    position: 'absolute',
                    left: 0,
                    top: Math.round(fit.itemSize * 0.5),
                    width: 12,
                    height: 12,
                    borderRadius: T.radius.pill,
                    background: lit ? accent : T.color.muted,
                  }}
                />
                {item.text}
              </div>
            );
          })}
        </div>
      </div>
    );
  };

  return (
    <ShotRoot>
      <ShotHead shot={shot} r={r} />
      <div
        style={{
          position: 'absolute',
          left: mid,
          top: top - 10,
          width: 1,
          height: fit.panelH + 20,
          background: alpha(T.color.ink, 0.3),
          ...wipeDown(seamP),
        }}
      />
      {panel(sides.left, false, r.hero.x)}
      {panel(sides.right, true, r.hero.x + r.hero.w - fit.panelW)}
    </ShotRoot>
  );
};

/* ------------------------------------------------------------- mechanism -- */

const Mechanism: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('mechanism', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  if (!visual) return <Statement shot={shot} film={film} index={index} />;

  const box = pictureBox('mechanism', r.hero);
  const beat = recentBeat(shot.beats, Math.max(0, frame) / fps);
  const ringP = beat
    ? clamp01((frame - Math.round(beat.atSeconds * fps)) / 12)
    : 0;
  const intro = progress('settle', frame, fps, openingAt(fps) / fps);

  return (
    <ShotRoot>
      <ShotHead shot={shot} r={r} />
      <div
        style={{
          position: 'absolute',
          left: r.hero.x + 4,
          top: r.hero.y + 4,
          width: r.hero.w - 8,
          height: r.hero.h - 8,
          boxSizing: 'border-box',
          borderRadius: 22,
          border: `2px solid ${alpha(accent, 0.55)}`,
          opacity: intro * (0.9 - 0.5 * ringP),
          scale: String(1.014 - 0.014 * ringP),
          pointerEvents: 'none',
        }}
      />
      {visual.kind === 'flow' ? (
        <div style={{ position: 'absolute', left: box.x, top: box.y }}>
          <Diagram
            v={visual}
            accent={accent}
            d={shot.durationSeconds}
            box={box}
            revealFrom={visual.revealFrom}
          />
        </div>
      ) : (
        <FittedBody visual={visual} box={box} accent={accent} shot={shot} />
      )}
    </ShotRoot>
  );
};

/* ---------------------------------------------------------------- layers -- */

const LayersShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('layers', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  if (!visual || visual.kind !== 'layers') {
    return <Statement shot={shot} film={film} index={index} />;
  }

  const from = visual.revealFrom ?? 0;
  const layers = visual.layers;
  const fit = fitVisual(visual, r.hero, shot.visualScale);
  const stackH = Math.min(r.hero.h, fit.height * fit.zoom);
  let active = 0;
  layers.forEach((layer, i) => {
    const start = landAt(layer, i, layers.length, shot, from, fps);
    if (Math.round(frame) >= start) active = i;
  });
  const bandY = layers.length ? ((active + 0.5) / layers.length) * 100 : 50;
  const outline = progress('fade', frame, fps, openingAt(fps) / fps);
  const stackNatural = fit.bands.reduce(
    (total: number, height: number) => total + height + 14,
    -14,
  );
  const bandTops = fit.bands.map(
    (_: number, i: number) =>
      r.hero.y +
      (r.hero.h - stackH) / 2 +
      (fit.height - stackNatural) * fit.zoom +
      fit.bands
        .slice(0, i)
        .reduce((total: number, height: number) => total + height + 14, 0) *
        fit.zoom,
  );

  return (
    <ShotRoot>
      <ShotHead shot={shot} r={r} />
      {/* The pool of light follows the band whose `at` has passed most recently.
          Band heights are even, so the index places it inside the stack. */}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y + (r.hero.h - stackH) / 2,
          width: r.hero.w,
          height: stackH,
          background: `radial-gradient(44% 26% at 46% ${bandY.toFixed(1)}%, ${alpha(accent, 0.1)} 0%, transparent 72%)`,
          pointerEvents: 'none',
        }}
      />
      {/* Every band is outlined from the start, so the depth of the stack is on
          screen before its first layer is named. */}
      {fit.bands.map((height: number, i: number) => {
        const start = landAt(layers[i], i, layers.length, shot, from, fps);
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: r.hero.x,
              top: bandTops[i],
              width: r.hero.w,
              height: height * fit.zoom,
              boxSizing: 'border-box',
              borderRadius: 8 * fit.zoom,
              border: `2px dashed ${alpha(T.color.ink, 0.2)}`,
              opacity:
                outline * (1 - progress('rise', frame, fps, start / fps)),
            }}
          />
        );
      })}
      <AbsoluteFill
        style={{ filter: 'drop-shadow(0 16px 22px rgba(0,0,0,0.45))' }}
      >
        <FittedBody visual={visual} box={r.hero} accent={accent} shot={shot} />
      </AbsoluteFill>
    </ShotRoot>
  );
};

/* -------------------------------------------------------------- timeline -- */

const TimelineShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('timeline', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  if (!visual || visual.kind !== 'timeline') {
    return <Statement shot={shot} film={film} index={index} />;
  }

  const from = visual.revealFrom ?? 0;
  const events = visual.events;
  const fit = timelineLayout(events, r.hero);
  const open = openingAt(fps);
  const starts = events.map((event, i) =>
    landAt({ at: event.beat }, i, events.length, shot, from, fps),
  );
  let current = -1;
  starts.forEach((start, i) => {
    if (frame >= start && (current < 0 || start >= starts[current])) current = i;
  });
  // The playhead reaches each event on the frame that event lands, then runs on
  // to the end of the rail with the rest of the line.
  const stops = [
    { f: Math.min(0, ...starts), x: 0 },
    ...starts.map((f, i) => ({ f, x: fit.centres[i] })),
    { f: Math.max(shot.durationFrames, ...starts.map((f) => f + 1)), x: r.hero.w },
  ].sort((m, n) => m.f - n.f || m.x - n.x);
  const next = stops.findIndex((stop) => stop.f > frame);
  const past = stops[next < 0 ? stops.length - 1 : Math.max(0, next - 1)];
  const ahead = next < 0 ? past : stops[next];
  const head =
    past.x +
    (ahead.f > past.f
      ? ((frame - past.f) / (ahead.f - past.f)) * (ahead.x - past.x)
      : 0);
  const railTop = r.hero.y + fit.railY;
  const toneOf = (mark?: string) =>
    mark === 'good'
      ? T.color.good
      : mark === 'risk'
        ? T.color.risk
        : mark === 'emphasis'
          ? T.color.accent
          : accent;

  return (
    <ShotRoot>
      <ShotHead shot={shot} r={r} />
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: railTop - 2,
          width: r.hero.w,
          height: 4,
          borderRadius: 2,
          background: alpha(T.color.ink, 0.16),
          ...enter('wipe', progress('wipe', frame, fps, open / fps)),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: railTop - 2,
          width: Math.max(0, head),
          height: 4,
          borderRadius: 2,
          background: accent,
        }}
      />
      {events.map((event, i) => {
        const x = r.hero.x + fit.centres[i];
        const landed = frame >= starts[i];
        const p = progress('rise', frame, fps, starts[i] / fps);
        const grow = progress('pop', frame, fps, starts[i] / fps);
        const shown = progress('fade', frame, fps, (open + 4 * i) / fps);
        const lit = i === current;
        const tone = toneOf(event.mark);
        const dot = 18 + (lit ? 14 * grow : 0);
        return (
          <div key={i}>
            <div
              style={{
                position: 'absolute',
                left: x - fit.colW / 2,
                width: fit.colW,
                bottom: film.height - railTop + 30,
                textAlign: 'center',
                fontSize: fit.dateSize,
                fontWeight: 800,
                lineHeight: 1.1,
                whiteSpace: 'nowrap',
                color: lit ? tone : T.color.ink,
                // The dates are up from the start, so the span is readable
                // before the first event lands on it.
                opacity: shown * (lit ? 1 : landed ? 0.78 : 0.4),
              }}
            >
              {event.at}
            </div>
            <div
              style={{
                position: 'absolute',
                left: x - dot / 2,
                top: railTop - dot / 2,
                width: dot,
                height: dot,
                boxSizing: 'border-box',
                borderRadius: T.radius.pill,
                background: landed ? tone : T.color.base,
                border: `3px solid ${landed ? tone : alpha(T.color.ink, 0.35)}`,
                boxShadow: lit ? `0 0 34px ${alpha(tone, 0.6)}` : undefined,
                opacity: shown,
              }}
            />
            <div
              style={{
                ...enter('rise', p),
                position: 'absolute',
                left: x - fit.inner / 2,
                top: railTop + 44,
                width: fit.inner,
                textAlign: 'center',
                opacity: p * (lit ? 1 : 0.72),
              }}
            >
              <div
                style={{
                  fontSize: fit.labelSize,
                  textWrap: 'balance',
                  fontWeight: 700,
                  lineHeight: 1.16,
                  color: lit ? T.color.ink : T.color.inkSoft,
                }}
              >
                {event.label}
              </div>
              {event.sub ? (
                <div
                  style={{
                    marginTop: 14,
                    fontSize: fit.subSize,
                    lineHeight: 1.3,
                    color: T.color.inkSoft,
                  }}
                >
                  {event.sub}
                </div>
              ) : null}
            </div>
          </div>
        );
      })}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x + Math.round(head) - 1,
          top: railTop - 16,
          width: 2,
          height: 32,
          background: accent,
          boxShadow: `0 0 18px ${alpha(accent, 0.55)}`,
        }}
      />
    </ShotRoot>
  );
};

/* -------------------------------------------------------------- evidence -- */

const Evidence: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('evidence', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const open = openingAt(fps);
  if (!visual) return <Statement shot={shot} film={film} index={index} />;

  const claim =
    visual.kind === 'proof' || visual.kind === 'sidecar'
      ? visual.claim
      : shot.title ?? '';
  // Fit here as well as inside Headline so the connector can start at the real
  // baseline. Same input, same computation, same lines — nothing is measured.
  const fitted = fitHeadline(claim, {
    maxWidth: Math.floor((r.title ? r.title.w : r.hero.w) * 0.88),
    maxLines: 2,
    maxSize: 64,
    minSize: 52,
    tracking: T.type.tracking.display,
  });
  const claimBottom =
    (r.title ? r.title.y : r.hero.y - 60) +
    Math.round(fitted.lines.length * fitted.size * T.type.lineHeight.display);
  const connectorTop = claimBottom + 12;
  const connectorLen = Math.max(12, r.hero.y - 10 - connectorTop);

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Kicker text={shot.kicker} at={open} />
        </Box>
      ) : null}
      {r.title ? (
        <Box r={r.title}>
          <Headline
            text={claim}
            accent={accent}
            at={open}
            maxWidth={r.title.w}
            maxSize={64}
            minSize={52}
            maxLines={2}
            accentWord={emphasisOf(shot)}
          />
        </Box>
      ) : null}
      <svg
        width={2}
        height={connectorLen}
        style={{
          position: 'absolute',
          left: (r.title ? r.title.x : r.hero.x) + 1,
          top: connectorTop,
          overflow: 'visible',
        }}
      >
        <line
          x1={1}
          y1={0}
          x2={1}
          y2={connectorLen}
          stroke={alpha(accent, 0.55)}
          strokeWidth={1}
          pathLength={1}
          strokeDasharray={1}
          {...enter('draw', progress('draw', frame, fps, (open + 6) / fps))}
        />
      </svg>
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: r.hero.y,
          width: r.hero.w,
          height: r.hero.h,
        }}
      >
        <HeroFrame accent={accent} at={open} />
      </div>
      <FittedBody
        visual={visual}
        box={pictureBox('evidence', r.hero)}
        accent={accent}
        shot={shot}
      />
    </ShotRoot>
  );
};

/* ----------------------------------------------------------------- quote -- */

const QuoteShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('quote', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual && shot.visual.kind === 'quote' ? shot.visual : null;
  const text = visual ? visual.text : shot.title ?? '';
  const who = visual ? visual.attribution : shot.sub;
  const at = beatAt(shot, fps);

  return (
    <ShotRoot>
      <div
        style={{
          position: 'absolute',
          left: r.hero.x - 22,
          top: r.hero.y - 96 - (index % 2) * 8,
          fontFamily: 'Georgia, "Times New Roman", serif',
          fontSize: 300,
          lineHeight: 1,
          color: alpha(accent, 0.12),
          opacity: progress('settle', frame, fps, (at + 2) / fps),
          pointerEvents: 'none',
        }}
      >
        {'\u201C'}
      </div>
      <Box r={r.hero}>
        <Headline
          text={text}
          accent={accent}
          at={at}
          maxWidth={r.hero.w}
          maxSize={88}
          minSize={64}
          maxLines={4}
          align={r.hero.align}
          accentWord={null}
          lineHeight={1.06}
          weight={700}
        />
        {who ? (
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, (at + 20) / fps)),
              marginTop: 40,
              fontSize: 28,
              letterSpacing: '0.04em',
              color: T.color.muted,
            }}
          >
            {who}
          </div>
        ) : null}
      </Box>
    </ShotRoot>
  );
};

/* ------------------------------------------------------------- checklist -- */

const Checklist: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('checklist', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const open = openingAt(fps);
  if (!visual || visual.kind !== 'checklist') {
    return <Statement shot={shot} film={film} index={index} />;
  }

  const from = visual.revealFrom ?? 0;
  const items = visual.items;
  const fit = checklistLayout(items, r.hero);
  const { rowH, visible } = fit;
  const listY = r.hero.y + Math.round((r.hero.h - rowH * visible) / 2);
  const lift = items
    .slice(visible)
    .reduce(
      (sum, item, i) =>
        sum +
        progress(
          'slide',
          frame,
          fps,
          landAt(item, visible + i, items.length, shot, from, fps) / fps,
        ),
      0,
    ) * rowH;

  return (
    <ShotRoot>
      <ShotHead shot={shot} r={r} />
      {/* Rail: one dot per item, filled as each is spoken. It stays put while
          the list scrolls, so it reads as progress rather than as an index. */}
      {items.map((item, i) => {
        const start = landAt(item, i, items.length, shot, from, fps);
        const done = frame >= start;
        // Dots sit on the row centres while the whole list fits; past five items
        // they compress into the window the list scrolls through, so the rail
        // still reads as progress rather than as a second, wrong index.
        const step =
          items.length <= visible ? rowH : (rowH * visible) / items.length;
        const top = listY + i * step + Math.min(step, rowH) / 2 - 3;
        return (
          <div
            key={`rail-${i}`}
            style={{
              position: 'absolute',
              left: r.hero.x - 46,
              top: Math.round(top),
              width: 7,
              height: 7,
              borderRadius: T.radius.pill,
              background: done ? accent : alpha(T.color.ink, 0.18),
              opacity:
                (done ? 1 : 0.8) *
                progress('fade', frame, fps, (open + 3 * i) / fps),
            }}
          />
        );
      })}
      <div
        style={{
          position: 'absolute',
          left: r.hero.x,
          top: listY,
          width: r.hero.w,
          height: rowH * visible,
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            transform: `translateY(${-Math.round(lift)}px)`,
          }}
        >
          {items.map((item, i) => {
            const start = landAt(item, i, items.length, shot, from, fps);
            const check = clamp01((frame - start) / 10);
            return (
              <Interactive.Div
                key={i}
                name={`Item ${i + 1}`}
                style={{
                  height: rowH,
                  flexShrink: 0,
                  display: 'flex',
                  alignItems: 'center',
                  gap: fit.gap,
                }}
              >
                <div
                  style={{
                    // The empty boxes are up from the start: the viewer sees
                    // how many checks there are before the first is named.
                    opacity: progress('fade', frame, fps, (open + 3 * i) / fps),
                    boxSizing: 'border-box',
                    width: fit.boxSize,
                    height: fit.boxSize,
                    borderRadius: Math.round(fit.boxSize * 0.24),
                    border: `2px solid ${alpha(check > 0 ? accent : T.color.ink, check > 0 ? 0.7 : 0.3)}`,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0,
                  }}
                >
                  <svg width="70%" height="70%" viewBox="0 0 18 18">
                    <polyline
                      points="3,9 7,13 15,4"
                      fill="none"
                      stroke={accent}
                      strokeWidth={2.5}
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      pathLength={1}
                      strokeDasharray={1}
                      strokeDashoffset={1 - check}
                    />
                  </svg>
                </div>
                <div
                  style={{
                    ...enter('rise', progress('rise', frame, fps, start / fps)),
                    fontSize: fit.size,
                    lineHeight: 1.2,
                    fontWeight: 600,
                  }}
                >
                  {item.text}
                </div>
              </Interactive.Div>
            );
          })}
        </div>
      </div>
    </ShotRoot>
  );
};

/* ----------------------------------------------------------------- media -- */

const MediaShot: FC<ShotProps> = ({ shot, film, index }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('media', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const src = visual && 'src' in visual ? visual.src : null;
  if (!src) return <Statement shot={shot} film={film} index={index} />;

  const at = beatAt(shot, fps);
  const push = 1 + 0.04 * progress('push', frame, fps, 0, shot.durationSeconds);
  const slideIn = (offset: number) =>
    enter('slide', progress('slide', frame, fps, (at + offset) / fps));

  return (
    <ShotRoot>
      <AbsoluteFill style={{ overflow: 'hidden' }}>
        {isVideoSrc(src) ? (
          <OffthreadVideo
            src={staticFile(src)}
            muted
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              scale: String(push),
            }}
          />
        ) : (
          <Img
            src={staticFile(src)}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              scale: String(push),
            }}
          />
        )}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(to top, rgba(0,0,0,0.86) 0%, rgba(0,0,0,0.55) 26%, rgba(0,0,0,0.12) 55%, rgba(0,0,0,0) 74%)',
          pointerEvents: 'none',
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: r.title ? r.title.x - 26 : r.safe.x,
          top: (r.title ? r.title.y : r.safe.y) + 4,
          width: 2,
          height: 52,
          background: accent,
          ...wipeDown(progress('wipe', frame, fps, (at + 4) / fps)),
        }}
      />
      {r.title ? (
        <Box r={r.title}>
          <div
            style={{
              ...slideIn(0),
              fontSize: 56,
              fontWeight: 800,
              lineHeight: 1.05,
              letterSpacing: '-0.01em',
              color: T.color.ink,
            }}
          >
            {shot.title ?? ''}
          </div>
        </Box>
      ) : null}
      {r.sub ? (
        <Box r={r.sub}>
          <div
            style={{
              ...slideIn(6),
              fontSize: 30,
              lineHeight: 1.3,
              color: T.color.inkSoft,
            }}
          >
            {shot.sub ?? ''}
          </div>
        </Box>
      ) : null}
    </ShotRoot>
  );
};

/* ----------------------------------------------------------------- sting -- */

const StingShot: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('sting', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual;
  const at = beatAt(shot, fps);
  const p = progress('pop', frame, fps, at / fps);

  if (visual && visual.kind === 'lottie') {
    return (
      <ShotRoot>
        <Box
          r={r.hero}
          style={{
            alignItems: 'center',
            ...enter('settle', progress('settle', frame, fps, at / fps)),
          }}
        >
          <VisualBody
            visual={visual}
            accent={accent}
            durationSeconds={shot.durationSeconds}
          />
        </Box>
      </ShotRoot>
    );
  }

  const mark = visual && visual.kind === 'hero' ? visual.title : shot.title ?? '';
  return (
    <ShotRoot>
      <Box r={r.hero}>
        <div
          style={{
            ...enter('pop', p),
            fontSize: T.type.l,
            fontWeight: 900,
            letterSpacing: '-0.02em',
            color: T.color.ink,
            textAlign: 'center',
          }}
        >
          {mark}
        </div>
        <div style={{ marginTop: 26 }}>
          <Rule accent={accent} at={at + 8} width={72} thickness={2} />
        </div>
      </Box>
    </ShotRoot>
  );
};

/* --------------------------------------------------------------- chapter -- */

const ChapterShot: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('chapter', film);
  const accent = accentOf(shot, film);
  const visual =
    shot.visual && shot.visual.kind === 'chapter' ? shot.visual : null;
  const at = beatAt(shot, fps);
  const chapterIndex = film.chapters.findIndex((c) => c.id === shot.chapterId);
  const number = two(chapterIndex >= 0 ? chapterIndex + 1 : 1);
  const label = visual
    ? visual.title
    : shot.title
      ? shot.title
      : chapterIndex >= 0
        ? film.chapters[chapterIndex].label
        : '';
  const kicker = visual && visual.kicker ? visual.kicker : `Chapter ${number}`;

  return (
    <ShotRoot>
      <div
        style={{
          position: 'absolute',
          left: r.hero.x - 8,
          top: r.hero.y - 92,
          fontSize: 240,
          fontWeight: 900,
          lineHeight: 0.8,
          letterSpacing: '-0.05em',
          color: alpha(accent, 0.18),
          opacity: progress('settle', frame, fps, at / fps),
          pointerEvents: 'none',
        }}
      >
        {number}
      </div>
      <Box r={r.hero}>
        <Kicker text={kicker} at={at + 2} color={accent} />
        <div
          style={{
            marginTop: 22,
            ...enter('rise', progress('rise', frame, fps, (at + 4) / fps)),
            fontSize: 96,
            fontWeight: 800,
            lineHeight: 1.02,
            letterSpacing: '-0.02em',
            color: T.color.ink,
          }}
        >
          {label}
        </div>
        <div style={{ marginTop: 30 }}>
          <Rule accent={accent} at={at + 8} width={260} thickness={2} />
        </div>
      </Box>
    </ShotRoot>
  );
};

/* ------------------------------------------------------------------- end -- */

const EndShot: FC<ShotProps> = ({ shot, film }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const r = regionsFor('end', film);
  const accent = accentOf(shot, film);
  const visual = shot.visual && shot.visual.kind === 'cta' ? shot.visual : null;
  const title = visual ? visual.title : shot.title ?? '';
  const next = visual ? visual.next : shot.sub ?? '';
  const kicker = visual && visual.kicker ? visual.kicker : shot.kicker;
  const at = beatAt(shot, fps);
  const tracking = T.type.tracking.display;
  const fitted = fitHeadline(title, {
    maxWidth: r.hero.w,
    maxLines: 2,
    maxSize: T.type.l,
    minSize: 84,
    tracking,
  });

  return (
    <ShotRoot>
      {r.kicker ? (
        <Box r={r.kicker}>
          <Rule accent={accent} at={at} width={64} thickness={2} />
          {kicker ? (
            <div style={{ marginTop: 14 }}>
              <Kicker text={kicker} at={at + 4} align="center" />
            </div>
          ) : null}
        </Box>
      ) : null}
      <Box r={r.hero}>
        <div
          style={{
            ...enter('rise', progress('rise', frame, fps, at / fps)),
            fontSize: fitted.size,
            fontWeight: 900,
            lineHeight: 1,
            letterSpacing: `${tracking}em`,
            textAlign: 'center',
            color: T.color.ink,
          }}
        >
          {title}
        </div>
      </Box>
      {r.sub ? (
        <Box r={r.sub}>
          <div
            style={{
              ...enter('rise', progress('rise', frame, fps, (at + 10) / fps)),
              fontSize: 36,
              lineHeight: 1.3,
              color: T.color.muted,
              textAlign: 'center',
            }}
          >
            {next}
          </div>
        </Box>
      ) : null}
    </ShotRoot>
  );
};

/* ---------------------------------------------------------------- export -- */

export const SHOT_RENDERERS: Record<string, FC<ShotProps>> = {
  statement: Statement,
  number: NumberShot,
  contrast: Contrast,
  mechanism: Mechanism,
  layers: LayersShot,
  timeline: TimelineShot,
  evidence: Evidence,
  quote: QuoteShot,
  checklist: Checklist,
  media: MediaShot,
  sting: StingShot,
  chapter: ChapterShot,
  end: EndShot,
};

/**
 * The one entry point a Sequence uses. The schema only promises that `family` is
 * a non-empty string, so a storyboard written against an older grammar can name
 * a family this build has no component for; it renders as `statement` rather
 * than as an empty frame, which is the failure a viewer would notice last.
 */
export const Shot: FC<ShotProps> = ({ shot, film, index }) => {
  const Renderer = SHOT_RENDERERS[shot.family] ?? SHOT_RENDERERS.statement;
  return <Renderer shot={shot} film={film} index={index} />;
};
