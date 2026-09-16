// Test-McpOAuthReachability.js -- AgentHub triage probe: can this machine
// actually reach the OAuth MCP servers?
//
// WHY THIS EXISTS
// qwen-code's "Failed to discover OAuth configuration from MCP server" fires
// BEFORE any token exchange, so the Repair-QwenCodeMcpOAuth.js hotfix cannot
// be the cause and re-patching cannot fix it. The usual real cause is that the
// server URL is unreachable from this egress. This probe classifies why.
//
// WHAT IT DOES
// For every headerless httpUrl MCP server in %USERPROFILE%\.qwen\settings.json
// (the OAuth candidates; pass explicit URLs as arguments to override):
//   1. DNS-resolve the host.
//   2. Attempt a TLS handshake with the real SNI.
//   3. If that fails, attempt a control handshake against the same resolved
//      IP with SNI "example.com" (served by most shared anycast edges).
// Verdicts per server:
//   reachable               handshake completed.
//   dns-failure             name does not resolve.
//   hostname-keyed-block    real SNI is reset/refused, but the control SNI
//                           completes on the same IP: the block targets this
//                           hostname from this client/path (gateway, ISP
//                           middlebox, or the site's edge refusing this IP).
//                           No qwen-code change fixes it; remediate the
//                           network path (renew public IP, check gateway
//                           security blocklists, or change egress).
//   ip-or-path-unreachable  every TLS attempt to the resolved IP fails: the
//                           IP or the path to it is dead.
//
// USAGE
//   node Test-McpOAuthReachability.js            scan settings.json
//   node Test-McpOAuthReachability.js <url>...   probe specific server URLs
//
// EXIT CODES
//   0 every server reachable, 4 at least one blocked/unreachable,
//   1 hard error (nothing to probe, bad arguments)
//
// stdout is one JSON document. Read-only; changes nothing.

import dns from 'node:dns';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import tls from 'node:tls';
import { URL } from 'node:url';

const CONTROL_SNI = 'example.com';
const TIMEOUT_MS = 10000;

function settingsOAuthCandidates() {
  const settingsPath = path.join(os.homedir(), '.qwen', 'settings.json');
  const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
  const servers = (settings && settings.mcpServers) || {};
  const targets = [];
  for (const [name, server] of Object.entries(servers)) {
    if (!server || !server.httpUrl) continue;
    const headers = server.headers || {};
    const hasAuthHeader = Object.keys(headers).some(
      (key) => key.toLowerCase() === 'authorization'
    );
    if (!hasAuthHeader) targets.push({ name, url: server.httpUrl });
  }
  return targets;
}

function probeTls(address, port, servername) {
  return new Promise((resolve) => {
    const socket = tls.connect(
      { host: address, port, servername, rejectUnauthorized: false },
      () => {
        const cert = socket.getPeerCertificate();
        socket.end();
        resolve({
          ok: true,
          certCn: (cert && cert.subject && cert.subject.CN) || null,
        });
      }
    );
    socket.setTimeout(TIMEOUT_MS, () => {
      socket.destroy();
      resolve({ ok: false, error: 'timeout' });
    });
    socket.on('error', (err) => {
      resolve({ ok: false, error: `${err.code ? `${err.code} ` : ''}${err.message}` });
    });
  });
}

function probeTcp(address, port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: address, port }, () => {
      socket.end();
      resolve({ ok: true });
    });
    socket.setTimeout(TIMEOUT_MS, () => {
      socket.destroy();
      resolve({ ok: false, error: 'timeout' });
    });
    socket.on('error', (err) => {
      resolve({ ok: false, error: `${err.code ? `${err.code} ` : ''}${err.message}` });
    });
  });
}

async function checkServer(name, urlString) {
  let parsed;
  try {
    parsed = new URL(urlString);
  } catch (err) {
    return { name, url: urlString, verdict: 'bad-url', detail: String(err.message || err) };
  }
  const hostname = parsed.hostname;
  const isTls = parsed.protocol !== 'http:';
  const port = parsed.port ? Number(parsed.port) : isTls ? 443 : 80;

  let addresses;
  try {
    addresses = await dns.promises.lookup(hostname, { all: true });
  } catch (err) {
    return {
      name,
      url: urlString,
      verdict: 'dns-failure',
      detail: `${hostname}: ${err.code || err.message}`,
    };
  }

  const ordered = [
    ...addresses.filter((a) => a.family === 4),
    ...addresses.filter((a) => a.family === 6),
  ];

  let lastError = null;
  for (const entry of ordered) {
    const result = isTls
      ? await probeTls(entry.address, port, hostname)
      : await probeTcp(entry.address, port);
    if (result.ok) {
      return {
        name,
        url: urlString,
        verdict: 'reachable',
        address: entry.address,
        certCn: result.certCn || null,
      };
    }
    lastError = `${entry.address}: ${result.error}`;
  }

  if (!isTls) {
    return {
      name,
      url: urlString,
      verdict: 'ip-or-path-unreachable',
      detail: `TCP connect failed on every resolved address (${lastError})`,
    };
  }

  // Real SNI failed everywhere; run the control SNI against the last address
  // to separate a hostname-keyed block from a dead IP/path.
  const controlTarget = ordered[ordered.length - 1];
  const control = await probeTls(controlTarget.address, port, CONTROL_SNI);
  if (control.ok) {
    return {
      name,
      url: urlString,
      verdict: 'hostname-keyed-block',
      address: controlTarget.address,
      detail:
        `real SNI rejected (${lastError}) but control SNI "${CONTROL_SNI}" ` +
        `completes on the same IP (cert ${control.certCn}); a block targets ` +
        'this hostname from this egress',
    };
  }
  return {
    name,
    url: urlString,
    verdict: 'ip-or-path-unreachable',
    address: controlTarget.address,
    detail: `real SNI rejected (${lastError}) and control SNI also failed (${control.error})`,
  };
}

async function main() {
  const argUrls = process.argv.slice(2);
  let targets;
  if (argUrls.length > 0) {
    targets = argUrls.map((url, index) => ({ name: `arg-${index + 1}`, url }));
  } else {
    try {
      targets = settingsOAuthCandidates();
    } catch (err) {
      console.log(
        JSON.stringify({
          status: 'error',
          detail: `cannot read ~/.qwen/settings.json: ${err.message}`,
        })
      );
      process.exit(1);
    }
  }
  if (!targets.length) {
    console.log(
      JSON.stringify({
        status: 'error',
        detail: 'no headerless httpUrl MCP servers found to probe',
      })
    );
    process.exit(1);
  }

  const servers = [];
  for (const target of targets) {
    servers.push(await checkServer(target.name, target.url));
  }
  const notReachable = servers.filter((s) => s.verdict !== 'reachable').length;
  console.log(
    JSON.stringify({ status: notReachable === 0 ? 'all-reachable' : 'blocked', servers }, null, 2)
  );
  process.exit(notReachable === 0 ? 0 : 4);
}

main().catch((err) => {
  console.log(JSON.stringify({ status: 'error', detail: String((err && err.stack) || err) }));
  process.exit(1);
});
