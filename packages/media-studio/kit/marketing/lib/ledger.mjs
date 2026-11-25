// Cost ledger and budget cap. Every paid provider call is checked BEFORE it is made (projected spend against the
// per-run cap and the brand's cumulative cap) and recorded AFTER. ElevenLabs is counted in credits (the
// shared content ledger is the authority; this mirrors it for the run manifest); every other provider is counted in USD
// against its own cap, so a Deepgram or Runware charge can never eat the OpenAI cap.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { writeJson } from './util.mjs';

export class BudgetError extends Error {
  constructor(message, details) { super(message); this.name = 'BudgetError'; this.details = details; }
}

/**
 * Every provider a run can be charged under. `cap` is the budget key (per-run and brand cumulative). `legacy` marks the two
 * providers that have always run without a configured cap (their behaviour is unchanged); any other spending provider with
 * no cap configured refuses new spend. A provider with `cap: null` never spends (a human recording, licensed stock): it
 * only appears in cached, zero-unit rows.
 */
export const PROVIDERS = Object.freeze({
  elevenlabs: { unit: 'credits', cap: 'elevenlabsCredits', legacy: true },
  openai: { unit: 'usd', cap: 'openaiUsd', legacy: true },
  assemblyai: { unit: 'usd', cap: 'assemblyaiUsd' },
  deepgram: { unit: 'usd', cap: 'deepgramUsd' },
  runware: { unit: 'usd', cap: 'runwareUsd' },
  azure: { unit: 'usd', cap: 'azureUsd' },
  recording: { unit: 'usd', cap: null },
  licensed: { unit: 'usd', cap: null },
});
/** Budget keys a brand or spec may carry, one per spending provider. */
export const CAP_KEYS = Object.freeze(Object.values(PROVIDERS).map((p) => p.cap).filter(Boolean));

function providerInfo(provider) {
  const info = Object.hasOwn(PROVIDERS, provider) ? PROVIDERS[provider] : null;
  if (!info) throw new Error(`unknown cost provider "${provider}" (known: ${Object.keys(PROVIDERS).join(', ')})`);
  return info;
}

export class CostLedger {
  /**
   * @param {object} o
   * @param {string} o.jobDir job folder; the run ledger is <jobDir>/cost-ledger.json
   * @param {string} [o.cumulativePath] jsonl shared by every run of the brand (cross-run cap)
   * @param {Record<string, number>} o.perRun budget keys from CAP_KEYS (elevenlabsCredits, openaiUsd, assemblyaiUsd, ...)
   * @param {Record<string, number>} o.cumulative same keys, brand-wide
   * @param {string} o.runId
   */
  constructor(o) {
    this.jobDir = o.jobDir;
    this.path = join(o.jobDir, 'cost-ledger.json');
    this.cumulativePath = o.cumulativePath || null;
    this.perRun = o.perRun || {};
    this.cumulative = o.cumulative || {};
    this.runId = o.runId;
    this.entries = [];
    if (existsSync(this.path)) {
      try { this.entries = JSON.parse(readFileSync(this.path, 'utf8')).entries.filter((e) => e.run === o.runId); } catch { this.entries = []; }
    }
  }

  static capKey(provider) { return providerInfo(provider).cap; }

  runTotal(provider) {
    return this.entries.filter((e) => e.provider === provider && !e.cached).reduce((s, e) => s + e.units, 0);
  }

  cumulativeTotal(provider) {
    if (!this.cumulativePath || !existsSync(this.cumulativePath)) return this.runTotal(provider);
    let total = 0;
    for (const line of readFileSync(this.cumulativePath, 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { const e = JSON.parse(line); if (e.provider === provider && !e.cached) total += e.units; } catch { /* ignore a torn line */ }
    }
    return total;
  }

  /** Throw BudgetError unless `units` more of `provider` fits both caps. Call before every paid request. */
  check(provider, units, what = '') {
    const info = providerInfo(provider);
    if (!(units >= 0)) throw new BudgetError(`invalid spend estimate for ${provider}`);
    const key = info.cap;
    if (units > 0 && !key) throw new BudgetError(`${provider} is not a spending provider; it cannot be charged${what ? ` for ${what}` : ''}`);
    if (units > 0 && !info.legacy && this.perRun[key] === undefined && this.cumulative[key] === undefined) {
      throw new BudgetError(`no ${key} budget is configured, so new ${provider} spend${what ? ` (${what})` : ''} is refused: set budgets.${key} (or budgets.perRun.${key}) in the brand file or budget.${key} in the spec`, { scope: 'unconfigured', cap: key });
    }
    const run = this.runTotal(provider);
    const cum = this.cumulativeTotal(provider);
    const runCap = key ? this.perRun[key] : undefined;
    const cumCap = key ? this.cumulative[key] : undefined;
    if (runCap !== undefined && run + units > runCap) throw new BudgetError(`per-run ${provider} budget exceeded${what ? ` by ${what}` : ''}: ${run} + ${units} > ${runCap} ${info.unit}`, { run, units, cap: runCap, scope: 'run' });
    if (cumCap !== undefined && cum + units > cumCap) throw new BudgetError(`cumulative ${provider} budget exceeded${what ? ` by ${what}` : ''}: ${cum} + ${units} > ${cumCap} ${info.unit}`, { cum, units, cap: cumCap, scope: 'cumulative' });
    return { run, cumulative: cum };
  }

  /** Record a charge (estimated or actual). Cached/reused work is recorded with units 0 and cached: true. */
  charge(entry) {
    const info = providerInfo(entry.provider);
    // Estimated or actual, a charge must be a finite, non-negative number; cached rows are recorded as zero whatever they carry.
    const units = entry.units == null || entry.units === '' ? NaN : Number(entry.units);
    if (!entry.cached && !(Number.isFinite(units) && units >= 0)) throw new BudgetError(`invalid units ${String(entry.units)} for ${entry.provider}/${entry.service}: a charge must be a finite number of at least 0`);
    if (!entry.cached && units > 0 && !info.cap) throw new BudgetError(`${entry.provider} is not a spending provider; it cannot be charged`);
    const row = {
      at: new Date().toISOString(), run: this.runId, stage: entry.stage, provider: entry.provider, service: entry.service,
      unit: info.unit, units: entry.cached ? 0 : units, estimated: entry.estimated !== false,
      cached: !!entry.cached, ref: entry.ref || null, note: entry.note || null,
      ...(entry.paidElsewhere ? { paidElsewhere: { usdMicros: entry.paidElsewhere.usdMicros ?? null, estimated: entry.paidElsewhere.estimated ?? null } } : {}),
    };
    this.entries.push(row);
    this.persist(row);
    return row;
  }

  persist(row) {
    mkdirSync(dirname(this.path), { recursive: true });
    writeJson(this.path, { runId: this.runId, summary: this.summary(), entries: this.entries });
    if (this.cumulativePath && !row.cached && row.units > 0) {
      mkdirSync(dirname(this.cumulativePath), { recursive: true });
      appendFileSync(this.cumulativePath, `${JSON.stringify(row)}\n`, 'utf8');
    }
  }

  summary() {
    const by = {};
    for (const e of this.entries) {
      const k = `${e.provider}/${e.service}`;
      by[k] ||= { units: 0, unit: e.unit, calls: 0, cachedCalls: 0 };
      by[k].units = Number((by[k].units + e.units).toFixed(4));
      by[k][e.cached ? 'cachedCalls' : 'calls'] += 1;
    }
    const byProvider = {};
    for (const [name, info] of Object.entries(PROVIDERS)) {
      byProvider[name] = {
        unit: info.unit, units: Number(this.runTotal(name).toFixed(4)),
        calls: this.entries.filter((e) => e.provider === name && !e.cached).length,
        cachedCalls: this.entries.filter((e) => e.provider === name && e.cached).length,
      };
    }
    // Imported work is settled by the governed script's own ledger; here it stays zero-cost, but what it cost is recorded.
    const elsewhere = this.entries.filter((e) => e.paidElsewhere);
    const paidElsewhere = {
      usdMicros: elsewhere.reduce((sum, e) => sum + (e.paidElsewhere.usdMicros ?? 0), 0),
      estimated: elsewhere.some((e) => e.paidElsewhere.estimated !== false),
      unknownRows: elsewhere.filter((e) => e.paidElsewhere.usdMicros === null).length,
    };
    return {
      elevenlabsCredits: this.runTotal('elevenlabs'),
      openaiUsd: Number(this.runTotal('openai').toFixed(4)),
      perRunCap: this.perRun,
      cumulativeCap: this.cumulative,
      byService: by,
      byProvider,
      paidElsewhere,
    };
  }
}
