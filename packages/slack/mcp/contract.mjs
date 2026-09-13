import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

export function packageRoot() {
  return pkgRoot;
}

export function loadToolContract() {
  const raw = readFileSync(join(pkgRoot, 'schemas', 'tools.json'), 'utf8');
  const doc = JSON.parse(raw);
  if (!doc || !Array.isArray(doc.tools) || doc.tools.length === 0) {
    throw new Error('packages/slack/schemas/tools.json has no tools');
  }
  const names = new Set();
  for (const tool of doc.tools) {
    if (!tool.name || !tool.inputSchema) {
      throw new Error(`tool is missing name or inputSchema: ${JSON.stringify(tool)}`);
    }
    if (names.has(tool.name)) {
      throw new Error(`duplicate tool name: ${tool.name}`);
    }
    names.add(tool.name);
  }
  return doc;
}

export function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = canonicalize(value[key]);
    }
    return out;
  }
  return value;
}

export function slackContractHash(doc = loadToolContract()) {
  const parts = [...doc.tools]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((tool) => `${tool.name}\n${JSON.stringify(canonicalize(tool.inputSchema))}\n`);
  return createHash('sha256').update(parts.join(''), 'utf8').digest('hex').toUpperCase();
}

export function mcpToolList(doc = loadToolContract()) {
  return doc.tools.map((tool) => ({
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema,
  }));
}
