// Import retained queue evidence; never impersonate the stricter Local-AI adapter.
import {readFileSync,existsSync} from 'node:fs';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {bound} from './edit-map-clock.mjs';
const here=dirname(fileURLToPath(import.meta.url));
const lib=[join(here,'sync-lib.mjs'),join(here,'../kit/screencast/sync-lib.mjs')].find(existsSync);
const {offsetStats}=await import(pathToFileURL(lib).href);
const read=p=>JSON.parse(readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const norm=w=>String(w??'').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');
const tokens=s=>String(s).split(/\s+/).map(norm).filter(Boolean);
export const QUEUE_QWEN_SCHEMA='media-studio/queue-qwen-forced-alignment/1';
export function validateQueueQwenRaw(raw,script,duration){
  if(raw.ok!==true||!Array.isArray(raw.words)||!raw.words.length||raw.word_count!==raw.words.length||!Number.isFinite(duration)||duration<=0)throw Error('invalid successful queue alignment');
  const expected=tokens(script);
  if(tokens(raw.text).join(' ')!==expected.join(' '))throw Error('queue request text differs from locked script');
  let previous=0;
  const words=raw.words.map(w=>{
    if(typeof w.word!=='string'||!norm(w.word)||!Number.isFinite(w.start)||!Number.isFinite(w.end)||w.start<previous||w.end<w.start||w.end>duration||[w.start,w.end].some(t=>Math.abs(t/.08-Math.round(t/.08))>1e-5))throw Error('invalid queue word interval or80ms grid');
    previous=w.end;return {w:w.word,start:w.start,end:w.end};
  });
  if(words.map(w=>norm(w.w)).join(' ')!==expected.join(' '))throw Error('queue words do not cover complete ordered script');
  return {words,durationSeconds:duration};
}
function run(exe,args){
  const r=spawnSync(exe,args,{windowsHide:true,maxBuffer:192*1024*1024,timeout:180000});
  if(r.error||r.status!==0)throw Error('queue clock PCM decode/probe failed');return r.stdout;
}
const pcm=p=>run('ffmpeg',['-v','error','-nostdin','-threads','1','-filter_threads','1','-i',p,'-map','0:a:0','-vn','-ac','1','-ar','16000','-c:a','pcm_s16le','-f','s16le','pipe:1']);
export function readQueueQwenClock(root,m,bindings){
  if(m?.schema!==QUEUE_QWEN_SCHEMA||m.units!=='seconds'||m.gridSeconds!==.08||m.uncertaintySeconds!==null||m.transform!=='identity-decoded-pcm')throw Error('unsupported queue Qwen clock contract');
  if(m.engine?.name!=='studio_worker.engines.speech_runner.align'||m.engine.model!=='Qwen3ForcedAligner'||m.engine.modelRevision!==null||m.engine.rawTimestampMilliseconds!==null||m.engine.provenance!=='retrospective-source-inspection')throw Error('unsupported queue engine provenance');
  if(m.candidate?.sha256!==bindings.takeSha256||m.script?.sha256!==bindings.scriptSha256)throw Error('queue candidate/script binding differs');
  if(!['id','sessionId'].every(k=>typeof m.request?.[k]==='string'&&m.request[k].trim()))throw Error('queue request/session identity missing');
  const refs=['candidate','script','sourceAudio','raw','job','submission','receipt','segments','engineSource'];
  const paths=Object.fromEntries(refs.map(k=>[k,bound(root,m[k])]));
  const script=readFileSync(paths.script,'utf8').replace(/^\uFEFF/,''),raw=read(paths.raw),receipt=read(paths.receipt),segments=read(paths.segments),submission=read(paths.submission);
  if(submission.decodedAudioSha256!==m.sourceAudio.sha256||submission.scriptSha256!==m.script.sha256)throw Error('queue submission input hashes differ');
  const jobs=readFileSync(paths.job,'utf8').trim().split(/\r?\n/).map(x=>JSON.parse(x));
  const jobsMatching=jobs.filter(j=>j.id===m.request?.id);
  if(jobsMatching.length!==1)throw Error('queue request missing or ambiguous');
  const job=jobsMatching[0],segment=segments[m.request.id];
  if(job.op!=='asr.align'||job.engine!=='asr'||job.audio!==m.request.audio||job.language!=='English'||job.text!==raw.text||tokens(job.text).join(' ')!==tokens(script).join(' '))throw Error('queue job does not bind requested audio/script/engine');
  if(receipt.state!=='done'||receipt.class!=='speech'||receipt.session_id!==m.request.sessionId||!Array.isArray(receipt.errors)||receipt.errors.length||!Array.isArray(receipt.parts)||!receipt.parts.length||receipt.parts.some(p=>p.ok!==true||p.class!=='speech'||p.session_id!==receipt.session_id||!Array.isArray(p.errors)||p.errors.length)||segment?.status!=='succeeded'||segment.class!=='speech'||segment.error!==null||segment.text!==raw.text||segment.file!==m.request.output)throw Error('queue completion evidence differs');
  // Job-relative names must bind the retained files, not merely similarly named output.
  if(resolve(dirname(paths.job),job.audio)!==paths.sourceAudio||!/^[a-z0-9][a-z0-9-]*$/.test(m.request.project??'')||m.request.output!==`/data/productions/${m.request.project}--${job.production}/${job.audio.replace(/\.[^.\/]+$/,'.words.json')}`||!m.request.output.endsWith('/'+m.raw.path.split(/[\\/]/).at(-1)))throw Error('queue audio/output reference differs');
  const source=readFileSync(paths.engineSource,'utf8');
  if(!source.includes('def align(')||!source.includes('Qwen3ForcedAligner')||!source.includes('aligner.align(audio=request["audio"], text=request["text"]'))throw Error('retained adapter does not establish queue forced-aligner implementation');
  const probe=JSON.parse(run('ffprobe',['-v','error','-select_streams','a:0','-show_entries','stream=codec_name,sample_rate,channels','-of','json',paths.sourceAudio]).toString()).streams?.[0];
  if(probe?.codec_name!=='pcm_s16le'||probe.sample_rate!=='16000'||probe.channels!==1)throw Error('queue source must be mono16k PCM16');
  const actual=pcm(paths.sourceAudio),expected=pcm(paths.candidate);
  if(!actual.length||actual.length%2||!actual.equals(expected))throw Error('queue source is not exact complete decoded candidate PCM');
  const duration=actual.length/32000;
  if(!Number.isFinite(m.durationSeconds)||Math.abs(m.durationSeconds-duration)>1/16000)throw Error('queue duration differs from complete PCM');
  const clock=validateQueueQwenRaw(raw,script,duration);
  for(const k of refs)bound(root,m[k]);
  return {...clock,pcmSha256:createHash('sha256').update(actual).digest('hex'),pcmSamples:actual.length/2,requestId:m.request.id,sessionId:receipt.session_id};
}
export function measureQueueQwenClock(clock,cueWords,maxMs=40){
  if(!Number.isFinite(maxMs)||maxMs<0||maxMs>40)throw Error('invalid queue clock tolerance');
  if(clock.words.length!==cueWords.length||cueWords.some((w,i)=>norm(w.w??w.word??w.text)!==norm(clock.words[i].w)||!Number.isFinite(w.start)||!Number.isFinite(w.end)||w.start<0||w.end<w.start||(i&&w.start<cueWords[i-1].start)))throw Error('queue clock requires complete ordered cue words');
  const stats=offsetStats(clock.words.map((w,i)=>(w.start-cueWords[i].start)*1000),cueWords.map(w=>w.start));
  const errors=[];
  if(!stats)errors.push('no queue clock words');
  else {if(Math.abs(stats.offsetMs)>maxMs)errors.push(`queue encoded offset exceeds${maxMs}ms`);if(Math.abs(stats.driftMs)>maxMs)errors.push(`queue encoded drift exceeds${maxMs}ms`);}
  return {...clock,...stats,ok:!errors.length,errors,method:'queue-qwen-forced-alignment-identity-pcm-on-encoded',gridMs:80,uncertaintyMs:null,modelRevision:null,rawTimestampMilliseconds:null,limitations:['Retained queue output, not the strict Local-AI wrapper','Retrospective adapter inspection does not attest the executed model or adapter revision','80ms word grid is not40ms acoustic accuracy; provider accuracy unknown','Zero-duration model intervals retained without repair','Independent final-file content and audiovisual review required']};
}
