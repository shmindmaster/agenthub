import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkg = join(dirname(fileURLToPath(import.meta.url)), '..');
const validator = join(pkg, 'scripts', 'validate-capture-manifest.mjs');

// A per-shot manifest that satisfies every rule in the validator.
function shot() {
  return {
    scenario: 'S01-checkout',
    storyboardSegmentId: 'seg-01',
    route: '/checkout',
    viewport: { width: 1280, height: 720, deviceScaleFactor: 2 },
    captureSurface: {
      mode: 'page-only',
      extraneousChrome: 'none',
      irrelevantNavigation: 'hidden',
      plannedTreatment: 'native-full-frame',
      plannedActiveRegionCoverage: 0.8,
      deliveryLegibility: 'pass',
      deliveryFrame: { width: 1280, height: 720 },
      deliveredCrop: { x: 0, y: 0, width: 1280, height: 720 },
      sourceFrame: { width: 2560, height: 1440 },
      smallDelivery: false,
      browserZoomPercent: 100,
    },
    focus: { x: 0, y: 0, width: 100, height: 100 },
    interaction: {
      kind: 'click',
      target: 'Save button',
      cursor: {
        park: [10, 10], from: [100, 100], to: [200, 200], durationMs: 500,
        easing: 'eased-deceleration', scale: 1.2, settleBeforeActionMs: 300, holdAfterActionMs: 600,
      },
      cue: 'visual',
      feedback: { type: 'radial-pulse', durationMs: 350, brandColor: '#2563eb', opacity: 0.5 },
      keystrokeOverlay: false,
      pacing: { activity: 'meaningful-action', treatment: 'real-time', multiplier: 1, truthTreatment: 'real-time' },
      narrationSync: { cursorLeadSeconds: 0.5, actionAtSeconds: 2, resultVisibleAtSeconds: 2.5, spokenResultAtSeconds: 3 },
    },
  };
}

// A clips object as written to capture/receipt.json by record-job.mjs: no scenario, beat or captures.
function clipsManifest() {
  return {
    schemaVersion: '1.0.0',
    generator: 'media-studio/record-job',
    clips: {
      'S01-checkout': { ratio: '16:9', device: 'desktop', viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 },
    },
  };
}

function runValidator(manifest) {
  const dir = mkdtempSync(join(tmpdir(), 'capture-manifest-'));
  try {
    const file = join(dir, 'manifest.json');
    writeFileSync(file, JSON.stringify(manifest));
    return spawnSync(process.execPath, [validator, file], { encoding: 'utf8' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a clips manifest gets one clear error that names the next step, and exits 1', () => {
  const result = runValidator(clipsManifest());
  const errors = result.stderr.split('\n').filter(line => line.startsWith('[error]'));
  assert.equal(result.status, 1, result.stderr);
  assert.equal(errors.length, 1, `expected one error, got:\n${result.stderr}`);
  assert.match(errors[0], /clips manifest/);
  assert.match(errors[0], /capture\/receipt\.json/);
  assert.match(errors[0], /validate-product-picture\.mjs/);
  assert.match(errors[0], /validate-edit-map\.mjs/);
  assert.doesNotMatch(result.stderr, /missing "scenario"/);
});

test('a valid per-shot manifest passes', () => {
  const result = runValidator(shot());
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /1 manifest\(s\) checked: 0 error\(s\)\./);
});

test('a per-shot manifest that lacks a required field still fails', () => {
  const manifest = shot();
  delete manifest.route;
  const result = runValidator(manifest);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /\[error\] S01-checkout: missing "route"\./);
});
