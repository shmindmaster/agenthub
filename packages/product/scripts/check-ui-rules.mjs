#!/usr/bin/env node
// Static check for the UI rules that can be read from source. Read-only.
// Usage: check-ui-rules.mjs [--skip rule,rule] <directory>
// Exit 0 when clean, 1 when a rule is broken, 2 on bad usage.
// Rules and the exemption policy: references/ui-standard.md.

import fs from 'node:fs';
import path from 'node:path';

const RULES = ['viewport-font', 'letter-spacing', 'card-radius'];
const EXTENSIONS = new Set(['.css', '.scss', '.sass', '.less', '.html', '.htm', '.js', '.jsx', '.ts', '.tsx', '.vue', '.svelte', '.astro']);
const SKIP_DIRECTORIES = new Set(['node_modules', '.git', 'dist', 'build', '.next', '.nuxt', '.svelte-kit', 'coverage', 'out', 'vendor', '.turbo']);
const MAX_RADIUS_PX = 8;

const args = process.argv.slice(2);
const skipIndex = args.indexOf('--skip');
const skip = new Set(skipIndex >= 0 ? String(args[skipIndex + 1] ?? '').split(',').map((value) => value.trim()).filter(Boolean) : []);
const target = args.find((value, index) => !value.startsWith("--") && (skipIndex < 0 || index !== skipIndex + 1));
const unknownSkips = [...skip].filter((rule) => !RULES.includes(rule));

if (!target || unknownSkips.length) {
  console.error(`Usage: check-ui-rules.mjs [--skip ${RULES.join(',')}] <directory>`);
  if (unknownSkips.length) console.error(`Unknown rule: ${unknownSkips.join(', ')}`);
  process.exit(2);
}
const root = path.resolve(target);
if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error(`Not a directory: ${root}`);
  process.exit(2);
}

function* walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIP_DIRECTORIES.has(entry.name)) yield* walk(path.join(directory, entry.name));
    } else if (EXTENSIONS.has(path.extname(entry.name).toLowerCase()) && !/\.min\./.test(entry.name)) {
      yield path.join(directory, entry.name);
    }
  }
}

// The value after a property, up to the first `;`, `}`, `,` or closing quote outside brackets.
function valueAfter(line, from) {
  let depth = 0;
  let out = '';
  for (let i = from; i < line.length; i += 1) {
    const char = line[i];
    if (char === '(' || char === '[') depth += 1;
    if (char === ')' || char === ']') depth -= 1;
    if (depth <= 0 && (char === ';' || char === '}' || char === ',' || char === '"' || char === "'" || char === '`')) break;
    out += char;
  }
  return out.trim();
}

function toPx(value) {
  const match = /^(-?[\d.]+)(px|rem|em)$/i.exec(value.trim());
  if (!match) return null;
  return Number(match[1]) * (match[2].toLowerCase() === 'px' ? 1 : 16);
}

const findings = [];
const add = (file, lineNumber, rule, text) => {
  if (!skip.has(rule)) findings.push({ file: path.relative(root, file).split(path.sep).join('/'), line: lineNumber, rule, text: text.trim().slice(0, 120) });
};

for (const file of walk(root)) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  let selector = '';
  lines.forEach((line, index) => {
    const lineNumber = index + 1;
    if (/^\s*(\/\/|\/\*|\*)/.test(line)) return;

    // Track the latest CSS selector so a radius can be tied to a card rule.
    const selectorMatch = /^\s*([^{};@][^{};]*)\{/.exec(line);
    if (selectorMatch) selector = selectorMatch[1];

    for (const match of line.matchAll(/font-?size["']?\s*[:=]\s*["'`]?/gi)) {
      if (/\d(?:vw|vh|vmin|vmax|svw|svh|lvw|lvh|dvw|dvh)\b/i.test(valueAfter(line, match.index + match[0].length))) add(file, lineNumber, 'viewport-font', line);
    }
    if (/\btext-\[[^\]]*\d(?:vw|vh|vmin|vmax|svw|svh|lvw|lvh|dvw|dvh)\]/i.test(line)) add(file, lineNumber, 'viewport-font', line);

    for (const match of line.matchAll(/letter-?spacing["']?\s*[:=]\s*["'`]?/gi)) {
      const value = valueAfter(line, match.index + match[0].length);
      const number = /^(-?[\d.]+)(px|em|rem)?$/i.exec(value);
      if (number && Number(number[1]) !== 0) add(file, lineNumber, 'letter-spacing', line);
    }
    if (/\btracking-(?:tighter|tight|wide|wider|widest)\b/.test(line)) add(file, lineNumber, 'letter-spacing', line);

    for (const match of line.matchAll(/border-?radius["']?\s*[:=]\s*["'`]?/gi)) {
      const value = valueAfter(line, match.index + match[0].length);
      const largest = value.split(/\s+/).map(toPx).filter((px) => px !== null);
      const cardRule = /card/i.test(selector) || /card/i.test(line);
      if (cardRule && largest.some((px) => px > MAX_RADIUS_PX)) add(file, lineNumber, 'card-radius', line);
    }
    // Tailwind: a class string that names a card and uses a radius above 8px.
    for (const group of line.matchAll(/["'`]([^"'`]*\bcard\b[^"'`]*)["'`]/gi)) {
      for (const radius of group[1].matchAll(/\brounded(?:-[a-z]{1,2})?-(xl|2xl|3xl|\[([\d.]+)px\])/g)) {
        if (radius[2] === undefined || Number(radius[2]) > MAX_RADIUS_PX) add(file, lineNumber, 'card-radius', line);
      }
    }
  });
}

if (findings.length) {
  for (const finding of findings) console.error(`${finding.file}:${finding.line} ${finding.rule}: ${finding.text}`);
  console.error(`FAIL: ${findings.length} finding(s). Exempt a rule only when the repository's own design system requires it, and name that rule in the verdict.`);
  process.exit(1);
}
console.log(`PASS: no ${RULES.filter((rule) => !skip.has(rule)).join(', ')} findings under ${root}.`);
