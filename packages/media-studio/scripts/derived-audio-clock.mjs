// Preserve an opted-in ASR clock across a lossless audio-container boundary only.
// This is neither forced alignment nor an edit/time transform.
import { createHash } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { bound } from './edit-map-clock.mjs';
const here = dirname(fileURLToPath(import.meta.url));
function modulePath(candidates, label) {
  const file = candidates.map(p => join(here,p)).find(existsSync);
  if (!file) throw Error(`derived clock missing canonical ${label}`);
  return pathToFileURL(file).href;
}
const { measureWordSync, forcedWordOnsets } = await import(modulePath(['sync-lib.mjs','../kit/screencast/sync-lib.mjs'],'sync library'));
const { alignScript, scriptTokens, heardKeys } = await import(modulePath(['../cloud/cloud-ai.mjs','../../briefing-kit/cloud/cloud-ai.mjs','../kit/cloud/cloud-ai.mjs'],'cloud alignment library'));
const read = p => JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
function pcm(file, rate) {
  const r = spawnSync('ffmpeg', ['-v','error','-nostdin','-threads','1','-filter_threads','1','-i',file,'-map','0:a:0','-vn','-ac','1','-ar',String(rate),'-c:a','pcm_s16le','-f','s16le','pipe:1'], { windowsHide:true, maxBuffer:192*1024*1024, timeout:180000 });
  if (r.error || r.status !== 0) throw Error('derived clock PCM decode failed');
  return r.stdout;
}
function sourceFormat(file, rate) {
  const b=readFileSync(file);
  if(b.toString('ascii',0,4)!=='RIFF'||b.toString('ascii',8,12)!=='WAVE')throw Error('source upload must be retained WAV');
  for(let at=12;at+8<=b.length;){
    const size=b.readUInt32LE(at+4);
    if(at+8+size>b.length)throw Error('invalid source WAV chunk');
    if(b.toString('ascii',at,at+4)==='fmt '){
      if(size<16||b.readUInt16LE(at+8)!==1||b.readUInt16LE(at+10)!==1||b.readUInt32LE(at+12)!==rate||b.readUInt16LE(at+22)!==16)throw Error('source WAV must match declared mono PCM16 sample rate');
      return;
    }
    at+=8+size+(size%2);
  }
  throw Error('source WAV missing format');
}
export function readDerivedAudioClock(root, manifest, bindings) {
  if (manifest?.schema !== 'media-studio/derived-audio-clock/1' || manifest.transform !== 'identity-decoded-pcm' || bindings.allowAsrAnchored !== true) throw Error('derived ASR clock requires supported identity transform and explicit opt-in');
  const rate=manifest.pcm?.sampleRate;
  if(![16000,24000,48000].includes(rate)||manifest.pcm?.channels!==1||manifest.pcm?.sampleFormat!=='s16le')throw Error('requires explicit supported canonical mono PCM16 format');
  if (manifest.candidate?.sha256 !== bindings.takeSha256 || manifest.script?.sha256 !== bindings.scriptSha256) throw Error('derived candidate/script binding differs');
  const refs = ['candidate','script','sourceAudio','sourceAlignment','raw'];
  const paths = Object.fromEntries(refs.map(k => [k,bound(root,manifest[k])]));
  const report = read(paths.sourceAlignment), raw = read(paths.raw);
  if (report.schema !== 'cloud-speech/script-alignment/1' || report.method !== 'asr-anchored-alignment' || report.ok !== true || report.errors?.length !== 0 || report.provider?.name !== 'deepgram' || report.provider?.model !== 'nova-3') throw Error('requires successful canonical Nova3 ASR-anchored source clock');
  // The retained provider response itself binds the submitted WAV bytes. A
  // locally authored request-id declaration cannot substitute for that binding.
  if (!raw.metadata?.request_id || raw.metadata.sha256 !== manifest.sourceAudio.sha256 || !Object.values(raw.metadata.model_info ?? {}).some(x => x.arch === 'nova-3')) throw Error('retained provider response does not bind source audio/model');
  sourceFormat(paths.sourceAudio,rate);
  const expected = pcm(paths.candidate,rate), actual = pcm(paths.sourceAudio,rate);
  if (!expected.length || expected.length % 2 || !expected.equals(actual)) throw Error('source audio is not exact complete decoded candidate PCM');
  const duration = actual.length / (rate*2);
  if (!Number.isFinite(report.durationSeconds) || Math.abs(report.durationSeconds-duration) > .00051 || !Number.isFinite(raw.metadata.duration) || Math.abs(raw.metadata.duration-duration) > .001) throw Error('source/provider duration differs from complete PCM');
  const heard = raw.results?.channels?.[0]?.alternatives?.[0]?.words;
  if (!Array.isArray(heard) || !heard.length || heard.some((w,i) => typeof w.word !== 'string' || !Number.isFinite(w.start) || !Number.isFinite(w.end) || w.start < 0 || w.end < w.start || w.end > duration || (i && w.start < heard[i-1].start))) throw Error('invalid retained provider words');
  const regenerated = alignScript(scriptTokens(readFileSync(paths.script,'utf8').replace(/^\uFEFF/,'')),heardKeys(heard.map(w=>({text:w.word,start:w.start,end:w.end}))).filter(w=>w.key),duration);
  if (JSON.stringify(regenerated.words) !== JSON.stringify(report.words) || JSON.stringify(regenerated.coverage) !== JSON.stringify(report.coverage)) throw Error('source clock differs from retained provider response');
  // Validate complete script coverage, grid, interval bounds and input hashes
  // using the original source-audio identity, never rewriting it to the MP4.
  const words = scriptTokens(readFileSync(paths.script,'utf8')).map(w=>({w:w.text}));
  forcedWordOnsets(report,words,{takeSha256:manifest.sourceAudio.sha256,scriptSha256:bindings.scriptSha256,allowAsrAnchored:true});
  for (const k of refs) bound(root,manifest[k]);
  return { report, sourceAudioSha256:manifest.sourceAudio.sha256, scriptSha256:bindings.scriptSha256, pcmSampleRate:rate, pcmSamples:actual.length/2, pcmSha256:createHash('sha256').update(actual).digest('hex') };
}
export function measureDerivedAudioClock(clock,cueWords,maxMs=40) {
  const result = measureWordSync(clock.report,cueWords,{takeSha256:clock.sourceAudioSha256,scriptSha256:clock.scriptSha256,allowAsrAnchored:true},maxMs);
  return {...result,method:'asr-anchored-identity-pcm-on-encoded',sourceAudioSha256:clock.sourceAudioSha256,pcmSha256:clock.pcmSha256,pcmSampleRate:clock.pcmSampleRate,pcmSamples:clock.pcmSamples,limitations:['ASR anchored, not forced alignment','80 ms source grid and precision-limited words retain their original uncertainty','Exact complete canonical mono PCM identity permits no edits, drift, padding, truncation or offset','Mono sample-rate normalization verifies the ASR representation, not multichannel or full-band audio fidelity','Independent final-file content and audiovisual review remain required']};
}
