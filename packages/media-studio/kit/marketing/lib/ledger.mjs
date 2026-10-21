// Cost ledger and budget cap. Every paid provider call is checked BEFORE it is made (projected spend against the
// per-run cap and the brand's cumulative cap) and recorded AFTER. ElevenLabs is counted in credits (its own
// governed ledger in packages/elevenlabs is the authority; this mirrors it for the run manifest), OpenAI in USD.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { writeJson } from './util.mjs';

export class BudgetError extends Error {
  constructor(message, details) { super(message); this.name = 'BudgetError'; this.details = details; }
}

export const UNIT = { elevenlabs: 'credits', openai: 'usd' };

export class CostLedger {
  /**
   * @param {object} o
   * @param {string} o.jobDir job folder; the run ledger is <jobDir>/cost-ledger.json
   * @param {string} [o.cumulativePath] jsonl shared by every run of the brand (cross-run cap)
   * @param {{elevenlabsCredits?:number, openaiUsd?:number}} o.perRun
   * @param {{elevenlabsCredits?:number, openaiUsd?:number}} o.cumulative
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

  static capKey(provider) { return provider === 'elevenlabs' ? 'elevenlabsCredits' : 'openaiUsd'; }

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
    if (!(units >= 0)) throw new BudgetError(`invalid spend estimate for ${provider}`);
    const key = CostLedger.capKey(provider);
    const run = this.runTotal(provider);
    const cum = this.cumulativeTotal(provider);
    const runCap = this.perRun[key];
    const cumCap = this.cumulative[key];
    if (runCap !== undefined && run + units > runCap) throw new BudgetError(`per-run ${provider} budget exceeded${what ? ` by ${what}` : ''}: ${run} + ${units} > ${runCap} ${UNIT[provider]}`, { run, units, cap: runCap, scope: 'run' });
    if (cumCap !== undefined && cum + units > cumCap) throw new BudgetError(`cumulative ${provider} budget exceeded${what ? ` by ${what}` : ''}: ${cum} + ${units} > ${cumCap} ${UNIT[provider]}`, { cum, units, cap: cumCap, scope: 'cumulative' });
    return { run, cumulative: cum };
  }

  /** Record a charge (estimated or actual). Cached/reused work is recorded with units 0 and cached: true. */
  charge(entry) {
    const row = {
      at: new Date().toISOString(), run: this.runId, stage: entry.stage, provider: entry.provider, service: entry.service,
      unit: UNIT[entry.provider], units: entry.cached ? 0 : Number(entry.units), estimated: entry.estimated !== false,
      cached: !!entry.cached, ref: entry.ref || null, note: entry.note || null,
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
    return {
      elevenlabsCredits: this.runTotal('elevenlabs'),
      openaiUsd: Number(this.runTotal('openai').toFixed(4)),
      perRunCap: this.perRun,
      cumulativeCap: this.cumulative,
      byService: by,
    };
  }
}
