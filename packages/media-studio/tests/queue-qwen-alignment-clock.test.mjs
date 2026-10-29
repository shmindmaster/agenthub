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
