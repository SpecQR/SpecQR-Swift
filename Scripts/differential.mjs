// Test-only oracle driver. No oracle code is part of the Swift runtime.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { inflateSync } from 'node:zlib';
const root = path.resolve(import.meta.dirname, '..');
const oracle = path.resolve(process.env.SPECQR_ORACLE ?? path.join(root, '../upstream'));
const binary = path.resolve(process.env.SPECQR_CLI ?? path.join(root, '.build/release/specqr-cli'));
const load = async p => import(pathToFileURL(path.join(oracle, p)).href);
const api = await load('src/index.js');
const { normalizeOptions } = await load('src/options.js');
const { selectPlanForInput, selectPlanForManualSegments } = await load('src/internal/planning.js');
const { normalizeManualSegments, encodeSegments } = await load('src/encoding/modes.js');
const { buildResultArtifact } = await load('src/internal/build.js');
const require = createRequire(path.join(oracle, 'package.json'));
const qrcodegenModule = require('nayuki-qr-code-generator');
const qrcodegen = qrcodegenModule.default ?? qrcodegenModule;
const jsQR = require('jsqr');
const commit = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: oracle, encoding:'utf8'}).stdout.trim();
assert.equal(commit, '15ad15e5c770ea0e39072f8f88b2733018f02ffd');
const results = { sourceCommit:commit, fixed:0, auto:0, planning:0, negative:0, render:0, nayuki:0, decoded:0, intentionalSafetyDivergences:0 };
function swift(requests) {
  const r = spawnSync(binary, ['--json-lines'], {input:requests.map(x=>JSON.stringify(x)).join('\n')+'\n', encoding:'utf8', maxBuffer:128*1024*1024});
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.trim().split('\n').map(JSON.parse);
  assert.equal(lines.length, requests.length, `Swift response count ${r.stderr}`); return lines;
}
function jsSegments(segments) { return segments.map(s => ['numeric','alphanumeric','byte','kanji'].includes(s.mode) ? {mode:s.mode,data:s.bytes ?? s.text} : {...s}); }
function oracleInput(r) { return r.bytes ? Uint8Array.from(r.bytes) : r.text ?? ''; }
function expected(r) {
  const options = normalizeOptions({...r.options,output:'matrix',diagnostics:true});
  const plan = r.segments ? selectPlanForManualSegments(normalizeManualSegments(jsSegments(r.segments)),options) : selectPlanForInput(oracleInput(r), options);
  const built = buildResultArtifact(plan, options);
  const publicResult = r.segments ? api.generateSegments(jsSegments(r.segments), options) : api.generate(oracleInput(r), options);
  return {result:publicResult,plan,built,data:encodeSegments(plan.segments,plan.version,plan.errorCorrectionLevel)};
}
function compare(r,s) {
  assert.equal(s.error, undefined, JSON.stringify({r,s}));
  const e = expected(r), d=e.result.diagnostics;
  assert.deepEqual(s.matrix,e.result.matrix.map(row=>row.map(Number).join('')),`matrix ${JSON.stringify(r)}`);
  for (const key of ['version','errorCorrectionLevel','maskPattern','maskPenalty','dataBitLength','capacityBits','remainingBits','inputBytes','mode']) assert.equal(s[key],d[key],`${key} ${JSON.stringify(r)}`);
  assert.deepEqual(s.maskPenalties,d.maskPenalties,'maskPenalties');
  assert.deepEqual(s.dataCodewords,Array.from(e.data),'dataCodewords');
  assert.deepEqual(s.codewords,Array.from(e.built.interleaved.codewords),'interleaved');
  for (const key of ['mode','characterCount','byteCount','bitLength']) assert.deepEqual(s.segments.map(x=>x[key]), d.segments.map(x=>x[key]),`segments.${key} ${JSON.stringify(r)}`);
}
const eccMap={L:qrcodegen.QrCode.Ecc.LOW,M:qrcodegen.QrCode.Ecc.MEDIUM,Q:qrcodegen.QrCode.Ecc.QUARTILE,H:qrcodegen.QrCode.Ecc.HIGH};
const kinds = [
  {text:'123456789',options:{mode:'numeric'}},
  {text:'HELLO:1',options:{mode:'alphanumeric'}},
  {text:'aé',options:{mode:'byte'}},
  {bytes:[0,1,127,128,254,255]},
  {segments:[{mode:'numeric',text:'123'},{mode:'byte',bytes:[97]}]},
  {segments:[{mode:'eci',assignmentNumber:26},{mode:'byte',text:'雪'}]},
  {text:'漢字',options:{mode:'kanji'}},
  {segments:[{mode:'fnc1-second',applicationIndicator:'A'},{mode:'alphanumeric',text:'ABC'}]}
];
function referenceSegments(r) {
 const segments = r.segments ?? (r.bytes ? [{mode:'byte',bytes:r.bytes}] : [{mode:r.options.mode,text:r.text}]);
 return segments.map(s=> {
  switch(s.mode) {
   case 'numeric':return qrcodegen.QrSegment.makeNumeric(s.text);
   case 'alphanumeric':return qrcodegen.QrSegment.makeAlphanumeric(s.text);
   case 'byte':return qrcodegen.QrSegment.makeBytes(s.bytes ?? Array.from(new TextEncoder().encode(s.text)));
   case 'eci':return qrcodegen.QrSegment.makeEci(s.assignmentNumber);
   default:return null;
  }
 });
}
for(let version=1;version<=40;version++) {
 const requests=[];
 for(const [ei,errorCorrectionLevel] of ['L','M','Q','H'].entries()) for(let maskPattern=0;maskPattern<8;maskPattern++) {
  const kind=kinds[(version+ei+maskPattern)%kinds.length];
  requests.push({...kind,options:{...kind.options,version,errorCorrectionLevel,maskPattern}});
 }
 const answers=swift(requests);
 requests.forEach((r,i)=> {
  const s=answers[i]; compare(r,s);results.fixed++;
  const segments=referenceSegments(r);
  if(segments.every(Boolean)) {
   const q=qrcodegen.QrCode.encodeSegments(segments,eccMap[r.options.errorCorrectionLevel],version,version,r.options.maskPattern,false);
   assert.deepEqual(s.matrix,Array.from({length:q.size},(_,y)=>Array.from({length:q.size},(_,x)=>q.getModule(x,y)?'1':'0').join('')),'Nayuki matrix');results.nayuki++;
  }
 });
}
const auto=[];
for(const text of ['', 'A','HELLO WORLD','https://example.com/a?q=1','123456789012345678901234567890','日本語漢字かなカナ','abc12345678901234567890XYZ','😀e\u0301é','𝄞𐐷0\u0000\u007f','12A34B56C78D90', 'x'.repeat(300), '1'.repeat(1000)]) {
 for(const errorCorrectionLevel of ['L','M','Q','H']) for(const optimizeSegments of [true,false]) auto.push({text,options:{errorCorrectionLevel,optimizeSegments}});
}
for(const version of [1,2,9,10,26,27,40]) for(const errorCorrectionLevel of ['L','M','Q','H']) auto.push({text:'A1',options:{version,errorCorrectionLevel,boostErrorCorrection:true}});
for(const assignmentNumber of [0,127,128,16383,16384,999999]) auto.push({segments:[{mode:'eci',assignmentNumber},{mode:'byte',text:'ECI'}]});
for(const indicator of ['00','99','A','z']) auto.push({text:'ABC',options:{fnc1Second:indicator}});
for(const text of ['0109501101530003','010950110153000310LOT123\u001d17271231']) auto.push({text,options:{gs1:true}});
for(let i=0;i<auto.length;i+=24) {
 const batch=auto.slice(i,i+24);swift(batch).forEach((s,j)=>{compare(batch[j],s);results.auto++;});
}
const planning=[];
for(const version of [1,9,10,26,27,40]) for(const errorCorrectionLevel of ['L','M','Q','H']) for(const mode of ['numeric','alphanumeric','byte','kanji']) {
 const letter={numeric:'1',alphanumeric:'A',byte:'a',kanji:'漢'}[mode];
 const c=api.getCapacity({version,errorCorrectionLevel,mode});
 const cap=c.maxCharacters ?? c.maxBytes;
 for(const n of [Math.max(1,cap-1),cap,cap+1]) planning.push({command:'estimate',text:letter.repeat(n),options:{version,errorCorrectionLevel,mode}});
}
for(let i=0;i<planning.length;i+=24) {
 const batch=planning.slice(i,i+24);swift(batch).forEach((s,j)=>{
  const r=batch[j], e=api.estimate(r.text,r.options); assert.equal(s.error,undefined,JSON.stringify(s));
  for(const k of ['ok','selectedVersion','errorCorrectionLevel','dataBitLength','capacityBits','remainingBits','inputBytes','mode']) assert.equal(s[k],e[k],`planning.${k} ${JSON.stringify(r.options)}`);
  results.planning++;
 });
}
const negative=[
 {text:'x',options:{version:0}},{text:'x',options:{version:41}},{text:'x',options:{minVersion:20,maxVersion:10}},
 {text:'x',options:{maskPattern:8}},{text:'x',options:{eci:1000000}},{text:'x',options:{eci:-1}},
 {text:'x',options:{mode:'numeric'}},{text:'abc',options:{mode:'alphanumeric'}},{text:'😀',options:{mode:'kanji'}},
 {text:'x',options:{gs1:true,eci:26}},{text:'x',options:{gs1:true,fnc1Second:'A'}},
 {segments:[{mode:'byte',text:'x'},{mode:'fnc1'}]},
 {segments:[{mode:'structured-append',index:0,total:2,parity:0},{mode:'byte',text:'x'}]},
 {segments:[{mode:'fnc1'},{mode:'eci',assignmentNumber:26},{mode:'byte',text:'x'}]},
 {text:'x'.repeat(3000),options:{version:1}}
];
swift(negative).forEach((s,i)=> {const r=negative[i];let failed=false;try {r.segments?api.generateSegments(jsSegments(r.segments),r.options):api.generate(r.text,r.options);} catch {failed=true;} assert.ok(failed,'test must be invalid upstream');assert.ok(s.error,`negative ${JSON.stringify(r)}`);results.negative++;});
// Intentional safety correction: raw high-level FNC1 percent is preserved via byte mode.
const corrected = [];
for (const headers of [{gs1:true}, {fnc1Second:'A'}]) for (const optimizeSegments of [true,false])
 for (const text of ['10ABC%DEF','10ABC%%DEF','10LOT%\u001d21SER%IAL']) corrected.push({text,options:{...headers,optimizeSegments}});
swift(corrected).forEach((s,i)=>{compare({...corrected[i],options:{...corrected[i].options,mode:'byte'}},s);results.intentionalSafetyDivergences++;});
const rejectedPercent=[{text:'10ABC%DEF',options:{mode:'alphanumeric',gs1:true}},
 {text:'ABC%DEF',options:{mode:'alphanumeric',fnc1Second:'A'}},
 {segments:[{mode:'alphanumeric',text:'10ABC%DEF'}],options:{gs1:true}},
 {segments:[{mode:'alphanumeric',text:'ABC%DEF'}],options:{fnc1Second:'A'}}];
swift(rejectedPercent).forEach(s=>{assert.ok(s.error);results.intentionalSafetyDivergences++;});
const renders=[];
for(const render of [{},{scale:1,margin:0},{scale:3,margin:4,foreground:'#1358',background:'transparent'},{foreground:'red',background:'white'}]) for(const format of ['svg','svg-data-url',...(render.foreground==='red'?[]:['png'])]) renders.push({command:'render',text:'Render漢字123',format,render});
swift(renders).forEach((s,i)=> {const r=renders[i];const output=api.generate(r.text,{...r.render,output:r.format});const expected=r.format==='png'?'data:image/png;base64,'+Buffer.from(output).toString('base64'):output;assert.equal(s.output,expected,`render ${r.format}`);results.render++;});
const decodeCases=JSON.parse(fs.readFileSync(path.join(oracle,'fixtures/decode-cases.json')));
const decodeRequests=decodeCases.map(c=>({...c,options:{...c.options,...(c.options?.eci===true?{eci:26}:{})},segments:c.segments?.map(s=>({mode:s.mode,text:s.data})),bytes:c.binaryHex?Array.from(Buffer.from(c.binaryHex,'hex')):undefined}));
const decoderSwift=swift(decodeRequests);
decoderSwift.forEach((s,i)=>{
 const c=decodeCases[i];assert.equal(s.error,undefined);
 const scale=5,margin=4,size=s.matrix.length,width=(size+margin*2)*scale;
 const rgba=new Uint8ClampedArray(width*width*4);
 for(let y=0;y<width;y++) for(let x=0;x<width;x++) {const mx=Math.floor(x/scale)-margin,my=Math.floor(y/scale)-margin;const dark=mx>=0&&my>=0&&mx<size&&my<size&&s.matrix[my][mx]==='1';const p=(y*width+x)*4;rgba[p]=rgba[p+1]=rgba[p+2]=dark?0:255;rgba[p+3]=255;}
 const decoded=jsQR(rgba,width,width,{inversionAttempts:'dontInvert'});assert.ok(decoded,`decode ${c.id}`);assert.equal(decoded.data,c.expected??c.text);results.decoded++;
});
console.log(JSON.stringify(results,null,2));
