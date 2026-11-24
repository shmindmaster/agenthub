import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const retiredFolders = 'video|capture|generate|compose|review|visuals|brief|plan|develop';
const retiredSkillPath = new RegExp(`skills/(${retiredFolders})\\b`);
// Bare or ../-prefixed forms such as `video/references/x.md` or `../capture/SKILL.md`.
const retiredRelativeRefs = /(^|[^A-Za-z0-9_-])(video|capture|generate|compose|review|visuals|brief|plan|develop)\/(references\/|SKILL\.md)/;
const linkPattern = /\[[^\]\n]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;

function walk(dir, keep) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, keep));
    else if (keep(full)) out.push(full);
  }
  return out;
}

const rel = file => path.relative(root, file).split(path.sep).join('/');
const markdownFiles = () => [
  path.join(root, 'README.md'),
  ...walk(path.join(root, 'skills'), file => file.endsWith('.md')),
];
const textFiles = () => [
  ...walk(path.join(root, 'skills'), () => true),
  ...walk(path.join(root, 'policy'), () => true),
];

test('every relative markdown link in skills/ and README.md resolves from its own file', () => {
  const broken = [];
  for (const file of markdownFiles()) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, index) => {
      for (const match of line.matchAll(linkPattern)) {
        const target = match[1];
        if (/^(https?:|mailto:|#)/i.test(target) || target.includes('://')) continue;
        const bare = target.split('#')[0].split('?')[0];
        if (!bare) continue;
        const resolved = path.resolve(path.dirname(file), decodeURI(bare));
        if (!fs.existsSync(resolved)) broken.push(`${rel(file)}:${index + 1} -> ${target}`);
      }
    });
  }
  assert.equal(broken.length, 0, `broken relative links:\n${broken.join('\n')}`);
});

test('no skills/ or policy/ text names a retired skill folder', () => {
  const hits = [];
  for (const file of textFiles()) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, index) => {
      if (retiredSkillPath.test(line) || retiredRelativeRefs.test(line)) {
        hits.push(`${rel(file)}:${index + 1}: ${line.trim().slice(0, 160)}`);
      }
    });
  }
  assert.equal(hits.length, 0, `retired skill folder references:\n${hits.join('\n')}`);
});
