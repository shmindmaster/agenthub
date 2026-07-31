#!/usr/bin/env node
// Idempotently scaffolds a SubOps-style `apps/videos` Remotion workspace plus a
// `<Product>_Video_Program/` folder tree in a target repo that has no video
// infrastructure yet. Refuses to run against a repo that already has one of the
// three known conventions -- extend those in place instead (see
// product-demo-studio's router skill).
//
// Usage: node scaffold-video-workspace.mjs --repo <path> --product <Name> [--dry-run] [--install]
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { basename, join } from "node:path";
import { detectVideoConvention } from "./lib.mjs";

const args = process.argv.slice(2);
function flag(name) {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}
const dryRun = args.includes("--dry-run");
const autoInstall = args.includes("--install");
const repoPath = flag("--repo");
if (!repoPath || !existsSync(repoPath)) {
  console.error("Usage: node scaffold-video-workspace.mjs --repo <path> --product <Name> [--dry-run] [--install]");
  console.error(`Repo path missing or does not exist: ${repoPath}`);
  process.exit(1);
}
const productName = flag("--product") ?? basename(repoPath);
const productSlug = productName.replace(/[^A-Za-z0-9]/g, "");

const existing = detectVideoConvention(repoPath);
if (existing.convention !== "none") {
  console.error(
    `Refusing to scaffold: ${repoPath} already has video infrastructure (${existing.convention}` +
      `${existing.remotionDir ? ` at ${existing.remotionDir}` : ""}). Extend it in place instead.`,
  );
  process.exit(1);
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

const videosDir = join(repoPath, "apps", "videos");
const programDir = join(repoPath, `${productSlug}_Video_Program`);
const hasRootWorkspace = existsSync(join(repoPath, "pnpm-workspace.yaml"));

// --- apps/videos ---

write(
  join(videosDir, "package.json"),
  JSON.stringify(
    {
      name: `${productSlug.toLowerCase()}-videos`,
      version: "1.0.0",
      private: true,
      type: "module",
      scripts: {
        studio: "remotion studio src/index.tsx",
        typecheck: "tsc --noEmit",
        render: "remotion render src/index.tsx",
        "render:all": "tsx scripts/render-all.ts",
        "render:priority": "tsx scripts/render-priority.ts",
        "render:still": "tsx scripts/render-stills.ts",
        still: "remotion still src/index.tsx",
      },
      dependencies: {
        "@remotion/cli": "4.0.484",
        "@remotion/media": "4.0.484",
        react: "^19.2.6",
        "react-dom": "^19.2.6",
        remotion: "4.0.484",
        zod: "^4.3.6",
      },
      devDependencies: {
        "@types/node": "^24.12.4",
        "@types/react": "^19.2.6",
        "@types/react-dom": "^19.2.3",
        tsx: "^4.21.0",
        typescript: "^6.0.3",
      },
      // No pnpm engine pin: the portfolio's actual pnpm versions vary per repo
      // (observed 10.30.3 through 11.11.0) and pnpm enforces engines.pnpm as a
      // hard error, unlike Node's soft warning -- pinning one version here would
      // just be false friction copied from whichever repo was scaffolded first.
      engines: { node: ">=24.16.0" },
    },
    null,
    2,
  ) + "\n",
);

write(
  join(videosDir, "tsconfig.json"),
  JSON.stringify(
    {
      compilerOptions: {
        target: "ES2022",
        module: "ESNext",
        moduleResolution: "Bundler",
        jsx: "react-jsx",
        strict: true,
        esModuleInterop: true,
        skipLibCheck: true,
        noEmit: true,
      },
      include: ["src", "scripts"],
    },
    null,
    2,
  ) + "\n",
);

write(
  join(videosDir, "src", "content.ts"),
  `export const FPS = 30;

export const VIDEO_FORMATS = [
  { id: "wide", width: 1920, height: 1080, label: "16:9" },
  { id: "vertical", width: 1080, height: 1920, label: "9:16" },
  { id: "square", width: 1080, height: 1080, label: "1:1" },
] as const;

export type VideoFormat = (typeof VIDEO_FORMATS)[number];

export type Audience =
  | "Hero"
  | "Pillar"
  | "Persona"
  | "Training"
  | "Trust"
  | "Marketing"
  | "Sales";

export type VideoScene = {
  durationSeconds: number;
  eyebrow: string;
  title: string;
  caption: string;
  motif: string;
  asset?: string;
};

export type ProductVideo = {
  id: string;
  audience: Audience;
  title: string;
  subtitle: string;
  durationSeconds: number;
  durationInFrames: number;
  cta: string;
  scenes: VideoScene[];
};

type ProductVideoInput = Omit<ProductVideo, "durationInFrames">;

const makeVideo = (video: ProductVideoInput): ProductVideo => ({
  ...video,
  durationInFrames: video.durationSeconds * FPS,
});

// Add videos with makeVideo({ ... }) -- see product-demo-studio-render's SKILL.md
// for the schema, and new-video-catalog-entry.mjs to append entries safely.
export const videos = [] as ProductVideo[];

export const getVideo = (id: string): ProductVideo => {
  const video = videos.find((candidate) => candidate.id === id);
  if (!video) {
    throw new Error(\`Unknown ${productName} video: \${id}\`);
  }
  return video;
};
`,
);

write(
  join(videosDir, "src", "Video.tsx"),
  `import { AbsoluteFill, Easing, Sequence, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import type { ProductVideo, VideoScene } from "./content";

const Scene = ({ scene }: { scene: VideoScene }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = interpolate(frame, [0, Math.min(fps / 2, scene.durationSeconds * fps)], [0, 1], {
    extrapolateRight: "clamp",
    extrapolateLeft: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  return (
    <AbsoluteFill
      style={{ opacity, backgroundColor: "#0b0f19", color: "white", padding: 80, justifyContent: "center" }}
      name={\`Scene: \${scene.title}\`}
    >
      <div style={{ fontSize: 28, opacity: 0.7, marginBottom: 16 }}>{scene.eyebrow}</div>
      <div style={{ fontSize: 64, fontWeight: 600, marginBottom: 24 }}>{scene.title}</div>
      <div style={{ fontSize: 32, opacity: 0.85, maxWidth: "70%" }}>{scene.caption}</div>
    </AbsoluteFill>
  );
};

// Starter composition: renders each scene in its catalog-defined order and duration.
// Replace with per-video compositions as scenes grow motif-specific visuals -- see
// product-demo-studio-remotion's SKILL.md.
export const ProductVideoComposition = ({ video }: { video: ProductVideo }) => {
  const { fps } = useVideoConfig();
  let frameCursor = 0;

  return (
    <AbsoluteFill>
      {video.scenes.map((scene, index) => {
        const from = frameCursor;
        frameCursor += Math.round(scene.durationSeconds * fps);
        return (
          <Sequence key={index} from={from} durationInFrames={Math.round(scene.durationSeconds * fps)}>
            <Scene scene={scene} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
`,
);

write(
  join(videosDir, "src", "Root.tsx"),
  `import { Composition } from "remotion";
import { VIDEO_FORMATS, videos } from "./content";
import { ProductVideoComposition } from "./Video";

export const RemotionRoot = () => {
  return (
    <>
      {videos.map((video) =>
        VIDEO_FORMATS.map((format) => (
          <Composition
            key={\`\${video.id}-\${format.id}\`}
            id={\`\${video.id}-\${format.id}\`}
            component={ProductVideoComposition}
            durationInFrames={video.durationInFrames}
            fps={30}
            width={format.width}
            height={format.height}
            defaultProps={{ video }}
          />
        )),
      )}
    </>
  );
};
`,
);

write(
  join(videosDir, "src", "index.tsx"),
  `import { registerRoot } from "remotion";
import { RemotionRoot } from "./Root";

registerRoot(RemotionRoot);
`,
);

write(
  join(videosDir, "scripts", "render-pool.ts"),
  `// Shared concurrency-limited render pool -- runs multiple \`remotion render\`
// processes in parallel (capped to avoid overwhelming the machine) instead of
// one at a time. Used by render-all.ts and render-priority.ts.
import { spawn } from "node:child_process";
import { cpus } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const packageRoot = dirname(fileURLToPath(new URL("../package.json", import.meta.url)));
export const remotionCli = join(packageRoot, "node_modules", "@remotion", "cli", "remotion-cli.js");
export const concurrency = Math.max(1, Math.min(4, cpus().length - 1));

export type RenderJob = { compositionId: string; output: string };

function renderOne(job: RenderJob): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [remotionCli, "render", "src/index.tsx", job.compositionId, job.output, "--overwrite"],
      { cwd: packageRoot, stdio: "inherit" },
    );
    child.on("error", reject);
    child.on("exit", (code) =>
      code === 0 ? resolve() : reject(new Error(\`\${job.compositionId} exited with code \${code}\`)),
    );
  });
}

export async function runRenderPool(jobs: RenderJob[]): Promise<void> {
  let index = 0;
  let failed = false;
  async function worker() {
    while (index < jobs.length) {
      const job = jobs[index++];
      try {
        await renderOne(job);
      } catch (err) {
        failed = true;
        console.error(err);
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, jobs.length) }, worker));
  if (failed) process.exit(1);
}
`,
);

write(
  join(videosDir, "scripts", "render-all.ts"),
  `import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { VIDEO_FORMATS, videos } from "../src/content";
import { packageRoot, runRenderPool } from "./render-pool";

const outDir = join(packageRoot, "out");
mkdirSync(outDir, { recursive: true });

const jobs = videos.flatMap((video) =>
  VIDEO_FORMATS.map((format) => ({
    compositionId: \`\${video.id}-\${format.id}\`,
    output: join(outDir, \`\${video.id}-\${format.id}.mp4\`),
  })),
);

runRenderPool(jobs);
`,
);

write(
  join(videosDir, "scripts", "render-priority.ts"),
  `// Renders only videos marked Hero/Pillar -- adjust the filter as the catalog grows.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { VIDEO_FORMATS, videos } from "../src/content";
import { packageRoot, runRenderPool } from "./render-pool";

const outDir = join(packageRoot, "out");
mkdirSync(outDir, { recursive: true });

const priority = videos.filter((v) => v.audience === "Hero" || v.audience === "Pillar");
const jobs = priority.flatMap((video) =>
  VIDEO_FORMATS.map((format) => ({
    compositionId: \`\${video.id}-\${format.id}\`,
    output: join(outDir, \`\${video.id}-\${format.id}.mp4\`),
  })),
);

runRenderPool(jobs);
`,
);

write(
  join(videosDir, "scripts", "render-stills.ts"),
  `// Renders a single still frame per video for a quick layout/timing sanity check.
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { VIDEO_FORMATS, videos } from "../src/content";

const packageRoot = dirname(fileURLToPath(new URL("../package.json", import.meta.url)));
const remotionCli = join(packageRoot, "node_modules", "@remotion", "cli", "remotion-cli.js");

for (const video of videos) {
  const compositionId = \`\${video.id}-\${VIDEO_FORMATS[0].id}\`;
  const output = join(packageRoot, "out", "stills", \`\${compositionId}.png\`);
  spawnSync(
    process.execPath,
    [remotionCli, "still", "src/index.tsx", compositionId, output, "--frame=30", "--overwrite"],
    { cwd: packageRoot, stdio: "inherit" },
  );
}
`,
);

write(join(videosDir, "public", ".gitkeep"), "");

// Standalone workspace (no repo-root pnpm-workspace.yaml, e.g. Sabhi's frontend/+backend/
// layout with no apps/* monorepo root) needs its own build-script allowlist, or `pnpm install`
// fails closed on esbuild's native postinstall script (pnpm's supply-chain build-script gate).
// Repos that already have a root workspace file inherit that root's own allowlist instead --
// don't write a second, conflicting workspace root inside one of its packages.
if (!hasRootWorkspace) {
  write(join(videosDir, "pnpm-workspace.yaml"), "allowBuilds:\n  esbuild: true\n");
}

// --- <Product>_Video_Program folder tree ---

write(
  join(programDir, "00_Brief", "product-sensitivity-brief.md"),
  `# ${productName} sensitivity brief

Fill this in before capturing or scripting any video for ${productName}:

- What must never be shown on screen (real customer/patient data, specific figures, third-party
  logos, anything not yet publicly announced)?
- What claims are NOT yet substantiated (compliance status, accuracy numbers, customer counts)
  and must not appear in captions, voiceover, or on-screen copy?
- Which deterministic redaction and claim checks must pass before final presentation?
`,
);

for (const folder of [
  "01_QA_Evidence",
  "04_Training_Materials",
  "05_Product_Videos",
  "06_Marketing_Assets",
  "07_Sales_Outreach",
  "09_Final_Reports",
]) {
  write(join(programDir, folder, ".gitkeep"), "");
}

write(
  join(programDir, "README.md"),
  `# ${productName} Video Program

Production workspace for ${productName} demo, training, trust, and marketing videos.

This workspace is intentionally outside \`apps/\` for the Remotion project itself only in the
sense that final packaged outputs live here -- the actual Remotion source lives at
\`apps/videos/\`, matching the SubOps pattern.

## Directory map

- \`00_Brief/\` - per-product guardrails: what not to show, what claims are not yet substantiated.
- \`01_QA_Evidence/\` - trust, access-control, and data-handling video outputs.
- \`04_Training_Materials/\` - workflow walkthroughs.
- \`05_Product_Videos/\` - flagship and pillar product masters.
- \`06_Marketing_Assets/\` - social cuts, thumbnails, key art.
- \`07_Sales_Outreach/\` - design-partner and investor-oriented cuts.
- \`09_Final_Reports/\` - final QA reports, redaction logs, release notes.

## Before any output here counts as accepted

Every asset needs a release-evidence manifest (see product-demo-studio-render's SKILL.md and
check-evidence-gate.mjs) that binds the exact candidate, PASS arbiter decision, and PASS terminal
verification before it moves from a scratch render into one of the folders above.
`,
);

if (dryRun) {
  console.log("\nDry run complete. Re-run without --dry-run to write these files.");
} else if (autoInstall) {
  console.log(`\nScaffold complete for ${productName}. Running pnpm install in ${videosDir} ...`);
  const result = spawnSync("pnpm", ["install"], { cwd: videosDir, stdio: "inherit", shell: process.platform === "win32" });
  if (result.error || result.status !== 0) {
    console.error("pnpm install failed -- run it manually in apps/videos.");
    process.exit(result.status ?? 1);
  }
} else {
  console.log(`\nScaffold complete for ${productName}. Next: cd into apps/videos and run pnpm install (or re-run with --install).`);
}
