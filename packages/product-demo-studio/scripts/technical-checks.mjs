#!/usr/bin/env node
// FFmpeg/ffprobe-backed technical QA: codec/resolution/fps/duration/audio, black-frame,
// freeze-frame, loudness, and silence detection, plus scene-boundary frame extraction and a
// contact sheet -- deterministic evidence consumed by Product Demo Studio preflight and reviewers.
// Usage:
//   node technical-checks.mjs --video <path> --out <qa-output-dir> --spec <delivery-spec.json>
//     [--scenes 0,4.2,9.8] [--json]
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
const specPath = flag("--spec");
const deterministicOut = flag("--deterministic-out");
const candidateId = flag("--candidate-id");
const mediaArtifactId = flag("--artifact-id");
if (!videoPath || !outDir || (!specPath && !reportOnly)) {
  console.error(
    "Usage: node technical-checks.mjs --video <path> --out <qa-output-dir> --spec <delivery-spec.json> [--scenes 0,4.2,9.8] " +
      "[--json] [--report-only] [--silent] [--edge-tolerance 0.7] [--freeze-max 10] [--silence-max 3.5]",
  );
  process.exit(1);
}
if (!existsSync(videoPath)) {
  console.error(`Video not found: ${videoPath}`);
  process.exit(1);
}
if (specPath && !existsSync(specPath)) {
  console.error(`Delivery specification not found: ${specPath}`);
  process.exit(1);
}
if (deterministicOut && (!candidateId || !mediaArtifactId)) {
  console.error("--deterministic-out requires --candidate-id and --artifact-id.");
  process.exit(1);
}
let deliverySpec = null;
const deliverySpecShapeErrors = [];
if (specPath) {
  try {
    deliverySpec = JSON.parse(readFileSync(specPath, "utf8"));
  } catch (error) {
    console.error(`Invalid delivery specification JSON: ${error.message}`);
    process.exit(1);
  }
  const rejectUnknown = (value, allowed, label) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return;
    for (const key of Object.keys(value)) {
      if (!allowed.has(key)) deliverySpecShapeErrors.push(`${label}.${key} is not allowed.`);
    }
  };
  rejectUnknown(deliverySpec, new Set([
    "schemaVersion", "platform", "container", "video", "audio",
    "fastStartRequired", "maxConsecutiveDuplicateFrames",
  ]), "$");
  rejectUnknown(deliverySpec.video, new Set([
    "codec", "profile", "width", "height", "frameRate", "frameRateTolerance", "pixelFormat",
    "colorSpace", "colorTransfer", "colorPrimaries", "minimumDurationSeconds",
    "maximumDurationSeconds",
  ]), "$.video");
  rejectUnknown(deliverySpec.audio, new Set([
    "required", "codec", "sampleRate", "channels", "targetIntegratedLUFS",
    "loudnessToleranceLU", "maximumTruePeakDb",
  ]), "$.audio");
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

const report = {
  video: videoPath,
  deliverySpec: specPath ?? null,
  generator: {
    tool: "product-demo-studio-technical-checks",
    version: "1.0.0",
    command: process.argv.map((value) => JSON.stringify(value)).join(" "),
    ffmpegVersion: run("ffmpeg", ["-version"]).stdout.split(/\r?\n/, 1)[0],
    ffprobeVersion: run("ffprobe", ["-version"]).stdout.split(/\r?\n/, 1)[0],
  },
  checks: {},
};

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
    const subtitles = parsed.streams?.filter((s) => s.codec_type === "subtitle") ?? [];
    report.checks.metadata = {
      status: "ok",
      durationSeconds: Number(parsed.format?.duration ?? video?.duration ?? 0),
      videoCodec: video?.codec_name ?? null,
      videoProfile: video?.profile ?? null,
      width: video?.width ?? null,
      height: video?.height ?? null,
      frameRate: video?.r_frame_rate ?? null,
      pixelFormat: video?.pix_fmt ?? null,
      colorSpace: video?.color_space ?? null,
      colorTransfer: video?.color_transfer ?? null,
      colorPrimaries: video?.color_primaries ?? null,
      hasAudio: Boolean(audio),
      subtitleStreams: subtitles.length,
      audioCodec: audio?.codec_name ?? null,
      audioSampleRate: audio?.sample_rate ? Number(audio.sample_rate) : null,
      audioChannels: audio?.channels ?? null,
      formatName: parsed.format?.format_name ?? null,
    };
  }
}

const durationSeconds = report.checks.metadata?.durationSeconds ?? 0;

// --- Container fast-start and full decode integrity ---
{
  const bytes = readFileSync(videoPath);
  const moov = bytes.indexOf(Buffer.from("moov"));
  const mdat = bytes.indexOf(Buffer.from("mdat"));
  report.checks.fastStart = {
    status: "ok",
    applicable: moov !== -1 || mdat !== -1,
    moovOffset: moov,
    mdatOffset: mdat,
    enabled: moov !== -1 && mdat !== -1 && moov < mdat,
  };
  const decoded = run("ffmpeg", [
    "-v", "error",
    "-i", videoPath,
    "-map", "0:v?",
    "-map", "0:a?",
    "-sn",
    "-f", "null",
    "-",
  ]);
  const subtitleStreams = report.checks.metadata?.subtitleStreams ?? 0;
  const subtitles = subtitleStreams > 0
    ? run("ffmpeg", [
      "-v", "error",
      "-i", videoPath,
      "-map", "0:s",
      "-c:s", "copy",
      "-f", "null",
      "-",
    ])
    : { status: 0, stderr: "" };
  report.checks.subtitleIntegrity = {
    status: subtitles.status === 0 && subtitles.stderr.trim() === "" ? "ok" : "error",
    applicable: subtitleStreams > 0,
    streams: subtitleStreams,
    exitCode: subtitles.status,
    diagnostics: subtitles.stderr.trim(),
  };
  report.checks.decodeIntegrity = {
    status: decoded.status === 0 && decoded.stderr.trim() === "" && subtitles.status === 0 && subtitles.stderr.trim() === ""
      ? "ok"
      : "error",
    exitCode: decoded.status !== 0 ? decoded.status : subtitles.status,
    diagnostics: [decoded.stderr.trim(), subtitles.stderr.trim()].filter(Boolean).join("\n"),
  };
}

// --- Exact consecutive duplicate-frame analysis ---
{
  const { stdout, stderr, status } = run("ffmpeg", [
    "-v", "error",
    "-i", videoPath,
    "-map", "0:v:0",
    "-f", "framemd5",
    "-",
  ]);
  const hashes = stdout
    .split(/\r?\n/)
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => line.split(",").at(-1)?.trim())
    .filter(Boolean);
  let duplicateFrames = 0;
  let currentRun = 1;
  let maxConsecutiveRun = hashes.length > 0 ? 1 : 0;
  for (let index = 1; index < hashes.length; index++) {
    if (hashes[index] === hashes[index - 1]) {
      duplicateFrames++;
      currentRun++;
      maxConsecutiveRun = Math.max(maxConsecutiveRun, currentRun);
    } else {
      currentRun = 1;
    }
  }
  report.checks.duplicateFrames = {
    status: status === 0 ? "ok" : "error",
    analyzedFrames: hashes.length,
    duplicateFrames,
    maxConsecutiveRun,
    diagnostics: stderr.trim(),
  };
}

// --- Black-frame detection ---
{
  const { stderr, status } = run("ffmpeg", [
    "-i", videoPath,
    "-vf", "blackdetect=d=0.5:pic_th=0.98",
    "-an", "-f", "null", "-",
  ]);
  const ranges = [...stderr.matchAll(/black_start:([\d.]+) black_end:([\d.]+) black_duration:([\d.]+)/g)].map(
    (m) => ({ start: Number(m[1]), end: Number(m[2]), duration: Number(m[3]) }),
  );
  report.checks.blackFrames = {
    status: status === 0 ? "ok" : "error",
    exitCode: status,
    ranges,
    diagnostics: status === 0 ? "" : stderr.trim(),
  };
}

// --- Freeze-frame detection ---
{
  const { stderr, status } = run("ffmpeg", [
    "-i", videoPath,
    "-vf", "freezedetect=n=-60dB:d=0.5",
    "-an", "-f", "null", "-",
  ]);
  const starts = [...stderr.matchAll(/freeze_start:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const durations = [...stderr.matchAll(/freeze_duration:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const ranges = starts.map((start, i) => ({ start, duration: durations[i] ?? null }));
  report.checks.freezeFrames = {
    status: status === 0 ? "ok" : "error",
    exitCode: status,
    ranges,
    diagnostics: status === 0 ? "" : stderr.trim(),
  };
}

// --- Loudness (integrated LUFS, true peak) ---
if (report.checks.metadata?.hasAudio) {
  const { stderr, status } = run("ffmpeg", [
    "-i", videoPath,
    "-af", "loudnorm=print_format=json",
    "-f", "null", "-",
  ]);
  const jsonMatch = status === 0 ? stderr.match(/\{[\s\S]*\}/) : null;
  if (status !== 0) {
    report.checks.loudness = {
      status: "error",
      exitCode: status,
      message: "FFmpeg loudness analysis failed.",
      diagnostics: stderr.trim(),
    };
  } else if (jsonMatch) {
    try {
      const loud = JSON.parse(jsonMatch[0]);
      report.checks.loudness = {
        status: "ok",
        exitCode: status,
        integratedLUFS: Number(loud.input_i),
        truePeakDb: Number(loud.input_tp),
        loudnessRangeLU: Number(loud.input_lra),
      };
    } catch {
      report.checks.loudness = {
        status: "error",
        exitCode: status,
        message: "Could not parse loudnorm output.",
      };
    }
  } else {
    report.checks.loudness = {
      status: "error",
      exitCode: status,
      message: "loudnorm produced no parseable output.",
    };
  }
} else {
  report.checks.loudness = { status: "skipped", message: "No audio stream." };
}

// --- Silence detection ---
if (report.checks.metadata?.hasAudio) {
  const { stderr, status } = run("ffmpeg", [
    "-i", videoPath,
    "-af", "silencedetect=n=-30dB:d=0.5",
    "-f", "null", "-",
  ]);
  const starts = [...stderr.matchAll(/silence_start:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const ends = [...stderr.matchAll(/silence_end:\s*([\d.]+)/g)].map((m) => Number(m[1]));
  const ranges = starts.map((start, i) => ({ start, end: ends[i] ?? null }));
  report.checks.silence = {
    status: status === 0 ? "ok" : "error",
    exitCode: status,
    ranges,
    diagnostics: status === 0 ? "" : stderr.trim(),
  };
} else {
  report.checks.silence = { status: "skipped", message: "No audio stream." };
}

// --- Audio clipping detection (max sample volume) ---
if (report.checks.metadata?.hasAudio) {
  const { stderr, status } = run("ffmpeg", ["-i", videoPath, "-af", "volumedetect", "-f", "null", "-"]);
  const maxMatch = stderr.match(/max_volume:\s*(-?[\d.]+)\s*dB/);
  const maxVolumeDb = maxMatch ? Number(maxMatch[1]) : null;
  report.checks.clipping = {
    // 0 dBFS means samples hit full scale -- clipped. Anything at/above -0.1 dB is treated as clipped.
    status: status === 0 ? "ok" : "error",
    exitCode: status,
    maxVolumeDb,
    clipped: maxVolumeDb !== null && maxVolumeDb >= -0.1,
    diagnostics: status === 0 ? "" : stderr.trim(),
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
  const inputs = extractedFrames.flatMap((frame) => ["-i", frame.path]);
  const concatInputs = extractedFrames.map((_, index) => `[${index}:v]`).join("");
  const { status } = run("ffmpeg", [
    ...inputs,
    "-filter_complex",
    `${concatInputs}concat=n=${extractedFrames.length}:v=1:a=0,tile=${cols}x${rows}[sheet]`,
    "-map", "[sheet]",
    "-frames:v", "1",
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
const rationalToNumber = (value) => {
  if (typeof value !== "string") return Number(value);
  const [numerator, denominator = "1"] = value.split("/").map(Number);
  return denominator === 0 ? Number.NaN : numerator / denominator;
};

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
if (report.checks.decodeIntegrity.status !== "ok") {
  failures.push(`Full-stream decode reported corruption or truncation: ${report.checks.decodeIntegrity.diagnostics || "unknown decode error"}`);
}
if (report.checks.duplicateFrames.status !== "ok") {
  failures.push("Duplicate-frame analysis did not complete.");
}
if (report.checks.blackFrames.status !== "ok") {
  failures.push("Black-frame analysis did not complete.");
}
if (report.checks.freezeFrames.status !== "ok") {
  failures.push("Freeze-frame analysis did not complete.");
}
if (meta?.hasAudio && report.checks.loudness.status !== "ok") {
  failures.push("Loudness analysis did not complete.");
}
if (meta?.hasAudio && report.checks.silence.status !== "ok") {
  failures.push("Silence analysis did not complete.");
}
if (meta?.hasAudio && report.checks.clipping.status !== "ok") {
  failures.push("Clipping analysis did not complete.");
} else if (meta?.hasAudio && report.checks.clipping.maxVolumeDb === null) {
  failures.push("Clipping analysis did not produce a maximum sample level.");
}
if (deliverySpec) {
  const requiredSpec = deliverySpec.schemaVersion === "1.0.0" &&
    typeof deliverySpec.platform === "string" && deliverySpec.platform.length > 0 &&
    deliverySpec.video && typeof deliverySpec.video === "object" &&
    deliverySpec.audio && typeof deliverySpec.audio === "object" &&
    typeof deliverySpec.fastStartRequired === "boolean" &&
    Number.isInteger(deliverySpec.maxConsecutiveDuplicateFrames) &&
    deliverySpec.maxConsecutiveDuplicateFrames >= 1;
  if (!requiredSpec || deliverySpecShapeErrors.length > 0) {
    failures.push(
      `Delivery specification is incomplete, unsupported, or malformed${deliverySpecShapeErrors.length ? `: ${deliverySpecShapeErrors.join(" ")}` : "."}`,
    );
  } else if (meta?.status === "ok") {
    const expectedVideo = deliverySpec.video;
    const expectedAudio = deliverySpec.audio;
    for (const [label, observed, expected] of [
      ["video codec", meta.videoCodec, expectedVideo.codec],
      ["video profile", meta.videoProfile, expectedVideo.profile],
      ["width", meta.width, expectedVideo.width],
      ["height", meta.height, expectedVideo.height],
      ["pixel format", meta.pixelFormat, expectedVideo.pixelFormat],
      ["color space", meta.colorSpace, expectedVideo.colorSpace],
      ["color transfer", meta.colorTransfer, expectedVideo.colorTransfer],
      ["color primaries", meta.colorPrimaries, expectedVideo.colorPrimaries],
    ]) {
      if (expected !== undefined && observed !== expected) {
        failures.push(`Output ${label} is ${JSON.stringify(observed)}; expected ${JSON.stringify(expected)}.`);
      }
    }
    if (deliverySpec.container && !String(meta.formatName).split(",").includes(deliverySpec.container)) {
      failures.push(`Output container is ${JSON.stringify(meta.formatName)}; expected ${deliverySpec.container}.`);
    }
    const observedFps = rationalToNumber(meta.frameRate);
    if (Number.isFinite(expectedVideo.frameRate) &&
        Math.abs(observedFps - expectedVideo.frameRate) > (expectedVideo.frameRateTolerance ?? 0.01)) {
      failures.push(`Output frame rate is ${observedFps}; expected ${expectedVideo.frameRate}.`);
    }
    if (Number.isFinite(expectedVideo.minimumDurationSeconds) &&
        durationSeconds < expectedVideo.minimumDurationSeconds) {
      failures.push(`Output duration ${durationSeconds}s is below ${expectedVideo.minimumDurationSeconds}s.`);
    }
    if (Number.isFinite(expectedVideo.maximumDurationSeconds) &&
        durationSeconds > expectedVideo.maximumDurationSeconds) {
      failures.push(`Output duration ${durationSeconds}s exceeds ${expectedVideo.maximumDurationSeconds}s.`);
    }
    if (expectedAudio.required === true && !meta.hasAudio) failures.push("Delivery specification requires an audio stream.");
    if (expectedAudio.required === false && meta.hasAudio) failures.push("Delivery specification requires a silent output.");
    if (meta.hasAudio) {
      if (expectedAudio.codec && meta.audioCodec !== expectedAudio.codec) {
        failures.push(`Output audio codec is ${meta.audioCodec}; expected ${expectedAudio.codec}.`);
      }
      if (expectedAudio.sampleRate && meta.audioSampleRate !== expectedAudio.sampleRate) {
        failures.push(`Output audio sample rate is ${meta.audioSampleRate}; expected ${expectedAudio.sampleRate}.`);
      }
      if (expectedAudio.channels && meta.audioChannels !== expectedAudio.channels) {
        failures.push(`Output audio channel count is ${meta.audioChannels}; expected ${expectedAudio.channels}.`);
      }
      if (Number.isFinite(expectedAudio.targetIntegratedLUFS) &&
          Math.abs(report.checks.loudness.integratedLUFS - expectedAudio.targetIntegratedLUFS) >
            (expectedAudio.loudnessToleranceLU ?? 1)) {
        failures.push(
          `Integrated loudness is ${report.checks.loudness.integratedLUFS} LUFS; expected ` +
            `${expectedAudio.targetIntegratedLUFS} ± ${expectedAudio.loudnessToleranceLU ?? 1} LU.`,
        );
      }
      if (Number.isFinite(expectedAudio.maximumTruePeakDb) &&
          report.checks.loudness.truePeakDb > expectedAudio.maximumTruePeakDb) {
        failures.push(
          `True peak is ${report.checks.loudness.truePeakDb} dBTP; maximum is ${expectedAudio.maximumTruePeakDb} dBTP.`,
        );
      }
    }
    if (deliverySpec.fastStartRequired && !report.checks.fastStart.enabled) {
      failures.push("MP4 fast start is required but the moov atom follows media data.");
    }
    if (report.checks.duplicateFrames.maxConsecutiveRun >
        deliverySpec.maxConsecutiveDuplicateFrames) {
      failures.push(
        `Maximum exact duplicate-frame run is ${report.checks.duplicateFrames.maxConsecutiveRun}; ` +
          `allowed maximum is ${deliverySpec.maxConsecutiveDuplicateFrames}.`,
      );
    }
  }
} else if (!reportOnly) {
  failures.push("A versioned delivery specification is required for a gate result.");
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

if (deterministicOut) {
  mkdirSync(deterministicOut, { recursive: true });
  const generatedAt = new Date().toISOString();
  const mediaInput = {
    artifactId: mediaArtifactId,
    sha256: report.checks.checksum.sha256,
  };
  const generator = {
    tool: report.generator.tool,
    version: report.generator.version,
    command: report.generator.command,
  };
  const materialDuplicatePass = report.checks.duplicateFrames.status === "ok" &&
    (!deliverySpec || report.checks.duplicateFrames.maxConsecutiveRun <=
      deliverySpec.maxConsecutiveDuplicateFrames);
  const reportDefinitions = {
    mediaMetadata: [
      ["artifact-completeness", meta?.status === "ok"],
      ["output-specifications", report.pass],
    ],
    framesAndContactSheets: [
      ["asset-completeness", extractedFrames.length > 0 && report.checks.contactSheet?.status === "ok"],
    ],
    // Evidence that every resolved scene/beat boundary (0s, each --scenes value, and the
    // near-end timestamp) produced a distinct, non-duplicated representative frame.
    sceneBoundaries: [
      ["frame-duplicate", extractedFrames.length === timestamps.length && extractedFrames.length > 0],
    ],
    frameIntegrity: [
      ["frame-black", materialBlack.length === 0],
      ["frame-frozen", materialFreeze.length === 0],
      ["frame-duplicate", materialDuplicatePass],
      ["frame-corruption", report.checks.decodeIntegrity.status === "ok"],
    ],
    audioQuality: [
      ["audio-loudness", silentExpected || (report.checks.loudness.status === "ok" &&
        !failures.some((message) => message.startsWith("Integrated loudness") || message.startsWith("True peak")))],
      ["audio-clipping", silentExpected || (report.checks.clipping.status === "ok" &&
        report.checks.clipping.clipped === false)],
      ["audio-silence", silentExpected || (report.checks.silence.status === "ok" &&
        !failures.some((message) => message.includes("silence dropout")))],
    ],
    technicalDelivery: [
      ["render-errors", report.checks.decodeIntegrity.status === "ok"],
      ["output-specifications", report.pass],
      ["checksums-provenance", Boolean(report.checks.checksum.sha256)],
    ],
    // Evidence from the freeze/duplicate/black-frame measurements above that no motion-pathology
    // render error (frozen render, exact-duplicate stall, or black-frame dropout) reached mid-content.
    motionAnalysis: [
      [
        "render-errors",
        report.checks.freezeFrames.status === "ok" &&
          report.checks.duplicateFrames.status === "ok" &&
          report.checks.blackFrames.status === "ok" &&
          materialFreeze.length === 0 &&
          materialBlack.length === 0,
      ],
    ],
  };
  for (const [reportType, rawChecks] of Object.entries(reportDefinitions)) {
    const checks = rawChecks.map(([id, passed]) => ({
      id,
      passed,
      evidenceArtifactIds: [mediaArtifactId],
    }));
    const failed = checks.filter((check) => !check.passed).length;
    const deterministicReport = {
      schemaVersion: "1.0.0",
      candidateId,
      reportType,
      status: failed === 0 ? "PASS" : "FAIL",
      generator,
      inputs: [mediaInput],
      checks,
      summary: {
        total: checks.length,
        passed: checks.length - failed,
        failed,
      },
      generatedAt,
    };
    writeFileSync(
      join(deterministicOut, `${reportType}.json`),
      `${JSON.stringify(deterministicReport, null, 2)}\n`,
    );
  }
}

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
