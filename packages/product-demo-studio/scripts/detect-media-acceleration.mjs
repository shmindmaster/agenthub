#!/usr/bin/env node
// Detect compatible local media acceleration and emit a checksumable render-provenance manifest.
// Usage: node detect-media-acceleration.mjs --out <media-acceleration.json>
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";

const args = process.argv.slice(2);
const outputArg = args[args.indexOf("--out") + 1];
if (!args.includes("--out") || !outputArg) {
  console.error("Usage: node detect-media-acceleration.mjs --out <media-acceleration.json>");
  process.exit(1);
}

const query = spawnSync("nvidia-smi", [
  "--query-gpu=name,driver_version,memory.total",
  "--format=csv,noheader,nounits",
], { encoding: "utf8" });
const summary = spawnSync("nvidia-smi", [], { encoding: "utf8" });
const gpuLine = query.status === 0 ? query.stdout.trim().split(/\r?\n/)[0] : "";
const [name, driverVersion, memory] = gpuLine.split(",").map((part) => part?.trim());
const cudaVersion = /CUDA(?: UMD)? Version:\s*([0-9.]+)/i.exec(summary.stdout ?? "")?.[1] ?? null;
const nvidiaAvailable = Boolean(name && driverVersion && Number.parseInt(memory, 10) > 0);

const ffmpeg = spawnSync("ffmpeg", ["-hide_banner", "-encoders"], { encoding: "utf8" });
const ffmpegOutput = `${ffmpeg.stdout ?? ""}\n${ffmpeg.stderr ?? ""}`;
const nvencEncoders = ["av1_nvenc", "hevc_nvenc", "h264_nvenc"].filter((encoder) =>
  new RegExp(`\\b${encoder}\\b`).test(ffmpegOutput),
);
const usableNvencEncoders = nvidiaAvailable ? nvencEncoders.filter((encoder) => {
  const probe = spawnSync("ffmpeg", [
    "-v", "error", "-f", "lavfi", "-i", "color=c=black:size=256x256:rate=1",
    "-frames:v", "1", "-c:v", encoder, "-f", "null", "-",
  ], { encoding: "utf8" });
  return probe.status === 0;
}) : [];
let inference = {
  engine: null,
  available: false,
  cudaUsable: false,
  detail: "No supported local CUDA inference runtime was functionally probed.",
};
const configuredLocalAiRegistry = process.env.AGENTHUB_LOCAL_AI_REGISTRY;
const configuredLocalAiRoot = process.env.AGENTHUB_LOCAL_AI_ROOT;
const defaultLocalAiRoot = process.platform === "win32" ? "D:\\Local-AI" : null;
const localAiRoot = configuredLocalAiRoot ?? defaultLocalAiRoot;
const sharedRegistryPath = configuredLocalAiRegistry
  ? resolve(configuredLocalAiRegistry)
  : localAiRoot
    ? resolve(localAiRoot, "media", "registry.json")
    : null;
const inferenceRuntimes = [];
if (process.env.AGENTHUB_LOCAL_AI_PYTHON) inferenceRuntimes.push(process.env.AGENTHUB_LOCAL_AI_PYTHON);
if (sharedRegistryPath && existsSync(sharedRegistryPath)) {
  try {
    const registry = JSON.parse(readFileSync(sharedRegistryPath, "utf8"));
    for (const capability of registry.capabilities ?? []) {
      if (capability.status === "enabled" && typeof capability.runtime === "string") {
        inferenceRuntimes.push(capability.runtime);
      }
    }
  } catch {
    inference.detail = `Shared runtime registry could not be parsed: ${sharedRegistryPath}`;
  }
}
inferenceRuntimes.push("python");
for (const runtime of [...new Set(inferenceRuntimes)]) {
  if (runtime !== "python" && !existsSync(runtime)) continue;
  const probe = spawnSync(runtime, [
    "-c",
    "import json, torch; ok=bool(torch.cuda.is_available()); print(json.dumps({'engine':'pytorch','available':True,'cudaUsable':ok,'detail':('shared runtime '+torch.__version__+' cuda '+str(torch.version.cuda))}))",
  ], { encoding: "utf8" });
  if (probe.status !== 0) continue;
  try {
    const result = JSON.parse(probe.stdout.trim().split(/\r?\n/).at(-1));
    inference = { ...result, detail: `${result.detail}; executable=${runtime}` };
    if (inference.cudaUsable) break;
  } catch {
    inference.detail = `The local inference probe returned malformed output from ${runtime}.`;
  }
}
const gpuVideoAvailable = usableNvencEncoders.length > 0;
const selectedVideoEncoder = gpuVideoAvailable
  ? (usableNvencEncoders.includes("h264_nvenc") ? "h264_nvenc" : usableNvencEncoders.includes("av1_nvenc") ? "av1_nvenc" : usableNvencEncoders[0])
  : "libx264";
const mode = gpuVideoAvailable || inference.cudaUsable ? "gpu-preferred" : "cpu-fallback";
const fallbackReasons = [];
if (!gpuVideoAvailable) fallbackReasons.push("No advertised NVENC encoder completed a functional encode probe.");
if (!inference.cudaUsable) fallbackReasons.push(inference.detail);
const manifest = {
  schemaVersion: "1.0.0",
  detectedAt: new Date().toISOString(),
  mode,
  nvidia: {
    available: nvidiaAvailable,
    name: nvidiaAvailable ? name : null,
    driverVersion: nvidiaAvailable ? driverVersion : null,
    cudaVersion: nvidiaAvailable ? cudaVersion : null,
    memoryMiB: nvidiaAvailable ? Number.parseInt(memory, 10) : null,
  },
  ffmpeg: {
    available: ffmpeg.status === 0,
    nvencEncoders,
    usableNvencEncoders,
  },
  inference,
  selection: {
    videoEncoder: selectedVideoEncoder,
    mediaInferenceDevice: inference.cudaUsable ? "cuda" : "cpu",
  },
  fallbackReason: fallbackReasons.length > 0 ? fallbackReasons.join(" ") : null,
};
const outputPath = resolve(outputArg);
mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`${mode}: ${manifest.nvidia.name ?? "no NVIDIA GPU"}; video=${selectedVideoEncoder}; inference=${manifest.selection.mediaInferenceDevice}`);
