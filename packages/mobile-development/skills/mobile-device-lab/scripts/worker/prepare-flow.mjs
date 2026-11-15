#!/usr/bin/env node
// Prepare a committed Maestro flow for an Expo development build.
//
// A development client opens on the Expo development launcher until it is
// told where the bundle lives. The lab worker starts Metro and reverse-
// forwards it into the emulator, then runs the flow; every `launchApp` that
// clears state forgets the launcher's last server, so the development-client
// deep link must be opened again after EACH launch. This copies the flow and
// inserts, after every `- launchApp:` block (after its `clearState` line when
// present), a settle wait for the Expo dev launcher's home screen followed by
// `- openLink: "<launchUrl>"`. The settle matters: a link sent while the dev
// client is still creating its activity is dropped. The committed flow is
// never changed.
//
// Same pattern as apps/mobile/scripts/ios/guest-journeys.sh in the ABACare
// repository, kept app-agnostic: the link and any address rewrites arrive
// from the lab profile. Maestro runScript runs on the worker, not inside the
// emulator, so a profile maps emulator-alias addresses (10.0.2.2) to the
// worker's loopback for host-side scripts; the rewrite runs BEFORE insertion
// so the inserted link keeps the emulator-facing address.
//
// Usage: node prepare-flow.mjs <flow.yaml> <launchUrl> <output.yaml> [rewriteJson]
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function prepareFlow(text, launchUrl, flowRewrite = {}) {
  if (typeof text !== "string") throw new Error("flow text must be a string");
  if (typeof launchUrl !== "string" || launchUrl.trim() === "") {
    throw new Error("launchUrl must be a non-empty string");
  }
  if (flowRewrite === null || typeof flowRewrite !== "object" || Array.isArray(flowRewrite)) {
    throw new Error("flowRewrite must be an object of string replacements");
  }
  for (const [from, to] of Object.entries(flowRewrite)) {
    if (from === "" || typeof to !== "string") {
      throw new Error("flowRewrite entries must be non-empty string pairs");
    }
    text = text.split(from).join(to);
  }
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const trailingNewline = /\r?\n$/.test(text);
  const lines = text.split(/\r?\n/);
  // split leaves an empty tail element after a final newline; the join below
  // restores that newline exactly once.
  if (trailingNewline) lines.pop();
  const link = `- openLink: ${JSON.stringify(launchUrl)}`;
  // A launchApp that clears state restarts the app; a deep link sent while
  // the dev client is still creating its activity is dropped, and the
  // launcher home wins. Wait for the Expo dev launcher's own home screen
  // (app-agnostic) so the link arrives on the wired onNewIntent path.
  // Optional: with clearState false the launcher may auto-load straight
  // into the app and never show home.
  const settle = [
    '- extendedWaitUntil:',
    '    visible: "New development server"',
    '    timeout: 15000',
    '    optional: true',
  ];
  const out = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    out.push(line);
    if (/^- launchApp:\s*$/.test(line)) {
      // Keep the whole YAML mapping attached to launchApp. Comments after
      // clearState and later options (permissions, appId, etc.) are valid and
      // must not be split away when adding our following flow steps.
      while (i + 1 < lines.length && !/^-\s/.test(lines[i + 1])) {
        i += 1;
        out.push(lines[i]);
      }
      out.push(...settle, link);
    }
  }
  return out.join(eol) + (trailingNewline ? eol : "");
}

const isMain =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const [flowPath, launchUrl, outPath, rewriteJson] = process.argv.slice(2);
  if (!flowPath || !launchUrl || !outPath) {
    console.error("usage: prepare-flow.mjs <flow.yaml> <launchUrl> <output.yaml> [rewriteJson]");
    process.exit(2);
  }
  try {
    const rewrite = rewriteJson ? JSON.parse(rewriteJson) : {};
    const prepared = prepareFlow(readFileSync(flowPath, "utf8"), launchUrl, rewrite);
    writeFileSync(outPath, prepared, "utf8");
  } catch (error) {
    console.error(`prepare-flow: ${error.message}`);
    process.exit(1);
  }
}
