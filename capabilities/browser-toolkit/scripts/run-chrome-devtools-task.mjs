import { mkdir, readFile, writeFile } from "node:fs/promises";
import { isAbsolute, relative, resolve } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

function option(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

const planPath = option("--plan");
const outputDir = resolve(option("--output") || "../../reports/browser-toolkit/task");
if (!planPath) throw new Error("Usage: node scripts/run-chrome-devtools-task.mjs --plan <plan.json> [--output <directory>]");

const plan = JSON.parse(await readFile(resolve(planPath), "utf8"));
if (!Array.isArray(plan.steps) || plan.steps.length === 0) throw new Error("Plan must contain at least one step.");
await mkdir(outputDir, { recursive: true });

const browserUrl = plan.browserUrl || "http://127.0.0.1:9333";
const transport = new StdioClientTransport({
  command: "npx",
  cwd: outputDir,
  args: [
    "-y", "chrome-devtools-mcp@1.6.0",
    `--browser-url=${browserUrl}`,
    "--no-usage-statistics",
    "--no-performance-crux",
    "--redact-network-headers"
  ],
  stderr: "pipe"
});
const client = new Client({ name: "browser-toolkit-task", version: "0.2.2" });
const variables = {};
const report = { browserUrl, startedAt: new Date().toISOString(), status: "running", steps: [] };

function textFrom(result) {
  return (result.content || []).filter(item => item.type === "text").map(item => item.text).join("\n");
}

function redact(value) {
  return value
    .replace(/(authorization|cookie|set-cookie|x-api-key)(["']?\s*[:=]\s*)[^\s,;]+/gi, "$1$2<redacted>")
    .replace(/Bearer\s+[A-Za-z0-9._~-]+/gi, "Bearer <redacted>");
}

function substitute(value) {
  if (typeof value === "string") {
    return value.replace(/\{\{([A-Za-z][A-Za-z0-9_-]*)\}\}/g, (_, name) => {
      if (!(name in variables)) throw new Error(`Unknown captured variable: ${name}`);
      return variables[name];
    });
  }
  if (Array.isArray(value)) return value.map(substitute);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, nested]) => [key, substitute(nested)]));
  }
  return value;
}

function evidencePath(name) {
  if (isAbsolute(name)) throw new Error(`saveAs must be relative to the output directory: ${name}`);
  const candidate = resolve(outputDir, name);
  if (relative(outputDir, candidate).startsWith("..")) throw new Error(`saveAs escapes the output directory: ${name}`);
  return candidate;
}

try {
  await client.connect(transport);
  const advertised = new Set((await client.listTools()).tools.map(tool => tool.name));
  for (const [index, step] of plan.steps.entries()) {
    if (!step || typeof step.tool !== "string" || !advertised.has(step.tool)) {
      throw new Error(`Step ${index + 1} references an unavailable MCP tool: ${step?.tool}`);
    }
    const args = substitute(step.arguments || {});
    const result = await client.callTool({ name: step.tool, arguments: args });
    const output = redact(textFrom(result));
    if (result.isError) throw new Error(`Step ${index + 1} (${step.tool}) failed: ${output}`);
    for (const capture of step.captures || []) {
      const match = output.match(new RegExp(capture.pattern, capture.flags || "m"));
      if (!match?.[1]) throw new Error(`Step ${index + 1} did not produce capture ${capture.name}.`);
      variables[capture.name] = match[1];
    }
    if (step.saveAs) {
      const path = evidencePath(step.saveAs);
      await mkdir(resolve(path, ".."), { recursive: true });
      await writeFile(path, output);
    }
    report.steps.push({ id: step.id || `step-${index + 1}`, tool: step.tool, status: "passed", saveAs: step.saveAs || null });
  }
  report.status = "passed";
} catch (error) {
  report.status = "failed";
  report.error = redact(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  report.completedAt = new Date().toISOString();
  await writeFile(resolve(outputDir, "task-report.json"), JSON.stringify(report, null, 2));
  await client.close().catch(() => {});
}

if (report.status === "passed") console.log(`Chrome DevTools task passed. Evidence: ${outputDir}`);
