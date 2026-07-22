#!/usr/bin/env node
// FFmpeg/ffprobe-backed technical QA: codec/resolution/fps/duration/audio, black-frame,
// freeze-frame, loudness, and silence detection, plus scene-boundary frame extraction and a
// contact sheet -- the inputs product-demo-studio-qa's five reviewer agents inspect.
// Usage:
//   node technical-checks.mjs --video <path> --out <qa-output-dir> [--scenes 0,4.2,9.8] [--json]
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
};
const asJson = args.includes("--json");
// Fail-closed by default (Technical QA gate). --report-only downgrades to a non-zero-free report
// for callers that only want the raw data. --silent marks the video as intentionally without a
// narration/music track (e.g. a silent hero micro-clip) so a missing audio stream is not a failure.
const reportOnly = args.includes("--report-only");
const silentExpected = args.includes("--silent");
const num = (name, def) => {
  const v = flag(name);
  return v !== undefined ? Number(v) : def;
};
const edgeTol = num("--edge-tolerance", 0.7); // leading/trailing zone where fades/holds are allowed
const freezeMaxSeconds = num("--freeze-max", 10); // mid-content freeze longer than this fails
const silenceMaxSeconds = num("--silence-max", 3.5); // mid-content silence gap longer than this fails

const videoPath = flag("--video");
const outDir = flag("--out");
if (!videoPath || !outDir) {
  console.error(
    "Usage: node technical-checks.mjs --video <path> --out <qa-output-dir> [--scenes 0,4.2,9.8] " +
      "[--json] [--report-only] [--silent] [--edge-tolerance 0.7] [--freeze-max 10] [--silence-max 3.5]",
  );
  process.exit(1);
}
if (!existsSync(videoPath)) {
  console.error(`Video not found: ${videoPath}`);
  process.exit(1);
}

function which(cmd) {
  const probe = spawnSync(cmd, ["-version"], { encoding: "utf8" });
  return probe.error === undefined || probe.error?.code !== "ENOENT";
}

for (const cmd of ["ffmpeg", "ffprobe"]) {
  if (!which(cmd)) {
    console.error(
      `"${cmd}" was not found on PATH. Install FFmpeg (https://ffmpeg.org/download.html) and ` +
        "ensure both ffmpeg and ffprobe are on PATH before running technical QA checks. " +
        "No checks were skipped silently -- this run did not produce a QA report.",
    );
    process.exit(1);
  }
}

function run(cmd, cmdArgs) {
  const result = spawnSync(cmd, cmdArgs, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { stdout: result.stdout ?? "", stderr: result.stderr ?? "", status: result.status };
}

mkdirSync(outDir, { recursive: true });
const framesDir = join(outDir, "frames");
mkdirSync(framesDir, { recursive: true });

const report = { video: videoPath, checks: {} };

// --- Master checksum (provenance + "valid master checksum" gate input) ---
report.checks.checksum = { status: "ok", sha256: createHash("sha256").update(readFileSync(videoPath)).digest("hex") };

// --- Format/stream metadata ---
{
  const { stdout, status } = run("ffprobe", [
    "-v", "error",
    "-print_format", "json",
    "-show_format",
    "-show_streams",
    videoPath,
  ]);
  if (status !== 0) {
    report.checks.metadata = { status: "error", message: "ffprobe failed to read the file." };
  } else {
    const parsed = JSON.parse(stdout);
    const video = parsed.streams?.find((s) => s.codec_type === "video");
    const audio = parsed.streams?.find((s) => s.codec_type === "audio");
    report.checks.metadata = {
      status: "ok",
      durationSeconds: Number(parsed.format?.duration ?? video?.duration ?? 0),
      videoCodec: video?.codec_name ?? null,
      width: video?.width ?? null,
      height: video?.height ?? null,
      frameRate: video?.r_frame_rate ?? null,
      hasAudio: Boolean(audio),
      audioCodec: audio?.codec_name ?? null,
    };
  }
}

const durationSeconds = report.checks.metadata?.durationSeconds ?? 0;

// --- Black-frame detection ---
{
  const { stderr } = run("ffmpeg", [
    "-i", videoPath,
    "-vf", "blackdetect=d=0.5:pic_th=0.98",
    "-an", "-f", "null", "-",
  ]);
  const ranges = [...stderr.matchAll(/black_start:([\d.]+) black_end:([\d.]+) black_duration:([\d.]+)/g)].map(
    (m) => ({ start: Number(m[1]), end: Number(m[2]), duration: Number(m[3]) }),
  );
  report.checks.blackFrames = { status: "ok", ranges };
}

// --- Freeze-frame detection ---
{
  const { stderr } = run("ffmpeg", [
    "-i", videoPath,
    "-vf", "freezedetect=n=-60dB:d=0.5",
    "-an", "-f", "null", "-",
  ]);
  const starts = [...stderr.matchAll(/freeze_start:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const durations = [...stderr.matchAll(/freeze_duration:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const ranges = starts.map((start, i) => ({ start, duration: durations[i] ?? null }));
  report.checks.freezeFrames = { status: "ok", ranges };
}

// --- Loudness (integrated LUFS, true peak) ---
if (report.checks.metadata?.hasAudio) {
  const { stderr } = run("ffmpeg", [
    "-i", videoPath,
    "-af", "loudnorm=print_format=json",
    "-f", "null", "-",
  ]);
  const jsonMatch = stderr.match(/\{[\s\S]*\}/);
  if (jsonMatch) {
    try {
      const loud = JSON.parse(jsonMatch[0]);
      report.checks.loudness = {
        status: "ok",
        integratedLUFS: Number(loud.input_i),
        truePeakDb: Number(loud.input_tp),
        loudnessRangeLU: Number(loud.input_lra),
      };
    } catch {
      report.checks.loudness = { status: "error", message: "Could not parse loudnorm output." };
    }
  } else {
    report.checks.loudness = { status: "error", message: "loudnorm produced no parseable output." };
  }
} else {
  report.checks.loudness = { status: "skipped", message: "No audio stream." };
}

// --- Silence detection ---
if (report.checks.metadata?.hasAudio) {
  const { stderr } = run("ffmpeg", [
    "-i", videoPath,
    "-af", "silencedetect=n=-30dB:d=0.5",
    "-f", "null", "-",
  ]);
  const starts = [...stderr.matchAll(/silence_start:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const ends = [...stderr.matchAll(/silence_end:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const ranges = starts.map((start, i) => ({ start, end: ends[i] ?? null }));
  report.checks.silence = { status: "ok", ranges };
} else {
  report.checks.silence = { status: "skipped", message: "No audio stream." };
}

// --- Audio clipping detection (max sample volume) ---
if (report.checks.metadata?.hasAudio) {
  const { stderr } = run("ffmpeg", ["-i", videoPath, "-af", "volumedetect", "-f", "null", "-"]);
  const maxMatch = stderr.match(/max_volume:\s*(-?[\d.]+)\s*dB/);
  const maxVolumeDb = maxMatch ? Number(maxMatch[1]) : null;
  report.checks.clipping = {
    // 0 dBFS means samples hit full scale -- clipped. Anything at/above -0.1 dB is treated as clipped.
    status: "ok",
    maxVolumeDb,
    clipped: maxVolumeDb !== null && maxVolumeDb >= -0.1,
  };
} else {
  report.checks.clipping = { status: "skipped", message: "No audio stream." };
}

// --- Frame extraction at scene boundaries ---
const explicitScenes = (flag("--scenes") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean)
  .map(Number);
const timestamps = [0, ...explicitScenes, Math.max(durationSeconds - 0.1, 0)].filter(
  (t, i, arr) => arr.indexOf(t) === i,
);

const extractedFrames = [];
timestamps.forEach((t, i) => {
  const framePath = join(framesDir, `frame-${String(i).padStart(3, "0")}-t${t.toFixed(2)}s.png`);
  const { status } = run("ffmpeg", ["-ss", String(t), "-i", videoPath, "-frames:v", "1", "-y", framePath]);
  if (status === 0 && existsSync(framePath)) {
    extractedFrames.push({ timestampSeconds: t, path: framePath });
  }
});
report.checks.frames = { status: "ok", extracted: extractedFrames };

// --- Contact sheet from the extracted frames ---
if (extractedFrames.length > 0) {
  const contactSheetPath = join(outDir, "contact-sheet.png");
  const cols = Math.min(4, extractedFrames.length);
  const rows = Math.ceil(extractedFrames.length / cols);
  const { status } = run("ffmpeg", [
    "-pattern_type", "glob",
    "-i", join(framesDir, "frame-*.png"),
    "-vf", `tile=${cols}x${rows}`,
    "-y", contactSheetPath,
  ]);
  report.checks.contactSheet =
    status === 0 && existsSync(contactSheetPath)
      ? { status: "ok", path: contactSheetPath }
      : { status: "error", message: "Contact-sheet tiling failed; individual frames are still available." };
}

// --- Fail-closed verdict ---
// A range entirely inside the leading/trailing edge zone is an allowed fade or end-hold, not a defect.
const inEdgeZone = (start, end) => end <= edgeTol || start >= durationSeconds - edgeTol;
const meta = report.checks.metadata;
const failures = [];

if (meta?.status !== "ok") failures.push("ffprobe could not read format/stream metadata.");
if (meta?.status === "ok") {
  if (!meta.videoCodec) failures.push("No video codec / video stream.");
  if (!meta.width || !meta.height) failures.push("Missing frame dimensions (resolution).");
  if (!meta.frameRate || meta.frameRate === "0/0") failures.push("Missing/invalid frame rate.");
  if (!durationSeconds || durationSeconds <= 0) failures.push("Zero or unknown duration.");
  if (!meta.hasAudio && !silentExpected) {
    failures.push("No audio stream (pass --silent if this clip is intentionally silent).");
  }
}
const materialBlack = report.checks.blackFrames.ranges.filter((r) => !inEdgeZone(r.start, r.end));
if (materialBlack.length > 0) failures.push(`${materialBlack.length} mid-content black-frame range(s).`);

const materialFreeze = report.checks.freezeFrames.ranges.filter(
  (r) => r.duration != null && r.duration >= freezeMaxSeconds && r.start < durationSeconds - edgeTol,
);
if (materialFreeze.length > 0) {
  failures.push(`${materialFreeze.length} freeze range(s) >= ${freezeMaxSeconds}s mid-content.`);
}
if (report.checks.silence?.status === "ok") {
  const materialSilence = report.checks.silence.ranges.filter(
    (r) => r.end != null && r.end - r.start >= silenceMaxSeconds && !inEdgeZone(r.start, r.end),
  );
  if (materialSilence.length > 0) {
    failures.push(`${materialSilence.length} silence dropout(s) >= ${silenceMaxSeconds}s mid-content.`);
  }
}
if (report.checks.clipping?.clipped) failures.push(`Audio clipping (max_volume ${report.checks.clipping.maxVolumeDb} dB).`);
if (extractedFrames.length === 0) failures.push("No representative frames could be extracted.");

report.pass = failures.length === 0;
report.failures = failures;

const reportPath = join(outDir, "technical-report.json");
writeFileSync(reportPath, JSON.stringify(report, null, 2));

if (asJson) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`Technical QA report: ${reportPath}`);
  console.log(`Frames: ${framesDir} (${extractedFrames.length} extracted)`);
  if (report.checks.contactSheet?.path) console.log(`Contact sheet: ${report.checks.contactSheet.path}`);
  console.log(report.pass ? "PASS: technical checks" : `FAIL: technical checks\n  - ${failures.join("\n  - ")}`);
}

// Fail closed: a technically broken master must block the pipeline. --report-only opts out for
// callers that only want the data (e.g. inspecting an intentionally rough capture).
if (!report.pass && !reportOnly) process.exit(1);
