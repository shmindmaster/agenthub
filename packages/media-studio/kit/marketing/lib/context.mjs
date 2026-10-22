// Run context for one mvg invocation: spec, brand, workspace paths, cost ledger, injectable providers.
import { existsSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CostLedger } from './ledger.mjs';
import { fileSha, readJson, writeJson } from './util.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const MODULE_ROOT = resolve(here, '..');

export function loadContext({ specPath, flags = {}, providers = {}, now = new Date() }) {
  const spec = readJson(specPath);
  const specDir = dirname(resolve(specPath));
  const brandPath = spec.brand ? (isAbsolute(spec.brand) ? spec.brand : resolve(specDir, spec.brand)) : resolve(specDir, '..', 'brand', 'brand.json');
  if (!existsSync(brandPath)) throw new Error(`brand file not found: ${brandPath}`);
  const brand = readJson(brandPath);
  if (flags.qaDir && (flags.only || flags.stage) !== 'qa') throw new Error('--qa-dir is only valid for isolated QA');
  if (flags.qaDir && !flags.noVision && (flags.visionProvider || brand.vision?.provider || 'local') !== 'local') throw new Error('read-only external QA requires local vision; paid QA would modify the source cumulative spend ledger');
  const workspace = flags.workspace ? resolve(flags.workspace) : resolve(specDir, '..');
  const jobDir = join(workspace, 'jobs', spec.id);
  const runId = `${now.toISOString().replace(/[:.]/g, '-')}`;
  const perRun = { ...(brand.budgets?.perRun || {}), ...(spec.budget || {}) };
  const ledger = new CostLedger({
    jobDir: flags.qaDir ? resolve(flags.qaDir) : jobDir, runId, perRun,
    cumulative: { elevenlabsCredits: brand.budgets?.elevenlabsCredits, openaiUsd: brand.budgets?.openaiUsd },
    cumulativePath: join(workspace, '_spend', 'ledger.jsonl'),
  });
  return {
    spec, brand, specPath: resolve(specPath), specDir, brandPath, workspace, jobDir, runId, ledger, flags,
    adSchema: readJson(join(MODULE_ROOT, 'ad.schema.json')),
    brandSchema: readJson(join(MODULE_ROOT, 'brand.schema.json')),
    specSha: fileSha(resolve(specPath)), brandSha: fileSha(brandPath),
    providers,
    log: flags.quiet ? () => {} : (m) => console.error(`[mvg] ${m}`),
    workspaceId: `mvg:${brand.id}`,
  };
}

export function recordStage(ctx, stage, status, detail = {}) {
  const path = join(ctx.jobDir, 'manifest.json');
  const manifest = existsSync(path) ? readJson(path) : { specId: ctx.spec.id, stages: {} };
  manifest.specId = ctx.spec.id;
  manifest.specSha256 = ctx.specSha;
  manifest.brandSha256 = ctx.brandSha;
  manifest.stages[stage] = { status, at: new Date().toISOString(), runId: ctx.runId, ...detail };
  manifest.cost = ctx.ledger.summary();
  writeJson(path, manifest);
  return manifest;
}
