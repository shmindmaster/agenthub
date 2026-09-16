#!/usr/bin/env node
// Creates the smallest supported media-studio work area. The product
// repository is read-only input; traces, narration, caches, evidence, and video
// outputs stay in this external workspace.
//
// Usage: node scaffold-video-workspace.mjs --repo <path> [--product <Name>]
//        [--workspace <path>] [--dry-run] [--install]
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { basename, isAbsolute, join, relative, resolve } from "node:path";

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const dryRun = args.includes("--dry-run");
const autoInstall = args.includes("--install");
const repoPath = flag("--repo");

if (!repoPath || !existsSync(repoPath)) {
  console.error("Usage: node scaffold-video-workspace.mjs --repo <path> [--product <Name>] [--workspace <path>] [--dry-run] [--install]");
  process.exit(1);
}

const repoRoot = resolve(repoPath);
const productName = flag("--product") ?? basename(repoRoot);
const productSlug = productName.replace(/[^A-Za-z0-9]/g, "");
const defaultWorkRoot = process.env.AGENTHUB_PRODUCT_VIDEO_WORK_ROOT
  ?? join(process.env.LOCALAPPDATA ?? tmpdir(), "AgentHub", "media-studio");
const workspaceRoot = resolve(flag("--workspace") ?? join(defaultWorkRoot, productSlug));
const repoRelativeWorkspace = relative(repoRoot, workspaceRoot);

if (!repoRelativeWorkspace || (!repoRelativeWorkspace.startsWith("..") && !isAbsolute(repoRelativeWorkspace))) {
  console.error(`Refusing to scaffold inside the product repository: ${workspaceRoot}`);
  console.error("Use an external --workspace path or the default AgentHub local work root.");
  process.exit(2);
}

function write(path, content) {
  if (existsSync(path)) {
    console.log(`skip (exists): ${path}`);
    return;
  }
  console.log(`${dryRun ? "[dry-run] would write" : "write"}: ${path}`);
  if (dryRun) return;
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content);
}

write(
  join(workspaceRoot, "package.json"),
  `${JSON.stringify({
    name: `${productSlug.toLowerCase()}-demo-production`,
    private: true,
    type: "module",
    dependencies: {
      "@playwright/cli": "0.1.17",
      "@playwright/test": "1.62.1",
      "openai": "7.3.0",
      "playwright-recast": "0.19.2",
    },
    scripts: { render: "node render.mjs" },
    engines: { node: ">=20" },
  }, null, 2)}\n`,
);

write(
  join(workspaceRoot, "render.mjs"),
  `import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, unlink } from "node:fs/promises";
import { dirname, isAbsolute, parse, posix } from "node:path";
import { ElevenLabsProvider, OpenAIProvider, Recast } from "playwright-recast";

const argv = process.argv.slice(2);
const burnCaptions = argv.includes("--burn-captions");
const positional = argv.filter((value) => value !== "--burn-captions");
const input = positional[0] ?? "traces";
const output = positional[1] ?? "output/${productSlug}-demo.mp4";
const subtitles = positional[2];

for (const [name, value] of Object.entries({ input, output, subtitles })) {
  if (value && isAbsolute(value)) throw new Error(\`\${name} must be relative to the external workspace.\`);
}
if (existsSync(output)) throw new Error(\`Refusing to overwrite existing output: \${output}\`);
await mkdir(dirname(output), { recursive: true });

let pipeline = Recast.from(input)
  .parse()
  .speedUp({ duringIdle: 4, duringNetworkWait: 2, duringNavigation: 2, duringUserAction: 1 });

if (subtitles) {
  pipeline = pipeline.subtitlesFromSrt(subtitles);
  const provider = process.env.RECAST_TTS_PROVIDER
    ?? (process.env.OPENAI_API_KEY ? "openai" : process.env.ELEVENLABS_API_KEY ? "elevenlabs" : "none");
  if (provider === "openai") {
    pipeline = pipeline.voiceover(OpenAIProvider({
      voice: process.env.RECAST_TTS_VOICE ?? "nova",
      instructions: "Warm, concise, professional product demo narration.",
    }), { normalize: true });
  } else if (provider === "elevenlabs") {
    pipeline = pipeline.voiceover(ElevenLabsProvider({ voice: process.env.RECAST_TTS_VOICE }), { normalize: true });
  }
}

pipeline = pipeline
  .cursorOverlay({ approachMs: 500 })
  .clickEffect({ duration: 350, opacity: 0.5 })
  .autoZoom({ inputLevel: 1.4, clickLevel: 1.25, centerBias: 0.3 });

const parsed = parse(output);
const softOutput = burnCaptions
  ? posix.join(parsed.dir.replaceAll("\\\\", "/"), \`\${parsed.name}.soft\${parsed.ext}\`)
  : output;
await pipeline.render({
  format: "mp4",
  resolution: "1080p",
  fps: 60,
  burnSubtitles: false,
  embedSubtitles: Boolean(subtitles),
}).toFile(softOutput);

if (burnCaptions && subtitles) {
  const extracted = posix.join(parsed.dir.replaceAll("\\\\", "/"), \`\${parsed.name}.captions.srt\`);
  execFileSync("ffmpeg", ["-y", "-v", "error", "-i", softOutput, "-map", "0:s:0", extracted], { stdio: "inherit" });
  const filter = \`subtitles=filename='\${extracted}':charenc=UTF-8:force_style='FontName=Segoe UI,FontSize=20,PrimaryColour=&H00FFFFFF,OutlineColour=&H90000000,BorderStyle=3,Outline=1,Alignment=2,MarginV=48'\`;
  execFileSync("ffmpeg", ["-y", "-v", "error", "-i", softOutput, "-vf", filter, "-map", "0:v:0", "-map", "0:a?", "-map", "0:s?", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-c:a", "copy", "-c:s", "mov_text", "-movflags", "+faststart", output], { stdio: "inherit" });
  await Promise.all([unlink(softOutput), unlink(extracted)]);
}

console.log(output);
`,
);

write(
  join(workspaceRoot, "README.md"),
  `# ${productName} demo production\n\nThis is an external, disposable production workspace. The product repository remains read-only.\n\n## Capture\n\nUse \`pnpm exec playwright-cli\` for agent-operated sessions. It owns mouse/keyboard interaction,\ntrace capture, WebM recording, chapters, and optional action annotations. Use \`@playwright/test\`\nonly when the same capture must be deterministically rerun. Store any episode script here, never in\nthe product repository.\n\n## Inputs and outputs\n\n- \`traces/\`: Playwright \`trace.zip\` plus its sibling high-resolution WebM. The WebM is the video\n  source; trace screenshots are metadata fallback only.\n- \`narration/\`: optional SRT and audio sources.\n- \`output/\`: disposable render candidates.\n- \`evidence/\`: Product Demo Studio validation and review evidence.\n\nRun \`pnpm render -- traces output/${productSlug}-demo.mp4 narration/demo.srt --burn-captions\`. The\nthin adapter uses Recast for cursor/click/animated zoom and voice timing, keeps paths relative for\nWindows compatibility, embeds captions first, and uses one FFmpeg pass to burn the synchronized\ncaption track when requested. Install \`@elevenlabs/elevenlabs-js\` here only when ElevenLabs is\nselected; OpenAI is the minimal installed provider. After the release gate passes, package the\naccepted candidate into the product's mapped OneDrive review root. Do not copy this workspace into\nthe product repository.\n`,
);

for (const directory of ["traces", "narration", "output", "evidence"]) {
  write(join(workspaceRoot, directory, ".gitkeep"), "");
}

if (dryRun) {
  console.log(`\nDry run complete. Product repo remains untouched; external workspace: ${workspaceRoot}`);
} else if (autoInstall) {
  console.log(`\nExternal scaffold complete for ${productName}. Running pnpm install in ${workspaceRoot} ...`);
  const result = spawnSync("pnpm", ["install"], {
    cwd: workspaceRoot,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
  if (result.error || result.status !== 0) process.exit(result.status ?? 1);
} else {
  console.log(`\nExternal scaffold complete for ${productName} at ${workspaceRoot}. Product repo was not modified.`);
  console.log("Next: run pnpm install in the external workspace (or re-run with --install).\n");
}
