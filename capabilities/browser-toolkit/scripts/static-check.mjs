import { readFile, readdir } from "node:fs/promises";
import { join, relative } from "node:path";

const root = new URL("../", import.meta.url);
const required = [
  "README.md",
  "package.json",
  "package-lock.json",
  "versions.json",
  "mcp/chrome-devtools.json",
  "skills/browser-evidence/SKILL.md",
  "skills/browser-debugging/SKILL.md",
  "scripts/configure-agents.ps1",
  "scripts/merge-hermes-config.py",
  "scripts/launch-qa-chrome.ps1",
  "scripts/launch-agent-chrome.ps1",
  "scripts/validate-concurrency.ps1",
  "scripts/validate.ps1",
  "scripts/mcp-smoke.mjs",
  "scripts/run-chrome-devtools-task.mjs",
  "scripts/redact-sensitive-text.mjs",
  "fixtures/task-plan.example.json",
  "tests/redaction.test.mjs",
  "fixtures/browser-smoke/index.html"
];

async function filesUnder(url, prefix = "") {
  const entries = await readdir(url, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    if (entry.name === "node_modules") continue;
    const rel = join(prefix, entry.name).replaceAll("\\", "/");
    if (entry.isDirectory()) files.push(...await filesUnder(new URL(`${entry.name}/`, url), rel));
    else files.push(rel);
  }
  return files;
}

const failures = [];
const all = await filesUnder(root);
const upstreamFloatingVersionFiles = new Set([
  "adapters/claude-code/mcp.fragment.json",
  "adapters/cursor/mcp.json",
  "adapters/opencode/opencode.fragment.json",
  "adapters/qwen-code/settings.fragment.json",
  "docs/architecture.md",
  "mcp/chrome-devtools-autoconnect.example.json",
  "mcp/chrome-devtools.json",
  "scripts/configure-agents.ps1",
  "scripts/merge-hermes-config.py",
  "scripts/validate.ps1",
  "versions.json"
]);
for (const file of required) {
  if (!all.includes(file)) failures.push(`missing required file: ${file}`);
}

for (const file of all) {
  if (!/\.(json|md|mjs|ps1|py|yaml|yml|csv)$/.test(file)) continue;
  const text = await readFile(new URL(file.replaceAll("\\", "/"), root), "utf8");
  if (file.endsWith(".json")) {
    try { JSON.parse(text); } catch (error) { failures.push(`${file}: invalid JSON: ${error.message}`); }
  }
  if (file.endsWith("SKILL.md") && !/^---\r?\nname: [a-z0-9-]+\r?\ndescription: .+\r?\n---/s.test(text)) {
    failures.push(`${file}: missing valid skill frontmatter`);
  }
  if (/sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{16,}|api[_-]?key["']?\s*[:=]\s*["'][^<{][^"']{12,}/i.test(text)) {
    failures.push(`${file}: possible embedded credential`);
  }
  if (
    !["README.md", "scripts/static-check.mjs"].includes(file) &&
    !upstreamFloatingVersionFiles.has(file) &&
    /chrome-devtools-mcp@latest|vite-plugin-devtools-json@latest/.test(text)
  ) {
    failures.push(`${file}: floating package version`);
  }
}

const configureAgents = await readFile(new URL("scripts/configure-agents.ps1", root), "utf8");
if (!/\[string\]\$BrowserMode = 'TaskScoped'/.test(configureAgents)) {
  failures.push("configure-agents.ps1: TaskScoped must be the default browser mode");
}
if (!/Remove-BrowserMcpRegistration/.test(configureAgents)) {
  failures.push("configure-agents.ps1: task-scoped mode must remove persistent Chrome registrations");
}
const mergeHermes = await readFile(new URL("scripts/merge-hermes-config.py", root), "utf8");
if (!/--enable-chrome/.test(mergeHermes) || !/mcp_servers\.pop\("chrome-devtools", None\)/.test(mergeHermes)) {
  failures.push("merge-hermes-config.py: Chrome must be opt-in and removed by default");
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log(`Static checks passed for ${all.length} toolkit files.`);
