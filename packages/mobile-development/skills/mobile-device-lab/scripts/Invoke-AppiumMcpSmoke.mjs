import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { cleanupCreatedSessions } from "./AppiumSessionCleanup.mjs";

function readArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]?.replace(/^--/, "");
    const value = argv[i + 1];
    if (!key || value === undefined) throw new Error(`Invalid argument near ${argv[i] ?? "<end>"}`);
    result[key] = value;
  }
  for (const required of ["remote-url", "android-udid", "ios-udid", "android-app", "ios-app", "ios-bundle-id", "output-dir", "appium-package", "ios-device-name", "ios-platform-version"]) {
    if (!result[required]) throw new Error(`Missing --${required}`);
  }
  if (!/^appium-mcp@[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/.test(result["appium-package"])) {
    throw new Error("--appium-package must be an exact appium-mcp@<semver> pin from registry/mcps.json");
  }
  return result;
}

const args = readArgs(process.argv.slice(2));
fs.mkdirSync(args["output-dir"], { recursive: true });

const child = spawn(
  "cmd.exe",
  ["/d", "/s", "/c", `npx -y ${args["appium-package"]}`],
  {
    stdio: ["pipe", "pipe", "pipe"],
    env: { ...process.env, NO_UI: "true" },
  },
);

let stdoutBuffer = "";
let stderr = "";
let nextId = 1;
const pending = new Map();

child.stderr.on("data", (chunk) => {
  stderr += chunk.toString();
});
child.stdout.on("data", (chunk) => {
  stdoutBuffer += chunk.toString();
  while (stdoutBuffer.includes("\n")) {
    const lineEnd = stdoutBuffer.indexOf("\n");
    const line = stdoutBuffer.slice(0, lineEnd).trim();
    stdoutBuffer = stdoutBuffer.slice(lineEnd + 1);
    if (!line) continue;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      continue;
    }
    if (message.id !== undefined && pending.has(message.id)) {
      const entry = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) entry.reject(new Error(JSON.stringify(message.error)));
      else entry.resolve(message.result);
    }
  }
});

function request(method, params, timeoutMs = 900_000) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    pending.set(id, {
      resolve: (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      reject: (error) => {
        clearTimeout(timer);
        reject(error);
      },
    });
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });
}

function notify(method, params = {}) {
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
}

async function callTool(name, toolArgs, timeoutMs) {
  const result = await request("tools/call", { name, arguments: toolArgs }, timeoutMs);
  if (result?.isError) {
    const detail = (result.content ?? []).map((item) => item.text ?? "").join("\n");
    throw new Error(`${name} failed: ${detail}`);
  }
  return result;
}

function textOf(result) {
  return (result?.content ?? []).map((item) => item.text ?? "").join("\n");
}

function extractSessionId(result) {
  const text = textOf(result);
  const match = text.match(/created successfully with ID:\s*([0-9a-f-]{8,})/i)
    ?? text.match(/(?:sessionId|session id)["'\s:=]+([0-9a-f-]{8,})/i);
  return match?.[1] ?? null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function findElementWithRetry(label, sessionId, selector, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const result = await callTool("appium_find_element", {
        strategy: "accessibility id",
        selector,
        sessionId,
      });
      const resultText = textOf(result);
      const match = resultText.match(/(?:elementUUID|elementId|ELEMENT)["'\s:=]+([0-9a-f-]{8,})/i);
      if (match) return match[1];
      lastError = new Error(`${label}: could not resolve ${selector} element from ${resultText}`);
    } catch (error) {
      lastError = error;
    }
    await sleep(1000);
  }
  throw new Error(`${label}: ${selector} did not become ready within ${timeoutMs}ms: ${lastError?.message ?? "unknown error"}`);
}

async function exerciseSession(label, sessionId) {
  const inputId = await findElementWithRetry(label, sessionId, "message-input");
  await callTool("appium_gesture", { action: "tap", elementUUID: inputId, sessionId });
  // Driver-level setValue can mutate an iOS native field without emitting the
  // React Native change event. Real W3C key actions target the focused field
  // and prove the app itself observed the typing.
  await callTool("appium_set_value", { text: `hello-${label}`, w3cActions: true, sessionId });

  const buttonId = await findElementWithRetry(label, sessionId, "submit-message");
  await callTool("appium_gesture", { action: "tap", elementUUID: buttonId, sessionId });

  const sourceDeadline = Date.now() + 15_000;
  let sourceText = "";
  while (Date.now() < sourceDeadline) {
    const source = await callTool("appium_get_page_source", { sessionId });
    sourceText = textOf(source);
    if (sourceText.includes(`hello-${label}`)) break;
    await sleep(500);
  }
  if (!sourceText.includes(`hello-${label}`)) throw new Error(`${label}: echo text did not appear in page source within 15000ms`);
  const screenshot = await callTool("appium_screenshot", { maxWidth: 900, returnRawBase64: true, sessionId });
  const imageContent = (screenshot.content ?? []).find((item) => item.type === "image" && item.data);
  let screenshotArtifact = textOf(screenshot);
  if (imageContent) {
    const extension = imageContent.mimeType === "image/jpeg" ? "jpg" : "png";
    screenshotArtifact = path.join(args["output-dir"], `${label}-smoke.${extension}`);
    fs.writeFileSync(screenshotArtifact, Buffer.from(imageContent.data, "base64"));
  }
  if (!imageContent && !screenshotArtifact) throw new Error(`${label}: screenshot returned no image or artifact reference`);
  return {
    pageSourceContainsEcho: true,
    screenshotCaptured: true,
    screenshotArtifact,
  };
}

const report = {
  ok: false,
  protocolVersion: null,
  server: null,
  toolCount: 0,
  android: {},
  ios: {},
};
const createdSessionIds = [];

async function cleanupAllCreatedSessions() {
  return cleanupCreatedSessions(createdSessionIds, (sessionId) =>
    callTool("appium_session_management", { action: "delete", sessionId }, 120_000));
}

try {
  const initialized = await request("initialize", {
    protocolVersion: "2025-11-25",
    capabilities: {},
    clientInfo: { name: "agenthub-mobile-lab-smoke", version: "1.0.0" },
  }, 120_000);
  report.protocolVersion = initialized.protocolVersion;
  report.server = initialized.serverInfo;
  notify("notifications/initialized");

  const listed = await request("tools/list", {}, 120_000);
  const tools = listed.tools ?? [];
  report.toolCount = tools.length;
  const requiredTools = [
    "select_device",
    "appium_session_management",
    "appium_find_element",
    "appium_set_value",
    "appium_gesture",
    "appium_get_page_source",
    "appium_screenshot",
  ];
  const missing = requiredTools.filter((name) => !tools.some((tool) => tool.name === name));
  if (missing.length) throw new Error(`MCP tool catalog is missing: ${missing.join(", ")}`);

  await callTool("select_device", { platform: "android" }, 120_000);
  const androidSession = await callTool("appium_session_management", {
    action: "create",
    platform: "android",
    capabilities: JSON.stringify({
      "appium:app": path.resolve(args["android-app"]),
      "appium:udid": args["android-udid"],
      "appium:appPackage": "test.agenthub.mobilelab.smoke",
      "appium:autoGrantPermissions": true,
      "appium:newCommandTimeout": 600,
    }),
  });
  report.android.sessionId = extractSessionId(androidSession);
  if (!report.android.sessionId) throw new Error(`Could not parse Android session ID from ${textOf(androidSession)}`);
  createdSessionIds.push(report.android.sessionId);
  report.android.exercise = await exerciseSession("android", report.android.sessionId);

  const iosSession = await callTool("appium_session_management", {
    action: "create",
    platform: "ios",
    remoteServerUrl: args["remote-url"],
    capabilities: JSON.stringify({
      platformName: "iOS",
      "appium:automationName": "XCUITest",
      "appium:deviceName": args["ios-device-name"],
      "appium:platformVersion": args["ios-platform-version"],
      "appium:udid": args["ios-udid"],
      "appium:app": args["ios-app"],
      "appium:bundleId": args["ios-bundle-id"],
      "appium:noReset": true,
      "appium:newCommandTimeout": 600,
      "appium:wdaLaunchTimeout": 900000,
      "appium:wdaConnectionTimeout": 900000,
    }),
  }, 900_000);
  report.ios.sessionId = extractSessionId(iosSession);
  if (!report.ios.sessionId) throw new Error(`Could not parse iOS session ID from ${textOf(iosSession)}`);
  createdSessionIds.push(report.ios.sessionId);
  report.ios.exercise = await exerciseSession("ios", report.ios.sessionId);

  const sessions = await callTool("appium_session_management", { action: "list" });
  const sessionText = textOf(sessions);
  report.concurrentSessions = (sessionText.match(/sessionId=/g) ?? []).length >= 2;
  if (!report.concurrentSessions) throw new Error(`Concurrent session listing was not credible: ${sessionText}`);

  report.cleanupErrors = await cleanupAllCreatedSessions();
  report.sessionsCleaned = report.cleanupErrors.length === 0;
  if (!report.sessionsCleaned) {
    throw new Error(`Session cleanup failed: ${report.cleanupErrors.join(" | ")}`);
  }

  report.ok = true;
  fs.writeFileSync(
    path.join(args["output-dir"], "appium-mcp-smoke.json"),
    `${JSON.stringify(report, null, 2)}\n`,
  );
  process.stdout.write(`${JSON.stringify(report)}\n`);
} catch (error) {
  report.error = error instanceof Error ? error.message : String(error);
  report.stderrTail = stderr.slice(-4000);
  const additionalCleanupErrors = await cleanupAllCreatedSessions();
  report.cleanupErrors = [...(report.cleanupErrors ?? []), ...additionalCleanupErrors];
  report.sessionsCleaned = report.cleanupErrors.length === 0;
  fs.writeFileSync(
    path.join(args["output-dir"], "appium-mcp-smoke.json"),
    `${JSON.stringify(report, null, 2)}\n`,
  );
  process.stderr.write(`${JSON.stringify(report)}\n`);
  process.exitCode = 1;
} finally {
  child.kill();
}
