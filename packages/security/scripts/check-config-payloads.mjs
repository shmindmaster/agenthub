#!/usr/bin/env node
// Fleet-shared config-payload malware scanner. Canonical source for this
// capability; adapted from subops/scripts/check-config-payloads.mjs, which
// discovered the obfuscated-loader and campaign-marker signatures below on a
// real incident. Do not fork a second copy into another repo -- point that
// repo's pre-push hook at this file instead (see packages/security/README.md).
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const CONFIG_FILE_PATTERN =
  /(^|[/\\])(?:[A-Za-z0-9_.-]+\.)?(?:config|postcss|tailwind|vite|next|eslint|playwright|vitest|jest|prisma)\.(?:mjs|cjs|js|ts)$/;

// Files this signature applies to: postcss, tailwind, babel and eslint
// configs specifically -- a createRequire shim is unremarkable in, say,
// next.config.js (Next itself sometimes needs one) but is not a shape any
// of these four tools' own docs ever call for.
const CREATE_REQUIRE_SHIM_FILE_PATTERN = /(^|[/\\])[^/\\]*(?:postcss|tailwind|babel|eslint)[^/\\]*\.(?:mjs|cjs|js|ts)$/i;

const SKIP_DIRS = new Set([
  '.git',
  '.next',
  '.local',
  '.playwright-mcp',
  // Repowise's local index; its SQLite -shm/-wal files appear and vanish
  // while it reindexes, which made a stat() in this walk throw mid-push.
  '.repowise',
  '.source',
  '.vscode',
  '_archive',
  'build',
  'coverage',
  'dist',
  'legacy',
  'node_modules',
  'playwright-report',
  'plugins',
  'test-results',
]);

const MALICIOUS_SIGNATURES = [
  {
    name: "global['!']",
    test: (src) => /global\s*\[\s*['"]!\s*['"]\s*\]/.test(src),
  },
  {
    name: 'global require alias',
    test: (src) => /global\s*\[[^\]]+\]\s*=\s*require\b/.test(src),
  },
  {
    name: '_$_ obfuscated loader table',
    test: (src) => /_\$_[A-Za-z0-9]+/.test(src),
  },
  {
    name: 'known obfuscated loader symbol',
    test: (src) => /\b(?:var\s+EKc\s*=\s*sfL|Tgw\s*\(\s*2509\s*\))/.test(src),
  },
  {
    name: 'blockchain payload endpoint',
    test: (src) => normalized(src).includes('api.trongrid.io/v1/accounts') ||
      normalized(src).includes('fullnode.mainnet.aptoslabs.com/v1/accounts'),
  },
  {
    name: 'behavioral remote execution loader',
    test: (src) =>
      /(?:constructor\s*\.\s*constructor|\bFunction\s*\()/.test(src) &&
      /\beval\s*\(/.test(src) &&
      /(?:child_process|\.spawn\s*\(|\bfetch\s*\(|\bhttps?\s*:|api\.trongrid|aptoslabs)/.test(src),
  },
  {
    // Seen planted verbatim by an automated campaign that stamps a unique
    // A9-<year>-<sequence> tag into every config file it touches, alongside
    // the obfuscated loader signatures above. The tag itself is evidence
    // even where the rest of the payload varies.
    name: 'campaign marker',
    test: (src) => /global\.i\s*=\s*["']A9-\d{4}-\d+["']/.test(src),
  },
  {
    // A legitimate config file is authored by a human and stays within a
    // normal line width. A single line past 4000 characters in a config
    // file is itself a signal -- it is how minified/obfuscated payloads get
    // appended to an otherwise ordinary file without disturbing its
    // formatted body.
    name: 'overlong config line',
    test: (src) => src.split('\n').some((line) => line.length > 4000),
  },
  {
    // createRequire is a legitimate ESM shim in general, but planting one in
    // a postcss/tailwind/babel/eslint config is how a payload regains
    // require() inside a config format that is normally pure ESM -- observed
    // as a delivery step for the loader signatures above.
    name: 'createRequire shim in config',
    test: (src, filePath) =>
      CREATE_REQUIRE_SHIM_FILE_PATTERN.test(filePath.replace(/\\/g, '/')) &&
      /import\s*\{\s*createRequire\s*\}\s*from\s*['"](node:)?module['"]/.test(src),
  },
];

function normalized(src) {
  return src.replace(/[\s'"`+]/g, '').toLowerCase();
}

function shouldSkip(path) {
  return path
    .split(/[\\/]/)
    .some((part) => SKIP_DIRS.has(part));
}

function isConfigFile(path) {
  return CONFIG_FILE_PATTERN.test(path.replace(/\\/g, '/'));
}

function walk(dir, found = []) {
  if (!statSync(dir, { throwIfNoEntry: false })) return found;

  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (shouldSkip(full)) continue;

    // A file can disappear between readdir and stat (tool caches, editors).
    // A vanished file cannot carry a config payload, so it is not a finding.
    const stat = statSync(full, { throwIfNoEntry: false });
    if (!stat) continue;
    if (stat.isDirectory()) {
      walk(full, found);
    } else if (isConfigFile(full)) {
      found.push(full);
    }
  }

  return found;
}

export function scanConfigPayloads({ root = process.cwd() } = {}) {
  const resolvedRoot = resolve(root);
  const findings = [];

  for (const file of walk(resolvedRoot)) {
    let src;
    try {
      src = readFileSync(file, 'utf8');
    } catch (err) {
      if (err.code === 'ENOENT') {
        continue; // file disappeared; skip it, not a finding
      }
      throw err; // keep other errors fatal
    }

    for (const signature of MALICIOUS_SIGNATURES) {
      if (!signature.test(src, file)) continue;

      findings.push({
        file: relative(resolvedRoot, file).replace(/\\/g, '/'),
        signature: signature.name,
        line: firstSuspiciousLine(src, signature.name),
      });
      break;
    }
  }

  return findings;
}

function firstSuspiciousLine(src, signatureName) {
  const lines = src.split('\n');

  if (signatureName === 'overlong config line') {
    const index = lines.findIndex((line) => line.length > 4000);
    return index === -1 ? 1 : index + 1;
  }

  const markers = [
    'global',
    '_$_',
    'Tgw',
    'EKc',
    'trongrid',
    'aptoslabs',
    'constructor',
    'Function',
    'eval',
    'child_process',
    'createRequire',
  ];

  const index = lines.findIndex((line) => markers.some((marker) => line.includes(marker)));
  return index === -1 ? 1 : index + 1;
}

function parseArgs(argv) {
  let root = process.cwd();
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--root') {
      if (i + 1 >= argv.length) {
        console.error('Usage: --root requires a value');
        process.exit(2);
      }
      const value = argv[i + 1];
      if (value.startsWith('--')) {
        console.error('Usage: --root value must not start with --');
        process.exit(2);
      }
      root = value;
      i++;
    }
  }
  return { root };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { root } = parseArgs(process.argv.slice(2));
  const findings = scanConfigPayloads({ root });

  if (findings.length > 0) {
    console.error('Config payload scan failed: suspicious obfuscated loader signatures found.');
    for (const finding of findings) {
      console.error(`- ${finding.file}:${finding.line} (${finding.signature})`);
    }
    process.exit(1);
  }

  console.log('Config payload scan passed.');
}
