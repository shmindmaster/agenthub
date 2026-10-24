// Provider-native forced alignment of exact encoded audio. No invented grid or
// acoustic accuracy: loss and unknown provider uncertainty remain explicit.
import {createHash} from 'node:crypto';
import {readFileSync,statSync,existsSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
const here=dirname(fileURLToPath(import.meta.url));
const lib=[join(here,'sync-lib.mjs'),join(here,'../kit/screencast/sync-lib.mjs')].find(existsSync);
const {offsetStats}=await import(pathToFileURL(lib).href);
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const read=p=>JSON.parse(readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const norm=w=>String(w??'').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');
const tokens=s=>String(s).split(/\s+/).map(norm).filter(Boolean);
export function validateHostedRaw(raw,script,duration){
  if(!Number.isFinite(duration)||duration<=0)throw Error('invalid hosted duration');
  if(!Number.isFinite(raw.loss)||!Array.isArray(raw.words)||!raw.words.length||!Array.isArray(raw.characters)||!raw.characters.length)throw Error('missing provider word/character/loss evidence');
  let previous=0;
  for(const row of raw.characters){
    if(typeof row.text!=='string'||!row.text.length||!Number.isFinite(row.start)||!Number.isFinite(row.end)||row.start<previous||row.end<row.start||row.end>duration)throw Error('invalid provider character intervals');
    previous=row.end;
  }
  if(tokens(raw.characters.map(x=>x.text).join('')).join(' ')!==tokens(script).join(' '))throw Error('provider characters do not cover the complete ordered script');
  const wanted=tokens(script),allWords=raw.words.map(w=>({w:w.text,start:w.start,end:w.end,loss:w.loss}));
  previous=0;
  for(const w of allWords){
    if(typeof w.w!=='string'||!w.w.length||!Number.isFinite(w.start)||!Number.isFinite(w.end)||!Number.isFinite(w.loss)||w.start<previous||w.end<w.start||w.end>duration)throw Error('invalid provider word intervals/loss');
    previous=w.start;
  }
  // Eleven returns explicit whitespace entries in words; retain/validate their
  // intervals above, while comparison and cue clocks use lexical words only.
  const words=allWords.filter(w=>norm(w.w));
  if(words.some((w,i)=>i&&w.start<words[i-1].end))throw Error('overlapping provider lexical words');
  if(words.length!==wanted.length||words.some((w,i)=>norm(w.w)!==wanted[i]))throw Error('provider words do not cover the complete ordered script');
  return {words,durationSeconds:duration,providerLoss:raw.loss,gridMs:null,uncertaintyMs:null};
}
function bound(root,ref){
  if(!ref?.path||!/^[a-f0-9]{64}$/.test(ref.sha256??''))throw Error('missing hosted immutable binding');
  const p=resolve(root,ref.path);if(hash(p)!==ref.sha256)throw Error('hosted immutable input changed');return p;
}
function run(exe,args){
  const r=spawnSync(exe,args,{windowsHide:true,maxBuffer:128*1024*1024,timeout:180000});
  if(r.error||r.status!==0)throw Error('hosted alignment PCM decode/probe failed');return r.stdout;
}
function pcm(p){return run('ffmpeg',['-v','error','-nostdin','-threads','1','-filter_threads','1','-i',p,'-map','0:a:0','-vn','-ac','1','-ar','24000','-c:a','pcm_s16le','-f','s16le','pipe:1']);}
export function readHostedClock(root,manifest,bindings){
  if(manifest.schema!=='media-studio/hosted-forced-alignment/1'||manifest.provider!=='elevenlabs'||manifest.endpoint!=='/v1/forced-alignment'||manifest.units!=='seconds'||manifest.gridSeconds!==null||manifest.uncertaintySeconds!==null)throw Error('unsupported hosted forced-alignment provenance');
  if(manifest.request?.state!=='completed'||!manifest.request?.id||!manifest.request?.requestKey)throw Error('missing completed provider request');
  if(manifest.candidate?.sha256!==bindings.takeSha256||manifest.script?.sha256!==bindings.scriptSha256)throw Error('hosted candidate/script binding differs');
  const candidate=bound(root,manifest.candidate),script=bound(root,manifest.script),raw=bound(root,manifest.raw),audio=bound(root,manifest.uploadedAudio);
  if(statSync(candidate).size!==manifest.candidate.bytes)throw Error('hosted candidate bytes differ');
  if(!['pcm_s16le','flac'].includes(manifest.uploadedAudio.format)||manifest.uploadedAudio.sampleRate!==24000||manifest.uploadedAudio.channels!==1)throw Error('unsupported uploaded audio format');
  const probe=JSON.parse(run('ffprobe',['-v','error','-select_streams','a:0','-show_entries','stream=codec_name,sample_rate,channels,bits_per_raw_sample','-of','json',audio]).toString()).streams?.[0];
  if(probe?.codec_name!==manifest.uploadedAudio.format||probe.sample_rate!=='24000'||probe.channels!==1)throw Error('uploaded lossless audio codec/rate/channels differ from manifest');
  if(manifest.uploadedAudio.format==='flac'&&Number(probe.bits_per_raw_sample)!==16)throw Error('uploaded FLAC is not PCM16');
  const expected=pcm(candidate),actual=pcm(audio);
  if(!expected.length||!expected.equals(actual))throw Error('uploaded lossless audio is not the exact decoded candidate PCM');
  const duration=actual.length/48000;
  if(!Number.isFinite(manifest.durationSeconds)||manifest.durationSeconds<=0||Math.abs(manifest.durationSeconds-duration)>1/24000)throw Error('hosted duration differs from uploaded PCM');
  const clock=validateHostedRaw(read(raw),readFileSync(script,'utf8'),duration);
  // Recheck every binding after decode so concurrent file changes fail closed.
  for(const ref of [manifest.candidate,manifest.script,manifest.raw,manifest.uploadedAudio])bound(root,ref);
  return {...clock,pcmSha256:createHash('sha256').update(actual).digest('hex'),pcmSamples:actual.length/2};
}
export function measureHostedClock(clock,cueWords){
  if(clock.words.length!==cueWords.length||cueWords.some((w,i)=>norm(w.w??w.word??w.text)!==norm(clock.words[i].w)||!Number.isFinite(w.start)||!Number.isFinite(w.end)||w.start<0||w.end<w.start||(i&&w.start<cueWords[i-1].start)))throw Error('hosted clock must cover complete ordered cue words');
  const stats=offsetStats(clock.words.map((w,i)=>(w.start-cueWords[i].start)*1000),cueWords.map(w=>w.start));
  const errors=[];
  if(!stats)errors.push('no hosted words');
  else{
    if(Math.abs(stats.offsetMs)>40)errors.push('hosted encoded offset exceeds40ms');
    if(Math.abs(stats.driftMs)>40)errors.push('hosted encoded drift exceeds40ms');
  }
  return {ok:!errors.length,errors,...stats,method:'hosted-forced-alignment-on-encoded',gridMs:null,uncertaintyMs:null,provider:'elevenlabs',providerLoss:clock.providerLoss,words:clock.words,pcmSha256:clock.pcmSha256,pcmSamples:clock.pcmSamples};
}
