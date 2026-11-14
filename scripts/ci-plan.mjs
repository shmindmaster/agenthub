import { execFileSync } from 'node:child_process';
import { appendFileSync, readdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function hashOnlyForPackages(before, after, packages) {
  const scrub = value => {
    if (Array.isArray(value)) return value.map(scrub);
    if (!value || typeof value !== 'object') return value;
    const result = {};
    for (const [key, item] of Object.entries(value)) {
      const owner = typeof value.hashBasis === 'string' && value.hashBasis.match(/^packages\/([^/]+)$/)?.[1];
      result[key] = key === 'contentHash' && packages.includes(owner) ? '<package-hash>' : scrub(item);
    }
    return result;
  };
  return JSON.stringify(scrub(before)) === JSON.stringify(scrub(after));
}

export function classify(paths, hashOnly = false) {
  if (!paths.length) return { core: true, doctor: true, docs: true, packages: [] };
  const packages = [...new Set(paths.map(p => /^tests\/Test-(MediaStudio|FinishMedia)/.test(p) ? 'media-studio' : /^packages\/([a-z0-9-]+)\//.exec(p)?.[1]).filter(Boolean))].sort();
  let core = false, doctor = false, docs = false;
  for (const path of paths) {
    if (/^tests\/Test-(MediaStudio|FinishMedia)/.test(path)) continue;
    if (path.startsWith('packages/')) { if (!/^packages\/[a-z0-9-]+\//.test(path)) core = true; continue; }
    if (path === 'registry/capabilities.json' && packages.length && hashOnly) continue;
    if (/^(docs\/|README\.md$)/i.test(path)) { docs = true; continue; }
    if (/^(src\/doctor\/|test\/doctor\/)/.test(path)) { doctor = true; continue; }
    core = true;
  }
  return { core, doctor: doctor || core, docs, packages };
}

export function packageMatrix(packages) {
  return packages.flatMap(pkg => {
    const shards = pkg === 'media-studio' ? 4 : 1;
    const linux = Array.from({length:shards}, (_, shard) => ({package:pkg, os:'ubuntu-latest', shard, shards}));
    if (['coding-agent-dispatch', 'mobile-development'].includes(pkg)) {
      linux.push({package:pkg, os:'windows-latest', shard:0, shards:1});
    }
    return linux;
  });
}

function main() {
  let plan;
  try {
    const base = process.env.CI_BASE_SHA, head = process.env.CI_HEAD_SHA;
    if (!base || /^0+$/.test(base) || !head || process.env.GITHUB_EVENT_NAME === 'workflow_dispatch') throw Error('Full manual or missing base');
    const files = execFileSync('git', ['diff','--no-renames','--name-only','-z',base,head], {encoding:'utf8'}).split('\0').filter(Boolean);
    const packageNames = [...new Set(files.map(p => /^packages\/([a-z0-9-]+)\//.exec(p)?.[1]).filter(Boolean))];
    let hashOnly = false;
    if (files.includes('registry/capabilities.json') && packageNames.length) {
      const read = rev => JSON.parse(execFileSync('git',['show',`${rev}:registry/capabilities.json`],{encoding:'utf8'}));
      hashOnly = hashOnlyForPackages(read(base),read(head),packageNames);
    }
    plan = classify(files, hashOnly);
    console.log(`Changed files: ${files.join(', ')}; plan: ${JSON.stringify(plan)}`);
  } catch (error) {
    console.log(`Full manual/fallback run: ${error.message}`);
    plan = { core: true, doctor: true, docs: true, packages: readdirSync('packages', {withFileTypes:true}).filter(x => x.isDirectory() && /^[a-z0-9-]+$/.test(x.name)).map(x => x.name) };
  }
  const matrix = packageMatrix(plan.packages);
  appendFileSync(process.env.GITHUB_OUTPUT, `core=${plan.core}\ndoctor=${plan.doctor}\ndocs=${plan.docs}\npackages=${matrix.length > 0}\npackage_matrix=${JSON.stringify({include:matrix})}\n`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
