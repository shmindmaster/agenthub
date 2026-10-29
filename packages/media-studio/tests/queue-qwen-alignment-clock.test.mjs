import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {QUEUE_QWEN_SCHEMA,validateQueueQwenRaw,readQueueQwenClock,measureQueueQwenClock} from '../scripts/queue-qwen-alignment-clock.mjs';
const raw=()=>({ok:true,text:'Hello world',word_count:2,words:[{word:'Hello',start:.08,end:.16},{word:'world',start:.24,end:.32}]});
const cue=()=>raw().words.map(w=>({w:w.word,start:w.start,end:w.end}));
test('retained grid is exact, zero duration preserved and uncertainty unknown',()=>{
 const r=raw();r.words[0].end=.08;
 const c=validateQueueQwenRaw(r,'Hello world',.4),m=measureQueueQwenClock(c,cue());
 assert.equal(c.words[0].end,.08);assert.equal(m.ok,true);assert.equal(m.gridMs,80);assert.equal(m.uncertaintyMs,null);assert.equal(m.modelRevision,null);assert.equal(m.rawTimestampMilliseconds,null);
});
test('bad intervals, grid, missing words, counts, source status and script order rejected',()=>{
 for(const mutate of [r=>r.ok=false,r=>r.word_count=3,r=>r.words.pop(),r=>r.words.reverse(),r=>r.words[0].start=.081,r=>r.words[0].end=.48,r=>r.words[0].start=-.08,r=>r.words[1].start=.08,r=>r.words[1].end=.16,r=>r.text='Other text',r=>r.words[0].word='Invented']){
  const r=raw();mutate(r);assert.throws(()=>validateQueueQwenRaw(r,'Hello world',.4));
 }
});
test('40ms gate remains active, not a model accuracy claim',()=>{
 const c=validateQueueQwenRaw(raw(),'Hello world',.4);
 assert.equal(measureQueueQwenClock(c,cue().map(w=>({...w,start:w.start+.05,end:w.end+.05}))).ok,false);
 assert.equal(measureQueueQwenClock(c,cue().map((w,i)=>({...w,start:w.start+i*.05,end:w.end+i*.05}))).ok,false);
 assert.throws(()=>measureQueueQwenClock(c,cue().reverse()));
 assert.equal(measureQueueQwenClock(c,cue().map(w=>({...w,start:w.start+.03,end:w.end+.03})),20).ok,false);
 assert.equal(measureQueueQwenClock(c,cue().map(w=>({...w,start:w.start+.03,end:w.end+.03})),40).ok,true);
});
function wav(){const b=Buffer.alloc(44+12800);b.write('RIFF');b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(16000,24);b.writeUInt32LE(32000,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(12800,40);return b;}
function fixture(fn){
 const root=mkdtempSync(join(tmpdir(),'queue-clock-'));
 try{
 const put=(p,data)=>{mkdirSync(dirname(join(root,p)),{recursive:true});writeFileSync(join(root,p),typeof data==='object'&&!Buffer.isBuffer(data)?JSON.stringify(data):data);};
 const ref=p=>({path:p,sha256:createHash('sha256').update(readFileSync(join(root,p))).digest('hex')});
 put('candidate.wav',wav());put('uploads/source.wav',wav());put('story/locked-script.txt','Hello world');put('source.words.json',raw());
 const job={id:'align',op:'asr.align',engine:'asr',production:'unit',audio:'uploads/source.wav',text:'Hello world',language:'English'};
 put('jobs.jsonl',JSON.stringify(job)+'\n');
 put('status.json',{state:'done',class:'speech',session_id:'session',errors:[],parts:[{class:'speech',session_id:'session',ok:true,errors:[]}]});
 const output='/data/productions/test-project--unit/uploads/source.words.json';
 put('segments.json',{align:{status:'succeeded',class:'speech',error:null,text:'Hello world',file:output}});
 put('engine.py','def align(request):\n # Qwen3ForcedAligner\n aligner.align(audio=request["audio"], text=request["text"])');
 put('submission.json',{decodedAudioSha256:ref('uploads/source.wav').sha256,scriptSha256:ref('story/locked-script.txt').sha256});
 const m={schema:QUEUE_QWEN_SCHEMA,units:'seconds',gridSeconds:.08,uncertaintySeconds:null,transform:'identity-decoded-pcm',durationSeconds:.4,engine:{name:'studio_worker.engines.speech_runner.align',model:'Qwen3ForcedAligner',modelRevision:null,rawTimestampMilliseconds:null,provenance:'retrospective-source-inspection'},request:{project:'test-project',id:'align',sessionId:'session',audio:job.audio,output},candidate:ref('candidate.wav'),sourceAudio:ref('uploads/source.wav'),script:ref('story/locked-script.txt'),raw:ref('source.words.json'),job:ref('jobs.jsonl'),receipt:ref('status.json'),segments:ref('segments.json'),submission:ref('submission.json'),engineSource:ref('engine.py')};
 const bindings={takeSha256:m.candidate.sha256,scriptSha256:m.script.sha256};
 fn({root,m,bindings,put,ref,job});
 }finally{rmSync(root,{recursive:true,force:true});}
}
test('real PCM import and CLI preserve external method, original metadata and hash bindings',()=>fixture(({root,m,bindings,put})=>{
 assert.equal(readQueueQwenClock(root,m,bindings).pcmSamples,6400);
 put('qa/queue-qwen-alignment.json',m);put('plan/cue-sheet.json',{beats:[{narration:{words:cue()}}]});
 const cli=fileURLToPath(new URL('../scripts/validate-word-sync.mjs',import.meta.url));
 const r=spawnSync(process.execPath,[cli,root,join(root,'candidate.wav')],{windowsHide:true});
 assert.equal(r.status,0,r.stderr?.toString()+r.stdout?.toString());
 const report=JSON.parse(readFileSync(join(root,'qa/word-sync.json')));
 assert.equal(report.method,'queue-qwen-forced-alignment-identity-pcm-on-encoded');assert.equal(report.inputs.alignment.path,'qa/queue-qwen-alignment.json');assert.equal(report.thresholds.driftMaxMs,40);assert.equal(report.modelRevision,null);
 // Other film gates deliberately have no evidence in this clock-only fixture.
 // Inspect this branch independently; never pretend the fixture releases a film.
 put('job.json',{syncClock:'forced-aligner'});
 const viewer=fileURLToPath(new URL('../scripts/validate-viewer-release.mjs',import.meta.url));
 const check=()=>JSON.parse(spawnSync(process.execPath,[viewer,root,join(root,'candidate.wav')],{windowsHide:true}).stdout.toString());
 assert.equal(check().errors.some(e=>e.includes('queue Qwen')),false);
 assert.equal(report.engineName,'studio_worker.engines.speech_runner.align');assert.equal(report.executionPrecision,null);
 for(const [key,forged] of [['engineName','studio_worker.cluster_runner.align'],['executionPrecision','float32']]){
  const original=report[key];report[key]=forged;put('qa/word-sync.json',report);
  assert.equal(check().errors.some(e=>e.includes(`queue Qwen clock ${key} differs from current inputs`)),true);
  report[key]=original;put('qa/word-sync.json',report);
  assert.equal(check().errors.some(e=>e.includes('queue Qwen')),false);
 }
 report.pcmSha256='0'.repeat(64);put('qa/word-sync.json',report);
 assert.equal(check().errors.some(e=>e.includes('queue Qwen clock pcmSha256 differs')),true);
 report.pcmSha256=readQueueQwenClock(root,m,bindings).pcmSha256;put('qa/word-sync.json',report);
 const b=wav();b.writeInt16LE(10,100);put('uploads/source.wav',b);
 assert.equal(check().errors.some(e=>e.includes('invalid queue Qwen provenance: immutable input changed')),true);
}));
test('every changed retained reference fails even when timestamps still look plausible',()=>fixture(({root,m,bindings})=>{
 for(const key of ['candidate','sourceAudio','script','raw','job','submission','receipt','segments','engineSource']){
  const p=join(root,m[key].path),before=readFileSync(p);writeFileSync(p,Buffer.concat([before,Buffer.from(' ')]));
  assert.throws(()=>readQueueQwenClock(root,m,bindings),/immutable input/);writeFileSync(p,before);
 }
}));
test('rehashed different PCM, false completion, wrong job and manufactured provenance fail',()=>fixture(({root,m,bindings,put,ref,job})=>{
 for(const patch of [{schema:'local-ai/forced-alignment/1'},{durationSeconds:.5},{engine:{...m.engine,modelRevision:'invented'}},{engine:{...m.engine,rawTimestampMilliseconds:[80,160]}}])assert.throws(()=>readQueueQwenClock(root,{...m,...patch},bindings));
 for(const v of [null,undefined,''])for(const k of ['id','sessionId'])assert.throws(()=>readQueueQwenClock(root,{...m,request:{...m.request,[k]:v}},bindings),/identity missing/);
 put('bad-status.json',{state:'done',class:'speech',session_id:'session',errors:['failure'],parts:[]});assert.throws(()=>readQueueQwenClock(root,{...m,receipt:ref('bad-status.json')},bindings));
 put('bad-job.jsonl',JSON.stringify({...job,op:'asr.transcribe'})+'\n');assert.throws(()=>readQueueQwenClock(root,{...m,job:ref('bad-job.jsonl')},bindings));
 const b=wav();b.writeInt16LE(100,100);put('candidate.wav',b);const candidate=ref('candidate.wav');
 assert.throws(()=>readQueueQwenClock(root,{...m,candidate},{...bindings,takeSha256:candidate.sha256}),/exact complete decoded/);
}));

function h100Fixture(f){
 const {m,put,ref}=f;
 const r=raw();delete r.ok;put('source.words.json',r);m.raw=ref('source.words.json');
 m.engine.name='studio_worker.cluster_runner.align';m.request.sessionId=null;m.request.output='uploads/source.words.json';
 const status={state:'done',class:'h100',session_id:'-',errors:[],parts:[{class:'h100',session_id:null,ok:true,errors:[]}]};
 const segment={status:'succeeded',class:'h100',op:'asr.align',route:'cluster-job',error:null,text:'Hello world',file:m.request.output};
 const source='def align(job):\n # Qwen3ForcedAligner\n common.stage_checkpoint("qwen3-forced-aligner", spec)\n dtype=torch.float32, device_map="cpu"\n cpu_aligner(str(common.checkpoint_path("qwen3-forced-aligner"))).align(audio=str(source), text=job["text"])';
 put('status.json',status);m.receipt=ref('status.json');put('segments.json',{align:segment});m.segments=ref('segments.json');put('engine.py',source);m.engineSource=ref('engine.py');
 return {...f,status,segment,source};
}
test('H100 CPU queue import binds real null-session and relative-output shapes without inventing raw success',()=>fixture(f=>{
 const {root,m,bindings}=h100Fixture(f),c=readQueueQwenClock(root,m,bindings),report=measureQueueQwenClock(c,cue());
 assert.equal(c.pcmSamples,6400);assert.equal(c.sessionId,null);assert.equal(c.engineName,'studio_worker.cluster_runner.align');assert.equal(c.executionPrecision,null);
 assert.equal(report.ok,true);assert.equal(report.modelRevision,null);assert.equal(report.rawTimestampMilliseconds,null);assert.equal(report.uncertaintyMs,null);assert.equal(report.gridMs,80);
}));
test('H100 rejects false, ambiguous, mixed-route and spoofed completion even with rehashed references',()=>fixture(f=>{
 const {root,m,bindings,put,ref,status,segment}=h100Fixture(f);
 const reject=(key,path,value)=>{put(path,value);assert.throws(()=>readQueueQwenClock(root,{...m,[key]:ref(path)},bindings));};
 for(const patch of [{state:'failed'},{class:'speech'},{session_id:null},{session_id:'invented'},{errors:['failed']},{parts:[]},...['ok','class','session_id','errors'].map(k=>({parts:[{...status.parts[0],[k]:({ok:false,class:'speech',session_id:'invented',errors:['failed']})[k]}]}))])reject('receipt','bad-status.json',{...status,...patch});
 for(const patch of [{status:'failed'},{class:'speech'},{op:'asr.transcribe'},{route:'http'},{error:'failure'},{text:'Other text'},{file:'other.words.json'}])reject('segments','bad-segments.json',{align:{...segment,...patch}});
 reject('segments','bad-segments.json',{align:segment,extra:segment});
 for(const ok of [true,false,null])reject('raw','bad.words.json',{...raw(),ok});
 reject('job','bad-jobs.jsonl',JSON.stringify(f.job)+'\n'+JSON.stringify({...f.job,id:'another'})+'\n');
 for(const sessionId of ['session',undefined,''])assert.throws(()=>readQueueQwenClock(root,{...m,request:{...m.request,sessionId}},bindings));
 assert.throws(()=>readQueueQwenClock(root,{...m,request:{...m.request,output:'/data/productions/test-project--unit/uploads/source.words.json'}},bindings));
}));
test('H100 requires retained CPU forced-aligner source and unchanged independent input evidence',()=>fixture(f=>{
 const {root,m,bindings,put,ref,source}=h100Fixture(f);
 for(const text of [source.replace('device_map="cpu"','device_map="cuda:0"'),source.replace('dtype=torch.float32','dtype=torch.bfloat16'),source.replace('cpu_aligner','asr_transcriber'),source.replace('common.stage_checkpoint','unverified_checkpoint')]){
  put('bad-engine.py',text);assert.throws(()=>readQueueQwenClock(root,{...m,engineSource:ref('bad-engine.py')},bindings));
 }
 for(const key of ['candidate','sourceAudio','script','raw','job','submission','receipt','segments','engineSource']){
  const p=join(root,m[key].path),before=readFileSync(p);writeFileSync(p,Buffer.concat([before,Buffer.from(' ')]));assert.throws(()=>readQueueQwenClock(root,m,bindings),/immutable input/);writeFileSync(p,before);
 }
 for(const patch of [{modelRevision:'invented'},{rawTimestampMilliseconds:[80,160]},{name:'local-ai.audio.align'}])assert.throws(()=>readQueueQwenClock(root,{...m,engine:{...m.engine,...patch}},bindings));
}));


test('H100 imports selected job from complete batch and original48k PCM without changing submitted bytes',()=>fixture(f=>{
 const {root,m,bindings,put,ref,status,segment,job}=h100Fixture(f);
 const source=Buffer.alloc(44+38400);wav().copy(source,0,0,44);source.writeUInt32LE(source.length-8,4);source.writeUInt32LE(48000,24);source.writeUInt32LE(96000,28);source.writeUInt32LE(38400,40);
 put('uploads/source.wav',source);m.sourceAudio=ref('uploads/source.wav');
 put('submission.json',{decodedAudioSha256:m.sourceAudio.sha256,scriptSha256:m.script.sha256});m.submission=ref('submission.json');
 const other={...job,id:'other',audio:'uploads/other.wav',text:'Different script'};
 const otherSegment={...segment,text:other.text,file:'uploads/other.words.json'};
 const jobs=[job,other],segments={align:segment,other:otherSegment};
 put('jobs.jsonl',jobs.map(j=>JSON.stringify(j)).join('\n'));m.job=ref('jobs.jsonl');put('segments.json',segments);m.segments=ref('segments.json');
 assert.equal(readQueueQwenClock(root,m,bindings).pcmSamples,6400);assert.deepEqual(readFileSync(join(root,'uploads/source.wav')),source);
 const reject=(key,path,value)=>{put(path,value);assert.throws(()=>readQueueQwenClock(root,{...m,[key]:ref(path)},bindings));};
 for(const bad of [[job,job],[job,{...other,id:job.id}],[job,{...other,audio:job.audio}],[job,{...other,op:'asr.transcribe'}]])reject('job','bad-jobs.jsonl',bad.map(j=>JSON.stringify(j)).join('\n'));
 for(const bad of [{align:segment},{...segments,extra:otherSegment},{...segments,other:{...otherSegment,status:'failed'}},{align:otherSegment,other:segment},{...segments,other:{...otherSegment,text:'mixed'}}])reject('segments','bad-segments.json',bad);
 reject('receipt','bad-status.json',{...status,parts:[...status.parts,{...status.parts[0],ok:false}]});
 const changed=Buffer.from(source);changed.writeInt16LE(32000,100);put('uploads/source.wav',changed);const changedRef=ref('uploads/source.wav');put('submission.json',{decodedAudioSha256:changedRef.sha256,scriptSha256:m.script.sha256});
 assert.throws(()=>readQueueQwenClock(root,{...m,sourceAudio:changedRef,submission:ref('submission.json')},bindings),/exact complete decoded/);
}));


test('explicit unknown grid retains raw model timestamps without rounding, while legacy grid remains enforced',()=>fixture(f=>{
 const {root,m,bindings,put,ref}=f;
 const r=raw();r.words[0].start=.081;r.words[0].end=.208;r.words[1].start=.216;r.words[1].end=.384;
 put('source.words.json',r);m.raw=ref('source.words.json');
 assert.throws(()=>readQueueQwenClock(root,m,bindings),/grid/);
 m.gridSeconds=null;
 const clock=readQueueQwenClock(root,m,bindings),report=measureQueueQwenClock(clock,r.words.map(w=>({w:w.word,start:w.start,end:w.end})));
 assert.deepEqual(clock.words,r.words.map(w=>({w:w.word,start:w.start,end:w.end})));assert.equal(report.gridMs,null);assert.equal(report.uncertaintyMs,null);assert.equal(report.ok,true);
 assert.equal(measureQueueQwenClock(clock,r.words.map(w=>({w:w.word,start:w.start+.03,end:w.end+.03})),20).ok,false);
 for(const mutate of [x=>x.words[0].start=-.01,x=>x.words[1].start=.1,x=>x.words[1].end=.5,x=>x.words[0].start=NaN,x=>x.words[0].word='Wrong']){const bad=structuredClone(r);mutate(bad);assert.throws(()=>validateQueueQwenRaw(bad,'Hello world',.4,null));}
}));


test('speech batch binds every job and permits only genuine successful null-output staging records',()=>fixture(f=>{
 const {root,m,bindings,put,ref,job}=f;
 const other={...job,id:'other',audio:'uploads/other.wav',text:'Other script'};
 const selected={status:'succeeded',class:'speech',error:null,text:job.text,file:m.request.output};
 const extra={...selected,text:other.text,file:'/data/productions/test-project--unit/uploads/other.words.json'};
 const staging={status:'succeeded',class:'speech',error:null,text:null,file:null};
 const segments={align:selected,other:extra,'unpack-test-project--unit-001':staging};
 put('jobs.jsonl',[job,other].map(j=>JSON.stringify(j)).join('\n'));m.job=ref('jobs.jsonl');put('segments.json',segments);m.segments=ref('segments.json');
 assert.equal(readQueueQwenClock(root,m,bindings).pcmSamples,6400);
 for(const bad of [{...segments,other:{...extra,text:job.text}},{...segments,other:{...extra,status:'failed'}},{align:extra,other:selected},{...segments,unknown:staging},{...segments,'unpack-test-project--unit-001':{...staging,file:'fake'}}]){put('bad-segments.json',bad);assert.throws(()=>readQueueQwenClock(root,{...m,segments:ref('bad-segments.json')},bindings));}
 put('bad-jobs.jsonl',[job,job].map(j=>JSON.stringify(j)).join('\n'));assert.throws(()=>readQueueQwenClock(root,{...m,job:ref('bad-jobs.jsonl')},bindings));
}));


test('terminal endpoint allowance is explicit bounded editorial policy, preserves raw time and defaults strict',()=>fixture(f=>{
 const {root,m,bindings,put,ref}=f;
 const r=raw();r.words[1].end=.406208333;put('source.words.json',r);m.raw=ref('source.words.json');m.gridSeconds=null;
 assert.throws(()=>readQueueQwenClock(root,m,bindings));
 m.terminalEndpointToleranceMs=10;
 const c=readQueueQwenClock(root,m,bindings);assert.equal(c.words[1].end,r.words[1].end);assert.equal(c.terminalEndpointToleranceMs,10);assert.ok(Math.abs(c.terminalEndpointOvershootMs-6.208333)<1e-8);
 for(const tolerance of [-1,NaN,Infinity,10.1,'10'])assert.throws(()=>validateQueueQwenRaw(r,'Hello world',.4,null,tolerance),/endpoint policy/);
 for(const mutate of [x=>x.words[1].end=.411,x=>{x.words[1].start=.401;x.words[1].end=.405;},x=>{x.words[0].end=.401;x.words[1].start=.402;x.words[1].end=.405;}]){const bad=structuredClone(r);mutate(bad);assert.throws(()=>validateQueueQwenRaw(bad,'Hello world',.4,null,10));}
 assert.equal(validateQueueQwenRaw(raw(),'Hello world',.4,null).terminalEndpointOvershootMs,0);
}));
