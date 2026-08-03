#!/usr/bin/env node
// Build the six craft calibration masters and their companion artifacts.
//
// Fixtures are synthetic and deterministic: the same stills, the same shot list,
// the same encoder settings produce byte-identical output, so the checksums in
// catalog.json are stable and a fixture cannot drift without the catalog failing.
//
// Each fixture differs from `clean-pass` in exactly one property. That is the
// point — a reviewer that trips on the wrong criterion has not detected the
// planted defect, it has found something else.
//
// Usage: node build-craft-fixtures.mjs [--stills <dir>] [--out <dir>]

import { mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const arg = (flag, fallback) => {
  const i = argv.indexOf(flag);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
};
const STILLS = resolve(arg("--stills", join(here, "..", "fixtures", "craft", "_stills")));
const OUT = resolve(arg("--out", join(here, "..", "fixtures", "craft")));

const FPS = 30;
const W = 1920;
const H = 1080;

/* ------------------------------------------------------------------ *
 * Shot lists. One property differs per fixture; everything else holds.
 * ------------------------------------------------------------------ */

const HERO_LINE = "127 of 127 lines matched";

const CLEAN_SHOTS = [
  { still: "s1_before", secs: 4.5, beat: "cold-open + before-state" },
  { still: "s2_working", secs: 2.5, beat: "action" },
  { still: "s3_hero", secs: 4.0, beat: "hero reveal", hero: true },
  { still: "s4_guardrail", secs: 3.0, beat: "guardrail" },
  { still: "s7_endcard", secs: 3.0, beat: "close" },
];

const IDENTITY_RUNG = [
  "Every month, 127 lines get matched by hand.",
  "One action.",
  "Done. Every line, every invoice.",
  "Nothing posts until you say so.",
  "Close the month in an afternoon.",
];

const FEATURE_RUNG = [
  "Northwind Ledger includes automated reconciliation.",
  "Select Reconcile to start the matching engine.",
  "The engine matches 127 ledger lines against the bank feed.",
  "An approval step is included in the workflow.",
  "Northwind Ledger. Automated reconciliation included.",
];

const FIXTURES = {
  "clean-pass": {
    expectedVerdict: "PASS",
    trips: [],
    shots: CLEAN_SHOTS,
    lines: IDENTITY_RUNG,
    planted: "None. Correct arc, one hero held 4.0s, identity-rung payoff.",
  },

  "no-hold": {
    expectedVerdict: "FAIL",
    trips: [{ criterion: "results-land", classification: "capture-fixable", severity: "degrades" }],
    // Only difference from clean-pass: the hero shot is cut 600ms after the reveal.
    shots: CLEAN_SHOTS.map((s) => (s.hero ? { ...s, secs: 0.6 } : s)),
    lines: IDENTITY_RUNG,
    planted: "Hero shot cut 600ms after the reveal. Nothing else changed.",
  },

  "buried-hero": {
    expectedVerdict: "FAIL",
    trips: [{ criterion: "hero-moment-staged", classification: "capture-fixable", severity: "blocks" }],
    // The hero lands at ~37% and is followed by two more beats, so it is not the payoff.
    shots: [
      { still: "s1_before", secs: 3.0, beat: "cold-open" },
      { still: "s2_working", secs: 2.0, beat: "action" },
      { still: "s3_hero", secs: 1.2, beat: "hero reveal, buried", hero: true },
      { still: "s4_guardrail", secs: 4.0, beat: "feature beat" },
      { still: "s2_working", secs: 3.5, beat: "feature beat" },
      { still: "s7_endcard", secs: 3.0, beat: "close" },
    ],
    lines: [
      "Every month, 127 lines get matched by hand.",
      "One action.",
      "Done. Every line, every invoice.",
      "There is also an approval step.",
      "And a full processing log.",
      "Close the month in an afternoon.",
    ],
    planted: "Hero at 37% of runtime, followed by two feature beats. Never the payoff.",
  },

  "three-heroes": {
    expectedVerdict: "FAIL",
    trips: [{ criterion: "single-hero", classification: "capture-fixable", severity: "blocks" }],
    shots: [
      { still: "s1_before", secs: 3.5, beat: "cold-open" },
      { still: "s2_working", secs: 2.0, beat: "action" },
      { still: "s3_hero", secs: 2.5, beat: "reveal 1", hero: true },
      { still: "s5_hero_b", secs: 2.5, beat: "reveal 2", hero: true },
      { still: "s6_hero_c", secs: 2.5, beat: "reveal 3", hero: true },
      { still: "s4_guardrail", secs: 2.0, beat: "guardrail" },
      { still: "s7_endcard", secs: 2.5, beat: "close" },
    ],
    lines: [
      "Every month, 127 lines get matched by hand.",
      "One action.",
      "Done. Every line, every invoice.",
      "And the full amount cleared.",
      "And zero exceptions raised.",
      "Nothing posts until you say so.",
      "Close the month in an afternoon.",
    ],
    planted: "Three competing reveals of equal weight. No single protected hero.",
  },

  "dead-wait": {
    expectedVerdict: "FAIL",
    trips: [{ criterion: "bounded-waits", classification: "product-fix-required", severity: "blocks" }],
    shots: [
      { still: "s1_before", secs: 4.0, beat: "cold-open" },
      { still: "s2_working", secs: 6.5, beat: "frozen wait, no state change" },
      { still: "s3_hero", secs: 3.5, beat: "hero reveal", hero: true },
      { still: "s4_guardrail", secs: 2.5, beat: "guardrail" },
      { still: "s7_endcard", secs: 2.5, beat: "close" },
    ],
    lines: [
      "Every month, 127 lines get matched by hand.",
      "One action.",
      "Done. Every line, every invoice.",
      "Nothing posts until you say so.",
      "Close the month in an afternoon.",
    ],
    planted: "6.5s on a single frame with no visible state change. Uncut in the master.",
  },

  "feature-rung": {
    expectedVerdict: "FAIL",
    trips: [{ criterion: "wiifm-rung", classification: "capture-fixable", severity: "degrades" }],
    // Visually byte-identical shot list to clean-pass. Only the narration rung differs.
    shots: CLEAN_SHOTS,
    lines: FEATURE_RUNG,
    planted: "Same visuals as clean-pass. Payoff lands on the feature rung, not outcome or identity.",
  },
};

/* ------------------------------------------------------------------ */

const run = (cmd, args) => {
  const r = spawnSync(cmd, args, { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`${cmd} exited ${r.status}\n${(r.stderr || "").slice(-1200)}`);
  return r.stdout;
};

const stamp = (s) => {
  const ms = Math.round(s * 1000);
  const p = (n, w = 2) => String(n).padStart(w, "0");
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(
    Math.floor(ms / 1000) % 60,
  )},${p(ms % 1000, 3)}`;
};

const sha256 = (p) => createHash("sha256").update(readFileSync(p)).digest("hex");

function buildSrt(shots, lines) {
  let t = 0;
  const cues = [];
  shots.forEach((s, i) => {
    const text = lines[i];
    if (text) {
      // Caption spans the shot, minus a 150ms tail so cues never abut.
      cues.push(`${cues.length + 1}\n${stamp(t)} --> ${stamp(t + Math.max(0.4, s.secs - 0.15))}\n${text}\n`);
    }
    t += s.secs;
  });
  return cues.join("\n");
}

function buildFixture(id, spec) {
  const dir = join(OUT, id);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });

  const total = spec.shots.reduce((a, s) => a + s.secs, 0);

  // --- concat list ---------------------------------------------------
  const listPath = join(dir, "shots.txt");
  const list = spec.shots
    .map((s) => `file '${join(STILLS, s.still + ".png")}'\nduration ${s.secs}`)
    .join("\n");
  // The concat demuxer ignores the final duration unless the last file repeats.
  writeFileSync(listPath, `${list}\nfile '${join(STILLS, spec.shots.at(-1).still + ".png")}'\n`);

  // --- transcript ----------------------------------------------------
  const srtPath = join(dir, "transcript.srt");
  writeFileSync(srtPath, buildSrt(spec.shots, spec.lines), "utf8");

  // --- master --------------------------------------------------------
  const masterPath = join(dir, `${id}.mp4`);
  run("ffmpeg", [
    "-y", "-v", "error",
    // Bitexact strips encoder version strings and creation timestamps so a
    // rebuild is byte-identical and the catalog checksums stay stable.
    "-fflags", "+bitexact", "-flags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
    "-f", "concat", "-safe", "0", "-i", listPath,
    // Low-level bed so the audio stream is valid and silencedetect does not fire
    // on every fixture. These are craft fixtures, not audio fixtures.
    "-f", "lavfi", "-i", `anoisesrc=color=brown:amplitude=0.015:seed=20260731:r=48000:d=${total}`,
    "-vf", [
      `scale=${W}:${H}:force_original_aspect_ratio=decrease`,
      `pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=#f4f6f9`,
      `subtitles=filename='${srtPath}':charenc=UTF-8:force_style='FontSize=22,PrimaryColour=&H00FFFFFF,OutlineColour=&H90000000,BorderStyle=3,Outline=1,Alignment=2,MarginV=56'`,
      "format=yuv420p",
    ].join(","),
    "-r", String(FPS),
    "-c:v", "libx264", "-profile:v", "high", "-crf", "23", "-preset", "medium",
    "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2",
    "-movflags", "+faststart",
    "-t", String(total),
    masterPath,
  ]);
  rmSync(listPath);

  // --- storyboard ----------------------------------------------------
  let t = 0;
  const beats = spec.shots.map((s, i) => {
    const beat = {
      index: i,
      beat: s.beat,
      startsAt: Number(t.toFixed(3)),
      endsAt: Number((t + s.secs).toFixed(3)),
      durationMs: Math.round(s.secs * 1000),
      isHero: Boolean(s.hero),
      narration: spec.lines[i] ?? null,
    };
    t += s.secs;
    return beat;
  });
  writeFileSync(
    join(dir, "storyboard.json"),
    JSON.stringify({ fixtureId: id, fps: FPS, durationSeconds: Number(total.toFixed(3)), beats }, null, 2) + "\n",
  );

  // --- timing deltas -------------------------------------------------
  // The interval between a state change and the cut away from it. This is what
  // converts "the payoff felt rushed" into a number a reviewer can cite.
  writeFileSync(
    join(dir, "timing-deltas.json"),
    JSON.stringify(
      {
        fixtureId: id,
        note: "stateChangeToCutMs is the hold on each beat. Hero beats under 1000ms fail results-land.",
        beats: beats.map((b) => ({
          index: b.index,
          beat: b.beat,
          isHero: b.isHero,
          stateChangeToCutMs: b.durationMs,
        })),
        heroCount: beats.filter((b) => b.isHero).length,
        heroPositionRatio: beats.filter((b) => b.isHero).map((b) => Number((b.startsAt / total).toFixed(3))),
        longestStaticStretchMs: Math.max(...beats.map((b) => b.durationMs)),
      },
      null,
      2,
    ) + "\n",
  );

  // --- expected result ------------------------------------------------
  writeFileSync(
    join(dir, "expected-criteria.json"),
    JSON.stringify(
      {
        fixtureId: id,
        expectedVerdict: spec.expectedVerdict,
        plantedDefect: spec.planted,
        mustTrip: spec.trips,
        mustNotTrip: "any criterion not listed in mustTrip",
      },
      null,
      2,
    ) + "\n",
  );

  const dur = Number(
    run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", masterPath]).trim(),
  );

  return {
    id,
    expectedVerdict: spec.expectedVerdict,
    plantedDefect: spec.planted,
    mustTrip: spec.trips,
    durationSeconds: Number(dur.toFixed(3)),
    artifacts: {
      master: { artifactPath: `fixtures/craft/${id}/${id}.mp4`, sha256: sha256(masterPath) },
      storyboard: { artifactPath: `fixtures/craft/${id}/storyboard.json`, sha256: sha256(join(dir, "storyboard.json")) },
      transcript: { artifactPath: `fixtures/craft/${id}/transcript.srt`, sha256: sha256(srtPath) },
      timingDeltas: { artifactPath: `fixtures/craft/${id}/timing-deltas.json`, sha256: sha256(join(dir, "timing-deltas.json")) },
      expectedCriteria: { artifactPath: `fixtures/craft/${id}/expected-criteria.json`, sha256: sha256(join(dir, "expected-criteria.json")) },
    },
  };
}

if (!existsSync(STILLS)) {
  console.error(`Stills not found at ${STILLS}. Run capture-stills.mjs first.`);
  process.exit(2);
}

mkdirSync(OUT, { recursive: true });
const entries = Object.entries(FIXTURES).map(([id, spec]) => {
  const e = buildFixture(id, spec);
  console.log(`${id.padEnd(14)} ${String(e.durationSeconds).padStart(6)}s  ${e.expectedVerdict.padEnd(4)}  ${e.artifacts.master.sha256.slice(0, 12)}`);
  return e;
});

writeFileSync(
  join(OUT, "catalog.json"),
  JSON.stringify(
    {
      schemaVersion: "1.0.0",
      set: "craft",
      note: "Craft-domain calibration fixtures. Rendered masters for the four video review domains. Regenerate with build-craft-fixtures.mjs; checksums must match or a fixture has drifted.",
      fixtureIds: entries.map((e) => e.id),
      fixtures: entries,
    },
    null,
    2,
  ) + "\n",
);
console.log(`\ncatalog: ${join(OUT, "catalog.json")}`);
