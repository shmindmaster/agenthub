import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { isAbsolute, relative, resolve } from 'node:path';

export const PROFILES = Object.freeze({
  'briefing-board': { width: 1600, height: 1000, fps: 30 },
  onboarding: { width: 1600, height: 1000, fps: 30 },
  'youtube-16x9': { width: 1920, height: 1080, fps: 30 },
  linkedin: { width: 1920, height: 1080, fps: 30 },
  'linkedin-4x5': { width: 1080, height: 1350, fps: 30 },
  'square-1x1': { width: 1080, height: 1080, fps: 30 },
  'vertical-9x16': { width: 1080, height: 1920, fps: 30 },
  presentation: { width: 1920, height: 1080, fps: 30 },
  webcast: { width: 1920, height: 1080, fps: 30 },
});
export const CAMPAIGN_FORMS = Object.freeze({
  'campaign-flagship': [60, 70],
  'campaign-comparison': [60, 80],
  'campaign-short': [10, 20],
  'campaign-outreach': [70, 80],
});

export function frameFor(job) {
  const profile = job.deliveryProfile || 'briefing-board';
  const frame = PROFILES[profile];
  if (!frame) throw new Error(`unknown deliveryProfile ${profile}`);
  return { profile, ...frame };
}

// Source coordinates are fractions of the receipt-bound capture, independent of its pixel size.
// One filter is shared by composition and encoded-source comparison so a crop cannot weaken binding.
export function sourceRegionError(region) {
  if (region == null) return null;
  const values = [region.x, region.y, region.width, region.height];
  if (values.some((value) => !Number.isFinite(value)) || region.x < 0 || region.y < 0 || region.width < .1 || region.height < .1 || region.x + region.width > 1.000001 || region.y + region.height > 1.000001) return 'sourceRegion must be a bounded normalized rectangle with width and height at least 0.1.';
  return null;
}

export function sourcePictureFilter(region, frame) {
  const error = sourceRegionError(region);
  if (error) throw new Error(error);
  const crop = region ? `crop=iw*${region.width}:ih*${region.height}:iw*${region.x}:ih*${region.y},` : '';
  return `${crop}scale=${frame.width}:${frame.height}:force_original_aspect_ratio=decrease,pad=${frame.width}:${frame.height}:(ow-iw)/2:(oh-ih)/2`;
}

export function probeVideo(file) {
  const data = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_type,width,height:format=duration', '-of', 'json', file], { encoding: 'utf8' }));
  const video = data.streams?.find((stream) => stream.codec_type === 'video');
  return { width: Number(video?.width), height: Number(video?.height), duration: Number(data.format?.duration) };
}

function validateCampaignFile(rootPath, ref, label, errors) {
  if (!ref?.path || !/^[a-f0-9]{64}$/i.test(ref.sha256 || '')) { errors.push(`${label} requires path and SHA-256.`); return null; }
  const file = resolve(rootPath, ref.path);
  const rel = relative(rootPath, file);
  if (isAbsolute(rel) || rel === '..' || rel.startsWith('../') || rel.startsWith('..\\')) { errors.push(`${label} escapes the external job workspace.`); return null; }
  if (!existsSync(file)) { errors.push(`${label} file is missing.`); return null; }
  const actual = createHash('sha256').update(readFileSync(file)).digest('hex');
  if (actual !== ref.sha256.toLowerCase()) errors.push(`${label} SHA-256 does not match the file.`);
  return file;
}

function validateCampaignContinuity(rootPath, continuity, segmentIds, errors) {
  const proofPath = resolve(rootPath, 'evidence/demo-scenario-proof.json');
  const proof = existsSync(proofPath) ? JSON.parse(readFileSync(proofPath, 'utf8')) : null;
  if (!proof) errors.push('campaign requires evidence/demo-scenario-proof.json for record continuity.');
  const provenRecordIds = new Set((proof?.continuity?.entities || []).map((entity) => entity.id));
  if (continuity?.mode === 'single-record') {
    if (!continuity.recordId || !continuity.scenarioId) errors.push('single-record continuity requires recordId and scenarioId.');
    if (proof && (proof.scenarioId !== continuity.scenarioId || !provenRecordIds.has(continuity.recordId))) errors.push('single-record continuity differs from the proven scenario or record.');
    const boardPath = resolve(rootPath, 'story/storyboard.json');
    if (existsSync(boardPath) && JSON.parse(readFileSync(boardPath, 'utf8')).scenarioId !== continuity.scenarioId) errors.push('single-record scenarioId differs from the storyboard.');
  } else if (continuity?.mode === 'labeled-vignettes') {
    const vignettes = continuity.vignettes;
    if (!Array.isArray(vignettes) || vignettes.length < 2) errors.push('labeled-vignettes requires at least two labeled records.');
    const seen = new Set();
    for (const vignette of vignettes || []) {
      if (!vignette.id || !vignette.label || !vignette.recordId || !Array.isArray(vignette.segmentIds) || !vignette.segmentIds.length) errors.push('each vignette needs id, visible label, recordId, and segmentIds.');
      for (const id of vignette.segmentIds || []) { if (!segmentIds.has(id) || seen.has(id)) errors.push(`vignette segment ${id} is missing or duplicated.`); seen.add(id); }
      if (proof && !provenRecordIds.has(vignette.recordId)) errors.push(`vignette ${vignette.id} record is outside the proven scenario.`);
    }
    if (segmentIds.size && seen.size !== segmentIds.size) errors.push('every campaign segment must belong to one labeled vignette.');
    if (new Set((vignettes || []).map((v) => v.recordId)).size !== (vignettes || []).length) errors.push('labeled vignettes must name distinct records.');
  } else errors.push('campaign continuity mode must be single-record or labeled-vignettes.');
}

function validateCampaignClaims(rootPath, claims, segmentIds, errors) {
  if (!Array.isArray(claims) || !claims.length) errors.push('campaign requires dated claims.');
  for (const claim of claims || []) {
    if (!claim.id || !claim.text || !/^\d{4}-\d{2}-\d{2}$/.test(claim.asOf || '') || !Number.isFinite(Date.parse(claim.asOf)) || Date.parse(claim.asOf) > Date.now()) errors.push(`claim ${claim.id || '?'} needs text and a valid, nonfuture asOf date.`);
    if (!Array.isArray(claim.segmentIds) || !claim.segmentIds.length || claim.segmentIds.some((id) => !segmentIds.has(id))) errors.push(`claim ${claim.id || '?'} must cite campaign segmentIds.`);
    validateCampaignFile(rootPath, claim.evidence, `claim ${claim.id || '?'} evidence`, errors);
  }
}

function validateCampaignAssets(rootPath, campaignAssets, errors) {
  const assets = new Map();
  const assetFiles = new Map();
  if (!Array.isArray(campaignAssets) || !campaignAssets.length) errors.push('campaign requires asset provenance.');
  for (const asset of campaignAssets || []) {
    if (!asset.id || !asset.origin || !asset.rights || !['captured-ui', 'authored-graphic', 'licensed', 'generated'].includes(asset.origin)) errors.push(`asset ${asset.id || '?'} needs origin and rights.`);
    const file = validateCampaignFile(rootPath, asset, `asset ${asset.id || '?'}`, errors);
    if (file) assetFiles.set(file, asset);
    if (assets.has(asset.id)) errors.push(`duplicate asset id ${asset.id}.`);
    assets.set(asset.id, asset);
  }
  return { assets, assetFiles };
}

function validateCampaignCaptureProvenance(rootPath, segments, segmentIds, assetFiles, errors) {
  // Match the compositor's segment/scene assignment. Only clips that enter the picture
  // (including extras) are required; unused captured takes may remain in the manifest.
  const manifestPath = resolve(rootPath, 'capture/manifest.json');
  if (!existsSync(manifestPath)) errors.push('campaign requires capture/manifest.json to verify source asset provenance.');
  else {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    const raw = manifest.composeClips || manifest.clips || manifest.entries || manifest.captures || [];
    const clips = raw.map((clip) => {
      const id = clip.id || clip.scenario || clip.storyboardSegmentId;
      let file = clip.file || clip.clip || clip.video || clip.output;
      if (!file) for (const ext of ['webm', 'mp4', 'png']) {
        const candidate = resolve(rootPath, 'capture', 'clips', `${id}.${ext}`);
        if (existsSync(candidate)) { file = `clips/${id}.${ext}`; break; }
      }
      return { ...clip, id, file, segments: clip.segments || [clip.storyboardSegmentId] };
    }).filter((clip) => clip.file);
    const bySegment = new Map(), byScene = new Map(), sceneQueue = new Map();
    for (const segment of segments) {
      const scene = segment.scene;
      if (!byScene.has(scene)) byScene.set(scene, []);
      byScene.get(scene).push(segment.id);
    }
    for (const clip of clips) for (const key of clip.segments || []) {
      if (!key) continue;
      if (segmentIds.has(key)) { bySegment.set(key, clip); continue; }
      const scene = String(key).replace(/[a-z]$/, '');
      const targets = byScene.get(scene) || byScene.get(key) || [];
      if (!targets.length) continue;
      const index = sceneQueue.get(scene) || 0; sceneQueue.set(scene, index + 1);
      const target = targets[Math.min(index, targets.length - 1)];
      if (bySegment.has(target) && bySegment.get(target) !== clip) {
        const previous = bySegment.get(target);
        previous.extras = [...(previous.extras || []), clip];
      } else bySegment.set(target, clip);
    }
    const boardPath = resolve(rootPath, 'story/storyboard.json');
    const screenplayPath = resolve(rootPath, 'story/screenplay.json');
    const board = existsSync(boardPath) ? JSON.parse(readFileSync(boardPath, 'utf8')) : {};
    const beats = board.beats || board.scenes || [];
    const screenplay = existsSync(screenplayPath) ? JSON.parse(readFileSync(screenplayPath, 'utf8')) : {};
    const screenplayModes = new Map((screenplay.scenes || []).map((scene) => [scene.id, scene.visualMode]));
    const cardModes = new Set(['card', 'slide', 'diagram', 'talking-head', 'motif', 'animation', 'narration-only', 'broll']);
    const isScreen = (id) => {
      const beat = beats.find((item) => item.id === id || (item.segments || []).includes(id));
      const mode = beat?.visualMode || screenplayModes.get(id) || screenplayModes.get(String(id).replace(/[a-z]+$/, '')) || 'screen';
      return !cardModes.has(mode);
    };
    const used = new Map();
    for (const [id, clip] of bySegment) for (const source of [clip, ...(clip.extras || [])]) {
      if (!used.has(source)) used.set(source, new Set());
      used.get(source).add(id);
    }
    for (const [clip, ids] of used) {
      const source = resolve(rootPath, 'capture', clip.file);
      const rel = relative(rootPath, source);
      if (isAbsolute(rel) || rel === '..' || rel.startsWith('../') || rel.startsWith('..\\')) errors.push(`capture clip ${clip.id} escapes the external job workspace.`);
      else if (!assetFiles.has(source)) errors.push(`used capture clip ${clip.id} (${clip.file}) is missing from campaign asset provenance.`);
      else if ([...ids].some(isScreen) && /\.(webm|mp4|mov)$/i.test(clip.file) && assetFiles.get(source).origin !== 'captured-ui') errors.push(`screen capture clip ${clip.id} must have captured-ui asset provenance.`);
    }
  }
}

function validateCampaignDerivative(rootPath, sourceJobId, derivative, campaignAssets, errors) {
  if (sourceJobId || derivative) {
    if (!sourceJobId || !derivative || derivative.parentJobId !== sourceJobId) errors.push('derivative parentJobId must match sourceJobId.');
    validateCampaignFile(rootPath, derivative?.parentCandidate, 'parent candidate', errors);
    if (!Array.isArray(derivative?.sourceAssets) || !derivative.sourceAssets.length) errors.push('derivative requires source asset hashes.');
    for (const [index, asset] of (derivative?.sourceAssets || []).entries()) {
      validateCampaignFile(rootPath, asset, `derivative source asset ${index + 1}`, errors);
      if (!(campaignAssets || []).some((item) => item.path === asset.path && item.sha256?.toLowerCase() === asset.sha256?.toLowerCase())) errors.push(`derivative source asset ${index + 1} is not recorded in campaign asset provenance.`);
    }
    for (const asset of (campaignAssets || []).filter((item) => item.origin === 'captured-ui')) if (!(derivative?.sourceAssets || []).some((source) => source.path === asset.path && source.sha256?.toLowerCase() === asset.sha256?.toLowerCase())) errors.push(`captured UI asset ${asset.id} is missing from derivative source lineage.`);
  }
}

function validateCampaignGeometry(frame, campaign, timeline, graphics, assets, errors) {
  const safe = { left: Math.ceil(frame.width * .05), right: Math.ceil(frame.width * .05), top: Math.ceil(frame.height * .08), bottom: Math.ceil(frame.height * (frame.height > frame.width ? .20 : .12)) };
  const rects = campaign.protectedRegions || [];
  for (const rect of rects) if (![rect.x, rect.y, rect.width, rect.height].every(Number.isFinite) || rect.width <= 0 || rect.height <= 0 || rect.x < 0 || rect.y < 0 || rect.x + rect.width > frame.width || rect.y + rect.height > frame.height) errors.push('protectedRegion must be a valid rectangle in the delivery frame.');
  const overlaps = (a, b) => a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
  const caption = campaign.captionRegion;
  if (frame.height > frame.width && !caption) errors.push('portrait campaign requires captionRegion in the delivery frame.');
  if (caption) {
    if (![caption.x, caption.y, caption.width, caption.height].every(Number.isFinite) || caption.width <= 0 || caption.height <= 0 || caption.x < safe.left || caption.y < safe.top || caption.x + caption.width > frame.width - safe.right || caption.y + caption.height > frame.height - safe.bottom) errors.push('captionRegion crosses the delivery-profile safe area.');
    if (rects.some((rect) => overlaps(caption, rect))) errors.push('captionRegion covers a declared product control.');
  }
  for (const [index, graphic] of graphics.entries()) {
    const label = `timed graphic ${index + 1}`;
    if (!assets.has(graphic.assetId)) errors.push(`${label} has no provenanced asset.`);
    else if (!/\.png$/i.test(assets.get(graphic.assetId).path)) errors.push(`${label} must use a transparent PNG asset.`);
    if (![graphic.x, graphic.y, graphic.width, graphic.height, graphic.startSeconds, graphic.endSeconds].every(Number.isFinite) || graphic.width <= 0 || graphic.height <= 0 || graphic.startSeconds < 0 || graphic.endSeconds <= graphic.startSeconds || graphic.endSeconds > timeline.durationSeconds) { errors.push(`${label} has invalid size or timing.`); continue; }
    if (graphic.x < safe.left || graphic.y < safe.top || graphic.x + graphic.width > frame.width - safe.right || graphic.y + graphic.height > frame.height - safe.bottom) errors.push(`${label} crosses the ${frame.profile} safe area.`);
    if (rects.some((rect) => overlaps(graphic, rect))) errors.push(`${label} covers a declared product control.`);
    if (caption && overlaps(graphic, caption)) errors.push(`${label} covers the captionRegion.`);
  }
  if (graphics.length && (!Array.isArray(rects) || !rects.length)) errors.push('timed graphics require protectedRegions for visible product controls.');
}

function validateCampaignVignetteTiming(continuity, segments, graphics, errors) {
  if (continuity?.mode === 'labeled-vignettes') {
    for (const vignette of continuity.vignettes || []) {
      const labels = graphics.filter((graphic) => graphic.vignetteId === vignette.id && graphic.visibleLabel === vignette.label);
      if (!labels.length) { errors.push(`vignette ${vignette.id} needs a timed, visible label graphic.`); continue; }
      for (const id of vignette.segmentIds || []) {
        const segment = segments.find((item) => item.id === id);
        if (!segment || !Number.isFinite(segment.startSeconds) || !Number.isFinite(segment.durationSeconds) || segment.durationSeconds <= 0) { errors.push(`vignette ${vignette.id} segment ${id} needs valid timeline timing.`); continue; }
        const start = segment.startSeconds;
        const labelUntil = start + Math.min(1.5, segment.durationSeconds);
        if (!labels.some((graphic) => graphic.startSeconds <= start && graphic.endSeconds >= labelUntil)) errors.push(`vignette ${vignette.id} label must cover the opening of segment ${id}.`);
        if (graphics.some((graphic) => graphic.vignetteId && graphic.vignetteId !== vignette.id && graphic.startSeconds < start + segment.durationSeconds && graphic.endSeconds > start)) errors.push(`vignette ${vignette.id} segment ${id} overlaps another vignette label.`);
      }
    }
  }
}

export function validateCampaign(root, job, timeline, graphics = []) {
  const errors = [];
  const form = job.programForm;
  if (!Object.hasOwn(CAMPAIGN_FORMS, form)) return errors;
  const campaign = job.campaign;
  if (job.kind !== 'product-screencast') errors.push(`${form} requires kind product-screencast.`);
  if (!campaign || typeof campaign !== 'object') return [...errors, 'campaign contract is required.'];
  if (!job.deliveryProfile) errors.push('campaign requires an explicit deliveryProfile.');
  if (!Array.isArray(graphics)) return [...errors, 'timed-graphics.json overlays must be an array.'];
  const frame = frameFor(job);
  const range = CAMPAIGN_FORMS[form];
  if (!Number.isFinite(timeline?.durationSeconds) || timeline.durationSeconds < range[0] || timeline.durationSeconds > range[1]) errors.push(`${form} timeline must be ${range[0]}–${range[1]} seconds.`);
  const segments = timeline?.segments || [];
  const segmentIds = new Set(segments.map((s) => s.id));
  const rootPath = resolve(root);
  const continuity = campaign.continuity;
  validateCampaignContinuity(rootPath, continuity, segmentIds, errors);
  validateCampaignClaims(rootPath, campaign.claims, segmentIds, errors);
  const { assets, assetFiles } = validateCampaignAssets(rootPath, campaign.assets, errors);
  validateCampaignCaptureProvenance(rootPath, segments, segmentIds, assetFiles, errors);
  validateCampaignDerivative(rootPath, job.sourceJobId, campaign.derivative, campaign.assets, errors);
  validateCampaignGeometry(frame, campaign, timeline, graphics, assets, errors);
  validateCampaignVignetteTiming(continuity, segments, graphics, errors);
  return errors;
}
