import type { FC } from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Interactive,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { VisualBody, type Visual } from "./Visuals";

export type { Visual } from "./Visuals";

export type BulletTone = "default" | "emphasis" | "risk" | "good";

export type BriefingBullet = {
  text: string;
  tone?: BulletTone;
  /**
   * When this line is actually spoken, in seconds from the scene start. The
   * builder derives it from word positions in the narration. Without it the
   * board falls back to a fixed stagger, which is what made every scene finish
   * animating inside ~1.3s and then sit frozen for the remaining 20-35s.
   */
  atSeconds?: number;
};

export type SceneArchetype =
  | "cold-open"
  | "full-bleed-broll"
  | "kinetic-statement"
  | "kinetic-number"
  | "before-after"
  | "comparison"
  | "diagram-build"
  | "timeline"
  | "process-flow"
  | "screen-in-context"
  | "talking-head-sidecar"
  | "quote-problem"
  | "evidence-proof"
  | "checklist-build"
  | "hero-reveal"
  | "cta-end-frame"
  | "chapter-card"
  | "lower-third"
  | "speaker-slide";

export type BriefingScene = {
  id: string;
  kicker: string;
  title: string;
  subtitle?: string;
  bullets: BriefingBullet[];
  durationSeconds: number;
  /** Scene-archetype library id. Required on viewer-facing jobs. */
  archetype?: SceneArchetype;
  /** Per-scene accent so a long program does not read as one endless slide. */
  accent?: string;
  /**
   * Optional richer body — code, a flow, a two-column contrast, a hero number,
   * a layer stack. When present it replaces the bullet list. Absent on every
   * scene authored before this existed, which renders exactly as it always did.
   */
  visual?: Visual;
  /**
   * Who is talking. Only "joel" changes anything: an interviewer's line renders
   * as a question card so the viewer never has to work out whether they are
   * hearing a question or an answer. Absent on scenes authored before this
   * existed, which render exactly as they always did.
   */
  speaker?: "joel" | "sarosh";
};

export type BriefingProps = {
  scenes: BriefingScene[];
  voiceoverFile?: string;
};

const TONE: Record<BulletTone, string> = {
  default: "#E8E4D9",
  emphasis: "#F5C518",
  risk: "#E85D5D",
  good: "#3DDC84",
};

const FALLBACK_ACCENT = "#F5C518";

export const sampleScenes: BriefingScene[] = [
  {
    id: "s1",
    kicker: "BOTTOM LINE",
    title: "One idea per slide",
    subtitle: "Hold until the line is spoken",
    bullets: [
      { text: "Dark field, yellow headline", tone: "emphasis", atSeconds: 1.6 },
      { text: "Color marks meaning, not decoration", tone: "good", atSeconds: 3.8 },
      { text: "Invented numbers are forbidden", tone: "risk", atSeconds: 6.0 },
    ],
    durationSeconds: 8,
  },
];

export const Briefing: FC<BriefingProps> = ({ scenes, voiceoverFile }) => {
  const { fps } = useVideoConfig();
  let start = 0;

  return (
    <AbsoluteFill style={{ backgroundColor: "#0B0B0B" }}>
      {voiceoverFile ? <Audio src={staticFile(voiceoverFile)} /> : null}
      {scenes.map((scene, sceneIndex) => {
        const durationInFrames = Math.max(1, Math.round(scene.durationSeconds * fps));
        const from = start;
        start += durationInFrames;
        return (
          <Sequence
            key={scene.id}
            from={from}
            durationInFrames={durationInFrames}
            name={scene.id}
          >
            <Slide scene={scene} sceneIndex={sceneIndex} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

/**
 * A field that is never completely still. Two very slow counter-drifting
 * glows plus a breathing vignette. It is deliberately low-contrast: the
 * intent is that a viewer never consciously notices it, only that the frame
 * stops feeling like a paused screenshot.
 */
const MovingField: FC<{ accent: string; durationSeconds: number }> = ({
  accent,
  durationSeconds,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const span = Math.max(1, durationSeconds * fps);

  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(60% 55% at 22% 28%, ${accent}14 0%, transparent 68%)`,
          translate: interpolate(frame, [0, span], ["-3% -2%", "4% 3%"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.linear,
          }),
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(52% 48% at 82% 76%, rgba(120,150,255,0.10) 0%, transparent 70%)",
          translate: interpolate(frame, [0, span], ["3% 2%", "-4% -3%"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.linear,
          }),
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(120% 100% at 50% 50%, transparent 45%, rgba(0,0,0,0.55) 100%)",
          opacity: interpolate(
            frame,
            [0, span * 0.5, span],
            [0.85, 1, 0.85],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.linear },
          ),
        }}
      />
    </AbsoluteFill>
  );
};

/** Word-by-word rise. A headline that assembles reads as spoken, not printed. */
const Title: FC<{ text: string; accent: string; atSeconds: number; size?: number }> = ({
  text,
  accent,
  atSeconds,
  size = 72,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const words = text.split(/\s+/).filter(Boolean);

  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        columnGap: 16,
        marginTop: 18,
        color: accent,
        fontSize: size,
        fontWeight: 800,
        lineHeight: 1.1,
      }}
    >
      {words.map((word, index) => {
        const at = atSeconds * fps + index * 0.055 * fps;
        return (
          <Interactive.Div
            key={`${word}-${index}`}
            name={`Title word ${index + 1}`}
            style={{
              opacity: interpolate(frame, [at, at + 0.32 * fps], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(
                frame,
                [at, at + 0.42 * fps],
                ["0px 26px", "0px 0px"],
                {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                },
              ),
            }}
          >
            {word}
          </Interactive.Div>
        );
      })}
    </div>
  );
};

const Bullet: FC<{
  bullet: BriefingBullet;
  index: number;
  at: number;
  isActive: boolean;
  accent: string;
}> = ({ bullet, index, at, isActive, accent }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const color = TONE[bullet.tone ?? "default"];
  const loud = bullet.tone === "emphasis" || bullet.tone === "risk";
  const atFrame = at * fps;

  return (
    <Interactive.Div
      name={`Bullet ${index + 1}`}
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 18,
        marginBottom: 18,
        // Lines already spoken recede so the eye tracks the line being said
        // now. This is what keeps the frame changing across a 30s scene
        // instead of only during its first second.
        opacity: interpolate(
          frame,
          [atFrame, atFrame + 0.34 * fps, atFrame + 1.5 * fps],
          [0, 1, isActive ? 1 : 0.45],
          {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          },
        ),
        translate: interpolate(
          frame,
          [atFrame, atFrame + 0.45 * fps],
          ["0px 18px", "0px 0px"],
          {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          },
        ),
      }}
    >
      <div
        style={{
          width: 4,
          alignSelf: "stretch",
          borderRadius: 2,
          backgroundColor: loud ? color : `${accent}55`,
          scale: interpolate(
            frame,
            [atFrame, atFrame + 0.5 * fps],
            [0, 1],
            {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            },
          ),
        }}
      />
      <div
        style={{
          color,
          fontSize: loud ? 37 : 34,
          fontWeight: loud ? 700 : 500,
          lineHeight: 1.45,
        }}
      >
        {bullet.text}
      </div>
    </Interactive.Div>
  );
};

/**
 * A scene carrying no list is an act break, not a slide with missing bullets.
 * Giving it the same top-left list frame as everything else is what made a
 * 14-scene program read as one continuous slab. Centred, oversized, and short:
 * it lands as a breath between sections.
 */
const Statement: FC<{ scene: BriefingScene; accent: string }> = ({ scene, accent }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const lead = scene.bullets[0];

  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
        textAlign: "center",
        padding: "96px 160px",
        fontFamily: 'Inter, "Segoe UI", system-ui, sans-serif',
      }}
    >
      <Interactive.Div
        name="Kicker"
        style={{
          opacity: interpolate(frame, [0, 0.5 * fps], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          color: accent,
          letterSpacing: "0.36em",
          fontSize: 24,
          fontWeight: 700,
          marginBottom: 28,
        }}
      >
        {scene.kicker}
      </Interactive.Div>
      <div
        style={{
          height: 2,
          width: interpolate(frame, [0.3 * fps, 1.4 * fps], ["0px", "220px"], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          backgroundColor: `${accent}88`,
          marginBottom: 34,
        }}
      />
      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          justifyContent: "center",
          columnGap: 20,
          color: "#F3EFE4",
          fontSize: 88,
          fontWeight: 800,
          lineHeight: 1.08,
          maxWidth: "94%",
        }}
      >
        {scene.title.split(/\s+/).filter(Boolean).map((word, index) => {
          const at = 0.55 * fps + index * 0.07 * fps;
          return (
            <Interactive.Div
              key={`${word}-${index}`}
              name={`Statement word ${index + 1}`}
              style={{
                opacity: interpolate(frame, [at, at + 0.4 * fps], [0, 1], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                }),
                translate: interpolate(
                  frame,
                  [at, at + 0.5 * fps],
                  ["0px 34px", "0px 0px"],
                  {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                    easing: Easing.bezier(0.16, 1, 0.3, 1),
                  },
                ),
              }}
            >
              {word}
            </Interactive.Div>
          );
        })}
      </div>
      {scene.subtitle ? (
        <Interactive.Div
          name="Subtitle"
          style={{
            opacity: interpolate(frame, [1.3 * fps, 2.0 * fps], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.bezier(0.16, 1, 0.3, 1),
            }),
            color: "#B7B2A4",
            fontSize: 34,
            marginTop: 30,
            maxWidth: "72%",
          }}
        >
          {scene.subtitle}
        </Interactive.Div>
      ) : null}
      {lead ? (
        <Interactive.Div
          name="Lead line"
          style={{
            opacity: interpolate(
              frame,
              [(lead.atSeconds ?? 2.2) * fps, ((lead.atSeconds ?? 2.2) + 0.5) * fps],
              [0, 1],
              {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              },
            ),
            color: TONE[lead.tone ?? "emphasis"],
            fontSize: 38,
            fontWeight: 700,
            marginTop: 44,
            maxWidth: "80%",
          }}
        >
          {lead.text}
        </Interactive.Div>
      ) : null}
    </AbsoluteFill>
  );
};

/**
 * The interviewer's line. Deliberately unlike every answer scene: off-white on
 * a darker ground, a heavy left rule, no accent colour and no diagram. Over
 * forty minutes the viewer stops reading the label and just recognises the
 * shape, which is the whole point of giving a question its own card.
 */
const Question: FC<{ scene: BriefingScene }> = ({ scene }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const span = Math.max(1, scene.durationSeconds * fps);
  const words = scene.title.split(/\s+/).filter(Boolean);
  // Measured at 0.13s/word: a 25-word question finished arriving at 3.6s of a
  // 14.5s line and then held for 9.8s — the worst frozen run in the programme.
  // The words have to land at roughly the rate they are spoken, so the card is
  // still being written while the question is still being asked.
  const step = Math.max(0.05, (scene.durationSeconds * 0.86) / Math.max(1, words.length));

  return (
    <AbsoluteFill style={{ backgroundColor: "#070707" }}>
      <MovingField accent="#5A5A5A" durationSeconds={scene.durationSeconds} />
      <AbsoluteFill
        style={{
          padding: "96px 130px",
          justifyContent: "center",
          fontFamily: 'Inter, "Segoe UI", system-ui, sans-serif',
          scale: interpolate(frame, [0, span], [1, 1.025], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.linear,
          }),
        }}
      >
        <div style={{ display: "flex", gap: 40 }}>
          <div
            style={{
              width: 5,
              borderRadius: 3,
              backgroundColor: "#4A4A4A",
              scale: interpolate(frame, [0, 0.7 * fps], ["1 0", "1 1"], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              transformOrigin: "top center",
            }}
          />
          <div style={{ flex: 1 }}>
            <div
              style={{
                opacity: interpolate(frame, [0, 0.45 * fps], [0, 1], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                }),
                color: "#6E6A62",
                letterSpacing: "0.34em",
                fontSize: 21,
                fontWeight: 700,
                marginBottom: 30,
              }}
            >
              {scene.kicker}
            </div>
            <div
              style={{
                display: "flex",
                flexWrap: "wrap",
                columnGap: 16,
                color: "#CFCABE",
                fontSize: 52,
                fontWeight: 500,
                lineHeight: 1.32,
                maxWidth: "96%",
              }}
            >
              {words.map((word, index) => {
                const at = (0.35 + index * step) * fps;
                return (
                  <Interactive.Div
                    key={`${word}-${index}`}
                    name={`Question word ${index + 1}`}
                    style={{
                      opacity: interpolate(frame, [at, at + 0.34 * fps], [0, 1], {
                        extrapolateLeft: "clamp",
                        extrapolateRight: "clamp",
                        easing: Easing.bezier(0.16, 1, 0.3, 1),
                      }),
                    }}
                  >
                    {word}
                  </Interactive.Div>
                );
              })}
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Slide: FC<{ scene: BriefingScene; sceneIndex: number }> = ({
  scene,
  sceneIndex,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const accent = scene.accent ?? FALLBACK_ACCENT;
  const span = Math.max(1, scene.durationSeconds * fps);

  if (scene.speaker === "joel" || scene.archetype === "quote-problem") {
    return <Question scene={scene} />;
  }

  // A visual owns the body. Checked before the act-break branch, because a
  // code block or a diagram legitimately carries no bullets at all.
  if (!scene.visual && scene.bullets.length <= 1) {
    return (
      <AbsoluteFill style={{ backgroundColor: "#0B0B0B" }}>
        <MovingField accent={accent} durationSeconds={scene.durationSeconds} />
        <AbsoluteFill
          style={{
            scale: interpolate(frame, [0, span], [1, 1.03], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
              easing: Easing.linear,
            }),
          }}
        >
          <Statement scene={scene} accent={accent} />
        </AbsoluteFill>
      </AbsoluteFill>
    );
  }

  // Narration-synced when the builder supplied timings; otherwise the old
  // fixed stagger, so scenes authored before this change still render.
  const reveals = scene.bullets.map((bullet, index) =>
    typeof bullet.atSeconds === "number"
      ? bullet.atSeconds
      : 0.45 + index * 0.18,
  );
  const activeIndex = reveals.reduce(
    (active, at, index) => (frame >= at * fps ? index : active),
    -1,
  );

  return (
    <AbsoluteFill style={{ backgroundColor: "#0B0B0B" }}>
      <MovingField accent={accent} durationSeconds={scene.durationSeconds} />
      <AbsoluteFill
        style={{
          padding: scene.visual ? "70px 110px 86px" : "96px 120px",
          fontFamily: 'Inter, "Segoe UI", system-ui, sans-serif',
          // Column flow so a visual body can claim the space under the title
          // instead of the title block dictating where the frame ends.
          display: "flex",
          flexDirection: "column",
          // A slow push-in across the whole scene. 3.5% over 20-35s is below
          // conscious notice but removes the frozen-frame quality entirely.
          scale: interpolate(frame, [0, span], [1, 1.035], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
            easing: Easing.linear,
          }),
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <Interactive.Div
            name="Kicker"
            style={{
              opacity: interpolate(frame, [0, 0.4 * fps], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              color: "#9A9588",
              letterSpacing: "0.28em",
              fontSize: 22,
              fontWeight: 600,
              whiteSpace: "nowrap",
            }}
          >
            {scene.kicker}
          </Interactive.Div>
          <div
            style={{
              height: 1,
              flex: 1,
              backgroundColor: `${accent}44`,
              scale: interpolate(frame, [0.2 * fps, 1.1 * fps], ["0 1", "1 1"], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              transformOrigin: "left center",
            }}
          />
          <Interactive.Div
            name="Scene number"
            style={{
              opacity: interpolate(frame, [0.5 * fps, 1.2 * fps], [0, 0.55], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              color: "#9A9588",
              fontSize: 20,
              fontWeight: 600,
              letterSpacing: "0.1em",
            }}
          >
            {String(sceneIndex + 1).padStart(2, "0")}
          </Interactive.Div>
        </div>

        <Title
          text={scene.title}
          accent={accent}
          atSeconds={0.15}
          size={scene.visual ? 54 : 72}
        />

        {scene.subtitle ? (
          <Interactive.Div
            name="Subtitle"
            style={{
              opacity: interpolate(frame, [0.5 * fps, 0.95 * fps], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(
                frame,
                [0.5 * fps, 1.0 * fps],
                ["0px 14px", "0px 0px"],
                {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                  easing: Easing.bezier(0.16, 1, 0.3, 1),
                },
              ),
              color: "#C4BFAF",
              fontSize: 32,
              marginTop: 16,
              maxWidth: "86%",
            }}
          >
            {scene.subtitle}
          </Interactive.Div>
        ) : null}

        {/* A visual is the point of its scene, so it takes the free space and
            sits in the middle of it. Left top-aligned it stranded a code block
            in the upper third with a dead half-frame underneath. */}
        <div
          style={{
            marginTop: scene.visual ? 30 : 48,
            ...(scene.visual
              ? { flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", minHeight: 0 }
              : {}),
          }}
        >
          {scene.visual ? (
            <VisualBody
              visual={scene.visual}
              accent={accent}
              durationSeconds={scene.durationSeconds}
            />
          ) : (
            scene.bullets.map((bullet, index) => (
              <Bullet
                key={`${scene.id}-${index}`}
                bullet={bullet}
                index={index}
                at={reveals[index]}
                isActive={index === activeIndex}
                accent={accent}
              />
            ))
          )}
        </div>
      </AbsoluteFill>

      {/* Momentum. A viewer can see the scene is going somewhere and how far
          in it is, which is most of what "this is not dragging" feels like. */}
      <AbsoluteFill style={{ justifyContent: "flex-end" }}>
        <div style={{ height: 3, backgroundColor: "#FFFFFF10" }}>
          <div
            style={{
              height: 3,
              backgroundColor: `${accent}AA`,
              width: interpolate(frame, [0, span], ["0%", "100%"], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.linear,
              }),
            }}
          />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
