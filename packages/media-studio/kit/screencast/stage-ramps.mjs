// Screen stage speed ramps of one clip: the typing spans found in its captured frames plus any the author declared. One function,
// used by the cue sheet (plan mode), the compose step and the encoded-film gate, so all three see the same time map before the
// narration is aligned. Contract: skills/studio/references/screen-stage.md.
import path from 'node:path';
import { typingSpans } from './stage-changes.mjs';
import { RAMP_SECONDS } from './sync-lib.mjs';

/**
 * @param jobRoot    the job workspace
 * @param entry      the clip's capture receipt entry (actions, viewport, stage.framesIndex)
 * @param index      parsed frames index { frames: [{ t, file }] } of the clip
 * @param id         clip id
 * @param cfg        job.screenStage ({ typingSpeed?: number | false })
 * @param manual     manifest clip `speedSpans`: [{ from, to, speed, reason }] in source seconds
 */
export function stageRamps({ jobRoot, entry, index, id, cfg = {}, manual = [] }) {
  const declared = [];
  for (const m of manual) {
    if (!(Number(m.speed) > 1) || !(Number(m.to) > Number(m.from))) throw new Error(`clip ${id}: speedSpans entries need from < to and speed > 1`);
    if (typeof m.reason !== 'string' || !m.reason.trim()) throw new Error(`clip ${id}: a speed span [${m.from}, ${m.to}] needs a reason (only real wait time or typing may be sped up)`);
    declared.push({ from: Number(m.from), to: Number(m.to), speed: Math.min(3, Number(m.speed)), reason: m.reason.trim() });
  }
  const typing = cfg.typingSpeed === false || cfg.typingSpeed === 1 ? [] : typingSpans({
    actions: entry.actions || [],
    frames: { times: index.frames.map((f) => f.t), files: index.frames.map((f) => path.join(jobRoot, 'capture', 'raw', id, 'frames', f.file)) },
    viewport: entry.viewport,
    speed: Number(cfg.typingSpeed) > 1 ? Number(cfg.typingSpeed) : 2,
  });
  const all = [...declared];
  for (const t of typing) if (!declared.some((d) => t.from < d.to && t.to > d.from)) all.push(t);
  return all.sort((a, b) => a.from - b.from).map((r) => ({ ...r, ramp: RAMP_SECONDS }));
}
