#!/usr/bin/env node
import { verifyEditMap } from './edit-map-clock.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
const [rootArg,candidateArg,mapArg]=process.argv.slice(2);
if(!rootArg||!candidateArg||!mapArg){console.error('usage: validate-edit-map.mjs <jobRoot> <candidate> <edit-map.json>');process.exit(2);}
const root=resolve(rootArg),out=join(root,'qa','encoded-edit-map.json');
let report;
try{report=verifyEditMap(root,resolve(mapArg),resolve(candidateArg));}catch(e){report={generator:'media-studio/validate-edit-map',ok:false,errors:[e.message]};}
mkdirSync(join(root,'qa'),{recursive:true});writeFileSync(out,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({ok:report.ok,errors:report.errors,out}));process.exit(report.ok?0:1);
