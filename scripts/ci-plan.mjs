import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Unknown changes deliberately take the full path. Add a narrow route only with
// an explicit test mapping and coverage for shared contracts.
export function classify(paths, registryHashOnly = false) {
  if (!paths.length) return 'full';
  const useful = paths.filter(p => !/^(docs\/|README\.md$)/i.test(p));
  if (!useful.length) return 'docs';
  if (useful.length !== paths.length) return 'full';
  if (useful.every(p => /^(src\/doctor\/|test\/doctor\/)/.test(p))) return 'doctor';
  const dispatch = useful.some(p => p.startsWith('packages/coding-agent-dispatch/'));
  if (dispatch && useful.every(p => p.startsWith('packages/coding-agent-dispatch/') || (p === 'registry/capabilities.json' && registryHashOnly))) return 'dispatch';
  return 'full';
}

export function onlyDispatchHashChanged(before, after) {
  let changed = 0;
  const scrub = value => {
    if (Array.isArray(value)) return value.map(scrub);
    if (!value || typeof value !== 'object') return value;
    const result = {};
    for (const [k,v] of Object.entries(value)) {
      if (k === 'contentHash' && value.hashBasis === 'packages/coding-agent-dispatch') { result[k] = '<hash>'; continue; }
      result[k] = scrub(v);
    }
    return result;
  };
  const count = v => {
    if (Array.isArray(v)) return v.reduce((n,x) => n + count(x),0);
    if (!v || typeof v !== 'object') return 0;
    return (v.hashBasis === 'packages/coding-agent-dispatch' && typeof v.contentHash === 'string' ? 1 : 0) + Object.values(v).reduce((n,x) => n + count(x),0);
  };
  changed = count(before);
  return changed > 0 && changed === count(after) && JSON.stringify(scrub(before)) === JSON.stringify(scrub(after));
}

function main() {
  let scope = 'full';
  try {
    const base = process.env.CI_BASE_SHA;
    const head = process.env.CI_HEAD_SHA;
    if (!base || /^0+$/.test(base) || !head || process.env.GITHUB_EVENT_NAME === 'workflow_dispatch') throw Error('No comparable base');
    const files = execFileSync('git', ['diff','--no-renames','--name-only','-z',base,head], {encoding:'utf8'}).split('\0').filter(Boolean);
    let hashOnly = false;
    if (files.includes('registry/capabilities.json')) {
      const read = rev => JSON.parse(execFileSync('git',['show',`${rev}:registry/capabilities.json`],{encoding:'utf8'}));
      hashOnly = onlyDispatchHashChanged(read(base),read(head));
    }
    scope = classify(files, hashOnly);
    console.log(`Changed files: ${files.join(', ')}; scope: ${scope}`);
  } catch (error) { console.log(`Using full suite: ${error.message}`); }
  const os = ['ubuntu-latest','macos-latest','windows-latest', ...(scope === 'full' ? ['macos-15-intel'] : [])];
  const shards = scope === 'full' ? 8 : 1;
  const matrix = os.flatMap(platform => Array.from({length:shards}, (_, shard) => ({os:platform,shard,shards})));
  appendFileSync(process.env.GITHUB_OUTPUT, `scope=${scope}\nmatrix=${JSON.stringify({include:matrix})}\n`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
