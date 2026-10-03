// Independent review: deterministic randomized exact-matrix comparison.
// SPECQR_ORACLE=/path/to/pinned/upstream SPECQR_CLI=/path/to/specqr-cli node randomized-matrix.mjs
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
if (!process.env.SPECQR_ORACLE || !process.env.SPECQR_CLI) throw new Error('Set SPECQR_ORACLE and SPECQR_CLI');
const q = await import(pathToFileURL(path.resolve(process.env.SPECQR_ORACLE, 'src/index.js')));
const binary=process.env.SPECQR_CLI;
function swift(rows){const p=spawnSync(binary,['--json-lines'],{input:rows.map(x=>JSON.stringify(x)).join('\n')+'\n',encoding:'utf8',maxBuffer:128e6});if(p.status!==0)throw new Error(p.stderr);return p.stdout.trim().split('\n').map(JSON.parse)}
let seed=187031; function rand(n){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n}
const chars=Array.from('01234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:abcdefghijklmnopqrstuvwxyz漢字日本語éé😀\u0301\u0000');
const rows=[];for(let i=0;i<700;i++){let text='';const n=rand(170);for(let j=0;j<n;j++)text+=chars[rand(chars.length)];rows.push({text,options:{errorCorrectionLevel:['L','M','Q','H'][rand(4)],minVersion:[1,9,10,26,27][rand(5)],maxVersion:40,...(i%3?{}:{eci:26}),...(i%4?{}:{optimizeSegments:false})}})}
let tested=0;
for(let offset=0;offset<rows.length;offset+=20){const batch=rows.slice(offset,offset+20),out=swift(batch);for(let j=0;j<batch.length;j++){const r=batch[j],s=out[j];const e=q.generate(r.text,{...r.options,output:'matrix',diagnostics:true});if(JSON.stringify(s.matrix)!==JSON.stringify(e.matrix.map(row=>row.map(Number).join('')))){console.log('MATRIX mismatch',r,s.version,e.diagnostics.version);process.exit(1)}tested++}}
console.log({randomMatrixPasses:tested});
