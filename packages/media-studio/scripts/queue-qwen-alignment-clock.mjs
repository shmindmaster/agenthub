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
export function validateQueueQwenRaw(raw,script,duration,gridSeconds=.08,terminalEndpointToleranceMs=0){
  if(!Number.isFinite(terminalEndpointToleranceMs)||terminalEndpointToleranceMs<0||terminalEndpointToleranceMs>10)throw Error('invalid terminal endpoint policy');
  if(![null,.08].includes(gridSeconds))throw Error('unsupported emitted timestamp grid');
  if(raw.ok!==true||!Array.isArray(raw.words)||!raw.words.length||raw.word_count!==raw.words.length||!Number.isFinite(duration)||duration<=0)throw Error('invalid successful queue alignment');
  const expected=tokens(script);
  if(tokens(raw.text).join(' ')!==expected.join(' '))throw Error('queue request text differs from locked script');
  let previous=0;
  const words=raw.words.map((w,i)=>{
    if(typeof w.word!=='string'||!norm(w.word)||!Number.isFinite(w.start)||!Number.isFinite(w.end)||w.start<previous||w.end<w.start||w.start>duration||w.end>duration+(i===raw.words.length-1?terminalEndpointToleranceMs/1000:0)||(gridSeconds!==null&&[w.start,w.end].some(t=>Math.abs(t/gridSeconds-Math.round(t/gridSeconds))>1e-5)))throw Error('invalid queue word interval or80ms grid');
    previous=w.end;return {w:w.word,start:w.start,end:w.end};
  });
  if(words.map(w=>norm(w.w)).join(' ')!==expected.join(' '))throw Error('queue words do not cover complete ordered script');
  return {words,durationSeconds:duration,gridSeconds,terminalEndpointToleranceMs,terminalEndpointOvershootMs:Math.max(0,(words.at(-1).end-duration)*1000)};
}
function run(exe,args){
  const r=spawnSync(exe,args,{windowsHide:true,maxBuffer:192*1024*1024,timeout:180000});
  if(r.error||r.status!==0)throw Error('queue clock PCM decode/probe failed');return r.stdout;
}
const pcm=p=>run('ffmpeg',['-v','error','-nostdin','-threads','1','-filter_threads','1','-i',p,'-map','0:a:0','-vn','-ac','1','-ar','16000','-c:a','pcm_s16le','-f','s16le','pipe:1']);
export function readQueueQwenClock(root,m,bindings){
  if(m?.schema!==QUEUE_QWEN_SCHEMA||m.units!=='seconds'||![null,.08].includes(m.gridSeconds)||m.uncertaintySeconds!==null||m.transform!=='identity-decoded-pcm')throw Error('unsupported queue Qwen clock contract');
  const h100=m.engine?.name==='studio_worker.cluster_runner.align';
  if(!['studio_worker.engines.speech_runner.align','studio_worker.cluster_runner.align'].includes(m.engine?.name)||m.engine.model!=='Qwen3ForcedAligner'||m.engine.modelRevision!==null||m.engine.rawTimestampMilliseconds!==null||m.engine.provenance!=='retrospective-source-inspection')throw Error('unsupported queue engine provenance');
  if(m.candidate?.sha256!==bindings.takeSha256||m.script?.sha256!==bindings.scriptSha256)throw Error('queue candidate/script binding differs');
  if(typeof m.request?.id!=='string'||!m.request.id.trim()||(h100?m.request.sessionId!==null:typeof m.request.sessionId!=='string'||!m.request.sessionId.trim()))throw Error('queue request/session identity missing');
  const refs=['candidate','script','sourceAudio','raw','job','submission','receipt','segments','engineSource'];
  const paths=Object.fromEntries(refs.map(k=>[k,bound(root,m[k])]));
  const script=readFileSync(paths.script,'utf8').replace(/^\uFEFF/,''),raw=read(paths.raw),receipt=read(paths.receipt),segments=read(paths.segments),submission=read(paths.submission);
  if(submission.decodedAudioSha256!==m.sourceAudio.sha256||submission.scriptSha256!==m.script.sha256)throw Error('queue submission input hashes differ');
  const jobs=readFileSync(paths.job,'utf8').trim().split(/\r?\n/).map(x=>JSON.parse(x));
  const jobsMatching=jobs.filter(j=>j.id===m.request?.id);
  if(jobsMatching.length!==1)throw Error('queue request missing or ambiguous');
  const job=jobsMatching[0],segment=segments[m.request.id];
  if(job.op!=='asr.align'||job.engine!=='asr'||job.audio!==m.request.audio||job.language!=='English'||job.text!==raw.text||tokens(job.text).join(' ')!==tokens(script).join(' '))throw Error('queue job does not bind requested audio/script/engine');
  const errorsEmpty=x=>Array.isArray(x)&&x.length===0;
  const completed=receipt.state==='done'&&errorsEmpty(receipt.errors)&&Array.isArray(receipt.parts)&&receipt.parts.length>0&&segment?.status==='succeeded'&&segment.error===null&&segment.text===raw.text&&segment.file===m.request.output;
  if(!completed)throw Error('queue completion evidence differs');
  if(h100){
    // The CPU runner's raw file has no success flag; only the queue's exact job completion can establish success.
    if(receipt.class!=='h100'||receipt.session_id!=='-'||receipt.parts.some(p=>p.ok!==true||p.class!=='h100'||p.session_id!==null||!errorsEmpty(p.errors))||segment.class!=='h100'||segment.op!=='asr.align'||segment.route!=='cluster-job'||Object.hasOwn(raw,'ok'))throw Error('H100 queue completion evidence differs');
  }else if(receipt.class!=='speech'||receipt.session_id!==m.request.sessionId||receipt.parts.some(p=>p.ok!==true||p.class!=='speech'||p.session_id!==receipt.session_id||!errorsEmpty(p.errors))||segment.class!=='speech')throw Error('queue completion evidence differs');
  // Bind every original job, including batches. Speech staging may add successful null-output unpack receipts.
  const ids=new Set(),outputs=new Set();
  for(const item of jobs){
    const relative=typeof item.audio==='string'?item.audio.replace(/\.[^.\/]+$/,'.words.json'):null;
    const output=h100?relative:`/data/productions/${m.request.project}--${item.production}/${relative}`,result=segments[item.id];
    if(typeof item.id!=='string'||!item.id.trim()||ids.has(item.id)||!relative||outputs.has(output)||item.op!=='asr.align'||item.engine!=='asr'||item.production!==job.production||item.language!=='English'||typeof item.text!=='string'||!item.text.trim()||result?.status!=='succeeded'||result.class!==(h100?'h100':'speech')||(h100&&(result.op!=='asr.align'||result.route!=='cluster-job'))||result.error!==null||result.text!==item.text||result.file!==output)throw Error('queue batch job/result binding differs');
    ids.add(item.id);outputs.add(output);
  }
  for(const [id,result] of Object.entries(segments))if(!ids.has(id)){
    const prefix=`unpack-${m.request.project}--${job.production}-`;
    if(h100||!id.startsWith(prefix)||!/^\d{3,}$/.test(id.slice(prefix.length))||result?.status!=='succeeded'||result.class!=='speech'||result.file!==null||result.text!==null||result.error!==null)throw Error('queue batch contains unbound results');
  }

  // Job-relative names must bind the retained files, not merely similarly named output.
  if(resolve(dirname(paths.job),job.audio)!==paths.sourceAudio||!/^[a-z0-9][a-z0-9-]*$/.test(m.request.project??'')||m.request.output!==(h100?job.audio.replace(/\.[^.\/]+$/,'.words.json'):`/data/productions/${m.request.project}--${job.production}/${job.audio.replace(/\.[^.\/]+$/,'.words.json')}`)||!m.request.output.endsWith('/'+m.raw.path.split(/[\\/]/).at(-1)))throw Error('queue audio/output reference differs');
  const source=readFileSync(paths.engineSource,'utf8');
  const alignCall=h100?'cpu_aligner(str(common.checkpoint_path("qwen3-forced-aligner"))).align(audio=str(source), text=job["text"]':'aligner.align(audio=request["audio"], text=request["text"]';
  if(!source.includes('def align(')||!source.includes('Qwen3ForcedAligner')||!source.includes(alignCall)||(h100&&(!source.includes('dtype=torch.float32, device_map="cpu"')||!source.includes('common.stage_checkpoint("qwen3-forced-aligner"'))))throw Error('retained adapter does not establish queue forced-aligner implementation');
  const probe=JSON.parse(run('ffprobe',['-v','error','-select_streams','a:0','-show_entries','stream=codec_name,sample_rate,channels','-of','json',paths.sourceAudio]).toString()).streams?.[0];
  if(probe?.codec_name!=='pcm_s16le'||!['16000','48000'].includes(probe.sample_rate)||probe.channels!==1)throw Error('queue source must be supported original mono16k/48k PCM16');
  const actual=pcm(paths.sourceAudio),expected=pcm(paths.candidate);
  if(!actual.length||actual.length%2||!actual.equals(expected))throw Error('queue source is not exact complete decoded candidate PCM');
  const duration=actual.length/32000;
  if(!Number.isFinite(m.durationSeconds)||Math.abs(m.durationSeconds-duration)>1/16000)throw Error('queue duration differs from complete PCM');
  const clock=validateQueueQwenRaw(h100?{...raw,ok:true}:raw,script,duration,m.gridSeconds,m.terminalEndpointToleranceMs??0);
  for(const k of refs)bound(root,m[k]);
  return {...clock,pcmSha256:createHash('sha256').update(actual).digest('hex'),pcmSamples:actual.length/2,requestId:m.request.id,sessionId:h100?null:receipt.session_id,engineName:m.engine.name,executionPrecision:null};
}
export function measureQueueQwenClock(clock,cueWords,maxMs=40){
  if(!Number.isFinite(maxMs)||maxMs<0||maxMs>40)throw Error('invalid queue clock tolerance');
  if(clock.words.length!==cueWords.length||cueWords.some((w,i)=>norm(w.w??w.word??w.text)!==norm(clock.words[i].w)||!Number.isFinite(w.start)||!Number.isFinite(w.end)||w.start<0||w.end<w.start||(i&&w.start<cueWords[i-1].start)))throw Error('queue clock requires complete ordered cue words');
  const stats=offsetStats(clock.words.map((w,i)=>(w.start-cueWords[i].start)*1000),cueWords.map(w=>w.start));
  const errors=[];
  if(!stats)errors.push('no queue clock words');
  else {if(Math.abs(stats.offsetMs)>maxMs)errors.push(`queue encoded offset exceeds${maxMs}ms`);if(Math.abs(stats.driftMs)>maxMs)errors.push(`queue encoded drift exceeds${maxMs}ms`);}
  return {...clock,...stats,ok:!errors.length,errors,method:'queue-qwen-forced-alignment-identity-pcm-on-encoded',gridMs:clock.gridSeconds===null?null:80,uncertaintyMs:null,modelRevision:null,rawTimestampMilliseconds:null,limitations:['Retained queue output, not the strict Local-AI wrapper','Retrospective adapter inspection does not attest the executed model or adapter revision',clock.gridSeconds===null?'Raw model timestamps have unknown global grid and acoustic accuracy':'80ms word grid is not40ms acoustic accuracy; provider accuracy unknown','Terminal endpoint allowance is an explicit editorial acceptance policy, not acoustic accuracy or codec rounding; raw times unchanged','Caption and film boundaries must remain within actual media duration','Zero-duration model intervals retained without repair','Independent final-file content and audiovisual review required']};
}
