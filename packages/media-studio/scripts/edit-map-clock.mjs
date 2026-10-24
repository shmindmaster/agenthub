// A derived clock is never a new forced alignment. The source clock and its
// uncertainty survive the edit; verification decodes the declared graph.
import { createHash } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const lib = [join(here, 'sync-lib.mjs'), join(here, '../kit/screencast/sync-lib.mjs')].find(existsSync);
const { forcedWordOnsets, textWords, offsetStats } = await import(pathToFileURL(lib).href);
export const sha = p => createHash('sha256').update(readFileSync(p)).digest('hex');
const read = p => JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
export function bound(root, ref) {
  if (!ref?.path || !/^[a-f0-9]{64}$/.test(ref.sha256 ?? '')) throw Error('missing immutable input binding');
  const p = resolve(root, ref.path);
  if (sha(p) !== ref.sha256) throw Error(`immutable input changed: ${ref.path}`);
  return p;
}
function ranges(rows, duration, label) {
  if (!Array.isArray(rows)) throw Error(`missing complete ${label} graph`);
  let end = 0;
  for (const row of rows) {
    if (!Array.isArray(row) || row.length !== 2 || row.some(v => !Number.isFinite(v)) || row[0] < end || row[0] < 0 || row[1] <= row[0] || row[1] > duration) throw Error(`invalid ${label} graph`);
    end = row[1];
  }
  return rows;
}
export function mapClock(source, script, map) {
  if (map.schema !== 'media-studio/edit-map/1') throw Error('unsupported edit-map schema');
  const duration = source.durationSeconds;
  if (!Number.isFinite(duration) || duration <= 0) throw Error('invalid source duration');
  const words = forcedWordOnsets(source, textWords(script).map(w => ({ w })), { takeSha256: map.source.candidate.sha256, scriptSha256: map.source.script.sha256 });
  const cuts = ranges(map.cuts, duration, 'cuts'), mutes = ranges(map.mutes, duration, 'mutes');
  if (cuts.some(([, b]) => b === duration)) throw Error('tail removal requires a fresh alignment and tail proof');
  const shifted = t => t - cuts.reduce((n, [a, b]) => n + Math.max(0, Math.min(t, b) - a), 0);
  const overlaps = (w, r) => Math.max(w.start, r[0]) < Math.min(w.end, r[1]) - 1e-9;
  if (words.some(w => cuts.some(r => overlaps(w, r)))) throw Error('cut intersects a source-aligned word; obtain a fresh alignment');
  const changedWords = words.filter(w => mutes.some(r => overlaps(w, r))).map(w => ({ ...w, reason: 'declared mute overlaps uncertain source word interval; independent final-file acoustic review required' }));
  return { words: words.map(w => ({ w: w.w, start: shifted(w.start), end: shifted(w.end) })),
    durationSeconds: shifted(duration), sourceUncertaintyMs: source.gridSeconds * 1000, changedWords };
}
export function measureMappedClock(mapped, cueWords, maxMs = 40) {
  if (mapped.words.length !== cueWords.length || cueWords.some((w, i) => String(w.w ?? w.word ?? w.text) !== String(mapped.words[i].w) || !Number.isFinite(w.start) || w.start < 0 || (i && w.start < cueWords[i - 1].start) || (w.end !== undefined && (!Number.isFinite(w.end) || w.end < w.start)))) throw Error('mapped clock must cover the complete ordered cue words');
  const stats = offsetStats(mapped.words.map((w, i) => (w.start - cueWords[i].start) * 1000), cueWords.map(w => w.start));
  const errors = [];
  if (!stats) errors.push('no mapped words');
  else {
    if (Math.abs(stats.offsetMs) > maxMs) errors.push(`encoded mapped audio is ${stats.offsetMs} ms off cue words (max +-${maxMs} ms)`);
    if (Math.abs(stats.driftMs) > maxMs) errors.push(`mapped A/V drift ${stats.driftMs} ms (max +-${maxMs} ms)`);
  }
  return { ok: !errors.length, errors, ...stats, method: 'verified-preserved-pcm-edit-map', gridMs: null,
    sourceGridMs: 80, sourceUncertaintyMs: mapped.sourceUncertaintyMs, changedWords: mapped.changedWords, words: mapped.words };
}
function run(cmd, args) {
  const r = spawnSync(cmd, args, { windowsHide: true, encoding: null, maxBuffer: 192 * 1024 * 1024, timeout: 180000 });
  if (r.error || r.status !== 0) throw Error(`${cmd} decode failed: ${r.error?.message ?? r.stderr?.toString().slice(-600)}`);
  return r.stdout;
}
const decode = (file, args) => run('ffmpeg', ['-nostdin', '-v', 'error', '-threads', '1', '-filter_threads', '1', '-filter_complex_threads', '1', '-i', file, ...args]);
function kept(cuts) { let at = 0; const out = []; for (const [a, b] of cuts) { if (a > at) out.push([at, a]); at = b; } out.push([at, null]); return out; }
export function filters(map, media) {
  const ks = kept(map.cuts), n = ks.length, audio = media === 'a';
  const mute = map.mutes.length ? `volume=0:enable='${map.mutes.map(([a,b]) => `between(t,${a},${b})`).join('+')}',` : '';
  const split = n > 1 ? `${audio ? 'asplit' : 'split'}=${n}${ks.map((_,i) => `[x${i}]`).join('')}` : `${audio ? 'anull' : 'null'}[x0]`;
  return `[0:${media}]${audio ? mute : ''}${split};` + ks.map(([a,b],i) => `[x${i}]${audio ? 'atrim' : 'trim'}=start=${a}${b === null ? '' : `:end=${b}`},${audio ? 'asetpts' : 'setpts'}=PTS-STARTPTS[y${i}]`).join(';') + ';' + ks.map((_,i) => `[y${i}]`).join('') + `concat=n=${n}:v=${audio ? 0 : 1}:a=${audio ? 1 : 0}[out]`;
}
export function comparePcm(expected, actual) {
  if (expected.length !== actual.length || !expected.length || expected.length % 4) throw Error('complete decoded PCM sample count mismatch');
  const n = expected.length / 4, block = 4000, windows = [];
  for (let from = 0; from < n; from += block) {
    const until = Math.min(n, from + block); let xx=0, yy=0, xy=0, ee=0;
    for (let i=from;i<until;i++) { const x=expected.readFloatLE(i*4), y=actual.readFloatLE(i*4); if (!Number.isFinite(x) || !Number.isFinite(y)) throw Error('nonfinite decoded PCM'); xx+=x*x; yy+=y*y; xy+=x*y; ee+=(x-y)**2; }
    const rms=Math.sqrt(xx/(until-from)), errorRms=Math.sqrt(ee/(until-from));
    const correlation = rms >= .005 ? xy / Math.sqrt(xx*yy) : null;
    if (errorRms > Math.max(.001, rms*.15) || (correlation !== null && (!Number.isFinite(correlation) || correlation < .98))) throw Error(`decoded PCM correspondence failed at ${from/16000}s`);
    windows.push({ startSeconds: from/16000, endSeconds: until/16000, rms, errorRms, correlation });
  }
  if (!windows.some(w=>w.correlation !== null)) throw Error('no energetic PCM to verify');
  return { sampleRate:16000, channels:1, format:'f32le', expectedSamples:n, finalSamples:n, coverage:'all samples including silence and tail', windows,
    expectedPcmSha256:createHash('sha256').update(expected).digest('hex'), finalPcmSha256:createHash('sha256').update(actual).digest('hex') };
}
export function compareFrames(a,b) {
  const size=400*250;
  if (!a.length || a.length!==b.length || a.length%size) throw Error('decoded picture frame count mismatch');
  let maxMae=0, maxP99=0;
  for(let from=0;from<a.length;from+=size) { let sum=0;const hist=new Uint32Array(256);for(let j=0;j<size;j++){const d=Math.abs(a[from+j]-b[from+j]);sum+=d;hist[d]++;}let count=0,p99=0;for(;p99<255;p99++){count+=hist[p99];if(count>=size*.99)break;}maxMae=Math.max(maxMae,sum/size);maxP99=Math.max(maxP99,p99); }
  if(maxMae>3 || maxP99>16)throw Error('decoded picture correspondence failed');
  return {frames:a.length/size,maxFrameMAE:maxMae,maxFrameP99AbsoluteError:maxP99};
}
export function verifyEditMap(root, mapPath, candidate) {
  const map=read(mapPath), original=bound(root,map.source?.candidate), ap=bound(root,map.source?.alignment), sp=bound(root,map.source?.script);
  if(resolve(candidate)!==bound(root,map.candidate))throw Error('edit-map candidate differs from requested candidate');
  const source=read(ap), mapped=mapClock(source,readFileSync(sp,'utf8').replace(/^\uFEFF/,''),map);
  const expected=decode(original,['-filter_complex',filters(map,'a'),'-map','[out]','-ac','1','-ar','16000','-f','f32le','-']);
  const actual=decode(candidate,['-vn','-ac','1','-ar','16000','-f','f32le','-']);
  const pcm=comparePcm(expected,actual);
  if(Math.abs(pcm.finalSamples/16000-mapped.durationSeconds)>.08)throw Error('decoded duration differs from mapped source clock');
  let picture=null;
  if(map.verifyPicture===true) {
    const ea=decode(original,['-filter_complex',filters(map,'v')+';[out]fps=2,scale=400:250[small]','-map','[small]','-an','-threads:v','1','-pix_fmt','gray','-f','rawvideo','-']);
    const aa=decode(candidate,['-an','-vf','fps=2,scale=400:250','-threads:v','1','-pix_fmt','gray','-f','rawvideo','-']);
    picture=compareFrames(ea,aa);
    // Always compare the final native frame separately: 2fps can omit a tail.
    const tail=file=>run('ffmpeg',['-nostdin','-v','error','-threads','1','-filter_threads','1','-sseof','-1','-i',file,'-an','-vf','scale=400:250,reverse,select=eq(n\\,0)','-frames:v','1','-threads:v','1','-pix_fmt','gray','-f','rawvideo','-']);
    picture.tail=compareFrames(tail(original),tail(candidate));
    picture.limitations=['2fps sampled lossy luma correspondence plus final native frame; not continuous visual review'];
  }
  // Inputs remain immutable across expensive decoding.
  for(const ref of [map.source.candidate,map.source.alignment,map.source.script,map.candidate])bound(root,ref);
  return {schema:'media-studio/verified-edit-map/1',generator:'media-studio/validate-edit-map',ok:true,errors:[],candidate:{path:resolve(candidate),sha256:sha(candidate),bytes:statSync(candidate).size},
    inputs:{editMap:{path:mapPath,sha256:sha(mapPath)},sourceCandidate:map.source.candidate,sourceAlignment:map.source.alignment,script:map.source.script},
    thresholds:{minPcmCorrelation:.98,maxPcmRelativeRmsError:.15,maxQuietRmsError:.001,maxFrameMAE:3,maxFrameP99AbsoluteError:16},
    pcm,picture,mapped,limitations:['No new forced alignment; source80ms uncertainty retained','Declared mutes can alter source word intervals; independent final-file content review remains mandatory']};
}
export function readVerifiedMap(root, report, bindings) {
  if(report?.schema!=='media-studio/verified-edit-map/1'||report.generator!=='media-studio/validate-edit-map'||report.ok!==true||report.errors?.length!==0)throw Error('requires canonical verified edit map');
  if(report.candidate?.sha256!==bindings.takeSha256||report.inputs?.script?.sha256!==bindings.scriptSha256)throw Error('verified edit-map input SHA-256 mismatch');
  const mp=bound(root,report.inputs.editMap),map=read(mp);
  if (bindings.editMapSha256 && report.inputs.editMap.sha256 !== bindings.editMapSha256) throw Error('selected edit map differs from verified edit map');
  if (map.candidate.sha256 !== bindings.takeSha256 || map.source.script.sha256 !== bindings.scriptSha256) throw Error('edit-map candidate/script binding mismatch');
  for (const [key, ref] of [['sourceCandidate',map.source.candidate],['sourceAlignment',map.source.alignment],['script',map.source.script]]) {
    if (report.inputs[key]?.sha256 !== ref.sha256 || resolve(root,report.inputs[key]?.path ?? '') !== resolve(root,ref.path)) throw Error('proof source binding differs from graph');
  }
  for(const ref of [map.source.candidate,map.source.alignment,map.source.script,map.candidate])bound(root,ref);
  const mapped=mapClock(read(bound(root,map.source.alignment)),readFileSync(bound(root,map.source.script),'utf8').replace(/^\uFEFF/,''),map);
  if(JSON.stringify(mapped)!==JSON.stringify(report.mapped))throw Error('derived clock changed after verification');
  const th=report.thresholds;
  if(th?.minPcmCorrelation!==.98||th?.maxPcmRelativeRmsError!==.15||th?.maxQuietRmsError!==.001||th?.maxFrameMAE!==3||th?.maxFrameP99AbsoluteError!==16)throw Error('edit-map thresholds differ from canonical');
  const pcm=report.pcm;
  if(pcm?.sampleRate!==16000||pcm.channels!==1||pcm.format!=='f32le'||!['expectedPcmSha256','finalPcmSha256'].every(k=>/^[a-f0-9]{64}$/.test(pcm[k]??'')))throw Error('invalid PCM format/hash proof');
  if(!Number.isInteger(pcm?.expectedSamples)||pcm.expectedSamples<=0||pcm.expectedSamples!==pcm.finalSamples||!Array.isArray(pcm.windows)||pcm.windows.length!==Math.ceil(pcm.finalSamples/4000))throw Error('incomplete PCM proof');
  for(let i=0;i<pcm.windows.length;i++){const w=pcm.windows[i];if(w.startSeconds!==i*.25||w.endSeconds!==Math.min(pcm.finalSamples/16000,(i+1)*.25)||!Number.isFinite(w.rms)||w.rms<0||!Number.isFinite(w.errorRms)||w.errorRms<0||w.errorRms>Math.max(.001,w.rms*.15)||(w.rms>=.005&&(!Number.isFinite(w.correlation)||w.correlation<.98||w.correlation>1.000001)))throw Error('invalid PCM window proof');}
  if(!pcm.windows.some(w=>w.rms>=.005)||Math.abs(pcm.finalSamples/16000-mapped.durationSeconds)>.08)throw Error('PCM duration/energy proof mismatch');
  const goodPicture=p=>Number.isInteger(p?.frames)&&p.frames>0&&Number.isFinite(p.maxFrameMAE)&&p.maxFrameMAE>=0&&p.maxFrameMAE<=3&&Number.isFinite(p.maxFrameP99AbsoluteError)&&p.maxFrameP99AbsoluteError>=0&&p.maxFrameP99AbsoluteError<=16;
  if(map.verifyPicture===true && (!goodPicture(report.picture)||!goodPicture(report.picture.tail)||report.picture.tail.frames!==1||Math.abs(report.picture.frames-pcm.finalSamples/16000*2)>1))throw Error('incomplete picture/tail proof');
  return mapped;
}
