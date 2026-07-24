import { access, copyFile, mkdir, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const browserUrl = process.env.BROWSER_TOOLKIT_CDP_URL || "http://127.0.0.1:9333";
const targetUrl = process.env.BROWSER_TOOLKIT_BASE_URL || "http://127.0.0.1:41731";
const outputDir = resolve(process.env.BROWSER_TOOLKIT_OUTPUT_DIR || "../../reports/browser-toolkit/manual");
await mkdir(outputDir, { recursive: true });

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
const client = new Client({ name: "browser-toolkit-smoke", version: "0.1.0" });
const evidence = { targetUrl, browserUrl, startedAt: new Date().toISOString(), checks: {}, tools: [] };
let temporaryScreenshotPath;

function textual(result) {
  return (result.content || []).filter(item => item.type === "text").map(item => item.text).join("\n");
}
function uidFor(snapshot, role, name) {
  for (const line of snapshot.split(/\r?\n/)) {
    const match = line.match(/\buid=([^\s]+)\s+([^\s]+)/);
    if (!match || match[2].toLowerCase() !== role.toLowerCase()) continue;
    if (line.toLowerCase().includes(`"${name.toLowerCase()}"`)) return match[1];
  }
  throw new Error(`Could not locate ${role} named "${name}" in snapshot.`);
}
async function call(name, args = {}) {
  if (!evidence.tools.includes(name)) throw new Error(`MCP tool not advertised: ${name}`);
  evidence.currentStage = name;
  const result = await client.callTool({ name, arguments: args });
  if (result.isError) throw new Error(`${name} failed: ${textual(result)}`);
  return result;
}
function safeText(value) {
  return value
    .replace(/(authorization|cookie|set-cookie|x-api-key)(["']?\s*[:=]\s*)[^\s,;]+/gi, "$1$2<redacted>")
    .replace(/Bearer\s+[A-Za-z0-9._~-]+/gi, "Bearer <redacted>");
}

try {
  await client.connect(transport);
  const listed = await client.listTools();
  evidence.tools = listed.tools.map(tool => tool.name).sort();
  await writeFile(resolve(outputDir, "tool-list.json"), JSON.stringify(listed.tools.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })), null, 2));

  await call("navigate_page", { type: "url", url: targetUrl });
  const snapshotResult = await call("take_snapshot", { verbose: true });
  const snapshot = textual(snapshotResult);
  await writeFile(resolve(outputDir, "accessibility-snapshot.txt"), safeText(snapshot));
  evidence.checks.snapshot = snapshot.includes("Controlled browser smoke");

  const inputUid = uidFor(snapshot, "textbox", "Synthetic name");
  const buttonUid = uidFor(snapshot, "button", "Submit synthetic form");
  await call("fill", { uid: inputUid, value: "Ada Lovelace" });
  await call("click", { uid: buttonUid });
  if (evidence.tools.includes("wait_for")) {
    await call("wait_for", { text: ["Submitted: Ada Lovelace"], timeout: 5000 });
  }
  const resultSnapshot = textual(await call("take_snapshot"));
  await writeFile(resolve(outputDir, "result-snapshot.txt"), safeText(resultSnapshot));
  evidence.checks.businessOutcome = resultSnapshot.includes("Submitted: Ada Lovelace");
  if (!evidence.checks.businessOutcome) throw new Error("Submitted business outcome was not observed.");

  temporaryScreenshotPath = resolve(tmpdir(), `browser-toolkit-${process.pid}.png`);
  const screenshotPath = resolve(outputDir, "smoke.png");
  await call("take_screenshot", { format: "png", filePath: temporaryScreenshotPath });
  await access(temporaryScreenshotPath);
  await copyFile(temporaryScreenshotPath, screenshotPath);
  await unlink(temporaryScreenshotPath);
  temporaryScreenshotPath = undefined;
  evidence.checks.screenshot = true;

  if (evidence.tools.includes("list_console_messages")) {
    const result = await call("list_console_messages", { includePreservedMessages: true });
    await writeFile(resolve(outputDir, "console.txt"), safeText(textual(result)));
    evidence.checks.console = true;
  }
  if (evidence.tools.includes("list_network_requests")) {
    const result = await call("list_network_requests", { includePreservedRequests: true });
    const network = safeText(textual(result));
    await writeFile(resolve(outputDir, "network.txt"), network);
    evidence.checks.network = network.includes("/api/submit");
  }
  if (evidence.tools.includes("lighthouse_audit")) {
    const result = await call("lighthouse_audit", {});
    await writeFile(resolve(outputDir, "lighthouse.txt"), safeText(textual(result)));
    evidence.checks.lighthouse = true;
  } else {
    evidence.checks.lighthouse = "not-advertised";
  }

  evidence.completedAt = new Date().toISOString();
  evidence.status = "passed";
  delete evidence.currentStage;
} catch (error) {
  evidence.completedAt = new Date().toISOString();
  evidence.status = "failed";
  evidence.error = safeText(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  await writeFile(resolve(outputDir, "smoke-report.json"), JSON.stringify(evidence, null, 2));
  await client.close().catch(() => {});
  if (temporaryScreenshotPath) await unlink(temporaryScreenshotPath).catch(() => {});
}

if (evidence.status === "passed") {
  console.log(`Chrome DevTools MCP smoke passed. Evidence: ${outputDir}`);
}
