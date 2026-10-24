// @ts-check
// Skills and instruction files: what each host would load at startup.

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

export const MANAGED_MARKER = '<!-- agenthub:managed -->';

/**
 * @typedef {object} SkillEntry
 * @property {string} name        Directory name.
 * @property {string | null} declaredName  frontmatter `name`.
 * @property {boolean} hasDescription
 * @property {string} dir
 * @property {string} source      The skills directory it was found in.
 * @property {string} hash        Hash of SKILL.md with line endings normalised.
 */

/**
 * Lists skills (sub-directories holding SKILL.md) in one directory.
 * Junctions and symlinks are followed, as the hosts follow them.
 * @param {string} dir
 * @returns {{ exists: boolean, skills: SkillEntry[] }}
 */
export function listSkills(dir) {
  let names;
  try {
    names = readdirSync(dir);
  } catch {
    return { exists: false, skills: [] };
  }
  /** @type {SkillEntry[]} */
  const skills = [];
  for (const name of names.sort()) {
    if (name.startsWith('.')) continue;
    const skillDir = join(dir, name);
    const file = join(skillDir, 'SKILL.md');
    let text;
    try {
      if (!statSync(skillDir).isDirectory()) continue;
      text = readFileSync(file, 'utf8');
    } catch {
      continue;
    }
    const fm = parseFrontmatter(text);
    skills.push({
      name,
      declaredName: typeof fm.name === 'string' && fm.name ? fm.name : null,
      hasDescription: typeof fm.description === 'string' && fm.description.trim().length > 0,
      dir: skillDir,
      source: dir,
      hash: hashText(text),
    });
  }
  return { exists: true, skills };
}

/**
 * Reads top-level `key: value` pairs from a leading --- block. Enough for
 * name/description; folded and quoted values are unwrapped.
 * @param {string} text
 * @returns {Record<string, string>}
 */
export function parseFrontmatter(text) {
  const normalized = text.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  if (!normalized.startsWith('---\n')) return {};
  const end = normalized.indexOf('\n---', 4);
  if (end < 0) return {};
  const lines = normalized.slice(4, end).split('\n');
  /** @type {Record<string, string>} */
  const out = {};
  for (let i = 0; i < lines.length; i++) {
    const m = /^([A-Za-z_][\w-]*):\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    let value = m[2].trim();
    if (/^[>|][-+]?$/.test(value) || value === '') {
      const block = [];
      while (i + 1 < lines.length && /^\s+\S/.test(lines[i + 1])) block.push(lines[++i].trim());
      value = block.join(' ');
    }
    out[m[1]] = value.replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}

/**
 * @typedef {object} InstructionFile
 * @property {string} path
 * @property {boolean} exists
 * @property {number} bytes
 * @property {number} estimatedTokens  bytes / 4, the usual rough rate for English Markdown.
 * @property {boolean} managed         Carries the AgentHub managed marker.
 * @property {string | null} bodyHash  Hash with the first heading and the marker removed, to compare hosts.
 */

/**
 * @param {string} path
 * @returns {InstructionFile}
 */
export function readInstructionFile(path) {
  let text;
  try {
    if (!statSync(path).isFile()) throw new Error('not a file');
    text = readFileSync(path, 'utf8');
  } catch {
    return { path, exists: false, bytes: 0, estimatedTokens: 0, managed: false, bodyHash: null };
  }
  const bytes = Buffer.byteLength(text, 'utf8');
  const body = text
    .replace(/\r\n?/g, '\n')
    .replace(MANAGED_MARKER, '')
    .replace(/^\s*#[^\n]*\n/, '')
    .trim();
  return {
    path,
    exists: true,
    bytes,
    estimatedTokens: Math.round(bytes / 4),
    managed: text.includes(MANAGED_MARKER),
    bodyHash: body ? hashText(body) : null,
  };
}

/**
 * Lists rule files (Markdown/MDC) in a rules directory, for hosts such as
 * Cursor whose global instructions are a directory of rules.
 * @param {string} dir
 * @returns {InstructionFile[]}
 */
export function listRuleFiles(dir) {
  let names;
  try {
    names = readdirSync(dir);
  } catch {
    return [];
  }
  return names
    .filter((n) => /\.(md|mdc)$/i.test(n))
    .sort()
    .map((n) => readInstructionFile(join(dir, n)))
    .filter((f) => f.exists);
}

/** @param {string} text */
function hashText(text) {
  return createHash('sha256').update(text.replace(/\r\n?/g, '\n')).digest('hex').slice(0, 16);
}
