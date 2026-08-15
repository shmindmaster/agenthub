#!/usr/bin/env node
// Provider-agnostic narration (TTS) generation with per-segment regenerate-only-changed.
// Usage:
//   node generate-narration.mjs --script <path> --out <dir>
//     [--provider elevenlabs|openai] [--voice <id>] [--model <id>]
//     [--api-key-env <ENV_VAR_NAME>] [--force]
//
// Script file (JSON or this plugin's simple YAML-object-list shape) under a top-level `segments:`
// key, each with { id, text, voice? }. See skills/product-demo-studio-narration/SKILL.md.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readManifestList } from "./lib.mjs";

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
};
const force = args.includes("--force");
const scriptsDir = dirname(fileURLToPath(import.meta.url));
const elevenLabsOwnerCli = resolve(
  scriptsDir,
  "../../elevenlabs/scripts/elevenlabs_cli.py",
);

const scriptPath = flag("--script");
const outDir = flag("--out");
if (!scriptPath || !outDir) {
  console.error(
    "Usage: node generate-narration.mjs --script <path> --out <dir> " +
      "[--provider elevenlabs|openai] [--voice <id>] [--model <id>] [--api-key-env <VAR>] " +
      "[--voice-profile <path>] [--preset natural-warm|expressive|calm] [--no-context] [--force]",
  );
  process.exit(1);
}

// The prerecorded Voice Quality Standard -- see product-demo-studio-narration SKILL, "Voice quality
// standard". These are the DEFAULT PVC settings for prerecorded narration. They are deliberate: do
// NOT silently change them. optimize_streaming_latency is intentionally never sent (0 = highest
// quality) because aggressive latency optimization degrades prerecorded narration.
//
// speed was 0.92 until 2026-08-06: live-verified across a 6-episode ElevenLabs
// eleven_multilingual_v2 narration series (abacare) that any speed below 1.0 (ElevenLabs'
// documented neutral rate) reads as an artificially slowed, sluggish narrator regardless of
// per-line pacing elsewhere in the pipeline -- reset to 1.0. stability/style are untouched;
// only speed was independently proven wrong.
const VOICE_QUALITY_STANDARD = {
  // ElevenLabs-specific and therefore NOT seeded into the resolved profile: it
  // reaches generation as the elevenlabs provider's defaultModel. Seeding it
  // into the shared profile made it outrank every other provider's default, so
  // the local provider was handed "eleven_multilingual_v2" as an engine name.
  elevenLabsModel: "eleven_multilingual_v2",
  stability: 0.42,
  similarity_boost: 0.75,
  style: 0.0,
  speed: 1.0,
  use_speaker_boost: true,
  // ElevenLabs: "auto" enables normalization of numbers/dates/acronyms -- the standard's
  // "Text normalization: enabled". Set to "on" to force it, "off" only with a reason.
  apply_text_normalization: "auto",
};

// Named presets from the standard. Try these before touching style; only raise style to 0.05 then
// 0.10 after pacing and stability are already good and quality clearly improves.
// natural-warm/calm speeds reset to 1.0 alongside the standard above (2026-08-06) -- both were
// sub-1.0 slowdowns with the same proven defect. expressive is untouched: a deliberately slower,
// more deliberate pace is a plausible intentional choice for dramatic/expressive delivery, not
// the same accidental-slowdown bug.
const VOICE_PRESETS = {
  "natural-warm": { stability: 0.42, similarity_boost: 0.75, speed: 1.0, style: 0.0 },
  expressive: { stability: 0.35, similarity_boost: 0.72, speed: 0.9, style: 0.0 },
  calm: { stability: 0.5, similarity_boost: 0.78, speed: 1.0, style: 0.0 },
};

// Resolve the Local-AI control plane. Matches detect-media-acceleration.mjs:
// LOCAL_AI_ROOT wins, then the documented Windows default.
function localAiRoot() {
  return process.env.LOCAL_AI_ROOT ?? (process.platform === "win32" ? "D:\\Local-AI" : null);
}

function localAiControl() {
  const root = localAiRoot();
  if (!root) return null;
  const control = join(root, "ai.ps1");
  return existsSync(control) ? control : null;
}

const PROVIDERS = {
  // The owner's own voice is generated locally and never leaves the machine.
  // ai.ps1 is the single control plane for the Local-AI stack -- this shells out
  // to it rather than importing the engine directly, so engine changes (model
  // routing, identity gating, pronunciation) land here without touching this
  // file.
  local: {
    defaultApiKeyEnv: null, // local inference has no credential
    requiresApiKey: false,
    defaultModel: "qwen-clone",
    async generate({ text, voice, model }) {
      const control = localAiControl();
      if (!control) {
        throw new Error(
          `Local-AI control plane not found. Expected ai.ps1 under ${localAiRoot() ?? "(no root)"}; ` +
            "set LOCAL_AI_ROOT or pass --provider elevenlabs|openai.",
        );
      }
      // A voice profile id, not an API voice id. Profiles live under
      // data/artifacts/media/voice-corpus/voices/<id>/.
      const profile = voice ?? process.env.LOCAL_AI_VOICE;
      if (!profile) {
        throw new Error(
          "The local provider needs a voice profile id -- pass --voice <profile>, set a per-segment " +
            "\"voice\" field, set LOCAL_AI_VOICE, or put \"voiceId\" in the --voice-profile.",
        );
      }
      const tempRoot = mkdtempSync(join(tmpdir(), "agenthub-localai-"));
      const outputPath = join(tempRoot, "narration.wav");
      try {
        // Invoked with -Command and the call operator, NOT -File. ai.ps1 declares
        // [CmdletBinding()], which enables PowerShell's common parameters; under
        // -File the argument `--out` prefix-matches both -OutVariable and
        // -OutBuffer and the script dies with "the parameter name 'out' is
        // ambiguous" before it runs. The call operator does not bind that way.
        //
        // Values travel in environment variables rather than inline in the
        // command string. Narration text routinely contains quotes and
        // apostrophes; interpolating it into a PowerShell command line would
        // both break on them and make the caller responsible for escaping
        // arbitrary text into a shell. PowerShell expands $env: references in
        // argument position without re-tokenizing, so a value with spaces or
        // quotes arrives as exactly one argument.
        const command =
          `& '${control.replace(/'/g, "''")}' voice $env:AGENTHUB_LAI_MODEL ` +
          "--voice $env:AGENTHUB_LAI_VOICE --text $env:AGENTHUB_LAI_TEXT --out $env:AGENTHUB_LAI_OUT";
        const result = spawnSync(
          process.env.AGENTHUB_PWSH ?? "pwsh",
          ["-NoProfile", "-Command", command],
          {
            encoding: "utf8",
            maxBuffer: 8 * 1024 * 1024,
            env: {
              ...process.env,
              AGENTHUB_LAI_MODEL: model,
              AGENTHUB_LAI_VOICE: profile,
              AGENTHUB_LAI_TEXT: text,
              AGENTHUB_LAI_OUT: outputPath,
            },
          },
        );
        if (result.status !== 0 || !existsSync(outputPath)) {
          throw new Error(
            `Local-AI narration failed (${result.status ?? "launch error"}): ` +
              `${(result.stderr || result.error?.message || "no output").trim()}`,
          );
        }
        // WAV, not MP3: the local engines emit uncompressed audio and it stays
        // uncompressed through composition. Encoding here would add a lossy
        // generation for no benefit.
        return { buffer: readFileSync(outputPath), ext: "wav", voice: profile };
      } finally {
        rmSync(tempRoot, { recursive: true, force: true });
      }
    },
  },
  elevenlabs: {
    defaultApiKeyEnv: "ELEVENLABS_API_KEY",
    defaultModel: VOICE_QUALITY_STANDARD.elevenLabsModel,
    async generate({ text, voice, model, apiKey, settings, previousText, nextText }) {
      const voiceId = voice ?? process.env.ELEVENLABS_VOICE_ID;
      if (!voiceId) {
        throw new Error(
          "ElevenLabs requires a voice id -- pass --voice <id>, set a per-segment \"voice\" field, " +
            "set ELEVENLABS_VOICE_ID, or put \"voiceId\" in the --voice-profile.",
        );
      }
      if (!existsSync(elevenLabsOwnerCli)) {
        throw new Error(`Canonical elevenlabs CLI is missing: ${elevenLabsOwnerCli}`);
      }
      const tempRoot = mkdtempSync(join(tmpdir(), "agenthub-elevenlabs-"));
      const outputPath = join(tempRoot, "narration.mp3");
      try {
        const ownerArgs = [
          elevenLabsOwnerCli,
          "tts",
          "--text", text,
          "--output", outputPath,
          "--voice-id", voiceId,
          "--model-id", model,
          "--stability", String(settings.stability),
          "--similarity-boost", String(settings.similarity_boost),
          "--style", String(settings.style),
          "--speed", String(settings.speed),
          settings.use_speaker_boost ? "--use-speaker-boost" : "--no-use-speaker-boost",
          "--text-normalization", settings.apply_text_normalization,
          ...(previousText ? ["--previous-text", previousText] : []),
          ...(nextText ? ["--next-text", nextText] : []),
        ];
        const result = spawnSync(process.env.AGENTHUB_PYTHON ?? "python", ownerArgs, {
          encoding: "utf8",
          // The shared elevenlabs owner reads only its canonical variable. Map a caller's
          // approved custom --api-key-env value into the child process without putting the secret
          // on the command line or logging either value.
          env: { ...process.env, ELEVENLABS_API_KEY: apiKey },
          maxBuffer: 8 * 1024 * 1024,
        });
        if (result.status !== 0 || !existsSync(outputPath)) {
          throw new Error(
            `Canonical elevenlabs CLI failed (${result.status ?? "launch error"}): ` +
              `${(result.stderr || result.error?.message || "no output").trim()}`,
          );
        }
        return { buffer: readFileSync(outputPath), ext: "mp3", voice: voiceId };
      } finally {
        rmSync(tempRoot, { recursive: true, force: true });
      }
    },
  },
  openai: {
    defaultApiKeyEnv: "OPENAI_API_KEY",
    defaultModel: "gpt-4o-mini-tts",
    async generate({ text, voice, model, apiKey, settings }) {
      const voiceName = voice ?? "alloy";
      const res = await fetch("https://api.openai.com/v1/audio/speech", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        // OpenAI TTS has no stability/style/speaker-boost; speed is the one shared control.
        body: JSON.stringify({
          model,
          voice: voiceName,
          input: text,
          response_format: "mp3",
          speed: settings.speed ?? 1.0,
        }),
      });
      if (!res.ok) {
        throw new Error(`OpenAI TTS failed (${res.status}): ${await res.text()}`);
      }
      return { buffer: Buffer.from(await res.arrayBuffer()), ext: "mp3", voice: voiceName };
    },
  },
};

// Build the effective voice profile: standard defaults, overlaid by an immutable --voice-profile
// file (the cache-key input), then a named --preset. The full resolved profile is hashed into the
// per-segment cache key, so any settings change correctly re-generates instead of serving a stale
// take at the old voice.
function loadVoiceProfile() {
  const profilePath = flag("--voice-profile");
  const preset = flag("--preset");
  let profile = { ...VOICE_QUALITY_STANDARD };
  if (profilePath) {
    const disk = JSON.parse(readFileSync(profilePath, "utf8"));
    const settings = disk.settings ?? disk;
    profile = { ...profile, ...settings };
    if (disk.model) profile.model = disk.model;
    if (disk.voiceId) profile.voiceId = disk.voiceId;
  }
  if (preset) {
    if (!VOICE_PRESETS[preset]) {
      throw new Error(
        `Unknown --preset "${preset}". Known presets: ${Object.keys(VOICE_PRESETS).join(", ")}.`,
      );
    }
    profile = { ...profile, ...VOICE_PRESETS[preset] };
  }
  return profile;
}

function resolveProvider() {
  const explicit = flag("--provider");
  if (explicit) {
    if (!PROVIDERS[explicit]) {
      throw new Error(`Unknown --provider "${explicit}". Known providers: ${Object.keys(PROVIDERS).join(", ")}.`);
    }
    return explicit;
  }
  // Local first. The owner's voice is a local capability, and routing it to a
  // cloud provider both sends his speech off the machine and returns a voice
  // that is not his. Cloud providers remain the default for any other voice.
  //
  // This is also why local is not merely "another entry in the list": before
  // it existed, a machine with no cloud key could not run this script at all,
  // while the sibling SKILL.md instructed agents to use the local route.
  if (localAiControl()) return "local";

  const available = [
    process.env.ELEVENLABS_API_KEY ? "elevenlabs" : null,
    process.env.OPENAI_API_KEY ? "openai" : null,
  ].filter(Boolean);
  if (available.length === 1) return available[0];
  if (available.length > 1) {
    throw new Error(
      `Multiple narration providers are configured (${available.join(", ")}). ` +
        "Pass --provider explicitly so credential availability cannot silently change the approved voice profile.",
    );
  }
  throw new Error(
    "No narration provider available: the Local-AI control plane was not found and neither " +
      "ELEVENLABS_API_KEY nor OPENAI_API_KEY is set. Set LOCAL_AI_ROOT to a Local-AI install, " +
      "set one of those env vars, or pass --provider plus --api-key-env <VAR>.",
  );
}

function hashSegment({ text, voice, provider, model, settings, previousText, nextText }) {
  return createHash("sha256")
    .update(JSON.stringify({ text, voice, provider, model, settings, previousText, nextText }))
    .digest("hex");
}

function sha256File(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

async function main() {
  const provider = resolveProvider();
  const providerImpl = PROVIDERS[provider];
  // Local inference has no credential, so the key check is per-provider rather
  // than unconditional.
  const apiKeyEnv = flag("--api-key-env") ?? providerImpl.defaultApiKeyEnv;
  const apiKey = apiKeyEnv ? process.env[apiKeyEnv] : undefined;
  if (providerImpl.requiresApiKey !== false && !apiKey) {
    throw new Error(`Provider "${provider}" needs an API key in $${apiKeyEnv}, but it is not set.`);
  }

  const profile = loadVoiceProfile();
  const model = flag("--model") ?? profile.model ?? providerImpl.defaultModel;
  const voiceOverride = flag("--voice") ?? profile.voiceId;
  // Continuity context is an ElevenLabs feature; --no-context disables it.
  const useContext = provider === "elevenlabs" && !args.includes("--no-context");
  // The settings block hashed and sent per segment (voiceId lives outside settings, in `voice`).
  const settings = {
    stability: profile.stability,
    similarity_boost: profile.similarity_boost,
    style: profile.style,
    speed: profile.speed,
    use_speaker_boost: profile.use_speaker_boost,
    apply_text_normalization: profile.apply_text_normalization,
  };

  const segments = readManifestList(scriptPath, "segments");
  if (!segments || segments.length === 0) {
    throw new Error(`No segments found in ${scriptPath} (expected a top-level "segments:" list).`);
  }

  mkdirSync(outDir, { recursive: true });

  const manifestPath = join(outDir, "manifest.json");
  const previousManifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, "utf8")) : { segments: [] };
  const previousById = new Map(previousManifest.segments.map((s) => [s.id, s]));

  const results = [];
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    const voice = voiceOverride ?? segment.voice ?? null;
    const previousText = useContext ? segments[i - 1]?.text ?? null : null;
    const nextText = useContext ? segments[i + 1]?.text ?? null : null;
    const hash = hashSegment({ text: segment.text, voice, provider, model, settings, previousText, nextText });
    const previous = previousById.get(segment.id);

    // Check the extension the previous run actually produced, not a hardcoded
    // ".mp3". The local provider emits .wav, so a fixed .mp3 probe never finds
    // the existing file and re-renders every segment on every run, defeating
    // regenerate-only-changed entirely.
    const previousAudioPath = previous?.audioPath ?? join(outDir, `${segment.id}.mp3`);
    if (!force && previous?.hash === hash && existsSync(previousAudioPath)) {
      console.log(`[skip] ${segment.id} — unchanged`);
      results.push(previous);
      continue;
    }

    console.log(`[generate] ${segment.id} — ${provider}/${model}`);
    const { buffer, ext, voice: resolvedVoice } = await providerImpl.generate({
      text: segment.text,
      voice,
      model,
      apiKey,
      settings,
      previousText,
      nextText,
    });
    const audioPath = join(outDir, `${segment.id}.${ext}`);
    writeFileSync(audioPath, buffer);

    const record = {
      id: segment.id,
      text: segment.text,
      provider,
      model,
      voice: resolvedVoice,
      settings,
      contextUsed: Boolean(previousText || nextText),
      hash,
      audioPath,
      checksum: sha256File(buffer),
      // Duration is intentionally not computed here -- measure it from the actual audio file at
      // composition time via the selected external finisher,
      // never hand-estimated from word count or duplicated as a second source of truth.
      durationSeconds: null,
    };
    results.push(record);
    writeFileSync(join(outDir, `${segment.id}.json`), JSON.stringify(record, null, 2));
  }

  // voiceProfile is recorded at the top level so the delivery package manifest can cite the exact
  // voice+model profile the narration was produced with (Voice Quality Standard + delivery package).
  writeFileSync(
    manifestPath,
    JSON.stringify({ provider, model, voiceProfile: { ...settings, voiceId: voiceOverride ?? null }, segments: results }, null, 2),
  );
  console.log(`\nWrote ${results.length} segment(s) to ${outDir}`);
  console.log(`Manifest: ${manifestPath}`);
}

main().catch((err) => {
  console.error(`\n${err.message}`);
  process.exit(1);
});
