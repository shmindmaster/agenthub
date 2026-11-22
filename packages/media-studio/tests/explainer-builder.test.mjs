// The builder owns the clock. These tests pin that a shot lasts exactly as long
// as its cue, that beats resolve to spoken words, that a film which lands and
// cuts is refused, and that a failed build never writes props.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { buildExplainer, collectBeats, validatePlan } from '../kit/explainer/build-explainer.mjs';
import { build, clone, cueSheet, plan, receipts } from './fixtures/explainer/fixture.mjs';

const script = fileURLToPath(new URL('../kit/explainer/build-explainer.mjs', import.meta.url));

const errorsOf = (result) => (result.report?.errors ?? []).join('\n');

test('a six-shot film builds with contiguous frames, chapters and holds', () => {
  const result = build();
  assert.equal(result.ok, true, errorsOf(result));
  const { props } = result;
  assert.equal(props.shots.length, 6);
  assert.equal(props.totalSeconds, 26);
  assert.equal(props.film.chapters.length, 2);
  let frame = 0;
  for (const shot of props.shots) {
    assert.equal(shot.startFrame, frame);
    assert.ok(shot.durationFrames > 0);
    assert.ok(shot.holdSeconds >= 1, `${shot.id} hold ${shot.holdSeconds}`);
    frame += shot.durationFrames;
  }
  assert.equal(frame, 780);
  assert.equal(props.film.chapters[0].startFrame, 0);
  assert.equal(props.film.chapters[1].startFrame, props.film.chapters[0].endFrame);
  assert.equal(props.film.chapters[1].endFrame, 780);
});

test('a beat anchored to a spoken word lands on that word, before the shot ends', () => {
  const { props } = build();
  const payoff = props.shots.find((shot) => shot.id === 'f');
  assert.equal(payoff.beats.length, 1);
  const beat = payoff.beats[0];
  assert.ok(beat.atSeconds > 0.3 && beat.atSeconds < 1.2, `resolved to ${beat.atSeconds}`);
  assert.equal(beat.frame, Math.round(beat.atSeconds * 30));
  assert.ok(payoff.holdSeconds > 2);
});

test('beats are discovered in the visual tree with the path that carries them', () => {
  const beats = collectBeats({ kind: 'flow', nodes: [{ label: 'a', at: 0.5 }, { label: 'b', at: 1.5 }] });
  assert.deepEqual(beats.map((beat) => beat.atSeconds), [0.5, 1.5]);
  assert.match(beats[1].target, /nodes\[1\]/);
});

test('a missing shot, an orphan shot and a chapter out of order are all refused', () => {
  const missing = clone(plan);
  missing.shots = missing.shots.filter((shot) => shot.id !== 'c');
  missing.chapters[0].shots = missing.chapters[0].shots.filter((id) => id !== 'c');
  assert.match(validatePlan(missing, cueSheet).map((entry) => entry.code).join(','), /shot-missing/);

  const orphan = clone(plan);
  orphan.shots.push({ id: 'zz', archetype: 'cold-open', title: 'orphan' });
  assert.match(validatePlan(orphan, cueSheet).map((entry) => entry.code).join(','), /cue-missing/);

  const reordered = clone(plan);
  reordered.chapters[0].shots = ['b', 'a', 'c'];
  assert.match(validatePlan(reordered, cueSheet).map((entry) => entry.code).join(','), /chapter-order/);
});

test('an anchor with no spoken word fails the build and names the word', () => {
  const broken = clone(plan);
  broken.shots.find((shot) => shot.id === 'f').visual.at = '@Zeppelin';
  const result = buildExplainer({ cueSheet, receipts, plan: broken });
  assert.equal(result.ok, false);
  assert.match(errorsOf(result), /Zeppelin/);
  assert.equal(result.props, null);
});

test('a shot that lands and cuts is refused', () => {
  const broken = clone(plan);
  broken.shots.find((shot) => shot.id === 'b').visual.nodes[2].at = 4.0;
  const result = buildExplainer({ cueSheet, receipts, plan: broken });
  assert.equal(result.ok, false);
  assert.match(errorsOf(result), /lands and cuts/);
});

test('a beat after the end of its shot, and a first beat that is too late, are refused', () => {
  const after = clone(plan);
  after.shots.find((shot) => shot.id === 'b').visual.nodes[2].at = 4.45;
  assert.match(errorsOf(buildExplainer({ cueSheet, receipts, plan: after })), /at or after the end/);

  const late = clone(plan);
  late.shots.find((shot) => shot.id === 'b').visual.nodes[1].at = 2.1;
  late.shots.find((shot) => shot.id === 'b').visual.nodes[0].at = 2.4;
  late.shots.find((shot) => shot.id === 'b').visual.nodes[2].at = 2.9;
  assert.match(errorsOf(buildExplainer({ cueSheet, receipts, plan: late })), /hero does not appear/);
});

test('an unknown archetype or a visual its family cannot compose is refused', () => {
  const unknown = clone(plan);
  unknown.shots[0].archetype = 'talking-paper';
  assert.match(errorsOf(buildExplainer({ cueSheet, receipts, plan: unknown })), /archetype-known/);

  const wrong = clone(plan);
  wrong.shots.find((shot) => shot.id === 'c').visual = { kind: 'flow', nodes: [{ label: 'x' }] };
  assert.match(errorsOf(buildExplainer({ cueSheet, receipts, plan: wrong })), /visual-kind/);
});

test('a film of type-only frames reports the cap instead of shipping quietly', () => {
  const typed = clone(plan);
  const typedShot = typed.shots.find((shot) => shot.id === 'c');
  typedShot.archetype = 'kinetic-statement';
  delete typedShot.visual;
  const result = buildExplainer({ cueSheet, receipts, plan: typed });
  assert.equal(result.ok, true, errorsOf(result));
  assert.ok(result.report.warnings.some((warning) => /type-only/.test(warning)), result.report.warnings.join('\n'));
});

test('the CLI writes props and a report, and writes no props when it fails', () => {
  const root = mkdtempSync(join(tmpdir(), 'explainer-'));
  mkdirSync(join(root, 'story'), { recursive: true });
  mkdirSync(join(root, 'takes'), { recursive: true });
  writeFileSync(join(root, 'story/cue-sheet.json'), JSON.stringify(cueSheet));
  for (const cue of cueSheet.cues) {
    writeFileSync(join(root, 'takes', `${cue.id}.receipt.json`), JSON.stringify({ word_boundaries: receipts[cue.id] }));
  }
  writeFileSync(join(root, 'story/explainer-plan.json'), JSON.stringify(plan));

  const good = spawnSync(process.execPath, [script, root], { encoding: 'utf8', windowsHide: true });
  assert.equal(good.status, 0, good.stdout + good.stderr);
  assert.ok(existsSync(join(root, 'picture/explainer-props.json')));
  assert.ok(existsSync(join(root, 'picture/explainer-props.report.json')));
  const report = JSON.parse(readFileSync(join(root, 'picture/explainer-props.report.json'), 'utf8'));
  assert.equal(report.ok, true);

  const broken = clone(plan);
  broken.shots.find((shot) => shot.id === 'f').visual.at = '@Nope';
  writeFileSync(join(root, 'story/explainer-plan.json'), JSON.stringify(broken));
  const bad = spawnSync(process.execPath, [script, root], { encoding: 'utf8', windowsHide: true });
  assert.equal(bad.status, 1);
  assert.match(bad.stdout + bad.stderr, /Nope/);
});

test('a polyglot archetype takes the composition its visual asks for', () => {
  // diagram-build carries flow, layers or map in the catalogue. The layers
  // stack used to be unreachable: the shot resolved to mechanism whatever the
  // kind, so the only layer composition in the kit could not appear in a film.
  const layered = clone(plan);
  const shot = layered.shots.find((entry) => entry.id === 'b');
  shot.visual = {
    kind: 'layers',
    caption: 'revision over plan over commitments',
    layers: [
      { label: 'Revision', at: 0.6 },
      { label: 'Plan', at: 1.7 },
      { label: 'Commitments', at: 2.6, mark: 'risk' },
    ],
  };
  const result = build({ plan: layered });
  assert.equal(result.ok, true, errorsOf(result));
  const built = result.props.shots.find((entry) => entry.id === 'b');
  assert.equal(built.family, 'layers');
  assert.equal(built.visual.kind, 'layers');
});
